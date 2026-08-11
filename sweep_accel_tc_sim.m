function sweep_accel_tc_sim()
%SWEEP_ACCEL_TC_SIM  Sweep gear ratio x TC gain through accel_tc_sweep_sim.slx, per map.
%
%   sweep_accel_tc_sim        % builds the model if needed, runs both maps, plots
%
% TC-tuning version of sweep_accel_sim.m. Two axes instead of one: gear ratio, and kp.
%
% ONE PAGE PER MAP. A map is not just a gain, it bundles kp + output clamp + torque
% ceiling. 150 Nm map is kp 0.470 / clamp 0.75 / 150 Nm. 130 Nm map is 0.591 / 0.70 /
% 130 Nm. On one axis you'd read "kp 0.59 beats kp 0.47" without noticing the ceiling
% moved too. Separate pages keep each map self-consistent.
%
% DON'T QUOTE AN ABSOLUTE 0-75 m FROM THIS. The logged runs don't reconcile with
% p.r_wheel = 0.221: at that radius the car put more energy into the road than the motor
% made, which needs eta > 1. See tools/radius_from_energy_balance.py. Until someone tapes
% a rear tyre, absolute times carry a ~10% scale error. Relative comparisons (gain vs
% gain, ratio vs ratio, TC on vs off) are fine, the error mostly cancels.
%
% Gains below are compile-time defaults. The log pins full throttle at 123.0 Nm, which
% matches no compile-time map, so NVM was written and the live gains are UNKNOWN.

    mdl  = 'accel_tc_sweep_sim';
    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here,'lib'));
    if ~exist(fullfile(here,'output'),'dir'), mkdir(fullfile(here,'output')); end

    p = params_cfr26();
    if ~bdIsLoaded(mdl)
        if isfile(fullfile(here,[mdl '.slx'])), load_system(mdl);
        else, build_accel_tc_sweep_simulink(); end
    end

    % Restore baseline config on every exit path, including Ctrl-C. Otherwise a killed
    % sweep leaves the workspace on whatever ratio it died on and the next bare run
    % quietly reports that instead of the real car. Same reason sweep_accel_sim.m does it.
    tcBase = struct('enabled',true,'target_slip',0.10,'kp',0.470,'ki',0.0,'kd',0.110, ...
                    'ilim',0.0,'maxlim',0.75,'ileak_ms',500,'rate_hz',100, ...
                    'speed_gate',0.5,'emulate_firmware_pure_p',true);
    tyreCfg = struct('mu_scale',1.00);
    cleanup = onCleanup(@() sweep_cleanup(p, tcBase, tyreCfg)); %#ok<NASGU>
    assignin('base','tyreCfg',tyreCfg);

    % A map is kp + clamp + torque ceiling, moved together. See the header.
    maps = struct( ...
        'name',   {'150 Nm map', '130 Nm map (compile-time DEFAULT)'}, ...
        'tag',    {'150Nm',      '130Nm'}, ...
        'kp',     {0.470,        0.591}, ...
        'kd',     {0.110,        0.070}, ...
        'maxlim', {0.75,         0.70 }, ...
        'Tmax',   {150,          130  });

    gears  = p.gears_to_test(:)';
    kpList = [0.235 0.470 0.591 0.940 1.500];

    fig = figure('Name','TC tuning sweep (Simulink)','Position',[40 40 1180 700]);
    tg  = uitabgroup(fig);
    S   = struct('map',{},'kp',{},'ratio',{},'t75',{},'pkslip',{},'peak_y',{},'vtrap',{});

    for mi = 1:numel(maps)
        M  = maps(mi);
        pM = p; pM.T_driver_max = M.Tmax;
        fprintf('\n=== %s: kp %.3f, clamp %.2f, torque ceiling %d Nm ===\n', ...
                M.name, M.kp, M.maxlim, M.Tmax);

        % ---- axis 1: gear ratio at this map's OWN gains ----
        tcM = tcBase; tcM.kp = M.kp; tcM.kd = M.kd; tcM.maxlim = M.maxlim;
        tcM.ki = 0; tcM.ilim = 0;          % both maps ship the integral disabled twice over
        t75r  = nan(size(gears));  t75off = nan(size(gears));  pk = nan(size(gears));
        fprintf('  ratio sweep at this map''s own gains\n');
        fprintf('   ratio   t75_on  t75_off  TC worth  pk slip  trap kph  redline kph\n');
        for i = 1:numel(gears)
            [t75r(i), Ron]  = runsim(mdl, pM, tcM, gears(i));
            tcOff = tcM; tcOff.enabled = false;
            t75off(i)       = runsim(mdl, pM, tcOff, gears(i));
            pk(i)           = Ron.pkslip;
            fprintf('  %6.2f %8.3f %8.3f %9.3f %8.2f %9.1f %12.1f\n', ...
                gears(i), t75r(i), t75off(i), t75off(i)-t75r(i), Ron.pkslip, ...
                Ron.vtrap*3.6, (p.redline/gears(i))*(2*pi/60)*p.r_wheel*3.6);
        end

        % ---- axis 2: kp at the current car's ratio ----
        fprintf('  gain sweep at the current %.2f:1\n', p.gear_current);
        fprintf('     kp    t75   pk slip  peak y\n');
        t75k = nan(size(kpList)); pky = nan(size(kpList)); pks = nan(size(kpList));
        for j = 1:numel(kpList)
            s = tcM; s.kp = kpList(j);
            [t75k(j), R] = runsim(mdl, pM, s, p.gear_current);
            pky(j) = R.peak_y; pks(j) = R.pkslip;
            mark = ''; if abs(kpList(j)-M.kp) < 1e-9, mark = '  <- THIS MAP'; end
            fprintf('  %5.3f %7.3f %8.2f %7.2f%s\n', kpList(j), t75k(j), pks(j), pky(j), mark);
            S(end+1) = struct('map',M.tag,'kp',kpList(j),'ratio',p.gear_current, ...
                't75',t75k(j),'pkslip',pks(j),'peak_y',pky(j),'vtrap',R.vtrap); %#ok<AGROW>
        end

        % ---- this map's own page ----
        tab = uitab(tg, 'Title', M.tag);
        tl  = tiledlayout(tab, 1, 2, 'Padding','compact', 'TileSpacing','compact');
        title(tl, sprintf('%s  (kp %.3f, clamp %.2f, ceiling %d Nm)', ...
              M.name, M.kp, M.maxlim, M.Tmax), 'FontWeight','bold');

        ax = nexttile(tl);
        plot(ax, gears, t75r, 'o-', 'LineWidth',1.8); hold(ax,'on');
        plot(ax, gears, t75off, 's--', 'LineWidth',1.2);
        xline(ax, p.gear_current, 'r--', sprintf('current %.2f', p.gear_current));
        [~,kb] = min(t75r);
        plot(ax, gears(kb), t75r(kb), 'p', 'MarkerSize',14, 'MarkerFaceColor','g');
        grid(ax,'on'); xlabel(ax,'gear ratio'); ylabel(ax,'0-75 m (s)');
        legend(ax, {'TC on','TC off','current','best on this grid'}, 'Location','best');
        title(ax, sprintf('0-75 m vs ratio (best %.2f:1 -> %.3f s)', gears(kb), t75r(kb)));

        ax = nexttile(tl);
        yyaxis(ax,'left');  plot(ax, kpList, t75k, 'o-', 'LineWidth',1.8);
        ylabel(ax,'0-75 m (s)');
        yyaxis(ax,'right'); plot(ax, kpList, pks, 's--', 'LineWidth',1.4);
        ylabel(ax,'peak slip');
        xline(ax, M.kp, 'k--', 'this map''s kp');
        grid(ax,'on'); xlabel(ax,'kp');
        title(ax, sprintf('gain sweep at %.2f:1', p.gear_current));
    end

    % ---- one comparison page, so the maps can be read against each other ----
    tab = uitab(tg, 'Title','150 vs 130 Nm');
    ax  = axes(tab); hold(ax,'on');
    for mi = 1:numel(maps)
        m = strcmp({S.map}, maps(mi).tag);
        plot(ax, [S(m).kp], [S(m).t75], 'o-', 'LineWidth',1.8, 'DisplayName', maps(mi).name);
    end
    grid(ax,'on'); xlabel(ax,'kp'); ylabel(ax,'0-75 m (s)');
    legend(ax,'Location','best');
    title(ax, sprintf(['0-75 m vs kp, both maps, at %.2f:1' newline ...
        'the 130 Nm map carries a LOWER TORQUE CEILING, so its curve sitting higher is ' ...
        'mostly the ceiling, not the gain'], p.gear_current));

    % Say it out loud if TC never fired. A flat gain sweep looks like "gains don't
    % matter", which is the wrong read: what it actually means is the controller never
    % got to act, so the sweep carries no information about gains at all.
    if all([S.peak_y] == 0)
        fprintf(2, '\n*** TC NEVER ENGAGED IN ANY RUN (peak y = 0 everywhere). ***\n');
        fprintf(2, 'The gain sweep above is degenerate. Do not read it as "kp does not\n');
        fprintf(2, 'matter". Peak slip hits %.2f but that happens below the %.1f m/s\n', ...
                max([S.pkslip]), tcBase.speed_gate);
        fprintf(2, 'speed gate, where the firmware TC is blind by design. Past the gate\n');
        fprintf(2, 'slip sits under the %.2f target so there is nothing to cut.\n', ...
                tcBase.target_slip);
        fprintf(2, 'The real car spun to 7.58 on every standing start, so the model and\n');
        fprintf(2, 'the car disagree here. Prime suspect is the extrapolated high-slip\n');
        fprintf(2, 'tail (measured data stops at SL 0.186). UNRESOLVED, see the handoff.\n\n');
    end

    save_tabfig(fig, fullfile(here,'output','AccelTCSweep'));
    writetable(struct2table(S), fullfile(here,'output','accel_tc_sweep.csv'));
    fprintf('\nSaved: output/accel_tc_sweep.csv + a tabbed figure (%d tabs)\n', ...
            numel(maps)+1);
    fprintf(['REMINDER: absolute t75 here is unvalidated pending the tyre-size question ' ...
             '(see header).\n']);
end

function [t75, R] = runsim(mdl, p, tc, G)
%RUNSIM  One Simulink run at this config. Returns t75 plus the summary signals.
%   The config goes into the base workspace because that is where the model's sampler
%   reads it from; lib/accel_tc_sweep_sample.m keys its cache on these values, so no
%   explicit cache clear is needed and a stale trace is not reachable.
    assignin('base','p',p); assignin('base','tcCfg',tc); assignin('base','G',G);
    so   = sim(mdl);
    % Derive the To Workspace variable names the same way the build script does, rather
    % than hardcoding them. makeValidName turns 'y (TC cut)' into 'y_TCCut_', which is not
    % what you would guess, and a wrong guess only shows up at run time.
    nm   = @(s) matlab.lang.makeValidName(s);
    t75  = so.get('t75').signals.values(end);
    R.pkslip = max(so.get('slip').signals.values);
    R.peak_y = max(so.get(nm('y (TC cut)')).signals.values);
    v        = so.get(nm('v (m/s)')).signals.values;
    x        = so.get(nm('x (m)')).signals.values;
    k        = find(x >= 75, 1);
    if isempty(k), R.vtrap = NaN; else, R.vtrap = v(k); end
end

function sweep_cleanup(p, tcBase, tyreCfg)
%SWEEP_CLEANUP  Restore baseline base-workspace state on any exit path.
    assignin('base','p',p);
    assignin('base','tcCfg',tcBase);
    assignin('base','tyreCfg',tyreCfg);
    assignin('base','G',p.gear_current);
end

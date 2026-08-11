%% CFR27 ACCELERATION MODEL *WITH TRACTION CONTROL*  (accel_model_tc.m)
%
% WHAT THIS IS
%   A SECOND accel sim, separate from accel_model.m. Same car, same params, same
%   inertia-based physics, but with two things accel_model.m does not have:
%     1. a real REAR-WHEEL SPEED STATE, so wheel slip is a physical quantity that
%        the tyre generates force from, instead of an instantaneous force cap
%     2. a TRACTION CONTROLLER that mirrors the firmware's, so you can sweep gains
%        in sim before touching the car
%
% WHY IT EXISTS (read this before comparing the two sims)
%   accel_model.m has a documented UNIT BUG in its traction cap: motor torque
%   already has eta_drivetrain applied, and the cap divides by eta again, so the
%   cap is ~26% too high and never binds. It is left that way on purpose so no
%   published number moves. THIS file sidesteps that entirely: it never uses a
%   torque cap. A wheel that is spinning too fast simply makes less force,
%   because that is what tyres do. The launch comes out traction-limited by
%   PHYSICS rather than by a clamp, which is the honest behaviour the bugged cap
%   fails to produce.
%
% FIRMWARE THIS MIRRORS (concordia-fsae/firmware, READ-ONLY reference -- this
% file does not modify or ship anything to the car):
%   components/vc/front/src/torque.c   calc_traction_control_reduction()
%   components/shared/code/libs/lib_pid.c
%   components/shared/code/app/app_vehicleSpeed.c  getAxleSlip()
%
%   slip  = (v_rear_axle - v_vehicle) / v_vehicle          <- rear axle, NOT rear/front
%   x     = slip - target                                  <- lib_pi_typeb_calc
%   y     = clamp(kp*x + i_term + d_term, 0, maxTcLimit)   <- lib_pid_typeb_sum
%   T_out = T_driver * (1 - y)                             <- torque.c:1411-1412
%
%   *** THE SHIPPED CONTROLLER IS PURE PROPORTIONAL. ***
%   calc_traction_control_reduction calls lib_pi_typeb_calc, which writes ONLY
%   p_term and i_term -- it never writes d_term. The variant that does compute a
%   derivative is lib_pid_typeb_calc, which the TC does not call. So d_term stays
%   0 from lib_pid_init and kd has NO EFFECT. On top of that both shipped gain
%   maps have ki = 0 AND ilim = 0, so the integral is disabled twice over.
%   Net: y = clamp(kp*(slip-target), 0, maxlim).
%   This sim implements the FULL PI(D) so you can explore what turning ki/kd on
%   would do, but tc.emulate_firmware_pure_p = true reproduces the shipped
%   behaviour exactly. Keep it true when comparing against logged data.
%
% USAGE
%   accel_model_tc                       % baseline run + gain sweep + figures
%   Edit the tc struct below to change target slip / gains / limits.

clear; clc; close all;
here = fileparts(mfilename('fullpath'));
cd(here);
if ~exist('output','dir'), mkdir('output'); end
addpath(fullfile(here,'lib'));
p = params_cfr26();

%% ================= TRACTION CONTROL CONFIG (all tunable) =================
% Defaults are the firmware's 150 Nm map (components/vc/front/include/torque.h).
tc.enabled        = true;
tc.target_slip    = 0.10;    % TC_TARGET_SLIP
tc.kp             = 0.470;   % TC_150NM_KP
tc.ki             = 0.0;     % TC_150NM_KI   (shipped as 0)
tc.kd             = 0.110;   % TC_150NM_KD   (shipped, but has NO effect -- see header)
tc.ilim           = 0.0;     % TC_150NM_ILIM (shipped as 0 -> integral fully disabled)
tc.maxlim         = 0.75;    % TC_150NM_MAX  (max fraction of torque removable)
tc.ileak_ms       = 500;     % TC_ILEAK_MS
tc.rate_hz        = 100;     % torque_periodic_100Hz
tc.speed_gate     = 0.5;     % TC_VEHICLESPEED_THRESHOLD_MPS (below this TC is OFF)
tc.emulate_firmware_pure_p = true;   % true = ignore kd exactly like the firmware does

%% ================= TYRE SLIP MODEL =================
% accel_model.m only ever asks "what is peak grip". A TC sim needs the whole
% curve, because the controller lives on its shape: force must RISE with slip,
% peak, then FALL. Magic-formula shape, scaled to the same peak mu that
% lib/tire_mu_x.m gives at this load, so the two sims agree on peak grip.
%   mu(s) = mu_peak * sin( C * atan( B * s ) )
% B and C are set so the peak sits at s = tyre.s_peak. GUESSESTIMATE: we have no
% longitudinal tyre test (see params_cfr26 tyre block), so the SHAPE is assumed.
% It is the honest structure, not a measured curve.
% mu_scale: the params tyre block gives mu = LMUX*PDX1 = 1.365 at nominal load, and
% flags it as DERIVED (Calspan never ran a longitudinal sweep). Today's TC-active
% standing launches back-figure an EFFECTIVE launch mu of 1.20-1.27 from vehicle
% acceleration (a_p90 0.77-0.82 g against the transferred rear load) -- about 10%
% below the params number. That 10% is the difference between a car that just holds
% and one that lights the rears up, which is what the log actually shows. Set 1.0 to
% run the params tyre, ~0.91 to run the grip we measured today.  MEASURED (3 launches)
%
% *** CALIBRATION / KNOWN LIMITATION -- read before quoting a time ***
% Sweeping mu_scale, this model is BISTABLE around 0.97:
%     mu_scale >= 0.98 -> tyre hooks up, slip parks at 0.10, 0-75 m = 4.67 s, TC idle
%     mu_scale <= 0.96 -> breaks away to slip 6-11, limit-cycles, 0-75 m = 5.7-6.0 s
% The real car did BOTH at once: it spun to slip 7.6 off the line AND still ran
% ~4.4 s, because TC caught it inside ~0.3 s and it recovered to near-optimal.
% This model cannot reproduce that, which tells us the assumed tyre TAIL is too
% pessimistic: mu at high slip here falls to ~0.52 of peak, so once it lets go it
% struggles to hook back up. A real tyre recovers better than that.
% WHAT WOULD FIX IT: a measured longitudinal mu-slip curve (we have none -- the
% params tyre block says so). Until then, treat the ABSOLUTE 0-75 m from this file
% as unvalidated in the breakaway regime, and use it for COMPARING GAINS, where the
% tyre model is common to every run and largely cancels.
tyre.mu_scale = 1.00;   % 1.00 = params tyre. See the CALIBRATION note below.
tyre.s_peak = 0.12;    % slip at peak grip (GUESSESTIMATE -- no long. tyre data)
tyre.C      = 1.65;    % magic-formula shape factor (GUESSESTIMATE)
tyre.B      = tan(pi/(2*tyre.C)) / tyre.s_peak;   % puts the peak exactly at s_peak

%% ================= RUN =================
fprintf('=== CFR27 ACCEL + TRACTION CONTROL ===\n');
fprintf('firmware mirror: target slip %.2f | kp %.3f ki %.3f kd %.3f | ilim %.2f maxlim %.2f\n', ...
    tc.target_slip, tc.kp, tc.ki, tc.kd, tc.ilim, tc.maxlim);
if tc.emulate_firmware_pure_p
    fprintf('MODE: emulate_firmware_pure_p = TRUE -> kd ignored (as shipped). ');
    if tc.ki == 0 || tc.ilim == 0
        fprintf('ki/ilim = 0 -> PURE P.\n');
    else
        fprintf('PI.\n');
    end
end

R = accel_tc_core(p, tc, tyre, p.gear_current);
fprintf('\nbaseline @ %.2f:1 : 0-75 m = %.3f s | 0-100 kph = %s | trap %.1f kph\n', ...
    p.gear_current, R.t75, fmtnan(R.t100), R.vtrap*3.6);
fprintf('  peak slip %.2f | %.0f%% of run above target | peak reduction y %.2f\n', ...
    max(R.slip), 100*mean(R.slip > tc.target_slip), max(R.y));

% TC off, same physics, for the price of traction control
tcOff = tc; tcOff.enabled = false;
R0 = accel_tc_core(p, tcOff, tyre, p.gear_current);
fprintf('  TC OFF (same tyre model): 0-75 m = %.3f s | peak slip %.2f\n', R0.t75, max(R0.slip));
fprintf('  -> TC is worth %+.3f s over 75 m in this model\n', R0.t75 - R.t75);

%% ================= GAIN SWEEP =================
% Sweep kp and ki around the shipped values so gains can be compared BEFORE
% they go on the car. Metrics are the ones you actually tune against.
fprintf('\n=== GAIN SWEEP @ %.2f:1 (target slip %.2f) ===\n', p.gear_current, tc.target_slip);
fprintf('   kp     ki  |  0-75m   peak slip  settle(s)  sse     osc  peak_y\n');
fprintf('  %s\n', repmat('-',1,64));
kpList = [0.235 0.470 0.940 1.500 2.500];
kiList = [0 2.0];
sweep = struct('kp',{},'ki',{},'t75',{},'pk',{},'settle',{},'sse',{},'osc',{},'py',{});
for ki = kiList
    for kp = kpList
        s = tc; s.kp = kp; s.ki = ki;
        if ki > 0, s.ilim = 0.5; end     % integral is useless unless ilim is opened up
        Rk = accel_tc_core(p, s, tyre, p.gear_current);
        M  = slip_metrics(Rk, s.target_slip);
        mark = ''; if abs(kp-0.470)<1e-9 && ki==0, mark = '  <- SHIPPED'; end
        fprintf('  %5.3f %5.2f  | %6.3f    %6.2f     %6s  %+6.3f  %4d  %5.2f%s\n', ...
            kp, ki, Rk.t75, max(Rk.slip), fmtnan(M.settle), M.sse, M.osc, max(Rk.y), mark);
        sweep(end+1) = struct('kp',kp,'ki',ki,'t75',Rk.t75,'pk',max(Rk.slip), ...
            'settle',M.settle,'sse',M.sse,'osc',M.osc,'py',max(Rk.y)); %#ok<SAGROW>
    end
end
fprintf('\n  settle = first entry into +/-0.02 of target, held 0.3 s\n');
fprintf('  sse    = mean slip error over the last 1 s of the 75 m run\n');
fprintf('  osc    = sign changes of the slip error (ringing proxy)\n');

%% ================= PER-MAP TC SWEEPS (150 Nm and 130 Nm) =================
% The sweep above varies kp against ONE torque ceiling. That is not how the car
% works: each NVM map bundles its own kp, clamp AND maxTorqueNm, so changing map
% changes three things at once. These two sweeps keep each map self-consistent.
%
% Gains are the compile-time defaults from firmware components/vc/front/include/
% torque.h. The LIVE gains come from NVM and today's log proves NVM was written
% (full-throttle request pinned at 123.0 Nm, which is no compile-time map), so
% treat these as DEFAULT-ASSUMED, not as what the car ran.
maps = struct( ...
    'name',   {'150 Nm map', '130 Nm map (compile-time DEFAULT)'}, ...
    'kp',     {0.470,  0.591}, ...
    'kd',     {0.110,  0.070}, ...
    'maxlim', {0.75,   0.70 }, ...
    'Tmax',   {150,    130  });

for mi = 1:numel(maps)
    M0 = maps(mi);
    pM = p; pM.T_driver_max = M0.Tmax;     % map also sets the torque ceiling
    fprintf('\n=== TC SWEEP, %s (kp %.3f, clamp %.2f, T_max %d Nm) ===\n', ...
        M0.name, M0.kp, M0.maxlim, M0.Tmax);

    tcM = tc; tcM.kp = M0.kp; tcM.kd = M0.kd; tcM.maxlim = M0.maxlim;
    tcM.ki = 0; tcM.ilim = 0;              % both maps ship the integral disabled

    tcMoff = tcM; tcMoff.enabled = false;
    Roff = accel_tc_core(pM, tcMoff, tyre, p.gear_current);
    fprintf('  TC OFF                : 0-75 m = %6.3f s | peak slip %5.2f\n', ...
        Roff.t75, max(Roff.slip));

    fprintf('   kp     ki  |  0-75m   peak slip  settle(s)  sse     osc  peak_y\n');
    fprintf('  %s\n', repmat('-',1,64));
    for ki = kiList
        for kp = kpList
            s = tcM; s.kp = kp; s.ki = ki;
            if ki > 0, s.ilim = 0.5; end
            Rk = accel_tc_core(pM, s, tyre, p.gear_current);
            Mk = slip_metrics(Rk, s.target_slip);
            mark = ''; if abs(kp-M0.kp)<1e-9 && ki==0, mark = '  <- THIS MAP'; end
            fprintf('  %5.3f %5.2f  | %6.3f    %6.2f     %6s  %+6.3f  %4d  %5.2f%s\n', ...
                kp, ki, Rk.t75, max(Rk.slip), fmtnan(Mk.settle), Mk.sse, Mk.osc, ...
                max(Rk.y), mark);
        end
    end
    sM = tcM;
    Rm = accel_tc_core(pM, sM, tyre, p.gear_current);
    fprintf('  -> at this map''s own gains, TC is worth %+.3f s over 75 m\n', ...
        Roff.t75 - Rm.t75);
end

%% ================= VALIDATION vs TODAY'S LOG =================
fprintf('\n=== VALIDATION ===\n');
fprintf('Logged standing launches (today, TC active) reached ~4.2-4.8 s over 75 m\n');
fprintf('by speed integration, hand-timed ~4.4 s. This sim: %.3f s.\n', R.t75);
fprintf('Slip behaviour in the log: peak ~7.6 at the launch instant (before the TC\n');
fprintf('speed gate opens), settling into 0.08-0.15 by ~0.8 s. This sim: peak %.2f,\n', max(R.slip));
fprintf('settling %s.\n', fmtnan(getfield(slip_metrics(R,tc.target_slip),'settle')));
fprintf('NOTE the log is 10 Hz and the controller runs at 100 Hz, so logged slip\n');
fprintf('peaks are undersampled -- the real peaks are higher than what was recorded.\n');

%% ================= FIGURES =================
fig = figure('Name','Accel + traction control','Position',[40 40 1080 620]);
tg = uitabgroup(fig);

ax = axes(uitab(tg,'Title','Slip vs time'));
plot(ax, R.t, R.slip, 'LineWidth',1.8); hold(ax,'on');
plot(ax, R0.t, R0.slip, '--', 'LineWidth',1.2);
yline(ax, tc.target_slip, 'k:', 'target', 'LineWidth',1.3);
xlabel(ax,'time (s)'); ylabel(ax,'rear axle slip'); grid(ax,'on');
legend(ax, {'TC on','TC off'}, 'Location','northeast');
ylim(ax,[0 min(2, max(0.5,max(R0.slip)))]);
title(ax, sprintf('Slip regulation (kp=%.3f ki=%.2f) -- does it settle on target?', tc.kp, tc.ki));

ax = axes(uitab(tg,'Title','Torque + reduction'));
yyaxis(ax,'left');
plot(ax, R.t, R.T_driver, ':', 'LineWidth',1.3); hold(ax,'on');
plot(ax, R.t, R.T_cmd, '-', 'LineWidth',1.8);
ylabel(ax,'motor torque (Nm)');
yyaxis(ax,'right'); plot(ax, R.t, R.y, 'LineWidth',1.4);
ylabel(ax,'TC reduction fraction y'); ylim(ax,[0 1]);
xlabel(ax,'time (s)'); grid(ax,'on');
legend(ax,{'driver demand','after TC','reduction y'},'Location','east');
title(ax,'How hard and how fast TC cuts');

ax = axes(uitab(tg,'Title','Speed + distance'));
yyaxis(ax,'left');  plot(ax, R.t, R.v*3.6, 'LineWidth',1.8); ylabel(ax,'speed (kph)');
yyaxis(ax,'right'); plot(ax, R.t, R.x, 'LineWidth',1.4); ylabel(ax,'distance (m)');
yline(ax, 75, 'k:', '75 m'); xlabel(ax,'time (s)'); grid(ax,'on');
title(ax, sprintf('0-75 m = %.3f s', R.t75));

ax = axes(uitab(tg,'Title','Gain sweep'));
kps = [sweep.kp]; t75s = [sweep.t75]; kis = [sweep.ki];
hold(ax,'on');
for ki = kiList
    m = kis == ki;
    plot(ax, kps(m), t75s(m), '-o', 'LineWidth',1.6, 'DisplayName', sprintf('ki = %.1f', ki));
end
xline(ax, 0.470, 'k--', 'shipped kp');
xlabel(ax,'kp'); ylabel(ax,'0-75 m (s)'); grid(ax,'on'); legend(ax,'Location','best');
title(ax,'0-75 m vs proportional gain');

save_tabfig(fig, fullfile('output','AccelTC'));
writetable(struct2table(sweep), 'output/accel_tc_gain_sweep.csv');
fprintf('\nSaved: output/accel_tc_gain_sweep.csv + 1 tabbed figure (4 tabs)\n');

%% ============================ LOCAL FUNCTIONS ============================
function M = slip_metrics(R, target)
%SLIP_METRICS  Settling / steady error / ringing on the slip trace.
    s = R.slip; t = R.t;
    ok = isfinite(s) & t > 0.05;
    s = s(ok); t = t(ok);
    M.settle = NaN;
    inb = abs(s - target) <= 0.02;
    for a = 1:numel(t)
        if inb(a)
            w = t >= t(a) & t <= t(a)+0.3;
            if all(inb(w)), M.settle = t(a); break; end
        end
    end
    tail = s(t >= max(t)-1.0);
    M.sse = mean(tail) - target;
    e = s - target;
    M.osc = sum(diff(sign(e)) ~= 0);
end

function s = fmtnan(x)
    if isnan(x), s = 'n/a'; else, s = sprintf('%.3f', x); end
end

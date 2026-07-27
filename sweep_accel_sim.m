function sweep_accel_sim()
%SWEEP_ACCEL_SIM  Sweep gear ratios through accel_sim.slx, print 0-75m times.
%   Builds the model first if it isn't loaded. Cross-check against
%   accel_model.m: 4.61:1 -> 4.80 s (was documented as ~4.72 s, which is the
%   4.80:1 row -- the old grid never contained 4.61 to check against).
    mdl = 'accel_sim';
    p = params_cfr26();                 % for the baseline ratio to restore on exit
    if ~bdIsLoaded(mdl)
        if isfile([mdl '.slx']), load_system(mdl); else, build_accel_simulink(); end
    end
    % Tell the model's StopFcn to stay quiet (no per-ratio plot/print) during the sweep,
    % and restore state on the way out. The onCleanup fires on EVERY exit path -- normal
    % finish, an error mid-loop, or a Ctrl-C -- so it (a) clears SWEEP_MODE and (b) resets
    % G_ratio to the baseline. Without (b) an interrupted sweep would leave G_ratio parked
    % on whatever ratio it died on (e.g. 5.20), and the next bare Run would silently give
    % that ratio's number instead of the real 4.61 car.
    assignin('base','SWEEP_MODE',true);
    cleanup = onCleanup(@() sweep_cleanup(p.gear_current));
    % Same ratio list as gear_ratio_optimization (params is the single source of
    % truth): 4.00-5.20 INCLUDING the current 4.61. The old 4.0:0.2:5.2 grid never
    % contained 4.61, so the sweep never actually simulated the car's own ratio.
    gears = p.gears_to_test(:)';
    t75s  = nan(size(gears));
    fprintf('\n=== accel_sim.slx: 0-75m by gear ratio ===\n');
    for i = 1:numel(gears)
        assignin('base','G_ratio',gears(i));
        out = sim(mdl);
        x = out.x_log; t = x.Time(find(x.Data>=75,1));
        if ~isempty(t), t75s(i) = t; end
        fprintf(' %.2f:1 -> 0-75m %.2f s\n', gears(i), t75s(i));
    end
    % Visual result: 0-75 m vs gear ratio (so the sweep shows something, not just text).
    figure('Name','accel_sim sweep');
    plot(gears, t75s, 'o-', 'LineWidth', 1.6); grid on; hold on;
    xline(p.gear_current, 'r--', sprintf('current %.2f', p.gear_current));
    xlabel('Gear ratio'); ylabel('0-75 m (s)');
    title('accel\_sim.slx: 0-75 m vs gear ratio (higher ratio = quicker off the line)');
end

function sweep_cleanup(baseline)
%SWEEP_CLEANUP  Restore base-workspace state after a sweep (any exit path).
    if evalin('base','exist(''SWEEP_MODE'',''var'')')
        evalin('base','clear SWEEP_MODE');
    end
    assignin('base','G_ratio', baseline);   % never leave the model on a stale swept ratio
end

function sweep_accel_sim()
%SWEEP_ACCEL_SIM  Sweep gear ratios through accel_sim.slx, print 0-75m times.
%   Builds the model first if it isn't loaded. Cross-check against
%   accel_model.m: 4.61:1 -> ~4.72 s.
    mdl = 'accel_sim';
    if ~bdIsLoaded(mdl)
        if isfile([mdl '.slx']), load_system(mdl); else, build_accel_simulink(); end
    end
    % Tell the model's StopFcn to stay quiet (no per-ratio plot/print) during the sweep.
    assignin('base','SWEEP_MODE',true);
    cleanup = onCleanup(@() evalin('base','clear SWEEP_MODE'));
    gears = 4.0:0.2:5.2;
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
    xline(4.61, 'r--', 'current 4.61');
    xlabel('Gear ratio'); ylabel('0-75 m (s)');
    title('accel\_sim.slx: 0-75 m vs gear ratio (higher ratio = quicker off the line)');
end

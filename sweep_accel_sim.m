function sweep_accel_sim()
%SWEEP_ACCEL_SIM  Sweep gear ratios through accel_sim.slx, print 0-75m times.
%   Builds the model first if it isn't loaded. Cross-check against
%   accel_model.m: 4.61:1 -> ~4.72 s.
    mdl = 'accel_sim';
    if ~bdIsLoaded(mdl)
        if isfile([mdl '.slx']), load_system(mdl); else, build_accel_simulink(); end
    end
    gears = 4.0:0.2:5.2;
    fprintf('\n=== accel_sim.slx: 0-75m by gear ratio ===\n');
    for G = gears
        assignin('base','G_ratio',G);
        out = sim(mdl);
        x = out.x_log; t75 = x.Time(find(x.Data>=75,1));
        if isempty(t75), t75 = NaN; end
        fprintf(' %.2f:1 -> 0-75m %.2f s\n', G, t75);
    end
end

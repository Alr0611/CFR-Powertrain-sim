function [t75, v, x, slip, y, Tcmd] = accel_tc_sample(clk)
%ACCEL_TC_SAMPLE  Scalar sampler for the Simulink block.
%   Runs lib/accel_tc_core.m ONCE, caches the trace, then returns the six
%   signals at time clk. Exists because a MATLAB Function block cannot size a
%   struct returned from an extrinsic call -- it can size six doubles.
%   Config comes from the base workspace (build_accel_tc_simulink puts it there),
%   so the Simulink run and the .m run share one set of gains.
    persistent R
    if isempty(R)
        p    = evalin('base','p');
        tc   = evalin('base','tcCfg');
        tyre = evalin('base','tyreCfg');
        G    = evalin('base','G');
        R    = accel_tc_core(p, tc, tyre, G);
    end
    k    = min(max(round(clk*2000)+1, 1), numel(R.v));
    t75  = R.t75;  v = R.v(k);  x = R.x(k);
    slip = R.slip(k);  y = R.y(k);  Tcmd = R.T_cmd(k);
end

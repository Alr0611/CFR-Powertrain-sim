function [t75, v, x, slip, y, Tcmd] = accel_tc_sweep_sample(clk)
%ACCEL_TC_SWEEP_SAMPLE  Scalar sampler for the TC SWEEP Simulink model.
%   Same job as lib/accel_tc_sample.m: run accel_tc_core once, cache it, hand Simulink one
%   sample per call. A MATLAB Function block can't size a struct from an extrinsic call
%   but can size six doubles.
%
%   Why it's separate: accel_tc_sample's cache only clears on an explicit
%   `clear accel_tc_sample`. Fine for one run, but a sweep runs the model dozens of times
%   and one missed clear gives you a table of plausible numbers that are all the same run.
%
%   This recomputes at clk == 0 instead. Every sim run starts at t = 0, so the trace is
%   always the current config's, and the base-workspace reads stay out of the per-step
%   path (they'd otherwise cost 4 evalin calls x ~14000 steps x ~90 runs).
    persistent R
    if isempty(R) || clk <= 0
        R = accel_tc_core(evalin('base','p'), evalin('base','tcCfg'), ...
                          evalin('base','tyreCfg'), evalin('base','G'));
    end
    k    = min(max(round(clk*2000)+1, 1), numel(R.v));
    t75  = R.t75;  v = R.v(k);  x = R.x(k);
    slip = R.slip(k);  y = R.y(k);  Tcmd = R.T_cmd(k);
end

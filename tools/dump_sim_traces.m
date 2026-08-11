function dump_sim_traces()
%DUMP_SIM_TRACES  Write sim traces to output/ for tools/rpm_vs_time_check.py to read.
%
%   dump_sim_traces
%
% Three variants so the size of each candidate lever is visible against the log:
%   base    as shipped
%   eta088  eta_drivetrain raised to 0.88, top of any defensible range
%   T150    driver torque cap lifted to the motor's 150 Nm datasheet peak
%
% Writes t, v, x, motor rpm and WHEEL rpm. The wheel column is the one the Python side
% compares against the undriven front wheels. Motor rpm is written too, but only so the
% comparison can show how much rear wheelspin inflates a motor-to-motor check.

    here = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(here,'lib'));
    if ~exist(fullfile(here,'output'),'dir'), mkdir(fullfile(here,'output')); end

    p = params_cfr26();
    tc = struct('enabled',true,'target_slip',0.10,'kp',0.470,'ki',0.0,'kd',0.110, ...
                'ilim',0.0,'maxlim',0.75,'ileak_ms',500,'rate_hz',100, ...
                'speed_gate',0.5,'emulate_firmware_pure_p',true);
    tyre = struct('mu_scale',1.00);
    G = p.gear_current;

    cases = {'base',   p.eta_drivetrain, p.T_driver_max; ...
             'eta088', 0.88,             p.T_driver_max; ...
             'T150',   p.eta_drivetrain, 150};

    for i = 1:size(cases,1)
        pp = p; pp.eta_drivetrain = cases{i,2}; pp.T_driver_max = cases{i,3};
        R = accel_tc_core(pp, tc, tyre, G);
        % wheel rpm straight from vehicle speed (no slip), which is what an undriven
        % front wheel would read. motor rpm includes the driven-wheel slip.
        wheel_rpm = R.v / pp.r_wheel * 60/(2*pi);
        rpm       = (R.slip .* max(R.v,0.10) + R.v) / pp.r_wheel * G * 60/(2*pi);
        T = table(R.t, R.v, R.x, rpm, wheel_rpm, ...
                  'VariableNames', {'t','v','x','rpm','wheel_rpm'});
        writetable(T, fullfile(here,'output',sprintf('sim_%s.csv', cases{i,1})));
        fprintf('%-8s t75 %.3f s | trap %.1f kph -> output/sim_%s.csv\n', ...
                cases{i,1}, R.t75, R.vtrap*3.6, cases{i,1});
    end
    fprintf('\nnow run: python tools/rpm_vs_time_check.py\n');
end

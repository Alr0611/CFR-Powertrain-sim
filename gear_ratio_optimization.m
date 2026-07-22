%% CFR26 GEAR RATIO OPTIMIZATION  --  "so what sprocket should we actually run?"
%
% Long story short
%   We drove the car. We recorded everything. Now the question is: what if we'd
%   been geared differently? This tries every ratio from 4.00 to 5.20 on the
%   SAME laps we actually drove, and reports what each one would've cost us.
%
% The trick 
%   Wheel speed doesn't care about gearing. The car went as fast as it went.
%   So we keep the real wheel speed, redo the motor math at each ratio, and
%   watch how much energy we'd have burned.
%
% Why does this code use 2 different runs?
%   Efficiency stuff  -> comp June 20. real comp track, better numbers.
%   Pack charge stuff -> July 11 test. Why not comp? Because comp DNF'd
%       (cell too hot yoikes), so it never reached the finish. You can't measure
%       "charge left at the end" on a run that didn't have an end.
%
% Rules
%   Numbers live in params_cfr26.m. Physics lives in lib/. Please don't put
%   either one in here.
%
% The accel column below is a quick-and-dirty estimate, good enough for
% comparing ratios. The real accel study (the one that counts spinning parts)
% is accel_model.m -- go there if accel is what you care about.

clear; clc; close all;
cd(fileparts(mfilename('fullpath')));   % run from the repo root so data/ and output/ paths resolve
addpath(fullfile(fileparts(mfilename('fullpath')), 'lib'));  % works wherever MATLAB is pointed
p = params_cfr26();

%% ---- LOAD DATA ----
D = readtable('data/endurance_july11_with_odo_wide.csv');   % July 11 (SOC + validation)
time      = D.t_s;
voltage   = D.BMSB_packVoltage / p.N_series;   % per-cell
I         = -(D.BMSB_packCurrent / p.N_parallel);   % per-cell, positive = discharge/motoring
motor_rpm = D.PM100DX_motorSpeed;
torque_fb = D.PM100DX_torqueFeedback;
wheel_rpm = mean([D.VCFRONT_wheelSpeedFL, D.VCFRONT_wheelSpeedFR, ...
                   D.VCREAR_wheelSpeedRL, D.VCREAR_wheelSpeedRR], 2);
N = length(time);
dt_vec = [diff(time); mean(diff(time))];
r_sign = corrcoef(motor_rpm, torque_fb);
if r_sign(1,2) < 0, torque_fb = -torque_fb; end   % positive torque = motoring
fprintf('July 11 (SOC source): %d samples, %.1f min\n', N, (time(end)-time(1))/60);

Dc = readtable('data/comp_june20_data.csv');   % Comp June 20 (efficiency source)
motor_rpm_c = Dc.PM100DX_motorSpeed;
torque_c    = Dc.PM100DX_torqueFeedback;
wheel_rpm_c = mean([Dc.VCFRONT_wheelSpeedFL, Dc.VCFRONT_wheelSpeedFR, ...
                    Dc.VCREAR_wheelSpeedRL, Dc.VCREAR_wheelSpeedRR], 2);
dt_vec_c = [diff(Dc.t_s); median(diff(Dc.t_s))];
% NaN-proof sign fix: comp logs motoring torque negative -> net torque*rpm < 0.
if sum(torque_c .* motor_rpm_c, 'omitnan') < 0, torque_c = -torque_c; end
rmse_c = sqrt(mean((wheel_rpm_c*p.gear_current - motor_rpm_c).^2, 'omitnan'));
fprintf('Comp (efficiency source): %d samples, %.1f min | RMSE(wheel*%.2f vs motor)=%.1f rpm\n', ...
    height(Dc), Dc.t_s(end)/60, p.gear_current, rmse_c);

%% ---- BATTERY MODEL VALIDATION (July 11) ----
rc = p.rc;
rc.SOC0 = interp1(p.rc.OCV_lookup, p.rc.SOC_lookupR, voltage(1), 'linear', 'extrap');
bms_soc = D.BMSB_packSOC;
fprintf('Initial SOC: %.1f%% from rest voltage (%.3f V/cell) | BMS %.1f%%\n', ...
    rc.SOC0*100, voltage(1), bms_soc(1));

[SOC_openloop, Vs_openloop] = run_open_loop(I, dt_vec, rc);
print_err('Open-loop RC', Vs_openloop - voltage);

% Extended Kalman Filter (voltage-corrected SOC)
Q_noise = [7e-8 0 0; 0 6e-5 0; 0 0 6e-5]; R_noise = 0.2;
Pcov = [1e-4 0 0; 0 1e-4 0; 0 0 1e-4];
dOCV = gradient(p.rc.OCV_lookup, p.rc.SOC_lookupR);
X = [rc.SOC0; 0; 0]; Vs_kf = zeros(N,1); SOC_kf = zeros(N,1);
for k = 1:N
    dt = dt_vec(k); SOC = X(1);
    if I(k) < 0, sfx='_c'; else, sfx='_d'; end
    Ri = interp1(p.rc.SOC_lookupR, p.rc.(['Ri' sfx]), 1-SOC, 'linear', 'extrap');
    R1 = interp1(p.rc.SOC_lookupR, p.rc.(['R1' sfx]), 1-SOC, 'linear', 'extrap');
    R2 = interp1(p.rc.SOC_lookupR, p.rc.(['R2' sfx]), 1-SOC, 'linear', 'extrap');
    C1 = interp1(p.rc.SOC_lookupR, p.rc.(['C1' sfx]), 1-SOC, 'linear', 'extrap');
    C2 = interp1(p.rc.SOC_lookupR, p.rc.(['C2' sfx]), 1-SOC, 'linear', 'extrap');
    tao1 = R1*C1; tao2 = R2*C2;
    V_R1 = exp(-dt/tao1)*X(2) + R1*(1-exp(-dt/tao1))*I(k);
    V_R2 = exp(-dt/tao2)*X(3) + R2*(1-exp(-dt/tao2))*I(k);
    VOCV = interp1(p.rc.SOC_lookupR, p.rc.OCV_lookup, X(1), 'linear', 'extrap');
    Ut = VOCV - V_R1 - V_R2 - I(k)*Ri;
    A = [1 0 0; 0 exp(-dt/tao1) 0; 0 0 exp(-dt/tao2)];
    B = [-dt/p.Q_cell; R1*(1-exp(-dt/tao1)); R2*(1-exp(-dt/tao2))];
    X = A*X + B*I(k); Pcov = A*Pcov*A' + Q_noise;
    dOCV_v = interp1(p.rc.SOC_lookupR, dOCV, X(1), 'linear', 'extrap');
    H = [dOCV_v, -1, -1];
    K1 = Pcov*H' / (H*Pcov*H' + R_noise);
    X = X + K1*(voltage(k) - Ut); Pcov = (eye(3) - K1*H)*Pcov;
    Vs_kf(k) = Ut; SOC_kf(k) = X(1);
end
print_err('Kalman', Vs_kf - voltage);
fprintf('Final SOC three ways: open-loop %.1f%% | Kalman %.1f%% | BMS %.1f%%\n', ...
    SOC_openloop(end)*100, SOC_kf(end)*100, bms_soc(end));
dcc = (rc.SOC0 - SOC_openloop(end))*100; dbms = bms_soc(1) - bms_soc(end);
fprintf('Energy throughput: coulomb dSOC=%.1f pts vs BMS dSOC=%.1f pts\n', dcc, dbms);

%% ---- GEAR RATIO SWEEP ----
% Efficiency from comp (scale measured motor op-point by ratio change; clean).
% SOC from July 11 (rescale measured current by the electrical-power delta).
P_shaft_old = torque_fb .* motor_rpm * (2*pi/60);            % July 11 shaft power
eff_old     = emrax208_efficiency(abs(motor_rpm), abs(torque_fb), p);
P_elec_old  = motoring_regen_power(P_shaft_old, eff_old);
P_wheel = zeros(size(P_shaft_old)); fwd = P_shaft_old >= 0;
P_wheel(fwd)  = P_shaft_old(fwd)  .* p.eta_drivetrain;
P_wheel(~fwd) = P_shaft_old(~fwd) ./ p.eta_drivetrain;

gears = p.gears_to_test; ng = numel(gears);
R = struct('ratio',{},'avg_eff',{},'hi_eff',{},'SOC',{},'SOC98',{}, ...
           'accel',{},'accel_hi',{},'accel_lo',{},'top_kph',{}, ...
           'infeas_T',{},'infeas_rpm',{});
op_points = struct('ratio',{},'rpm',{},'torque',{});
rc98 = rc; rc98.SOC0 = 0.98; soc_curves = cell(1,ng);
fprintf('\n=== Endurance + Efficiency Breakdown by Gear Ratio ===\n');
for i = 1:ng
    g = gears(i);

    % --- EFFICIENCY + from COMP (scale measured) ---
    rs = g / p.gear_current;
    rpm_c   = motor_rpm_c * rs;
    tq_c    = torque_c / rs;
    Ps_c    = tq_c .* rpm_c * (2*pi/60);
    eff_c   = emrax208_efficiency(abs(rpm_c), abs(tq_c), p);
    Pe_c    = motoring_regen_power(Ps_c, eff_c);
    act_c   = Ps_c > 1000;
    if any(act_c)
        mech = sum(Ps_c(act_c).*dt_vec_c(act_c));
        avg_eff = sum(Ps_c(act_c).*dt_vec_c(act_c)) / sum(Pe_c(act_c).*dt_vec_c(act_c)) * 100;
        insw = act_c & (eff_c >= p.eff_sweet);
        hi_eff = 100 * sum(Ps_c(insw).*dt_vec_c(insw)) / mech;
    else
        avg_eff = mean(eff_c)*100; hi_eff = 0;
    end
    op_points(i) = struct('ratio',g,'rpm',abs(rpm_c(act_c)),'torque',abs(tq_c(act_c)));

    % --- SOC from JULY 11 (rescale current by electrical-power ratio) ---
    rpm_new = wheel_rpm * g;
    Ps_new  = motoring_regen_power(P_wheel, p.eta_drivetrain);
    om_new  = rpm_new * (2*pi/60); tq_new = zeros(size(Ps_new));
    nz = om_new > 1e-3; tq_new(nz) = Ps_new(nz) ./ om_new(nz);
    eff_new = emrax208_efficiency(abs(rpm_new), abs(tq_new), p);
    Pe_new  = motoring_regen_power(Ps_new, eff_new);
    active  = Ps_new > 1000;
    scale = ones(size(P_elec_old)); vld = abs(P_elec_old) > 1;
    scale(vld) = Pe_new(vld) ./ P_elec_old(vld);
    I_new = I .* scale; I_new = max(min(I_new, max(I)*1.5), min(I)*1.5);
    [SOC_new, ~]   = run_open_loop(I_new, dt_vec, rc);
    [SOC_new98, ~] = run_open_loop(I_new, dt_vec, rc98);
    soc_curves{i}  = SOC_new;

    % Feasibility: does July 11 trace stay within motor limits at this ratio?
    T_env = min(p.T_flat_cap, interp1(p.Prpm, p.Pkw, min(abs(rpm_new),p.redline), ...
        'linear','extrap') * 9549 ./ max(abs(rpm_new),50));
    infeas_T   = 100 * sum(active & abs(tq_new) > T_env) / max(sum(active),1);
    infeas_rpm = 100 * sum(active & abs(rpm_new) > p.redline) / max(sum(active),1);

    % --- Accel (quick proxy) + grip band + top speed ---
    tir_hi = p.tir; tir_hi.LMUX = p.tir.LMUX*1.15;
    tir_lo = p.tir; tir_lo.LMUX = p.tir.LMUX*0.85;
    accel    = accel_075m(g, p.tir, p);
    accel_hi = accel_075m(g, tir_hi, p);
    accel_lo = accel_075m(g, tir_lo, p);
    top_kph  = top_speed(g, p) * 3.6;

    R(i) = struct('ratio',g,'avg_eff',avg_eff,'hi_eff',hi_eff,'SOC',SOC_new(end)*100, ...
        'SOC98',SOC_new98(end)*100,'accel',accel,'accel_hi',accel_hi,'accel_lo',accel_lo, ...
        'top_kph',top_kph,'infeas_T',infeas_T,'infeas_rpm',infeas_rpm);
    fprintf(' %5.2f:1 -> Eff=%5.1f%% | HiEff=%5.1f%% | SOC=%5.2f%% | 0-75m=%5.2fs | Top=%5.1f kph\n', ...
        g, avg_eff, hi_eff, R(i).SOC, accel, top_kph);
end

%% ---- COMPARISON TABLE ----
icur = find(abs([R.ratio]-p.gear_current) < 1e-6, 1);
fprintf('\n================ GEAR RATIO COMPARISON (efficiency: comp | SOC: July 11) ================\n');
fprintf(' Ratio  AvgEff  HiEff%%  FinalSOC   0-75m [nom (hi-lo mu)]  Top    | vs 4.61: dSOC dHiEff dAccel\n');
for i = 1:ng
    tag = '  '; if i==icur, tag='>>'; end
    fprintf('%s %4.2f   %5.1f  %5.1f   %5.2f    %5.2f (%4.2f-%4.2f)  %5.1f  | %+5.2f %+6.1f %+5.2f\n', ...
        tag, R(i).ratio, R(i).avg_eff, R(i).hi_eff, R(i).SOC, R(i).accel, R(i).accel_hi, R(i).accel_lo, ...
        R(i).top_kph, R(i).SOC-R(icur).SOC, R(i).hi_eff-R(icur).hi_eff, R(i).accel-R(icur).accel);
end
fprintf(' RANGE  %4.1f-%4.1f %4.1f-%4.1f %4.2f-%4.2f  %4.2f-%4.2f            %5.1f-%5.1f\n', ...
    min([R.avg_eff]),max([R.avg_eff]), min([R.hi_eff]),max([R.hi_eff]), ...
    min([R.SOC]),max([R.SOC]), min([R.accel_hi]),max([R.accel_lo]), min([R.top_kph]),max([R.top_kph]));
fprintf(' 98%%-start final SOC: %.1f%% (4.20) ... %.1f%% (4.61) ... %.1f%% (5.20)\n', ...
    R(abs([R.ratio]-4.20)<0.01).SOC98, R(icur).SOC98, R(abs([R.ratio]-5.20)<0.01).SOC98);
fprintf(' Accel band = +/-15%% longitudinal-mu uncertainty (Calspan ran no long. sweep).\n');
fprintf(' Eff/AvgEff = motor+inverter (physics model x eta_inverter) at each ratio''s operating\n');
fprintf('   points -- for RANKING ratios; a mild optimistic bound. MEASURED as-driven over\n');
fprintf('   endurance is ~78%%. Full battery->ground stack + per-stage: drivetrain_efficiency.m\n');
fprintf('=======================================================================================\n');

%% ================= FIGURES (4) =================
lib_figs(R, op_points, gears, soc_curves, time, voltage, Vs_kf, ...
    SOC_openloop, SOC_kf, bms_soc, p);

%% ---- EXPORT ----
writetable(struct2table(R), 'output/gear_ratio_results.csv');
fprintf('\nSaved: output/gear_ratio_results.csv + 2 figure windows (dashboard + operating-points map)\n');
fprintf('DATA: tire mu DERIVED (not measured); aero from Ford wind tunnel + aero lead;\n');
fprintf('chassis from tilt test; battery from HPPC. Remaining estimates: Crr, wheel k-factor.\n');

%% ---- LOCAL HELPERS ----
function print_err(name, err)
    ae = abs(err);
    fprintf('%s: RMSE=%.4f V | Mean=%.4f | P95=%.4f | Max=%.4f V\n', ...
        name, sqrt(mean(err.^2)), mean(err), prctile(ae,95), max(ae));
end

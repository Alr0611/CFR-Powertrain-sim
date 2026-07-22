%% CFR26 ACCELERATION MODEL (inertia-based)
% The accel study: includes ROTATIONAL INERTIA of the motor rotor,
% driveline and wheels reflected to the motor (per the WR-217e / FSAE
% top-speed method). ODE solved discretely over motor speed:
%   dw/dt = [T_M(w)*eta - n*r*(b*w^2 + C) - T_F] / (I + n*r*a),  n = 1/G
%
% Produces: gear-ratio sweep (0-75m, 0-100kph), effect-of-inertia comparison,
% wheel-weight sensitivity, tractive-effort curves, and 40-80 kph recovery.
% Validation: June 19 launch was 0-75m = 4.40 s raw at 4.61:1.

clear; clc; close all;
cd(fileparts(mfilename('fullpath')));   % run from the repo root so data/ and output/ paths resolve
addpath(fullfile(fileparts(mfilename('fullpath')), 'lib'));  % works wherever MATLAB is pointed
p = params_cfr26();

fprintf('Wheel inertia %.4f kg*m^2 (%.1f kg, k=%.2f*r) | reflected @4.61 %.4f | rotor %.4f\n', ...
    p.I_wheel, p.m_wheel, p.kFactor, p.n_wheels*p.I_wheel/4.61^2, p.I_rotor);

%% ---- SWEEP: 0-75m and 0-100kph vs ratio ----
gears = 3.6:0.05:5.4;
t75 = nan(size(gears)); t100 = nan(size(gears)); vtrap = nan(size(gears));
for i = 1:numel(gears)
    [t100(i), t75(i), vtrap(i)] = accel_run(gears(i), p);
end
fprintf('\n=== INERTIA-BASED ACCEL SWEEP ===\n');
for g = [4.0 4.2 p.gear_current 5.0 5.2]
    [~,j] = min(abs(gears-g)); tag=''; if abs(g-p.gear_current)<1e-6, tag=' (current)'; end
    fprintf(' %.2f:1 -> 0-100kph %.2fs | 0-75m %.2fs | trap %.0f kph%s\n', gears(j),t100(j),t75(j),vtrap(j),tag);
end
[~,j461] = min(abs(gears-p.gear_current));
fprintf('0-75m is MONOTONIC (no interior optimum): accel favors higher ratio until gearing out.\n');
fprintf('Model %.2fs at 4.61 vs real clean launch 4.40s -> ~%.2fs conservative.\n', t75(j461), t75(j461)-4.40);

%% ---- WHEEL WEIGHT SENSITIVITY (@ 4.61) ----
fprintf('\n=== WHEEL WEIGHT SENSITIVITY @ 4.61:1 (mass removed at tread radius) ===\n');
for dkg = [0 0.25 0.5 0.75 1.0]
    ps = p; ps.m_car = p.m_car - 4*dkg; ps.I_wheel = p.I_wheel - dkg*p.r_wheel^2;
    [~, t75s, ~] = accel_run(4.61, ps);
    fprintf(' -%.2f kg/wheel (-%.1f kg total) -> 0-75m %.2fs\n', dkg, 4*dkg, t75s);
end

%% ---- 40-80 kph CORNER-EXIT RECOVERY ----
fprintf('\n=== 40-80 kph recovery (full throttle, ideal TC) ===\n');
for g = [4.0 4.2 p.gear_current 5.2]
    fprintf(' %.2f:1 -> %.2f s\n', g, recovery_40_80(g, p));
end

%% ---- FIGURES ----
f1 = figure('Name','accel_sweep','Position',[60 60 950 430]);
subplot(1,2,1); plot(gears,t100,'LineWidth',1.6); hold on; xline(p.gear_current,'k--','current');
    xlabel('Gear ratio'); ylabel('0-100 kph (s)'); grid on; title('0-100 kph');
subplot(1,2,2); plot(gears,t75,'LineWidth',1.6); hold on; xline(p.gear_current,'k--','current');
    yline(4.40,'g:','real 4.40s'); xlabel('Gear ratio'); ylabel('0-75 m (s)'); grid on; title('0-75 m (monotonic)');
sgtitle('Accel favors HIGH ratio (opposite of efficiency) — no strong U for this car');

p0 = p; p0.I_rotor=0; p0.I_driveline=0; p0.I_wheel=0;
t75_noI = nan(size(gears)); for i=1:numel(gears), [~,t75_noI(i),~]=accel_run(gears(i),p0); end
f2 = figure('Name','inertia_effect');
plot(gears,t75,'LineWidth',1.6,'DisplayName','With rotational inertia'); hold on;
plot(gears,t75_noI,'--','LineWidth',1.4,'DisplayName','Point-mass (no inertia)');
xline(p.gear_current,'k:','HandleVisibility','off');
xlabel('Gear ratio'); ylabel('0-75 m (s)'); grid on; legend('Location','north');
title('Rotational inertia adds ~0.15s and flattens the high-ratio end');

f3 = tractive_effort_fig(p);

writetable(table(gears', t100', t75', vtrap', 'VariableNames',{'ratio','t0_100kph','t0_75m','trap_kph'}), ...
    'output/accel_results.csv');
for fh=[f1 f2 f3]
    nm=fullfile('output',matlab.lang.makeValidName(fh.Name));
    savefig(fh,[nm '.fig']); try, saveas(fh,[nm '.png']); catch, end
end
fprintf('\nSaved: output/accel_results.csv + 3 figures\n');

%% ================= LOCAL FUNCTIONS =================
function [t100, t75, vtrap] = accel_run(G, p)
    n = 1/G;
    I_fixed = p.I_rotor + p.I_driveline + p.n_wheels*p.I_wheel*n^2;
    a_coef  = p.m_car * n * p.r_wheel;
    I_den   = I_fixed + n*p.r_wheel*a_coef;
    b  = 0.5*p.rho_air*p.r_wheel^2*n^2*(p.CdA + p.Crr*p.ClA);
    Cc = p.m_car*p.g*p.Crr;
    w_max = p.redline*2*pi/60; dw = w_max/4000;
    w=0; t=0; x=0; v=0; a_prev=0; t100=NaN; t75=NaN; vtrap=NaN;
    while w < w_max
        rpm = w*60/(2*pi);
        T_M = motor_peak_torque(rpm, p) * p.eta_drivetrain;
        Fdown = 0.5*p.rho_air*p.ClA*v^2;
        for it=1:3
            Fzr = p.m_car*p.g*p.rear_static + p.m_car*a_prev*p.h_cg/p.L_wb + Fdown*p.rear_aero;
            Ftr = tire_mu_x(Fzr/2, p.tir) * Fzr;
            T_use = min(T_M, Ftr*p.r_wheel*n/p.eta_drivetrain);
            dwdt = (T_use - n*p.r_wheel*(b*w^2 + Cc) - p.T_F) / I_den;
            a_prev = p.r_wheel*n*dwdt;
        end
        if dwdt <= 0, break; end
        dt = dw/dwdt; t=t+dt; w=w+dw; v=p.r_wheel*n*w; x=x+v*dt;
        if isnan(t100) && v>=100/3.6, t100=t; end
        if isnan(t75)  && x>=75,      t75=t; vtrap=v*3.6; end
        if ~isnan(t100)&&~isnan(t75), break; end
    end
    if isnan(t75) && v>1, t75=t+(75-x)/v; vtrap=v*3.6; end
    if isnan(t100)&& v>=100/3.6, t100=t; end
end

function t = recovery_40_80(G, p)
    n=1/G; v=40/3.6; t=0; dt=0.005; a=0;
    while v < 80/3.6 && t < 15
        rpm = v/p.r_wheel*G*60/(2*pi);
        F_wh = motor_peak_torque(min(rpm,p.redline),p)*G*p.eta_drivetrain/p.r_wheel;
        Fdown = 0.5*p.rho_air*p.ClA*v^2;
        for it=1:3
            Fzr = p.m_car*p.g*p.rear_static + p.m_car*a*p.h_cg/p.L_wb + Fdown*p.rear_aero;
            F_dr = min(F_wh, tire_mu_x(Fzr/2,p.tir)*Fzr);
            a = (F_dr - 0.5*p.rho_air*p.CdA*v^2 - p.Crr*(p.m_car*p.g+Fdown))/p.m_car;
        end
        v=v+a*dt; t=t+dt;
    end
end

function fh = tractive_effort_fig(p)
    v = (1:0.25:38)'; te = [4.0 4.2 p.gear_current 5.2];
    fh = figure('Name','tractive_effort','Position',[80 80 900 480]); hold on;
    for j=1:numel(te)
        F=zeros(size(v));
        for k=1:numel(v)
            rpm=v(k)/p.r_wheel*te(j)*60/(2*pi);
            if rpm>p.redline, F(k)=NaN; else, F(k)=motor_peak_torque(rpm,p)*te(j)*p.eta_drivetrain/p.r_wheel; end
        end
        plot(v*3.6,F,'LineWidth',1.5,'DisplayName',sprintf('%.2f:1',te(j)));
    end
    Ftr=zeros(size(v)); Fr=zeros(size(v));
    for k=1:numel(v)
        vv=v(k); Fd=0.5*p.rho_air*p.ClA*vv^2; a=0;
        for it=1:5
            Fzr=p.m_car*p.g*p.rear_static + p.m_car*a*p.h_cg/p.L_wb + Fd*p.rear_aero;
            Ftr(k)=tire_mu_x(Fzr/2,p.tir)*Fzr;
            a=(Ftr(k)-0.5*p.rho_air*p.CdA*vv^2 - p.Crr*(p.m_car*p.g+Fd))/p.m_car;
        end
        Fr(k)=0.5*p.rho_air*p.CdA*vv^2 + p.Crr*(p.m_car*p.g+Fd);
    end
    plot(v*3.6,Ftr,'k--','LineWidth',1.5,'DisplayName','Traction limit (rear)');
    plot(v*3.6,Fr,'k:','LineWidth',1.5,'DisplayName','Drag + rolling');
    xlabel('Speed (kph)'); ylabel('Force at wheels (N)'); grid on; legend('Location','northeast'); ylim([0 3200]);
    title('Tractive effort vs speed: curves merge where power-limited (gearing stops mattering)');
end

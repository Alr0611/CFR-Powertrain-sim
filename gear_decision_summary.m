%% GEAR_DECISION_SUMMARY  One table with every trade axis, for the ratio decision meeting.
%
%   gear_decision_summary
%
% Pulls the four things that actually compete into one place:
%   accel        0-75 m at the car's REAL 123 Nm ceiling
%   top speed    redline-limited, since that is what binds at every ratio here
%   efficiency   % of real motoring time in the sweet spot, from comp telemetry
%   driveability road speed at the torque knee, which is the driver complaint
%
% Plus the sprocket combinations that can actually produce each ratio, because the ratio
% is not a free variable. It is two integers.
%
% Efficiency numbers come from the physics model, which is optimistic in absolute terms.
% Used here only to COMPARE ratios, where the bias is common to all of them and cancels.

clear; clc; close all;
here = fileparts(mfilename('fullpath')); cd(here);
addpath(fullfile(here,'lib'));
p = params_cfr26();

SPUR_DRIVER = 15; SPUR_DRIVEN = 30;      % on the motor shaft -> intermediate
CHAIN_DRIVER = 13; CHAIN_DRIVEN = 30;    % intermediate -> diff. THIS is what we change.
spur = SPUR_DRIVEN/SPUR_DRIVER;

fprintf('=== HOW THE RATIO IS BUILT ===\n');
fprintf('  spur  %d/%d = %.4f   (fixed unless the housing changes)\n', ...
    SPUR_DRIVEN, SPUR_DRIVER, spur);
fprintf('  chain %d/%d = %.4f   (this is the knob)\n', ...
    CHAIN_DRIVEN, CHAIN_DRIVER, CHAIN_DRIVEN/CHAIN_DRIVER);
fprintf('  total       = %.4f\n\n', spur*CHAIN_DRIVEN/CHAIN_DRIVER);

%% ---------- what ratios are actually buildable ----------
fprintf('=== BUILDABLE RATIOS, keeping the 15/30 spur ===\n');
fprintf('  G = 2.000 x (driven/driver). Only integer sprockets exist.\n\n');
% Bigger sprockets are better: chain tension is torque/radius, so a small driver runs
% higher link load, worse wrap angle and shorter chain life. 12T on 520 is about the
% practical floor. So list EVERY combo near each target and sort by driver size, do not
% silently return the first one found.
fprintf('  %6s %8s %8s %10s %12s  %s\n','driver','driven','G','vs 4.615','centre @60L','note');
pitch = 12.7; links = 60;      % 520 chain, nominal loop
cdist = @(zp,zd) pitch/8*((2*links - zd - zp) + ...
                 sqrt((2*links - zd - zp)^2 - 8*((zd-zp)/pi)^2));
for tgt = [4.00 4.20 4.40 4.6154 4.80 5.00 5.20]
    cands = struct('G',{},'zd',{},'zp',{});
    for zp = 16:-1:12
        for zd = 24:44
            G = spur*zd/zp;
            if abs(G-tgt)/tgt < 0.012
                cands(end+1) = struct('G',G,'zd',zd,'zp',zp); %#ok<SAGROW>
            end
        end
    end
    if isempty(cands), continue; end
    [~,ix] = sort([cands.zp],'descend'); cands = cands(ix);
    for i = 1:min(2,numel(cands))
        b = cands(i);
        n = '';
        if b.zp <= 12, n = 'driver too small, chain life'; end
        if abs(b.G-4.6154) < 1e-3, n = 'CURRENT'; end
        if i == 2, n = ['alt: ' n]; end
        fprintf('  %6d %8d %8.3f %+9.2f%% %10.1f mm  %s\n', ...
            b.zp, b.zd, b.G, 100*(b.G/4.6154-1), cdist(b.zp,b.zd), n);
    end
end
fprintf('\n  centre @60L = centre distance a fixed 60-link chain would need. It MOVES with\n');
fprintf('  sprocket size, so any ratio change is a packaging change too, not a bolt-on.\n');

%% ---------- the trade table ----------
tc = struct('enabled',true,'target_slip',0.10,'kp',0.470,'ki',0.0,'kd',0.110, ...
            'ilim',0.0,'maxlim',0.75,'ileak_ms',500,'rate_hz',100, ...
            'speed_gate',0.5,'emulate_firmware_pure_p',true);
ty.mu_scale = 1.00;

% efficiency + knee, straight out of peak_operating_point's method
D = readtable('data/comp_june20_data.csv');
wheelRpm = mean([D.VCFRONT_wheelSpeedFL, D.VCFRONT_wheelSpeedFR, ...
                 D.VCREAR_wheelSpeedRL,  D.VCREAR_wheelSpeedRR], 2, 'omitnan');
mRpm = D.PM100DX_motorSpeed; mTq = D.PM100DX_torqueFeedback;
if median(mTq(mRpm > 1000),'omitnan') < 0, mTq = -mTq; end
motoring = mRpm > 500 & wheelRpm > 50 & mTq > 2;
wRpm_m = wheelRpm(motoring); wTq_m = mTq(motoring)*p.gear_current;
hiDemand = wTq_m >= prctile(wTq_m, 90);
rpmGrid = 100:25:p.redline;
T_env   = arrayfun(@(r) motor_peak_torque(r,p), rpmGrid);
knee    = rpmGrid(find(T_env < p.T_flat_cap - 0.5, 1));

fprintf('\n=== THE TRADE ===\n');
fprintf('  %6s %9s %10s %9s %9s %11s %9s\n', ...
    'ratio','0-75m s','vs cur','topSpd','sweet%','kneeKPH','exitPast%');
G = [4.00 4.20 4.40 4.6154 4.80 5.00 5.20];
t0 = NaN;
S = struct('G',{},'t75',{},'vtop',{},'sweet',{},'kneeKph',{},'exitPast',{},'infeas',{});
for g = G
    R = accel_tc_core(p, tc, ty, g);
    vtop = (p.redline/g)*(2*pi/60)*p.r_wheel*3.6;
    rN = wRpm_m*g; tN = wTq_m/g;
    envN = arrayfun(@(r) motor_peak_torque(min(r,p.redline),p), rN);
    infeas = (rN > p.redline) | (tN > envN + 1e-9);
    eN = emrax208_efficiency(rN, tN, p); eN(infeas) = NaN;
    kneeKph = knee/g*(2*pi/60)*p.r_wheel*3.6;
    if abs(g-4.6154) < 1e-6, t0 = R.t75; end
    S(end+1) = struct('G',g,'t75',R.t75,'vtop',vtop, ...
        'sweet',100*mean(eN >= p.eff_sweet,'omitnan'), 'kneeKph',kneeKph, ...
        'exitPast',100*mean(rN(hiDemand) > knee), 'infeas',100*mean(infeas)); %#ok<SAGROW>
end
for s = S
    mark = ''; if abs(s.G-4.6154) < 1e-6, mark = '  <- CURRENT'; end
    fprintf('  %6.3f %9.3f %+9.3f %8.1f %9.1f %10.1f %9.1f%s\n', ...
        s.G, s.t75, s.t75-t0, s.vtop, s.sweet, s.kneeKph, s.exitPast, mark);
end
fprintf('\n  0-75m      at the REAL 123 Nm ceiling the car requests, not the 150 datasheet\n');
fprintf('  topSpd     redline-limited kph. Binds before drag at every ratio here.\n');
fprintf('  sweet%%     %% of real motoring time at motor eff >= %.0f%%\n', 100*p.eff_sweet);
fprintf('  kneeKPH    road speed where torque starts falling. Driver "it dies" number.\n');
fprintf('  exitPast%%  %% of corner exits already past the knee\n');

%% ---------- points-weighted view ----------
fprintf('\n=== WHAT IT IS WORTH, FSAE ELECTRIC POINTS ===\n');
fprintf('  Accel 100 | Skidpad 75 | Autocross 125 | Endurance 275 | Efficiency 100\n');
fprintf('  Endurance + Efficiency = 375 pts. Accel = 100 pts.\n');
fprintf('  Accel scoring is relative to the field best, so 0.06 s is worth ~1-2 pts.\n');
fprintf('  Efficiency scoring is relative to field energy use, where a few %% is real.\n');
fprintf('\n  So: do NOT trade endurance efficiency for a hundredth in accel.\n');

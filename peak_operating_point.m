%% PEAK_OPERATING_POINT  Where the motor is good, where the car actually ran, what gearing moves.
%
%   peak_operating_point
%
% Four questions, in order:
%   1. Where is the motor EFFICIENT?        rpm x torque -> efficiency
%   2. Where is the motor STRONG?           torque knee, peak power, rolloff
%   3. Where did the car ACTUALLY operate?  comp telemetry, overlaid on 1 and 2
%   4. What does GEAR RATIO do to that?     re-map the same driving to other ratios
%
% Q4 is the one that matters. It turns "4.2 should feel better" into "X% of motoring time
% moves out of the power-limited region", which is an argument you can defend.
%
% READ BEFORE QUOTING AN EFFICIENCY NUMBER FROM THIS. The efficiency surface is the
% PHYSICS MODEL (lib/emrax208_efficiency.m) and it is optimistic: at loaded points it says
% ~91-92% where telemetry measured 85.2%. p.eta_inverter was itself chosen to make the
% model agree with a measured number, so agreement here is partly calibration agreeing
% with itself. Use this to compare REGIONS and RATIOS, where the bias is common to every
% case and cancels. Do not quote an absolute efficiency off it.

clear; clc; close all;
here = fileparts(mfilename('fullpath')); cd(here);
if ~exist('output','dir'), mkdir('output'); end
addpath(fullfile(here,'lib'));
p = params_cfr26();

%% ======================= 1. EFFICIENCY MAP =======================
rpmGrid = 100:25:p.redline;
tqGrid  = 2:1:p.T_flat_cap;
[RPM, TQ] = meshgrid(rpmGrid, tqGrid);
EFF = emrax208_efficiency(RPM, TQ, p);

% Mask what the motor cannot hold. Without this the headline peak lands at
% 6000 rpm / 150 Nm = 94 kW, which the 68 kW power curve forbids.
T_env = arrayfun(@(r) motor_peak_torque(r, p), rpmGrid);
FEAS  = TQ <= repmat(T_env, numel(tqGrid), 1);
EFF_f = EFF; EFF_f(~FEAS) = NaN;

[bestEff, k] = max(EFF_f(:), [], 'omitnan');
[bi, bj] = ind2sub(size(EFF_f), k);
fprintf('=== 1. EFFICIENCY MAP (physics model, see header) ===\n');
fprintf('  peak INSIDE the envelope : %.1f%% at %d rpm, %d Nm (%.1f kW)\n', ...
    100*bestEff, rpmGrid(bj), tqGrid(bi), tqGrid(bi)*rpmGrid(bj)*2*pi/60/1000);
[uBest, ku] = max(EFF(:));
[ui, uj] = ind2sub(size(EFF), ku);
fprintf('  peak IGNORING the envelope: %.1f%% at %d rpm, %d Nm (%.1f kW) <- NOT reachable\n', ...
    100*uBest, rpmGrid(uj), tqGrid(ui), tqGrid(ui)*rpmGrid(uj)*2*pi/60/1000);

sweetMask = FEAS & (EFF >= p.eff_sweet);
fprintf('  sweet spot (eff >= %.0f%%) covers %.1f%% of the reachable rpm-torque area\n', ...
    100*p.eff_sweet, 100*sum(sweetMask(:))/sum(FEAS(:)));
colsIn = any(sweetMask,1); rowsIn = any(sweetMask,2);
fprintf('  and it spans %d-%d rpm, %d-%d Nm\n', ...
    rpmGrid(find(colsIn,1)), rpmGrid(find(colsIn,1,'last')), ...
    tqGrid(find(rowsIn,1)), tqGrid(find(rowsIn,1,'last')));

%% ======================= 2. TORQUE AND POWER ENVELOPE =======================
P_env_kW = T_env .* rpmGrid * 2*pi/60 / 1000;
[peakPower, kp_] = max(P_env_kW);
knee     = rpmGrid(find(T_env < p.T_flat_cap  - 0.5, 1));   % flat cap stops binding
kneeDrv  = rpmGrid(find(T_env < p.T_driver_max - 0.5, 1));  % same, at the VC ceiling
fprintf('\n=== 2. TORQUE AND POWER ENVELOPE ===\n');
fprintf('  peak torque   %.0f Nm, flat from 0 to %d rpm\n', p.T_flat_cap, knee);
fprintf('  TORQUE KNEE   %d rpm   <- past here torque falls as P/omega\n', knee);
fprintf('  peak power    %.1f kW at %d rpm\n', peakPower, rpmGrid(kp_));
fprintf('  at redline    %.0f Nm, %.1f kW\n', T_env(end), P_env_kW(end));
fprintf('  within 95%% of peak power over %d-%d rpm\n', ...
    rpmGrid(find(P_env_kW >= 0.95*peakPower, 1)), ...
    rpmGrid(find(P_env_kW >= 0.95*peakPower, 1, 'last')));
fprintf('  NOTE the driver never sees %.0f Nm. The VC requests %.0f Nm (p.T_driver_max,\n', ...
    p.T_flat_cap, p.T_driver_max);
fprintf('  MEASURED off the log). At that ceiling the knee moves to %d rpm.\n', kneeDrv);

%% ======================= 3. WHERE THE CAR ACTUALLY RAN =======================
D = readtable('data/comp_june20_data.csv');
wheelRpm = mean([D.VCFRONT_wheelSpeedFL, D.VCFRONT_wheelSpeedFR, ...
                 D.VCREAR_wheelSpeedRL,  D.VCREAR_wheelSpeedRR], 2, 'omitnan');
mRpm = D.PM100DX_motorSpeed;
mTq  = D.PM100DX_torqueFeedback;
% Sign convention differs between logs, so detect it rather than assume it.
if median(mTq(mRpm > 1000), 'omitnan') < 0, mTq = -mTq; end

moving   = mRpm > 500 & wheelRpm > 50;
motoring = moving & mTq > 2;              % on power, not coasting or regen
fprintf('\n=== 3. WHERE THE CAR ACTUALLY OPERATED (comp June 20) ===\n');
fprintf('  %d samples, %d moving, %d motoring (%.1f%% of moving)\n', ...
    height(D), sum(moving), sum(motoring), 100*sum(motoring)/sum(moving));

effAt = emrax208_efficiency(mRpm(motoring), mTq(motoring), p);
envAt = arrayfun(@(r) motor_peak_torque(min(r,p.redline), p), mRpm(motoring));
head  = envAt - mTq(motoring);
fprintf('  motor rpm    : median %.0f, p90 %.0f, max %.0f\n', ...
    median(mRpm(motoring)), prctile(mRpm(motoring),90), max(mRpm(motoring)));
fprintf('  motor torque : median %.0f Nm, p90 %.0f Nm, max %.0f Nm\n', ...
    median(mTq(motoring)), prctile(mTq(motoring),90), max(mTq(motoring)));
fprintf('  efficiency   : median %.1f%%, %.1f%% of motoring time in the sweet spot\n', ...
    100*median(effAt,'omitnan'), 100*mean(effAt >= p.eff_sweet));
fprintf('  torque headroom to the envelope: median %.0f Nm\n', median(head,'omitnan'));
fprintf('  %.1f%% of motoring time sits PAST the knee (%d rpm), i.e. power-limited\n', ...
    100*mean(mRpm(motoring) > knee), knee);

fprintf('\n  time-at-torque, motoring only:\n');
eT = [2 20 40 60 80 100 120 150];
for i = 1:numel(eT)-1
    fprintf('    %3d-%3d Nm  %5.1f%%\n', eT(i), eT(i+1), ...
        100*mean(mTq(motoring) >= eT(i) & mTq(motoring) < eT(i+1)));
end

%% ======================= 4. GEAR RATIO TRANSFORMATION =======================
% Wheel speed is what it is, the car went as fast as it went, and wheel torque demand is
% what it is too. Hold BOTH, redo the motor side at each ratio:
%     motor_rpm    = wheel_rpm * G
%     motor_torque = wheel_torque / G
% Same physics as gear_ratio_optimization.m, which holds wheel POWER invariant. Identical,
% since power = torque x speed and the two transform reciprocally.
%
% ASSUMPTION, and it is the honest limit of this: the driver demands the same wheel torque
% at the same speed regardless of gearing. Real drivers adapt. Read the output as "where
% would the same driving land", not "what the driver would do".
wRpm_m = wheelRpm(motoring);
wTq_m  = mTq(motoring) * p.gear_current;   % wheel torque, ratio-invariant

% "The motor feels like it is dying" is a CORNER EXIT complaint, not a cruising one.
% Median headroom over all motoring is useless for it: the car spends a third of its time
% under 20 Nm, so the median is dominated by part-throttle cruising and barely moves with
% ratio. Take the top decile of WHEEL TORQUE DEMAND instead. That subset is ratio-
% invariant, so the same physical moments are compared at every ratio.
hiDemand = wTq_m >= prctile(wTq_m, 90);

fprintf('\n=== 4. SAME DRIVING, DIFFERENT RATIOS ===\n');
fprintf('  (assumes identical wheel torque at identical speed. Drivers adapt, this does not.)\n');
fprintf('  hiHead/hiRPM are the top 10%% of wheel-torque demand, i.e. corner exit.\n\n');
fprintf('  ratio  kneeKPH  sweet%%  medEff%%  hiPastKnee%%  hiWheelRsv  infeas%%  overRed%%\n');
ratios = [4.00 4.20 4.40 4.61 4.80 5.00 5.20];
res = struct('G',{},'kneeKph',{},'infeas',{},'sweet',{},'medEff',{},'pastKnee',{}, ...
             'hiHead',{},'hiWheelRsv',{},'hiRpm',{},'hiPastKnee',{},'medRpm',{});
for g = ratios
    rN = wRpm_m * g;
    tN = wTq_m / g;
    envN = arrayfun(@(r) motor_peak_torque(min(r,p.redline), p), rN);
    over = rN > p.redline;
    infeas = over | (tN > envN + 1e-9);    % cannot be delivered at this ratio
    eN = emrax208_efficiency(rN, tN, p); eN(infeas) = NaN;
    headN = envN - tN;
    % Road speed at which the motor reaches its torque knee. The single most legible
    % number here: past this speed the motor is on the falling part of the curve.
    kneeKph = knee/g * (2*pi/60) * p.r_wheel * 3.6;
    fprintf('  %5.2f  %7.1f %7.1f %8.1f %12.1f %11.0f %8.1f %9.1f\n', ...
        g, kneeKph, 100*mean(eN >= p.eff_sweet, 'omitnan'), 100*median(eN,'omitnan'), ...
        100*mean(rN(hiDemand) > knee), median(headN(hiDemand),'omitnan')*g, ...
        100*mean(infeas), 100*mean(over));
    res(end+1) = struct('G',g,'kneeKph',kneeKph,'infeas',100*mean(infeas), ...
        'sweet',100*mean(eN >= p.eff_sweet,'omitnan'), 'medEff',100*median(eN,'omitnan'), ...
        'pastKnee',100*mean(rN > knee), 'hiHead',median(headN(hiDemand),'omitnan'), ...
        'hiWheelRsv',median(headN(hiDemand),'omitnan')*g, ...
        'hiRpm',median(rN(hiDemand)), 'hiPastKnee',100*mean(rN(hiDemand) > knee), ...
        'medRpm',median(rN)); %#ok<SAGROW>
end
fprintf('\n  kneeKPH      road speed where the motor hits its torque knee. Past this the\n');
fprintf('               motor is on the falling part of the curve. Most legible number here.\n');
fprintf('  sweet%%       motoring time at efficiency >= %.0f%%\n', 100*p.eff_sweet);
fprintf('  hiPastKnee%%  corner-exit time already past the knee\n');
fprintf('  hiWheelRsv   spare WHEEL torque at corner exit, Nm (motor headroom x G)\n');
fprintf('  infeas%%      demand exceeds the envelope, or rpm over redline\n');
fprintf('\n  THE TRADE, and the two columns look contradictory until you see why:\n');
fprintf('  short gearing (high G) gives MORE wheel torque reserve but reaches the knee at a\n');
fprintf('  LOWER road speed, so the shove arrives sooner and fades sooner. Long gearing\n');
fprintf('  holds flat torque to a higher speed but with less multiplication. "Feels like it\n');
fprintf('  is dying" is the fade, not the peak, so kneeKPH is the column that matches the\n');
fprintf('  driver complaint.\n');

%% ======================= FIGURES =======================
fig = figure('Name','Peak operating point','Position',[40 40 1150 700]);
tg = uitabgroup(fig);

ax = axes(uitab(tg,'Title','1. Efficiency map'));
contourf(ax, rpmGrid, tqGrid, 100*EFF_f, 20, 'LineColor','none'); hold(ax,'on');
plot(ax, rpmGrid, T_env, 'k-', 'LineWidth', 2);
yline(ax, p.T_driver_max, 'w--', 'VC ceiling 123 Nm', 'LineWidth', 1.4);
plot(ax, rpmGrid(bj), tqGrid(bi), 'rp', 'MarkerSize', 16, 'MarkerFaceColor','r');
colormap(ax, turbo); cb = colorbar(ax); cb.Label.String = 'motor+inverter efficiency (%)';
xlabel(ax,'motor rpm'); ylabel(ax,'motor torque (Nm)'); grid(ax,'on');
title(ax, sprintf('Efficiency (PHYSICS MODEL, optimistic). Peak %.1f%% at %d rpm / %d Nm', ...
    100*bestEff, rpmGrid(bj), tqGrid(bi)));

ax = axes(uitab(tg,'Title','2. Envelope'));
yyaxis(ax,'left');  plot(ax, rpmGrid, T_env, 'LineWidth', 2); ylabel(ax,'torque (Nm)');
yyaxis(ax,'right'); plot(ax, rpmGrid, P_env_kW, 'LineWidth', 2); ylabel(ax,'power (kW)');
xline(ax, knee, 'k--', sprintf('torque knee %d rpm', knee));
xline(ax, rpmGrid(kp_), 'r:', sprintf('peak power %.0f kW', peakPower));
xlabel(ax,'motor rpm'); grid(ax,'on');
title(ax,'Torque and power envelope. Past the knee, torque falls as P/omega');

ax = axes(uitab(tg,'Title','3. Where we ran'));
scatter(ax, mRpm(motoring), mTq(motoring), 6, 100*effAt, 'filled', 'MarkerFaceAlpha', 0.25);
hold(ax,'on');
plot(ax, rpmGrid, T_env, 'k-', 'LineWidth', 2);
contour(ax, rpmGrid, tqGrid, 100*EFF_f, [100*p.eff_sweet 100*p.eff_sweet], 'w-', 'LineWidth', 2);
yline(ax, p.T_driver_max, 'w--', 'VC ceiling');
xline(ax, knee, 'k--', 'torque knee');
colormap(ax, turbo); cb = colorbar(ax); cb.Label.String = 'efficiency (%)';
xlabel(ax,'motor rpm'); ylabel(ax,'motor torque (Nm)'); grid(ax,'on');
title(ax, sprintf('Comp June 20 motoring points (%d) vs what the motor can do', sum(motoring)));

ax = axes(uitab(tg,'Title','4. Ratio trade'));
yyaxis(ax,'left');
plot(ax, [res.G], [res.sweet], 'o-', 'LineWidth', 1.9); hold(ax,'on');
plot(ax, [res.G], [res.pastKnee], 's--', 'LineWidth', 1.5);
ylabel(ax,'% of motoring time');
plot(ax, [res.G], [res.hiPastKnee], '^:', 'LineWidth', 1.5);
yyaxis(ax,'right'); plot(ax, [res.G], [res.hiHead], 'd-.', 'LineWidth', 1.5);
ylabel(ax,'corner-exit torque headroom (Nm)');
xline(ax, p.gear_current, 'k--', sprintf('current %.2f', p.gear_current));
xlabel(ax,'gear ratio'); grid(ax,'on');
legend(ax, {'in sweet spot','past torque knee','corner exit past knee','corner-exit headroom'}, 'Location','best');
title(ax,'Same driving, re-geared. Higher ratio = more rpm, less motor torque');

save_tabfig(fig, fullfile('output','PeakOperatingPoint'));
writetable(struct2table(res), 'output/peak_operating_point_ratios.csv');
fprintf('\nSaved: output/peak_operating_point_ratios.csv + a 4-tab figure\n');

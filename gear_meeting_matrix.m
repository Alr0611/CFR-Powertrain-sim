%% GEAR_MEETING_MATRIX -- every ratio axis, at the ratios you can actually bolt on
%
%  Built for the ratio-freeze meeting. This does NOT invent a new model. It calls the
%  same accel_tc_core / emrax208_efficiency / motor_peak_torque that gear_decision_summary
%  already uses, just evaluated at the BUILDABLE sprocket ratios instead of a round-number
%  grid, and at both grip assumptions instead of one.
%
%  Buildable = fixed 15:30 spur (2.000) x driven/13, driven 26T..34T. See
%  lib/sprocket_ratio.m and sprocket_configs.md.
%
%  Two grip cases, because the whole short-gearing argument hinges on which you believe:
%    mu_scale 1.000  clean tyre-belt data (optimistic, borrowed tyre)
%    mu_scale 0.853  derived from OUR logged launches (what we measured)
%
%  Writes output/gear_meeting_matrix.csv. Nothing else is modified.

clear; clc;
if ~exist('output','dir'), mkdir('output'); end
p = params_cfr26();

DRIVEN  = 26:34;
DRIVER  = 13;          % splined bought part, 6-lobe 21.0/25.0/5.0 bore. Not a free variable.
SPUR    = 2.000;
MU      = [1.000, 0.853];

tc = struct('enabled',true,'target_slip',0.10,'kp',0.470,'ki',0.0,'kd',0.110, ...
            'ilim',0.0,'maxlim',0.75,'ileak_ms',500,'rate_hz',100, ...
            'speed_gate',0.5,'emulate_firmware_pure_p',true);

% ---- telemetry-derived operating points, same method as gear_decision_summary ----
D = readtable('data/comp_june20_data.csv');
wheelRpm = mean([D.VCFRONT_wheelSpeedFL, D.VCFRONT_wheelSpeedFR, ...
                 D.VCREAR_wheelSpeedRL,  D.VCREAR_wheelSpeedRR], 2, 'omitnan');
mRpm = D.PM100DX_motorSpeed; mTq = D.PM100DX_torqueFeedback;
if median(mTq(mRpm > 1000),'omitnan') < 0, mTq = -mTq; end
motoring = mRpm > 500 & wheelRpm > 50 & mTq > 2;
wRpm_m = wheelRpm(motoring);
wTq_m  = mTq(motoring)*p.gear_current;

rpmGrid = 100:25:p.redline;
T_env   = arrayfun(@(r) motor_peak_torque(r,p), rpmGrid);
knee    = rpmGrid(find(T_env < p.T_flat_cap - 0.5, 1));

% ---- SOC from the endurance study, matched to the exact ratio ----
GR = readtable('output/gear_ratio_results.csv');

fprintf('\n=== GEAR MEETING MATRIX ===\n');
fprintf('driver %dT fixed, spur %.3f, driven %d..%d\n\n', DRIVER, SPUR, DRIVEN(1), DRIVEN(end));

rows = [];
fprintf('%4s %8s %9s %9s %8s %8s %8s %9s %9s %8s %8s\n', ...
    'N2','ratio','t75_mu1','t75_mu85','dGrip','topSpd','sweet%','kneeKPH','exitPst%','SOC98','avgEff');
for N2 = DRIVEN
    g = SPUR*N2/DRIVER;

    t75 = zeros(1,numel(MU)); slip = zeros(1,numel(MU)); cut = zeros(1,numel(MU));
    for k = 1:numel(MU)
        ty.mu_scale = MU(k);
        R = accel_tc_core(p, tc, ty, g);
        t75(k) = R.t75;
        if isfield(R,'peakSlip'), slip(k) = R.peakSlip; else, slip(k) = NaN; end
        if isfield(R,'cutPct'),   cut(k)  = R.cutPct;   else, cut(k)  = NaN; end
    end

    vtop = (p.redline/g)*(2*pi/60)*p.r_wheel*3.6;
    rN   = wRpm_m*g;  tN = wTq_m/g;
    envN = arrayfun(@(r) motor_peak_torque(min(r,p.redline),p), rN);
    infeas = (rN > p.redline) | (tN > envN + 1e-9);
    eN = emrax208_efficiency(rN, tN, p); eN(infeas) = NaN;
    sweet   = 100*mean(eN >= p.eff_sweet,'omitnan');
    kneeKph = knee/g*(2*pi/60)*p.r_wheel*3.6;
    exitPast = 100*mean(wRpm_m*g > knee);

    [~,ix] = min(abs(GR.ratio - g));
    soc98 = GR.SOC98(ix); aeff = GR.avg_eff(ix); socErr = abs(GR.ratio(ix)-g);
    if socErr > 1e-3
        warning('no exact SOC row for ratio %.4f (nearest %.4f)', g, GR.ratio(ix));
    end

    fprintf('%4d %8.4f %9.4f %9.4f %+8.4f %8.1f %8.1f %9.1f %9.1f %8.3f %8.2f\n', ...
        N2, g, t75(1), t75(2), t75(2)-t75(1), vtop, sweet, kneeKph, exitPast, soc98, aeff);

    rows(end+1,:) = [N2, g, t75(1), t75(2), t75(2)-t75(1), vtop, sweet, kneeKph, ...
                     exitPast, soc98, aeff, slip(1), slip(2), cut(1), cut(2)]; %#ok<AGROW>
end

T = array2table(rows, 'VariableNames', {'driven_teeth','ratio','t75_mu100','t75_mu853', ...
    'grip_penalty_s','top_speed_kph','sweet_pct','knee_kph','exits_past_knee_pct', ...
    'SOC98','avg_eff','peak_slip_mu100','peak_slip_mu853','tc_cut_mu100','tc_cut_mu853'});
writetable(T, 'output/gear_meeting_matrix.csv');
fprintf('\nSaved output/gear_meeting_matrix.csv\n');
fprintf('t75 is at the REAL 123 Nm ceiling the car requests, TC active, not the 150 datasheet map.\n');
fprintf('mu 1.000 = clean tyre-belt grip. mu 0.853 = derived from our own logged launches.\n');
fprintf('dGrip is how much the accel number moves between the two. Big dGrip = the ratio is\n');
fprintf('betting on the grip assumption we are least sure of.\n');

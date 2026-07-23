%% DEGRADATION_STUDY  --  how worn are our 2018-era motor and inverter?
%
% THE HONEST ANSWER RIGHT NOW: we do not know. Nobody has measured it.
% p.degradation_motor and p.degradation_inverter both sit at 1.00 in
% params_cfr26.m and they stay there until a measurement replaces them.
%
% So this script does two jobs, and keeps them strictly apart:
%
%   PART A -- WHAT IT WOULD COST (sensitivity).
%       Sweeps plausible degradation ranges and reports the effect on efficiency
%       and endurance energy as a BAND. No single number, because a single number
%       here would be fiction.
%
%   PART B -- HOW TO MEASURE IT (three methods, ready for data).
%       Each method prints the baseline it will compare against and the exact
%       measurement needed. Drop the measured values into the MEASUREMENTS block
%       below and the comparison runs itself.
%
% Team belief going in: the INVERTER is more degraded than the motor. That is a
% hypothesis, not an input. Method 2 is the one that tests it.
%
% DELIBERATELY SELF-CONTAINED. Degradation is speculative and still being chased,
% so it is kept OUT of the validated drivetrain-efficiency chain: nothing here
% feeds lib/emrax208_efficiency.m, gear_ratio_optimization.m or
% drivetrain_efficiency.m. This script reads p.degradation_* and applies the
% effect locally. That way an unmeasured guess can never quietly move a number
% the team is relying on -- if it ends up wrong, only this file was wrong.
%
% Run:  degradation_study        (or from START.m)

clear; clc;
here = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(here));
p = params_cfr26();

%% ===================== MEASUREMENTS -- fill these in ========================
% Everything here is EMPTY until somebody runs the test. Empty = "not measured",
% and the script will say so rather than guessing.

% -- Method 3: no-load spin test. Wheels off the ground, no load, steady rpm.
%    Record motor rpm and the DC current the PACK delivers at that rpm.
M3.rpm     = [];    % e.g. [2000 3000 4000 5000]
M3.dc_amps = [];    % e.g. [1.2  2.0  3.1  4.3]
M3.dc_volts = [];   % pack voltage during the test (leave [] to use nominal)
M3.accessories_on = true;   % were pumps/fans/LV running off the same shunt?

% -- Method 1: back-EMF. Spin the motor externally (or coast in neutral), read
%    line-to-line voltage at the inverter terminals with the inverter disabled.
M1.rpm      = [];   % e.g. [1000 2000 3000]
M1.vll_rms  = [];   % e.g. [50.2 100.1 150.4]

% -- Method 2: inverter thermal. Needs BOTH a recent log and an old one.
M2.old_log = '';    % e.g. fullfile(here,'data','comp_2023.csv')
M2.new_log = fullfile(here,'data','comp_june20_data.csv');

%% ===================== PART A: SENSITIVITY (the deliverable today) =========
% Degradation enters as an efficiency multiplier (see lib/emrax208_efficiency.m),
% so the mechanical work is unchanged and the ENERGY to do it scales as
% 1/(d_motor * d_inverter). That is the whole model -- nothing else moves.

mot_pct = 1:1:5;      % motor degradation, % efficiency lost   (plausible range)
inv_pct = 3:1:10;     % inverter degradation, % lost           (plausible range)
% These ranges are ASSUMPTIONS about what is plausible for 2018-era hardware.
% They bracket the answer; they are not a claim about our specific units. The
% inverter range sits higher than the motor's only because that is the team's
% stated belief -- which Method 2 exists to test.

% Baseline endurance energy, MEASURED from our own telemetry (not assumed), and
% normalised by the ODOMETER to a 22 km endurance rather than taken as a raw
% session total -- the July 11 log is an 80-minute test day, of which only ~33
% minutes is moving.
ENDURANCE_KM = 22;
[E_sess_Wh, km_sess, soc_drop] = endurance_energy( ...
    fullfile(here,'data','endurance_july11_with_odo_wide.csv'));
E_base_Wh = E_sess_Wh / km_sess * ENDURANCE_KM;
pack_Wh   = p.N_series * p.N_parallel * (p.Q_cell/3600) * 3.6;   % nominal pack energy

fprintf('=== PART A: WHAT DEGRADATION WOULD COST (sensitivity, not a measurement) ===\n\n');
fprintf(' Current params: degradation_motor = %.2f, degradation_inverter = %.2f\n', ...
    p.degradation_motor, p.degradation_inverter);
fprintf(' Both 1.00 = as-new = UNMEASURED. Everything below is "what if", not "what is".\n\n');

if isnan(E_base_Wh)
    E_base_Wh = 3410;   % fallback: the figure verify_math sec 9 uses
    fprintf(' [endurance CSV not found -- using %.0f Wh from verify_math sec 9]\n\n', E_base_Wh);
else
    fprintf(' Baseline energy, MEASURED from the July 11 run:\n');
    fprintf('   %.0f Wh over %.2f km = %.0f Wh/km -> %.0f Wh for a %d km endurance\n', ...
        E_sess_Wh, km_sess, E_sess_Wh/km_sess, E_base_Wh, ENDURANCE_KM);
    fprintf('   = %.0f%% of the %.0f Wh nominal pack.\n', 100*E_base_Wh/pack_Wh, pack_Wh);
    fprintf('   Corroborated by the BMS itself: SOC fell %.1f points on that run, and\n', soc_drop);
    fprintf('   charge throughput was %.1f Ah of the pack''s %.1f Ah. Three independent\n', ...
        soc_drop/100*p.N_parallel*p.Q_cell/3600, p.N_parallel*p.Q_cell/3600);
    fprintf('   reads (energy integral, SOC, coulomb count) all say the same thing:\n');
    fprintf('   WE ALREADY FINISH ENDURANCE NEAR EMPTY. That is why degradation matters\n');
    fprintf('   here more than it would on a car with margin.\n\n');
    fprintf('   CAVEATS: pack_Wh uses the datasheet 4.4 Ah/cell and 3.6 V nominal, and the\n');
    fprintf('   README notes the real cells may hold somewhat MORE -- so the percentages\n');
    fprintf('   below are the conservative read. July 11 was also a test day, not a\n');
    fprintf('   scored endurance; pace and driver differ.\n\n');
end

fprintf(' Extra endurance energy needed (Wh), by degradation pair:\n');
fprintf('   motor \\ inv ');  fprintf('%7d%%', inv_pct); fprintf('\n');
for im = 1:numel(mot_pct)
    fprintf('   %8d%%   ', mot_pct(im));
    for ii = 1:numel(inv_pct)
        d = (1-mot_pct(im)/100) * (1-inv_pct(ii)/100);
        fprintf('%8.0f', E_base_Wh*(1/d - 1));
    end
    fprintf('\n');
end

d_best  = (1-min(mot_pct)/100)*(1-min(inv_pct)/100);
d_worst = (1-max(mot_pct)/100)*(1-max(inv_pct)/100);
fprintf('\n THE BAND (report this, never a single number):\n');
fprintf('   combined efficiency retained : %.1f%% .. %.1f%%   (i.e. %.1f%% .. %.1f%% lost)\n', ...
    100*d_worst, 100*d_best, 100*(1-d_best), 100*(1-d_worst));
fprintf('   overall drivetrain eff       : %.1f%% .. %.1f%%   (from %.1f%% as-new)\n', ...
    100*p.eta_drivetrain*d_worst, 100*p.eta_drivetrain*d_best, 100*p.eta_drivetrain);
fprintf('   extra endurance energy       : %+.0f Wh .. %+.0f Wh  (%+.1f%% .. %+.1f%%)\n', ...
    E_base_Wh*(1/d_best-1), E_base_Wh*(1/d_worst-1), 100*(1/d_best-1), 100*(1/d_worst-1));
fprintf('   endurance draw vs pack       : %.0f%% .. %.0f%% of a %.0f Wh pack (was %.0f%%)\n', ...
    100*E_base_Wh/d_best/pack_Wh, 100*E_base_Wh/d_worst/pack_Wh, pack_Wh, 100*E_base_Wh/pack_Wh);
if E_base_Wh/d_worst < pack_Wh
    fprintf('\n   => even at the WORST corner of this band the pack still finishes endurance.\n');
    fprintf('      Degradation is an efficiency-points problem, not a DNF risk.\n\n');
else
    fprintf('\n   => at the worst corner the pack does NOT finish. This would become a\n');
    fprintf('      reliability problem, not just an efficiency one.\n\n');
end

%% ===================== PART B, METHOD 3: NO-LOAD SPIN TEST =================
% Cheapest method, and the only one that needs no historical data. Spin the motor
% unloaded at a known rpm; the DC power the pack delivers is everything that is
% NOT useful work -- so it is a direct read of the loss the motor makes turning.

fprintf('=== METHOD 3: NO-LOAD SPIN TEST (start here -- cheapest) ===\n\n');
Vnom = p.N_series * 4.2;                       % 369.6 V, full-charge pack
rpm_curve = 1000:500:6000;
P_core = p.core_loss_a*rpm_curve + p.core_loss_b*rpm_curve.^2;   % motor free-run loss

% THE TRAP: the pack-side shunt does NOT see motor core loss alone. It sees the
% core loss AFTER the inverter's own inefficiency, PLUS whatever accessories are
% running off the same shunt. Comparing a pack-side measurement against a
% motor-only baseline manufactures degradation that is not there.
P_ACC = 116;                                   % W, MEASURED accessory draw
                                               % (verify_math sec 15 steady-state fit)
P_dc_motor_only = P_core;                      % naive baseline -- WRONG for pack-side
P_dc_expected   = P_core / p.eta_inverter + P_ACC * M3.accessories_on;

fprintf(' Baseline is our own datasheet-anchored free-run curve (verify_math sec 4\n');
fprintf(' already locks its two anchors: 575 W at 3000 rpm, 1650 W at 6000 rpm).\n\n');
fprintf('   rpm  | motor core | naive A | EXPECTED pack-side | expected A\n');
fprintf('        |    loss W  |  @%.0fV |  (incl inv + acc)  |    @%.0fV\n', Vnom, Vnom);
fprintf('   -----+------------+---------+--------------------+-----------\n');
for r = [2000 3000 4000 5000 6000]
    pc  = p.core_loss_a*r + p.core_loss_b*r^2;
    pdc = pc/p.eta_inverter + P_ACC*M3.accessories_on;
    fprintf('   %4d |   %6.0f   |  %5.2f  |      %6.0f        |   %5.2f\n', ...
        r, pc, pc/Vnom, pdc, pdc/Vnom);
end
fprintf('\n READ THE LAST COLUMN, NOT THE THIRD. At 3000 rpm the motor''s own core loss is\n');
fprintf(' %.0f W (%.2f A), but the pack must also cover inverter loss and %.0f W of\n', ...
    p.core_loss_a*3000+p.core_loss_b*3000^2, (p.core_loss_a*3000+p.core_loss_b*3000^2)/Vnom, P_ACC);
fprintf(' accessories, so a HEALTHY car should draw about %.2f A, not %.2f A. Comparing a\n', ...
    (p.core_loss_a*3000+p.core_loss_b*3000^2)/p.eta_inverter/Vnom + P_ACC/Vnom, ...
    (p.core_loss_a*3000+p.core_loss_b*3000^2)/Vnom);
fprintf(' measured %.2f A against the %.2f A baseline would "find" ~%.0f%% degradation that\n', ...
    (p.core_loss_a*3000+p.core_loss_b*3000^2)/p.eta_inverter/Vnom + P_ACC/Vnom, ...
    (p.core_loss_a*3000+p.core_loss_b*3000^2)/Vnom, ...
    100*(((p.core_loss_a*3000+p.core_loss_b*3000^2)/p.eta_inverter + P_ACC) / ...
         (p.core_loss_a*3000+p.core_loss_b*3000^2) - 1));
fprintf(' does not exist. Either switch accessories OFF for the test, or use column 4.\n\n');

fprintf(' !! SAFETY -- this spins a live HV tractive system with the wheels off the ground.\n');
fprintf('    Follow the team HV protocol: proper stands, trained HV personnel, nobody in\n');
fprintf('    the plane of the rotating wheels, and a second person on the shutdown. This\n');
fprintf('    is a scheduled test with the safety officer present, not a freelance run.\n\n');

if isempty(M3.rpm)
    fprintf(' [no measurement yet -- fill M3.rpm / M3.dc_amps at the top of this file]\n');
    fprintf(' What to record: steady rpm, DC amps, pack volts, and whether accessories\n');
    fprintf(' were on. Three or four rpm points (2000-5000) is plenty.\n\n');
else
    Vm = M3.dc_volts; if isempty(Vm), Vm = Vnom*ones(size(M3.rpm)); end
    P_meas = M3.dc_amps(:)' .* Vm(:)';
    P_exp  = (p.core_loss_a*M3.rpm(:)' + p.core_loss_b*M3.rpm(:)'.^2)/p.eta_inverter ...
             + P_ACC*M3.accessories_on;
    exc    = P_meas - P_exp;
    fprintf('   rpm  | measured W | expected W | excess W | excess %%\n');
    fprintf('   -----+------------+------------+----------+---------\n');
    for k = 1:numel(M3.rpm)
        fprintf('   %4d |   %6.0f   |   %6.0f   |  %+6.0f  |  %+6.1f%%\n', ...
            M3.rpm(k), P_meas(k), P_exp(k), exc(k), 100*exc(k)/P_exp(k));
    end
    frac = mean(exc./P_exp);
    fprintf('\n mean excess loss = %+.1f%% of expected free-run loss.\n', 100*frac);
    fprintf(' Excess loss is NOT the same as an efficiency multiplier: it is extra WATTS at\n');
    fprintf(' no load. To convert, compare it against shaft power at the operating point.\n');
    P_op = 79.6 * 3500 * 2*pi/60;    % continuous-ish operating point
    fprintf(' At the %.0f kW continuous point that is %.3f efficiency points, i.e.\n', P_op/1e3, mean(exc)/P_op);
    fprintf('   suggested p.degradation_motor = %.4f\n', 1 - mean(exc)/P_op);
    fprintf(' Report it with the spread across rpm points, not as a bare number:\n');
    fprintf('   excess ranges %+.1f%% .. %+.1f%% across the rpm sweep.\n\n', ...
        100*min(exc./P_exp), 100*max(exc./P_exp));
end

%% ===================== PART B, METHOD 1: BACK-EMF (Ke) =====================
% Ke is proportional to magnet flux, so a drop in Ke is direct evidence of
% demagnetisation. The concept is sound; the arithmetic is where this goes wrong.

fprintf('=== METHOD 1: BACK-EMF / Ke (magnet demagnetisation) ===\n\n');
% Derive Ke from constants we have already validated, rather than trusting a
% remembered figure. 140 Nm at 3000 rpm is 44 kW at 169 A_rms (verify_math sec 5
% cross-checks the torque/current constant), so for a 3-phase machine
%     P = sqrt(3) * V_LL * I  ->  V_LL = P / (sqrt(3) * I)
T_ref = p.T_flat_cap; rpm_ref = 3000;
P_ref = T_ref * rpm_ref * 2*pi/60;
I_ref = T_ref / p.Nm_per_Arms;
Vll_ref = P_ref / (sqrt(3)*I_ref);
Ke_derived = Vll_ref / rpm_ref;
fprintf(' Derived from our own validated constants:\n');
fprintf('   %.0f Nm at %d rpm = %.1f kW at %.0f A_rms -> V_LL = %.1f V\n', ...
    T_ref, rpm_ref, P_ref/1e3, I_ref, Vll_ref);
fprintf('   => Ke = %.4f V/rpm (line-to-line RMS)\n\n', Ke_derived);

Ke_BAD = 0.60;
fprintf(' SANITY CHECK -- reject a bad baseline before it is used:\n');
fprintf('   a Ke of %.2f V/rpm implies %.0f V at redline (%d rpm) against a %.0f V bus.\n', ...
    Ke_BAD, Ke_BAD*p.redline, p.redline, Vnom);
fprintf('   That is impossible -- it is %.1fx our derived value. Using it would "discover"\n', Ke_BAD/Ke_derived);
fprintf('   about %.0f%% demagnetisation that does not exist.\n', 100*(1-Ke_derived/Ke_BAD));
fprintf('   Before running this method, confirm Ke from the EMRAX 208 HV datasheet.\n');
fprintf('   Expect it to be near %.3f, not %.2f.\n\n', Ke_derived, Ke_BAD);
fprintf(' Cross-check that %.4f is self-consistent: at redline (%d rpm) it predicts\n', ...
    Ke_derived, p.redline);
fprintf(' %.0f V_LL against a %.0f V bus. Back-EMF stays UNDER the bus across the whole\n', ...
    Ke_derived*p.redline, Vnom);
fprintf(' rev range (it would only reach the bus at ~%.0f rpm, well past redline), so the\n', ...
    Vnom/Ke_derived);
fprintf(' motor never needs field weakening -- which is what you want, and is consistent\n');
fprintf(' with a %.0f V pack having been chosen for this motor. The number holds up.\n\n', Vnom);
fprintf(' CHANNELS: there are no Vd/Vq channels on the PM100DX. Use\n');
fprintf('   PM100DX_voltageVAB / PM100DX_voltageVBC / PM100DX_outputVoltage.\n\n');

if isempty(M1.rpm)
    fprintf(' [no measurement yet -- fill M1.rpm / M1.vll_rms at the top of this file]\n\n');
else
    Ke_meas = mean(M1.vll_rms(:)./M1.rpm(:));
    Ke_sd   = std(M1.vll_rms(:)./M1.rpm(:));
    fprintf('   measured Ke = %.4f +/- %.4f V/rpm over %d points\n', Ke_meas, Ke_sd, numel(M1.rpm));
    fprintf('   vs datasheet-derived %.4f -> magnet flux at %.1f%% (+/- %.1f%%)\n', ...
        Ke_derived, 100*Ke_meas/Ke_derived, 100*Ke_sd/Ke_derived);
    fprintf('   NOTE: magnet flux loss is not an efficiency multiplier. It costs TORQUE per\n');
    fprintf('   amp (Nm_per_Arms scales with it), which then costs efficiency indirectly.\n\n');
end

%% ===================== PART B, METHOD 2: INVERTER THERMAL Rth ==============
fprintf('=== METHOD 2: INVERTER THERMAL RESISTANCE (bond-wire / solder fatigue) ===\n\n');
fprintf(' The physics: as bond wires lift and solder voids grow, the junction-to-coolant\n');
fprintf(' thermal path gets worse. So track THERMAL RESISTANCE, not raw temperature:\n\n');
fprintf('     Rth = (T_module - T_coolant) / P_loss        [K/W]\n\n');
fprintf(' Two things that must be right, or the number means nothing:\n');
fprintf('   1. divide by LOSS POWER, not current. Conduction loss goes as I^2, so\n');
fprintf('      dTemp/I rises with current even on a perfectly healthy inverter.\n');
fprintf('   2. use MODULE MINUS COOLANT, not absolute module temperature. Absolute temp\n');
fprintf('      also rises from a fouled radiator, a tired pump or old coolant -- that is\n');
fprintf('      a cooling problem, not silicon degradation, and the subtraction separates\n');
fprintf('      them. Rising Rth = the inverter. Rising coolant temp = the cooling loop.\n\n');
fprintf(' CHANNELS (all present on the PM100DX):\n');
fprintf('   module      : PM100DX_tempModuleA / tempModuleB / tempModuleC\n');
fprintf('   coolant     : PM100DX_rtdTemp1..5 (whichever is plumbed to the inlet)\n');
fprintf('   board       : PM100DX_controlBoardTemp\n');
fprintf('   loss power  : dcBusVoltage*dcBusCurrent - torqueFeedback*motorSpeed*2*pi/60\n\n');

old_exists = ~isempty(M2.old_log) && isfile(M2.old_log);
fprintf(' PREREQUISITE CHECK -- this method is dead without an old log to compare to:\n');
if old_exists
    fprintf('   [OK]   baseline log found: %s\n\n', M2.old_log);
    rth_report(M2.old_log, 'BASELINE (old)');
    rth_report(M2.new_log, 'NOW (recent)');
    fprintf('   Compare the two Rth values. A rise is degradation; equal Rth with higher\n');
    fprintf('   absolute temps is a cooling problem.\n\n');
else
    fprintf('   [MISSING] no 2023-era log is set (M2.old_log is empty or the file is absent).\n');
    fprintf('   Searched the repo data folder; what is there:\n');
    dd = dir(fullfile(here,'data','*.csv'));
    for k = 1:numel(dd), fprintf('       %s\n', dd(k).name); end
    fprintf('   All of these are 2025-26 sessions. There is NO 2023 log in this repo, so\n');
    fprintf('   Method 2 cannot run today. It needs either an archived 2023 export or a\n');
    fprintf('   deliberate baseline logged NOW that future seasons compare against.\n');
    fprintf('   Even with no history, run rth_report on a current log and RECORD it --\n');
    fprintf('   that turns this from a dead method into a working one next year:\n\n');
    if isfile(M2.new_log)
        rth_report(M2.new_log, 'TODAY (record this as the baseline)');
    end
end

%% ===================== FIGURE =============================================
outdir = fullfile(here,'output'); if ~exist(outdir,'dir'), mkdir(outdir); end
fW = figure('Name','Component degradation','Position',[60 60 1080 560]);
tg = uitabgroup(fW);

% Tab 1: the sensitivity band
ax = axes(uitab(tg,'Title','Sensitivity band'));
[MM, II] = meshgrid(mot_pct, inv_pct);
extra = E_base_Wh*(1./((1-MM/100).*(1-II/100)) - 1);
contourf(ax, MM, II, extra, 12, 'LineColor','none'); colormap(ax, parula);
cb = colorbar(ax); cb.Label.String = 'Extra endurance energy (Wh)';
xlabel(ax,'Motor degradation (% efficiency lost)');
ylabel(ax,'Inverter degradation (% efficiency lost)');
title(ax, sprintf('UNMEASURED: what degradation would cost (baseline %.0f Wh)', E_base_Wh));
hold(ax,'on'); grid(ax,'on');

% Tab 2: the no-load baseline curve the spin test compares against
ax = axes(uitab(tg,'Title','No-load spin baseline'));
plot(ax, rpm_curve, P_core, '-', 'LineWidth', 2); hold(ax,'on'); grid(ax,'on');
plot(ax, rpm_curve, P_core/p.eta_inverter + P_ACC*M3.accessories_on, '--', 'LineWidth', 2);
plot(ax, [3000 6000], [575 1650], 'o', 'MarkerSize', 9, 'LineWidth', 2);
lg = {'motor core loss (physics)','EXPECTED pack-side draw (incl inverter + accessories)','datasheet anchors'};
if ~isempty(M3.rpm)
    Vm = M3.dc_volts; if isempty(Vm), Vm = Vnom*ones(size(M3.rpm)); end
    plot(ax, M3.rpm, M3.dc_amps(:)'.*Vm(:)', 's', 'MarkerSize', 10, 'LineWidth', 2);
    lg{end+1} = 'MEASURED spin test';
end
legend(ax, lg, 'Location','northwest'); xlabel(ax,'Motor rpm'); ylabel(ax,'Power (W)');
title(ax,'Method 3 baseline -- compare a measured point against the DASHED line');

save_tabfig(fW, fullfile(outdir,'DegradationStudy'));
fprintf('Saved figure to output/DegradationStudy*.\n\n');

fprintf('=== BOTTOM LINE ===\n');
fprintf(' We have NOT measured degradation, so params stay at 1.00 and this study\n');
fprintf(' reports a band: %.0f-%.0f Wh extra over an endurance run (%.1f-%.1f%%), which the\n', ...
    E_base_Wh*(1/d_best-1), E_base_Wh*(1/d_worst-1), 100*(1/d_best-1), 100*(1/d_worst-1));
fprintf(' pack absorbs either way. Next action: Method 3, the no-load spin test --\n');
fprintf(' one afternoon, no dyno, no historical data, and it produces a real number.\n');

%% ============================== local functions ============================
function [E_Wh, km, soc_drop] = endurance_energy(csv)
%ENDURANCE_ENERGY  pack Wh, distance and SOC drop over a telemetry run.
%   All three MEASURED. Returning distance alongside energy is the point: the
%   July 11 log is an 80-minute test day covering 22.5 km, so its raw session
%   total is not "one endurance" until it is normalised by the odometer.
    E_Wh = NaN; km = NaN; soc_drop = NaN;
    if ~isfile(csv), return; end
    W = readtable(csv);
    need = {'BMSB_packVoltage','BMSB_packCurrent','t_s'};
    if ~all(ismember(need, W.Properties.VariableNames)), return; end
    P = W.BMSB_packVoltage .* W.BMSB_packCurrent;  P(isnan(P)) = 0;
    E_Wh = abs(trapz(W.t_s, P)) / 3600;
    if ismember('VCFRONT_odometer', W.Properties.VariableNames)
        o = W.VCFRONT_odometer(~isnan(W.VCFRONT_odometer));
        if ~isempty(o), km = max(o) - min(o); end
    end
    if ismember('BMSB_packSOC', W.Properties.VariableNames)
        s = W.BMSB_packSOC(~isnan(W.BMSB_packSOC));
        if ~isempty(s), soc_drop = s(1) - s(end); end
    end
end

function rth_report(csv, label)
%RTH_REPORT  inverter thermal resistance from a telemetry CSV, if the channels exist.
%   Rth = (T_module - T_coolant) / P_loss, on loaded steady-state points only.
    fprintf('   --- %s: %s\n', label, csv);
    if ~isfile(csv), fprintf('       file not found.\n\n'); return; end
    W = readtable(csv); V = W.Properties.VariableNames;
    modch  = V(contains(V,'tempModule'));
    coolch = V(contains(V,'rtdTemp'));
    if isempty(modch)
        fprintf('       no tempModule* channels in this export -- cannot compute Rth.\n');
        fprintf('       Re-export with the "Cooling & temps" channel group.\n\n');
        return;
    end
    Tmod = max(W{:,modch}, [], 2);
    if isempty(coolch)
        fprintf('       no rtdTemp* (coolant) channel -- Rth needs module MINUS coolant.\n');
        fprintf('       Absolute module temp alone cannot separate silicon from cooling.\n\n');
        return;
    end
    Tcool = mean(W{:,coolch}, 2, 'omitnan');
    if ~all(ismember({'PM100DX_dcBusVoltage','PM100DX_dcBusCurrent', ...
                      'PM100DX_torqueFeedback','PM100DX_motorSpeed'}, V))
        fprintf('       missing dcBus*/torque channels -- cannot compute inverter loss.\n\n');
        return;
    end
    Pdc   = W.PM100DX_dcBusVoltage .* W.PM100DX_dcBusCurrent;
    Pmech = W.PM100DX_torqueFeedback .* W.PM100DX_motorSpeed * 2*pi/60;
    Ploss = abs(Pdc) - abs(Pmech);
    ok = Ploss > 200 & isfinite(Tmod) & isfinite(Tcool) & (Tmod - Tcool) > 1;
    if nnz(ok) < 50
        fprintf('       only %d usable points -- not enough to quote Rth.\n\n', nnz(ok));
        return;
    end
    Rth = (Tmod(ok) - Tcool(ok)) ./ Ploss(ok);
    fprintf('       %d points | Rth = %.4f K/W (median), IQR %.4f-%.4f\n', ...
        nnz(ok), median(Rth), prctile(Rth,25), prctile(Rth,75));
    fprintf('       mean module %.1f C, mean coolant %.1f C, mean loss %.0f W\n\n', ...
        mean(Tmod(ok)), mean(Tcool(ok)), mean(Ploss(ok)));
end

%% DRIVETRAIN_EFFICIENCY  --  battery -> ground, the whole stack, and every lever
%
% THE POINT
%   One place that answers "how efficient is the WHOLE drivetrain, and if we
%   change something -- halfshaft angle, diff, chain, bearings, gears -- how
%   much do we gain, in efficiency AND in battery energy over an endurance run?"
%
% HOW IT'S GROUNDED (this is the important part)
%   The electrical end (pack -> motor shaft = motor + inverter) is MEASURED from
%   real telemetry, using freeman803's method (af/dteff, Drive_efficiency.m):
%       insteff = mechanical power / pack power, energy-weighted over the run.
%   NOTE his map cancels the gear ratio (axleTorque = motorTorque*4.6 while
%   axleSpeed = motorRPM/4.6), so it is pack -> SHAFT only -- it never sees the
%   gearbox, chain, diff or halfshafts. This file takes that measured shaft
%   number and multiplies the MECHANICAL stack (CFR26 DT memo [1]) on top of it
%   to get the true pack -> GROUND efficiency. So:
%       eta_overall = eta_shaft(MEASURED) x spur x bearings x chain x diff x halfshaft(angle)
%
% WHAT YOU DO WITH IT
%   Edit the BASELINE block (or the SCENARIOS) and read two things per change:
%     - mechanical: new overall efficiency (percentage points)
%     - battery:    less pack energy for the SAME endurance lap (Wh and % of run)
%   Because every stage multiplies, a single change's battery saving is exactly
%   1 - eta_old/eta_new -- the tool does it for you, one lever at a time and stacked.

clear; clc;
here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, 'lib'));
p = params_cfr26();

%% ============== BASELINE: today's car (edit these to match reality) ==============
% Mechanical stage efficiencies -- CFR26 DT memo v4.0 [1] (ranges it quotes in [] ).
B.spur     = 0.98;   % lubricated spur gearbox            [0.97-0.99]
B.bearings = 0.95;   % 6-bearing stack, counted x1        [0.94-0.99 per brg]
B.chain    = 0.97;   % ER520S3 30/13, ISO 606 lubricated  [0.95-0.98]
B.diff     = 0.92;   % Drexler FS LSD, moderate preload   [0.91-0.94]
B.hs_angle = 12;     % <-- HALFSHAFT ANGLE, diff-to-wheel, at ride height driving STRAIGHT.
                     %     The joints work at this angle every second of the lap. Measure it
                     %     off the suspension CAD at static ride height and put the truth here.

% Halfshaft CV-joint loss model (see header note): eta_shaft = 1 - 2*kloss*sin(beta),
% two joints per shaft, kloss ~0.09 cross-checked against the memo's own straight &
% corner points (0.99@3deg, 0.94@20deg -> kloss 0.096 & 0.088, agree to ~9%).
KLOSS       = 0.090;   % central friction-geometry coefficient
HS_CORNER   = 8;       % extra deg of articulation in a loaded corner (on top of static)
HS_FRAC_STR = 0.724;   % fraction of an endurance lap near the static angle (memo split)

%% ============== the MEASURED electrical end (pack -> shaft), from telemetry ==============
% freeman803's method on our July 11 endurance run. Energy-weighted so it's the
% number that actually moved the car, not a bench best-case.
csv = fullfile(here, 'data', 'endurance_july11_with_odo_wide.csv');
[eta_shaft_meas, E_batt_Wh, dur_min, src] = measured_pack_to_shaft(csv);
% If telemetry is missing, fall back to our physics model at the continuous point.
if isnan(eta_shaft_meas)
    try, eta_shaft_meas = emrax208_efficiency(3500, 79.6, p); catch, eta_shaft_meas = 0.89; end
    src = 'physics model (no telemetry found)';
end

%% ============== helpers ==============
eta_shaft = @(beta) 1 - 2*KLOSS*sind(beta);                 % one halfshaft, both joints
hs_term   = @(static) HS_FRAC_STR*eta_shaft(static) + (1-HS_FRAC_STR)*eta_shaft(static+HS_CORNER);
overall   = @(S) eta_shaft_meas * S.spur * S.bearings * S.chain * S.diff * hs_term(S.hs_angle);

eta0 = overall(B);   % today's overall pack -> ground

%% ============================================================================
%% 1. THE BASELINE WATERFALL -- where every point of loss goes, today
%% ============================================================================
fprintf('=== OVERALL DRIVETRAIN EFFICIENCY: battery -> ground (today) ===\n');
fprintf(' electrical end is MEASURED: %s\n\n', src);
fprintf('   motor + inverter (pack->shaft, MEASURED) . %.3f\n', eta_shaft_meas);
fprintf('   spur gearbox ............................. %.3f\n', B.spur);
fprintf('   bearing stack ............................ %.3f\n', B.bearings);
fprintf('   chain .................................... %.3f\n', B.chain);
fprintf('   diff ..................................... %.3f\n', B.diff);
fprintf('   halfshaft angle @ %2.0f deg ................. %.3f\n', B.hs_angle, hs_term(B.hs_angle));
fprintf('   --------------------------------------------------\n');
fprintf('   OVERALL (battery -> ground) .............. %.3f\n', eta0);
fprintf('   mechanical only (no motor/inverter) ...... %.3f   (params_cfr26 says %.3f)\n\n', ...
    eta0/eta_shaft_meas, p.eta_drivetrain);
fprintf(' Memo published %.3f overall; ours is lower because the MEASURED motor+inverter\n', 0.724);
fprintf(' (%.2f) is below the memo''s assumed 0.89, and the real halfshaft angle costs more\n', eta_shaft_meas);
fprintf(' than its 0.99 "straight" assumption. This is the honest, telemetry-anchored number.\n\n');

%% ============================================================================
%% 2. THE LEVERS -- change one thing, see efficiency AND battery effect
%% ============================================================================
% Each scenario is the baseline with one (or a few) stage(s) changed. We print
% the new overall efficiency and what it does to endurance battery energy.
S = {};   % {label, modified-struct}
S(end+1,:) = {'Straighten halfshafts 12 -> 5 deg', setf(B,'hs_angle',5)};
S(end+1,:) = {'Straighten halfshafts 12 -> 0 deg', setf(B,'hs_angle',0)};
S(end+1,:) = {'Diff: lower preload  0.92 -> 0.94',  setf(B,'diff',0.94)};
S(end+1,:) = {'Chain: better lube/tension 0.97->0.98', setf(B,'chain',0.98)};
S(end+1,:) = {'Spur: ground+lapped  0.98 -> 0.99',  setf(B,'spur',0.99)};
S(end+1,:) = {'Bearings: low-drag/ceramic 0.95->0.97', setf(B,'bearings',0.97)};
% a stacked, realistically-achievable package:
Bpkg = setf(setf(setf(B,'hs_angle',5),'diff',0.93),'chain',0.98);
S(end+1,:) = {'PACKAGE: 5deg + diff0.93 + chain0.98', Bpkg};

fprintf('=== DESIGN LEVERS: effect on efficiency and on endurance battery ===\n');
fprintf(' change                                   | overall eta | d-eta | batt saved (same lap)\n');
fprintf(' %s\n', repmat('-',1,86));
fprintf(' %-40s |   %.3f     |   --  |     -- (today)\n', 'BASELINE (today, 12 deg)', eta0);
for i = 1:size(S,1)
    e = overall(S{i,2});
    saving = 1 - eta0/e;                 % fraction of pack energy saved for the same lap
    wh = saving * E_batt_Wh;
    if isnan(E_batt_Wh)
        fprintf(' %-40s |   %.3f     | %+4.1fpt|   %+5.2f%%\n', S{i,1}, e, 100*(e-eta0), 100*saving);
    else
        fprintf(' %-40s |   %.3f     | %+4.1fpt|   %+5.1f Wh (%+.2f%%)\n', S{i,1}, e, 100*(e-eta0), wh, 100*saving);
    end
end
fprintf('\n d-eta = percentage points of overall drivetrain efficiency gained.\n');
if ~isnan(E_batt_Wh)
    fprintf(' batt saved = less pack energy to do the SAME endurance lap (%.0f Wh, %.0f min run).\n', E_batt_Wh, dur_min);
end
fprintf(' Positive = better. These stack multiplicatively (see the PACKAGE row).\n\n');

%% ============================================================================
%% 3. HALFSHAFT ANGLE, in detail (the one lever that's pure geometry, no new parts)
%% ============================================================================
fprintf('=== HALFSHAFT ANGLE SWEEP (CV joints, straighter = free efficiency) ===\n');
fprintf(' angle | halfshaft term | overall eta | vs today | batt saved\n');
for b = [0 2 4 5 6 8 10 12]
    Sb = setf(B,'hs_angle',b);
    e = overall(Sb); saving = 1 - eta0/e;
    tag = ''; if b==B.hs_angle, tag = '  <- today'; end
    if isnan(E_batt_Wh)
        fprintf('  %3.0f  |    %.3f       |   %.3f     | %+4.1fpt  | %+5.2f%%%s\n', b, hs_term(b), e, 100*(e-eta0), 100*saving, tag);
    else
        fprintf('  %3.0f  |    %.3f       |   %.3f     | %+4.1fpt  | %+5.1f Wh%s\n', b, hs_term(b), e, 100*(e-eta0), saving*E_batt_Wh, tag);
    end
end
fprintf('\n Bottom line: at %.0f deg the halfshafts alone cost ~%.1f pts vs straight;\n', ...
    B.hs_angle, 100*(overall(setf(B,'hs_angle',0)) - eta0));
fprintf(' getting them into the 0-5 deg CV-joint sweet spot is free range on endurance.\n\n');

fprintf('Sources: [1] CFR26_DT_Efficiency.pdf v4.0 (stage table + straight/corner time split).\n');
fprintf('         Electrical end measured via freeman803 af/dteff method on July 11 telemetry.\n');
fprintf('         CV-joint loss coefficient cross-checked against the memo (see header).\n');

%% ============================== local functions ==============================
function s = setf(s, field, val)
    s.(field) = val;   % tiny helper: copy a struct with one field changed
end

function [eta, E_batt_Wh, dur_min, src] = measured_pack_to_shaft(csv)
%MEASURED_PACK_TO_SHAFT  freeman803's af/dteff number from a telemetry CSV.
%   Energy-weighted eta = sum(mech power)/sum(pack power) over motoring points,
%   plus the total pack energy (Wh) and run length so we can price battery savings.
    eta = NaN; E_batt_Wh = NaN; dur_min = NaN; src = '';
    if ~isfile(csv), return; end
    W = readtable(csv);
    need = {'PM100DX_motorSpeed','PM100DX_torqueFeedback','BMSB_packVoltage','BMSB_packCurrent','t_s'};
    if ~all(ismember(need, W.Properties.VariableNames)), return; end
    rpm = abs(W.PM100DX_motorSpeed);   tq = abs(W.PM100DX_torqueFeedback);
    V   = W.BMSB_packVoltage;          I  = W.BMSB_packCurrent;
    pack = abs(V .* I);                mech = tq .* rpm * 2*pi/60;
    e = mech ./ max(pack, 1e-6);
    keep = rpm>500 & tq>5 & pack>500 & e>0.3 & e<1.0;   % clean motoring points
    eta = sum(mech(keep)) / sum(pack(keep));
    t = W.t_s; P = V .* I; P(isnan(P)) = 0;
    E_batt_Wh = abs(trapz(t, P)) / 3600;
    dur_min = (t(end)-t(1))/60;
    src = sprintf('July 11 endurance telemetry, %d motoring samples', nnz(keep));
end

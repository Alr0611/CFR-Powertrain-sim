%% DRIVETRAIN_EFFICIENCY  --  battery -> ground, the whole stack, and every lever
%
% THE POINT
%   One place that answers "how efficient is the WHOLE drivetrain, and if we
%   change something -- halfshaft angle, diff, chain, bearings, gears -- how
%   much do we gain, in efficiency AND in battery over an endurance run?"
%   Everything is a PERCENTAGE, the way freeman803's Drive_efficiency.m reports
%   it (overall eff = mechanical power / pack power).
%
% HOW IT'S GROUNDED
%   The electrical end (pack -> motor shaft = motor + inverter) is MEASURED from
%   real telemetry, freeman803's af/dteff method: eff = mech power / pack power,
%   energy-weighted over the run. His map cancels the gear ratio (axleTorque =
%   motorTorque*4.6 while axleSpeed = motorRPM/4.6), so it is pack -> SHAFT only.
%   This file multiplies the MECHANICAL stack (CFR26 DT memo v4.0 [1]) on top:
%       eff_overall = eff_shaft(MEASURED) x spur x bearings x chain x diff x halfshaft(angle)
%
% WHAT YOU GET
%   - printed: the full waterfall + every design lever priced two ways
%              (new overall efficiency %, and battery saved on an endurance lap)
%   - figures (saved to output/): the waterfall, the halfshaft-angle sweep, a
%              levers comparison, and the MEASURED efficiency map (the twin of
%              freeman803's surf plot, for a side-by-side).

clear; clc;
here = fileparts(mfilename('fullpath'));
addpath(genpath(here));
p = params_cfr26();

%% ============== BASELINE: today's car (edit these to match reality) ==============
% Mechanical stage efficiencies -- CFR26 DT memo v4.0 [1] (ranges it quotes in []).
B.spur     = 0.98;   % lubricated spur gearbox            [0.97-0.99]
B.bearings = 0.95;   % 6-bearing stack, counted x1        [0.94-0.99 per brg]
B.chain    = 0.97;   % ER520S3 30/13, ISO 606 lubricated  [0.95-0.98]
B.diff     = 0.92;   % Drexler FS LSD, moderate preload   [0.91-0.94]
B.hs_angle = 12;     % <-- HALFSHAFT ANGLE, diff-to-wheel, at ride height driving STRAIGHT.
                     %     The joints work at this angle every second of the lap. Measure it
                     %     off the suspension CAD at static ride height and put the truth here.

% Halfshaft CV-joint loss model: eff_shaft = 1 - 2*kloss*sin(beta), two joints per
% shaft, kloss ~0.09 cross-checked against the memo's own straight & corner points
% (0.99@3deg, 0.94@20deg -> kloss 0.096 & 0.088, agree to ~9%).
KLOSS       = 0.090;   % friction-geometry coefficient
HS_CORNER   = 8;       % extra deg of articulation in a loaded corner (on top of static)
HS_FRAC_STR = 0.724;   % fraction of an endurance lap near the static angle (memo split)

%% ============== the MEASURED electrical end (pack -> shaft), from telemetry ==============
csv = fullfile(here, 'data', 'endurance_july11_with_odo_wide.csv');
[eff_shaft, E_batt_Wh, dur_min, src] = measured_pack_to_shaft(csv);
if isnan(eff_shaft)   % no telemetry -> fall back to our physics model at the continuous point
    try, eff_shaft = emrax208_efficiency(3500, 79.6, p); catch, eff_shaft = 0.89; end
    src = 'physics model (no telemetry found)';
end

%% ============== helpers ==============
eff_hs   = @(beta) 1 - 2*KLOSS*sind(beta);                       % one halfshaft, both joints
hs_term  = @(static) HS_FRAC_STR*eff_hs(static) + (1-HS_FRAC_STR)*eff_hs(static+HS_CORNER);
mech     = B.spur * B.bearings * B.chain * B.diff;              % mech stack minus the halfshaft
overall  = @(S) eff_shaft * S.spur * S.bearings * S.chain * S.diff * hs_term(S.hs_angle);
pct      = @(x) 100*x;

eff0 = overall(B);   % today's overall pack -> ground

%% ============================================================================
%% 1. THE BASELINE WATERFALL -- where every bit of loss goes, today (all %)
%% ============================================================================
fprintf('=== OVERALL DRIVETRAIN EFFICIENCY: battery -> ground (today) ===\n');
fprintf(' electrical end is MEASURED: %s\n\n', src);
fprintf('   motor + inverter (pack->shaft, MEASURED) . %5.1f%%\n', pct(eff_shaft));
fprintf('   spur gearbox ............................. %5.1f%%\n', pct(B.spur));
fprintf('   bearing stack ............................ %5.1f%%\n', pct(B.bearings));
fprintf('   chain .................................... %5.1f%%\n', pct(B.chain));
fprintf('   diff ..................................... %5.1f%%\n', pct(B.diff));
fprintf('   halfshaft angle @ %2.0f deg ................. %5.1f%%\n', B.hs_angle, pct(hs_term(B.hs_angle)));
fprintf('   --------------------------------------------------\n');
fprintf('   OVERALL (battery -> ground) .............. %5.1f%%\n', pct(eff0));
fprintf('   mechanical only (no motor/inverter) ...... %5.1f%%   (params_cfr26 says %.1f%%)\n\n', ...
    pct(eff0/eff_shaft), pct(p.eta_drivetrain));
fprintf(' Memo published 72.4%% overall; ours is lower because the MEASURED motor+inverter\n');
fprintf(' (%.1f%%) is below the memo''s assumed 89%%, and the real halfshaft angle costs more\n', pct(eff_shaft));
fprintf(' than its 99%% "straight" assumption. This is the honest, telemetry-anchored number.\n\n');

%% ============================================================================
%% 2. THE LEVERS -- change one thing, see efficiency % AND battery effect
%% ============================================================================
S = {};   % {label, modified-struct}
S(end+1,:) = {'Straighten halfshafts 12 -> 5 deg',   setf(B,'hs_angle',5)};
S(end+1,:) = {'Straighten halfshafts 12 -> 0 deg',   setf(B,'hs_angle',0)};
S(end+1,:) = {'Diff: lower preload  92 -> 94%',       setf(B,'diff',0.94)};
S(end+1,:) = {'Chain: better lube/tension 97 -> 98%', setf(B,'chain',0.98)};
S(end+1,:) = {'Spur: ground+lapped  98 -> 99%',       setf(B,'spur',0.99)};
S(end+1,:) = {'Bearings: low-drag/ceramic 95 -> 97%', setf(B,'bearings',0.97)};
S(end+1,:) = {'PACKAGE: 5deg + diff93 + chain98',     setf(setf(setf(B,'hs_angle',5),'diff',0.93),'chain',0.98)};

fprintf('=== DESIGN LEVERS: new overall efficiency, and battery saved on an endurance lap ===\n');
fprintf(' change                                   | overall eff | battery saved (same lap)\n');
fprintf(' %s\n', repmat('-',1,78));
fprintf(' %-40s |   %5.1f%%    |     -- (today)\n', 'BASELINE (today, 12 deg)', pct(eff0));
for i = 1:size(S,1)
    e = overall(S{i,2});  saving = 1 - eff0/e;   % battery fraction saved for the same lap
    if isnan(E_batt_Wh)
        fprintf(' %-40s |   %5.1f%%    |   +%.2f%%\n', S{i,1}, pct(e), pct(saving));
    else
        fprintf(' %-40s |   %5.1f%%    |   +%.1f Wh (+%.2f%%)\n', S{i,1}, pct(e), saving*E_batt_Wh, pct(saving));
    end
end
if ~isnan(E_batt_Wh)
    fprintf('\n battery saved = less pack energy to do the SAME endurance lap (%.0f Wh, %.0f min run).\n', E_batt_Wh, dur_min);
end
fprintf(' Changes stack multiplicatively -- see the PACKAGE row.\n\n');

%% ============================================================================
%% 3. HALFSHAFT ANGLE SWEEP -- the one lever that's pure geometry, no new parts
%% ============================================================================
fprintf('=== HALFSHAFT ANGLE SWEEP (CV joints, straighter = free efficiency) ===\n');
fprintf(' angle | halfshaft | overall eff | battery saved\n');
for b = [0 2 4 5 6 8 10 12]
    e = overall(setf(B,'hs_angle',b));  saving = 1 - eff0/e;
    tag = ''; if b==B.hs_angle, tag = '  <- today'; end
    if isnan(E_batt_Wh)
        fprintf('  %3.0f  |  %5.1f%%   |   %5.1f%%    |  +%.2f%%%s\n', b, pct(hs_term(b)), pct(e), pct(saving), tag);
    else
        fprintf('  %3.0f  |  %5.1f%%   |   %5.1f%%    |  +%.1f Wh%s\n', b, pct(hs_term(b)), pct(e), saving*E_batt_Wh, tag);
    end
end
fprintf('\n Bottom line: at %.0f deg the halfshafts cost the drivetrain ~%.1f%% vs straight;\n', ...
    B.hs_angle, pct(overall(setf(B,'hs_angle',0)) - eff0));
fprintf(' getting them into the 0-5 deg CV-joint sweet spot is free range on endurance.\n\n');

%% ============================================================================
%% 4. FIGURES (saved to output/)  -- so you can actually SEE and compare
%% ============================================================================
outdir = fullfile(here,'output'); if ~exist(outdir,'dir'), mkdir(outdir); end
figs = gobjects(0);

% ---- Fig 1: waterfall -- energy remaining (%) after each stage, today ----
lbl   = {'Battery','+ motor/inv','+ spur','+ bearings','+ chain','+ diff', sprintf('+ halfshaft@%d°',B.hs_angle)};
efac  = [1, eff_shaft, B.spur, B.bearings, B.chain, B.diff, hs_term(B.hs_angle)];
remain = cumprod(efac)*100;
f1 = figure('Name','DT efficiency waterfall','Position',[60 60 860 470]);
bar(remain,'FaceColor',[0.20 0.45 0.72],'EdgeColor','none'); hold on; grid on; ylim([0 112]);
set(gca,'XTick',1:numel(lbl),'XTickLabel',lbl); xtickangle(20);
ylabel('Energy remaining (%)');
text(1:numel(remain), remain+2.2, compose('%.1f%%',remain), 'HorizontalAlignment','center','FontWeight','bold');
title(sprintf('Battery \\rightarrow ground: %.1f%% reaches the wheels (today, %d° halfshafts)', remain(end), B.hs_angle));
figs(end+1) = f1;

% ---- Fig 2: halfshaft angle sweep -- overall eff and battery saved vs angle ----
angs  = 0:0.5:12;
ov_a  = arrayfun(@(bb) overall(setf(B,'hs_angle',bb)), angs)*100;
sv_a  = (1 - eff0./(ov_a/100))*100;
f2 = figure('Name','Halfshaft angle sweep','Position',[70 70 820 470]);
yyaxis left;  plot(angs, ov_a,'-','LineWidth',1.8); ylabel('Overall drivetrain efficiency (%)');
yyaxis right; plot(angs, sv_a,'--','LineWidth',1.5); ylabel('Endurance battery saved (%)');
xlabel('Halfshaft static angle (deg)'); grid on; xlim([0 12]);
xline(B.hs_angle,'r:','LineWidth',1.3,'Label',sprintf('today %d°',B.hs_angle),'LabelOrientation','horizontal');
title('Straighter halfshafts \rightarrow higher efficiency, less battery per lap');
figs(end+1) = f2;

% ---- Fig 3: design levers -- battery saved (%) per change, sorted ----
lev_lbl = S(:,1);
lev_sv  = cellfun(@(s) (1-eff0/overall(s))*100, S(:,2));
[svs, idx] = sort(lev_sv);
f3 = figure('Name','Design levers','Position',[80 80 900 470]);
barh(svs,'FaceColor',[0.30 0.62 0.40],'EdgeColor','none'); grid on;
set(gca,'YTick',1:numel(lev_lbl),'YTickLabel',lev_lbl(idx));
xlabel('Endurance battery saved (%)');
text(svs+0.05, 1:numel(svs), compose('%.2f%%',svs), 'VerticalAlignment','middle');
title('Which change buys the most range');
figs(end+1) = f3;

% ---- Fig 4: MEASURED efficiency map (the twin of freeman803's surf plot) ----
if isfile(csv)
    Wm = readtable(csv);
    M  = measured_efficiency_map(Wm.PM100DX_motorSpeed, Wm.PM100DX_torqueFeedback, ...
                                 Wm.BMSB_packVoltage,  Wm.BMSB_packCurrent);
    f4 = figure('Name','Measured pack-to-shaft map','Position',[90 90 760 470]);
    imagesc(M.rpmCenters, M.tqCenters, M.eff*100, 'AlphaData', ~isnan(M.eff)); axis xy;
    colormap(parula); cb = colorbar; cb.Label.String = 'Motor+inverter eff (%)'; caxis([70 95]);
    xlabel('Motor rpm'); ylabel('Motor torque (Nm)');
    title(sprintf('MEASURED motor+inverter map (af/dteff method), overall %.1f%%', M.eff_overall*100));
    figs(end+1) = f4;
end

for fh = figs
    nm = fullfile(outdir, matlab.lang.makeValidName(['DTeff_' fh.Name]));
    savefig(fh, [nm '.fig']); try, saveas(fh, [nm '.png']); catch, end
end
fprintf('Saved %d figures to output/ (waterfall, angle sweep, levers, measured map).\n\n', numel(figs));

fprintf('Sources: [1] CFR26_DT_Efficiency.pdf v4.0 (stage table + straight/corner time split).\n');
fprintf('         Electrical end measured via freeman803 af/dteff method on July 11 telemetry.\n');
fprintf('         CV-joint loss coefficient cross-checked against the memo (see header).\n');

%% ============================== local functions ==============================
function s = setf(s, field, val)
    s.(field) = val;   % copy a struct with one field changed
end

function [eff, E_batt_Wh, dur_min, src] = measured_pack_to_shaft(csv)
%MEASURED_PACK_TO_SHAFT  freeman803's af/dteff number from a telemetry CSV.
%   Energy-weighted eff = sum(mech power)/sum(pack power) over motoring points,
%   plus total pack energy (Wh) and run length so we can price battery savings.
    eff = NaN; E_batt_Wh = NaN; dur_min = NaN; src = '';
    if ~isfile(csv), return; end
    W = readtable(csv);
    need = {'PM100DX_motorSpeed','PM100DX_torqueFeedback','BMSB_packVoltage','BMSB_packCurrent','t_s'};
    if ~all(ismember(need, W.Properties.VariableNames)), return; end
    rpm = abs(W.PM100DX_motorSpeed);  tq = abs(W.PM100DX_torqueFeedback);
    V   = W.BMSB_packVoltage;         I  = W.BMSB_packCurrent;
    pack = abs(V .* I);               mechP = tq .* rpm * 2*pi/60;
    e = mechP ./ max(pack, 1e-6);
    keep = rpm>500 & tq>5 & pack>500 & e>0.3 & e<1.0;   % clean motoring points
    eff = sum(mechP(keep)) / sum(pack(keep));
    t = W.t_s; P = V .* I; P(isnan(P)) = 0;
    E_batt_Wh = abs(trapz(t, P)) / 3600;
    dur_min = (t(end)-t(1))/60;
    src = sprintf('July 11 endurance telemetry, %d motoring samples', nnz(keep));
end

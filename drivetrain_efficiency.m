%% DRIVETRAIN_EFFICIENCY  --  battery -> ground, the whole stack, and every lever
%
% The goal of this script
%   how efficient is the WHOLE drivetrain, and if we
%   change something -- halfshaft angle, diff, chain, bearings, gears -- how
%   much do we gain, in efficiency AND in battery over an endurance run?"
%   Everything is a PERCENTAGE, the way freeman803's Drive_efficiency.m reports
%   it (overall eff = mechanical power / pack power).
%
% How its grounded
%   The electrical end (pack -> motor shaft = motor + inverter) is MEASURED from
%   real telemetry, freeman803's af/dteff method: eff = mech power / pack power,
%   energy-weighted over the run. His map cancels the gear ratio (axleTorque =
%   motorTorque*4.6 while axleSpeed = motorRPM/4.6), so it is pack -> SHAFT only.
%   This file multiplies the MECHANICAL stack (CFR26 DT memo v4.0 [1]) on top:
%       eff_overall = eff_shaft(MEASURED) x spur x bearings x chain x diff x halfshaft(angle)
%
% Results
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
% AS-DRIVEN efficiency + energy come from the ENDURANCE run (the relevant duty cycle).
% The in-band CEILING (motor actually loaded) comes from the harder COMP session's
% steady-state points -- endurance's own steady points are still part-load.
csv   = fullfile(here, 'data', 'endurance_july11_with_odo_wide.csv');
comp  = fullfile(here, 'data', 'comp_june20_data.csv');
[eff_shaft, ~, E_batt_Wh, dur_min, src] = measured_pack_to_shaft(csv);    % as-driven + energy
[~, eff_inband]                          = measured_pack_to_shaft(comp);   % loaded-motor ceiling
if isnan(eff_shaft)   % no telemetry -> fall back to our physics model at the continuous point
    try, eff_shaft = emrax208_efficiency(3500, 79.6, p); catch, eff_shaft = 0.89; end
    src = 'physics model (no telemetry found)';
end
if isnan(eff_inband), eff_inband = 0.86; end   % measured steady-state ceiling (verify_math sec 15)

%% ============== helpers ==============
eff_hs   = @(beta) 1 - 2*KLOSS*sind(beta);                       % one halfshaft, both joints
hs_term  = @(static) HS_FRAC_STR*eff_hs(static) + (1-HS_FRAC_STR)*eff_hs(static+HS_CORNER);
mech     = B.spur * B.bearings * B.chain * B.diff;              % mech stack minus the halfshaft
eff_hw   = mech * hs_term(B.hs_angle);                         % HARDWARE only (mech incl halfshaft@current angle)
overall  = @(S) eff_shaft * S.spur * S.bearings * S.chain * S.diff * hs_term(S.hs_angle);
pct      = @(x) 100*x;
memo_ref = 0.89 * 0.98 * mech;   % reproduce memo v4.0 with ITS assumptions (89% motor, 0.98 halfshaft)

eff0 = overall(B);   % current overall pack -> ground, AS-DRIVEN (motor at its endurance part-load)

%% ============================================================================
%% 1. THE HEADLINE -- hardware first, then the motor, then the honest overall
%% ============================================================================
% Lead with the HARDWARE number (motor-independent). The battery->ground figure is
% split into a hardware-limited ceiling and a separate, labeled part-load cost, so
% nobody reads "62%" as "our drivetrain hardware is 62% efficient" -- it isn't.
fprintf('=== DRIVETRAIN EFFICIENCY: battery -> ground ===\n');
fprintf(' (electrical end MEASURED from telemetry: %s)\n\n', src);

fprintf(' HARDWARE -- the physical drivetrain, motor-independent:\n');
fprintf('   spur %.0f%% x bearings %.0f%% x chain %.0f%% x diff %.0f%% x halfshaft@%ddeg %.1f%%\n', ...
    pct(B.spur), pct(B.bearings), pct(B.chain), pct(B.diff), B.hs_angle, pct(hs_term(B.hs_angle)));
fprintf('   = %.1f%% mechanical hardware efficiency   (params_cfr26 eta_drivetrain = %.1f%%)\n\n', ...
    pct(eff_hw), pct(p.eta_drivetrain));

fprintf(' MOTOR + INVERTER -- THREE numbers, each measuring a different thing:\n');
fprintf('   ~90%%   physics model x eta_inverter at operating points -- gear_ratio_optimization\n');
fprintf('          uses THIS to RANK ratios; it is a mild optimistic bound (verify_math sec 15)\n');
fprintf('   %.1f%%  in efficient band -- MEASURED steady-state, comp session (motor loaded)\n', pct(eff_inband));
fprintf('   %.1f%%  as-driven -- MEASURED energy-weighted over the July 11 endurance run;\n', pct(eff_shaft));
fprintf('          endurance is driven gently, so even its steady points sit here (part-load,\n');
fprintf('          not a transient artifact).\n\n');

fprintf(' OVERALL = motor x hardware:\n');
fprintf('   %.1f%%  memo v4.0 -- we REPRODUCE it from the memo''s own assumptions (89%% motor,\n', pct(memo_ref));
fprintf('          0.98 halfshaft), confirming our stack is consistent with the memo\n');
fprintf('   %.1f%%  in-band ceiling: %.1f%% motor x %.1f%% hardware -- realistic best (motor loaded)\n', ...
    pct(eff_inband*eff_hw), pct(eff_inband), pct(eff_hw));
fprintf('   %.1f%%  as-driven: %.1f%% motor x %.1f%% hardware -- what the endurance lap delivered\n', ...
    pct(eff_shaft*eff_hw), pct(eff_shaft), pct(eff_hw));
fprintf('\n The %.1f -> %.1f%% drop is a PART-LOAD / OPERATIONAL cost (motor off its efficient\n', ...
    pct(eff_inband*eff_hw), pct(eff_shaft*eff_hw));
fprintf(' band much of an endurance lap) -- a gearing/driving lever (gear_ratio_optimization),\n');
fprintf(' NOT a hardware loss. The hardware is %.1f%% regardless of how it is driven.\n\n', pct(eff_hw));

%% ============================================================================
%% 2. WHERE THE LOSSES ARE + HEADROOM PER STAGE (every stage, same treatment)
%% ============================================================================
% Each stage gets the same treatment: how much it throws away now, a realistic
% best (top of the memo's quoted range / straight halfshafts / motor kept in its
% efficient band), and what closing that gap buys. Everything multiplies, so a
% stage going current c -> best b lifts overall by b/c and saves 1 - c/b of the pack.
St = {  % name                current               best         how you'd get there
    'motor + inverter',   eff_shaft,            eff_inband, 'OPERATIONAL: keep motor loaded / in its efficient band (measured ceiling) -- gear_ratio_optimization';
    'diff (LSD preload)', B.diff,               0.94,       'lower preload (top of Drexler range)';
    'bearing stack',      B.bearings,           0.97,       'low-drag / ceramic-hybrid bearings';
    'halfshaft angle',    hs_term(B.hs_angle),  hs_term(0), 'straighten geometry 12 -> 0 deg (CV joints)';
    'chain',              B.chain,              0.98,       'better lube + correct tension (top of ISO 606 range)';
    'spur gearbox',       B.spur,               0.99,       'ground + lapped teeth (top of AGMA range)'};
names = St(:,1); cur = cell2mat(St(:,2)); best = cell2mat(St(:,3));
loss_now = (1-cur)*100;  gain_ov = eff0.*(best./cur - 1)*100;  save_fr = 1 - cur./best;
[~,ord] = sort(save_fr,'descend');

fprintf('=== WHERE THE LOSSES ARE + HEADROOM PER STAGE (biggest opportunity first) ===\n');
fprintf(' stage              |  now -> best | loss now | overall gain | battery saved\n');
fprintf(' %s\n', repmat('-',1,80));
for i = ord'
    fprintf(' %-18s | %4.1f -> %4.1f | %5.1f%%   |   +%.2f%%     | %s\n', ...
        names{i}, pct(cur(i)), pct(best(i)), loss_now(i), gain_ov(i), battxt(save_fr(i), E_batt_Wh));
end
fprintf('\n loss now = %% of the energy entering that stage that it turns into heat.\n');
fprintf(' Motor+inverter is the biggest loss, but most of it is OPERATIONAL (keep the motor\n');
fprintf(' loaded) -- that''s the gear-ratio study''s job. The stages under it are hardware.\n\n');

%% ============================================================================
%% 3. STACKED PACKAGES + the halfshaft geometry sweep
%% ============================================================================
r = @(row) best(row)/cur(row);                     % improvement factor for a stage row
p_hw  = eff0 * r(2)*r(3)*r(5)*r(6);                 % all four mechanical hardware stages
p_hw5 = p_hw * (hs_term(5)/hs_term(B.hs_angle));   % + straighten halfshafts to 5 deg
p_hw0 = p_hw * (hs_term(0)/hs_term(B.hs_angle));   % + straighten to 0 deg
prow  = @(lbl,e) fprintf(' %-44s | %5.1f%% | %s\n', lbl, pct(e), battxt(1-eff0/e, E_batt_Wh));
fprintf('=== STACKED PACKAGES (hardware you''d change together) ===\n');
fprintf(' package                                      | overall | battery saved\n');
fprintf(' %s\n', repmat('-',1,74));
prow('Hardware only (diff + bearings + chain + spur)', p_hw);
prow('Hardware + straighten halfshafts to 5 deg',      p_hw5);
prow('Hardware + straighten halfshafts to 0 deg',      p_hw0);
fprintf(' (motor+inverter left out -- that''s operational, via the gear ratio.)\n\n');

fprintf('=== HALFSHAFT ANGLE SWEEP (the one continuous knob, pure geometry) ===\n');
fprintf(' angle | halfshaft | overall eff | battery saved\n');
for b = [0 2 4 5 6 8 10 12]
    e = overall(setf(B,'hs_angle',b));
    tag = ''; if b==B.hs_angle, tag = '  <- current'; end
    fprintf('  %3.0f  |  %5.1f%%   |   %5.1f%%    |  %s%s\n', ...
        b, pct(hs_term(b)), pct(e), battxt(1-eff0/e, E_batt_Wh), tag);
end
% Target band: 0-5 deg is the CV-joint sweet spot. The exact angle in there is set
% by diff packaging, not efficiency, so report the whole band as a RANGE, not a point.
e_str = overall(setf(B,'hs_angle',0));   % straight-ish end
e_5   = overall(setf(B,'hs_angle',5));   % 5 deg end
fprintf('\n TARGET BAND -- halfshafts in the 0-5 deg CV-joint sweet spot (a RANGE, not a point):\n');
fprintf('   halfshaft term : %.1f%% (@5 deg)  ..  %.1f%% (@0 deg)\n', pct(hs_term(5)), pct(hs_term(0)));
fprintf('   overall DT eff : %.1f%%  ..  %.1f%%   (up from %.1f%% at the current %.0f deg)\n', ...
    pct(e_5), pct(e_str), pct(eff0), B.hs_angle);
fprintf('   battery saved  : %s  ..  %s  per endurance lap\n', ...
    battxt(1-eff0/e_5, E_batt_Wh), battxt(1-eff0/e_str, E_batt_Wh));
fprintf('   Inside 0-5 deg the number barely moves -- getting OFF %.0f deg is the whole win;\n', B.hs_angle);
fprintf('   the exact angle is a diff-packaging call, not an efficiency one.\n\n');

%% ============================================================================
%% 4. FIGURES (saved to output/)  -- so you can actually SEE and compare
%% ============================================================================
outdir = fullfile(here,'output'); if ~exist(outdir,'dir'), mkdir(outdir); end
figs = gobjects(0);

% ---- Fig 1: waterfall -- energy remaining (%) after each stage, current car ----
lbl   = {'Battery','+ motor/inv','+ spur','+ bearings','+ chain','+ diff', sprintf('+ halfshaft@%d°',B.hs_angle)};
efac  = [1, eff_shaft, B.spur, B.bearings, B.chain, B.diff, hs_term(B.hs_angle)];
remain = cumprod(efac)*100;
f1 = figure('Name','DT efficiency waterfall','Position',[60 60 860 470]);
bar(remain,'FaceColor',[0.20 0.45 0.72],'EdgeColor','none'); hold on; grid on; ylim([0 112]);
set(gca,'XTick',1:numel(lbl),'XTickLabel',lbl); xtickangle(20);
ylabel('Energy remaining (%)');
text(1:numel(remain), remain+2.2, compose('%.1f%%',remain), 'HorizontalAlignment','center','FontWeight','bold');
title(sprintf('Battery \\rightarrow ground, as-driven: %.1f%% reaches the wheels at %d° halfshafts', remain(end), B.hs_angle));
figs(end+1) = f1;

% ---- Fig 2: halfshaft angle sweep -- overall eff and battery saved vs angle ----
angs  = 0:0.5:12;
ov_a  = arrayfun(@(bb) overall(setf(B,'hs_angle',bb)), angs)*100;
sv_a  = (1 - eff0./(ov_a/100))*100;
f2 = figure('Name','Halfshaft angle sweep','Position',[70 70 820 470]);
yyaxis left;  plot(angs, ov_a,'-','LineWidth',1.8); ylabel('Overall drivetrain efficiency (%)');
yyaxis right; plot(angs, sv_a,'--','LineWidth',1.5); ylabel('Endurance battery saved (%)');
xlabel('Halfshaft static angle (deg)'); grid on; xlim([0 12]);
try, xregion(0,5,'FaceColor',[0.30 0.62 0.40],'FaceAlpha',0.12); catch, end   % 0-5 deg target band
xline(B.hs_angle,'r:','LineWidth',1.3,'Label',sprintf('current %d°',B.hs_angle),'LabelOrientation','horizontal');
xline(5,'-','Color',[0.30 0.62 0.40],'LineWidth',1.0,'Label','0-5° target band','LabelOrientation','horizontal','LabelVerticalAlignment','bottom');
title('Straighter halfshafts \rightarrow higher efficiency, less battery per lap');
figs(end+1) = f2;

% ---- Fig 3: per-stage opportunity -- battery saved (%) if each stage hits its best ----
[svs, idx] = sort(save_fr*100);
f3 = figure('Name','Per-stage opportunity','Position',[80 80 960 470]);
barh(svs,'FaceColor',[0.30 0.62 0.40],'EdgeColor','none'); grid on;
set(gca,'YTick',1:numel(names),'YTickLabel',names(idx));
xlabel('Endurance battery saved if this stage reaches its realistic best (%)');
text(svs+0.1, 1:numel(svs), compose('%.1f%%',svs), 'VerticalAlignment','middle');
title('Where the range is: every stage, ranked');
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
fprintf('Saved %d figures to output/ (waterfall, angle sweep, per-stage opportunity, measured map).\n\n', numel(figs));

fprintf('Sources: [1] CFR26_DT_Efficiency.pdf v4.0 (stage table + straight/corner time split).\n');
fprintf('         Electrical end measured via freeman803 af/dteff method on July 11 telemetry.\n');
fprintf('         CV-joint loss coefficient cross-checked against the memo (see header).\n');

%% ============================== local functions ==============================
function s = setf(s, field, val)
    s.(field) = val;   % copy a struct with one field changed
end

function s = battxt(frac, Wh)
    % battery-saved cell: "+NN Wh (+X.XX%)" if we know the run energy, else "+X.XX%"
    if isnan(Wh), s = sprintf('+%.2f%%', frac*100);
    else,         s = sprintf('+%.0f Wh (+%.2f%%)', frac*Wh, frac*100); end
end

function [eff, eff_steady, E_batt_Wh, dur_min, src] = measured_pack_to_shaft(csv)
%MEASURED_PACK_TO_SHAFT  freeman803's af/dteff number from a telemetry CSV.
%   eff        = AS-DRIVEN: energy-weighted sum(mech)/sum(pack) over ALL motoring
%                points (part-load + transients included -- what actually happened).
%   eff_steady = same but STEADY-STATE only (constant speed & torque -- transients
%                filtered out). On a hard-driven session this is the loaded-motor
%                ceiling; on a gently-driven endurance run it can EQUAL eff, because
%                the whole run is part-load (so the low number isn't a transient bug).
%   Also returns pack energy (Wh) and run length for pricing battery savings.
    eff = NaN; eff_steady = NaN; E_batt_Wh = NaN; dur_min = NaN; src = '';
    if ~isfile(csv), return; end
    W = readtable(csv);
    need = {'PM100DX_motorSpeed','PM100DX_torqueFeedback','BMSB_packVoltage','BMSB_packCurrent','t_s'};
    if ~all(ismember(need, W.Properties.VariableNames)), return; end
    rpm = abs(W.PM100DX_motorSpeed);  tq = abs(W.PM100DX_torqueFeedback);
    V   = W.BMSB_packVoltage;         I  = W.BMSB_packCurrent;
    pack = abs(V .* I);               mechP = tq .* rpm * 2*pi/60;
    e = mechP ./ max(pack, 1e-6);
    keep = rpm>500 & tq>5 & pack>500 & e>0.3 & e<1.0;         % clean motoring points
    eff = sum(mechP(keep)) / sum(pack(keep));                % AS-DRIVEN
    steady = keep & movstd(rpm,11)<40 & movstd(tq,11)<3;     % constant speed & torque only
    if nnz(steady) > 50, eff_steady = sum(mechP(steady)) / sum(pack(steady)); end
    t = W.t_s; P = V .* I; P(isnan(P)) = 0;
    E_batt_Wh = abs(trapz(t, P)) / 3600;
    dur_min = (t(end)-t(1))/60;
    src = sprintf('%d motoring samples (%d steady-state)', nnz(keep), nnz(steady));
end

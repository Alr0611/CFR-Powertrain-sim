%% DRIVETRAIN_EFFICIENCY  --  
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
%   real telemetry, andrew's method: eff = mech power / pack power,
%   energy-weighted over the run. His map cancels the gear ratio (axleTorque =
%   motorTorque*4.6 while axleSpeed = motorRPM/4.6), so it is pack -> SHAFT only.
%   This file multiplies the MECHANICAL stack (CFR26 DT memo v4.0 [1]) on top:
%       eff_overall = eff_shaft(MEASURED) x spur x bearings x chain x diff x halfshaft(angle)
%
% Results
%   - printed: the battery->ground breakdown + every design lever priced two ways
%              (new overall efficiency %, and battery saved on an endurance lap)
%   - figures (saved to output/): the halfshaft-angle sweep, a levers comparison,
%              efficiency by stage, the motor efficiency map with its load/rpm
%              slices, and where every gear ratio puts the endurance operating
%              points on that map.

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
%% 1b. SPLITTING THE ELECTRICAL END: battery side vs inverter side
%% ============================================================================
% Everything above treats "motor + inverter" as ONE number, because that is all
% pack->shaft telemetry can see. To act on it we need to know which box is
% losing the energy -- a tired inverter and a tired pack call for completely
% different fixes.
%
% GOLD STANDARD: a dyno run. Aboud is arranging sponsor access. When that data
% lands it drops into DYNO below and this section switches over automatically.
%
% INTERIM, NO DYNO NEEDED: the inverter's own dc-bus channels measure the power
% entering the inverter. Then
%       pack power  - dc-bus power = everything UPSTREAM of the inverter
%                                    (accessories, contactors, cabling, pack IR)
%       dc-bus power - shaft power = the inverter + motor themselves
% which separates the battery side from the inverter side with no dyno at all.
%
% This is wired up and runs automatically the moment the channels are exportable.
% It is GATED on a physical plausibility check, because a mis-scaled current
% channel produces a beautifully plausible-looking split that is entirely wrong.
[split, split_msg] = split_battery_inverter(csv, eff_shaft);
fprintf('=== BATTERY SIDE vs INVERTER SIDE (splitting the electrical end) ===\n');
fprintf('%s\n', split_msg);
if split.valid
    fprintf('   upstream of inverter (accessories + pack IR + cabling) : %5.1f%% of pack power\n', 100*split.upstream_frac);
    fprintf('   inverter + motor                                       : %5.1f%%\n', 100*split.conv_frac);
    fprintf('   -> battery-side efficiency  %.3f\n', split.eta_battery);
    fprintf('   -> inverter+motor efficiency %.3f\n', split.eta_converter);
end
fprintf('\n');

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
%% 4. FIGURES (one TABBED window, saved to output/)
%% ============================================================================
% halfshaft-angle sweep (the continuous lever), levers ranked (what to fix first),
% efficiency by stage, the motor efficiency map + its load/rpm slices, and where
% every gear ratio puts the endurance operating points on that map. Everything
% else stays a printed table above.
outdir = fullfile(here,'output'); if ~exist(outdir,'dir'), mkdir(outdir); end
fW = figure('Name','Drivetrain efficiency','Position',[40 40 1040 580]);
tg = uitabgroup(fW);

% -- Tab: halfshaft angle sweep, overall eff + battery saved vs angle --
ax = axes(uitab(tg,'Title','Halfshaft angle sweep'));
angs  = 0:0.5:12;
ov_a  = arrayfun(@(bb) overall(setf(B,'hs_angle',bb)), angs)*100;
sv_a  = (1 - eff0./(ov_a/100))*100;
yyaxis(ax,'left');  plot(ax, angs, ov_a,'-','LineWidth',1.8); ylabel(ax,'Overall drivetrain efficiency (%)');
yyaxis(ax,'right'); plot(ax, angs, sv_a,'--','LineWidth',1.5); ylabel(ax,'Endurance battery saved (%)');
xlabel(ax,'Halfshaft static angle (deg)'); grid(ax,'on'); xlim(ax,[0 12]);
try, xregion(ax,0,5,'FaceColor',[0.30 0.62 0.40],'FaceAlpha',0.12); catch, end   % 0-5 deg target band
xline(ax, B.hs_angle,'r:','LineWidth',1.3,'Label',sprintf('current %d°',B.hs_angle),'LabelOrientation','horizontal');
title(ax,'Straighter halfshafts (shaded 0-5° = sweet spot)');

% -- Tab: levers ranked by battery saved (what to fix first) --
ax = axes(uitab(tg,'Title','Levers ranked'));
if isnan(E_batt_Wh)
    xq = save_fr*100; xlab = 'Endurance battery saved (%)'; lbls = compose('%.1f%%', save_fr*100);
else
    xq = save_fr*E_batt_Wh; xlab = 'Endurance battery saved if stage hits its best (Wh)';
    lbls = compose('%.0f Wh (%.1f%%)', xq, save_fr*100);
end
[xs, idx] = sort(xq);   % ascending -> biggest opportunity ends up at the top of barh
barh(ax, xs, 'FaceColor',[0.30 0.62 0.40],'EdgeColor','none'); grid(ax,'on');
set(ax,'YTick',1:numel(names),'YTickLabel',names(idx));
xlabel(ax, xlab); xlim(ax,[0 max(xq)*1.25]);
text(ax, xs+max(xq)*0.01, 1:numel(xs), lbls(idx), 'VerticalAlignment','middle');
title(ax,'What to fix first: stages ranked by battery saved');

% -- Tab: efficiency by stage (standalone %) -- the weakest link at a glance --
% One bar per stage = that stage's OWN CAPABILITY efficiency, so every stage is on
% the same footing (the five mechanical stages are capability numbers, so the motor
% must be too). For motor+inverter that is the MEASURED loaded (in-band) number, NOT
% the as-driven average -- 78% is the endurance AVERAGE dragged down by part-load,
% not the box's efficiency. As-driven is drawn as a caret on the motor bar and on the
% overall bar, so the operational gap is visible without pretending the hardware is
% worse than it is. Capability bars multiply to the in-band overall ceiling.
ax = axes(uitab(tg,'Title','Efficiency by stage'));
st_name = {'motor + inverter','spur gearbox','bearing stack','chain', ...
           'diff (LSD)', sprintf('halfshaft@%d deg',B.hs_angle)};
st_eff  = [eff_inband, B.spur, B.bearings, B.chain, B.diff, hs_term(B.hs_angle)] * 100;
[st_sorted, o] = sort(st_eff, 'ascend');           % weakest first -> shortest bar on top row
names_sorted   = st_name(o);
cols = repmat([0.62 0.66 0.70], numel(st_eff), 1); % muted grey for context
cols(1,:) = [0.91 0.41 0.20];                       % accent: the weakest stage
y = 1:numel(st_sorted);
hb = barh(ax, y, st_sorted, 0.62, 'FaceColor','flat','EdgeColor','none'); hold(ax,'on');
hb.CData = cols;
ov_cap = eff_inband*eff_hw*100;                    % in-band ceiling = capability product
ov_ad  = eff0*100;                                 % as-driven overall (part-loaded motor)
yov = numel(st_sorted) + 1.5;
barh(ax, yov, ov_cap, 0.62, 'FaceColor',[0.20 0.28 0.40],'EdgeColor','none');
grid(ax,'on'); xlim(ax,[0 108]); xlabel(ax,'Stage efficiency (%)');
set(ax,'YTick',[y, yov], 'YTickLabel',[names_sorted, {'OVERALL (motor in-band)'}]);
ylim(ax,[0 yov+0.9]);
text(ax, st_sorted+1, y, compose('%.1f%%', st_sorted), ...
    'VerticalAlignment','middle','FontWeight','bold');
text(ax, ov_cap+1, yov, compose('%.1f%%', ov_cap), 'VerticalAlignment','middle', ...
    'FontWeight','bold','Color',[0.20 0.28 0.40]);
% AS-DRIVEN carets: motor stage (78%) and overall (62%) -- the part-load reality
imot = find(strcmp(names_sorted,'motor + inverter'),1);
plot(ax, eff_shaft*100, imot, 'v', 'MarkerSize',9, 'MarkerFaceColor',[0.85 0.20 0.15], ...
    'MarkerEdgeColor','k');
text(ax, eff_shaft*100, imot-0.4, sprintf('as-driven %.0f%%', eff_shaft*100), ...
    'HorizontalAlignment','center','FontSize',8,'Color',[0.6 0.1 0.1]);
plot(ax, ov_ad, yov, 'v', 'MarkerSize',9, 'MarkerFaceColor',[0.85 0.20 0.15],'MarkerEdgeColor','k');
text(ax, ov_ad, yov-0.42, sprintf('as-driven %.0f%%', ov_ad), ...
    'HorizontalAlignment','center','FontSize',8,'Color',[0.6 0.1 0.1]);
xline(ax, ov_cap, ':', 'Color',[0.20 0.28 0.40], 'LineWidth',1.2);
title(ax, sprintf(['Stage CAPABILITY: weakest link is %s (%.0f%% loaded); six multiply to %.1f%% ' ...
    'ceiling. Red caret = as-driven (part-load) -> %.1f%% overall'], ...
    strtrim(names_sorted{imot}), st_sorted(imot), ov_cap, ov_ad));

%% ============================================================================
%% 5. WHERE WE ACTUALLY RUN vs THE EFFICIENT ISLAND (+ what gearing does)
%% ============================================================================
% Load the real endurance operating points so we can show, not assert, that the
% motor spends the lap OFF its efficient island -- and what a gear change does.
opp_rpm = []; opp_tq = [];
if isfile(csv)
    Wop = readtable(csv);
    if all(ismember({'PM100DX_motorSpeed','PM100DX_torqueFeedback'}, Wop.Properties.VariableNames))
        rr = abs(Wop.PM100DX_motorSpeed); qq = abs(Wop.PM100DX_torqueFeedback);
        mm = rr > 500 & qq > 2;                    % motoring points only
        opp_rpm = rr(mm); opp_tq = qq(mm);
    end
end

% -- Tab: motor+inverter efficiency MAP with our operating cloud + the island --
% IMPORTANT: the raw efficiency formula keeps rising with power, so its unconstrained
% max sits in the (unreachable) top-right corner. We mask the map to the motor's
% ACHIEVABLE torque envelope -- T <= min(T_flat_cap, peak-power/omega) -- so the
% "island" is a point the motor can actually reach. Colours are the CLEAN physics
% model; our MEASURED as-driven number sits ~10 pts below (accessories, transients,
% the low-torque tail), so read this map for POSITION, not absolute efficiency.
axm = axes(uitab(tg,'Title','Efficiency map'));
[RG, TG] = meshgrid(0:100:6000, 0:2:150);
EFF = emrax208_efficiency(RG, TG, p) * 100;
Pk_map = interp1(p.Prpm, p.Pkw, min(RG,p.redline), 'linear','extrap');   % kW available vs rpm
Tavail = min(p.T_flat_cap, Pk_map*9549 ./ max(RG,50));                    % reachable torque
EFF(TG > Tavail) = NaN;                              % grey out what the motor can't reach
contourf(axm, RG, TG, EFF, [70 75 80 84 86 88 90 91 92], 'LineColor',[.6 .6 .6], 'HandleVisibility','off');
hold(axm,'on'); colormap(axm, parula); clim(axm,[70 92]);
cb = colorbar(axm); cb.Label.String = 'motor + inverter efficiency (%, clean physics)';
E2 = EFF; E2(isnan(E2)) = -inf; [~, im] = max(E2(:));
hIsl = plot(axm, RG(im), TG(im), 'p', 'MarkerSize',18, 'MarkerFaceColor','w', ...
    'MarkerEdgeColor','k','LineWidth',1.3);
text(axm, RG(im), TG(im)-11, sprintf('island ~%.0f%%', EFF(im)), ...
    'HorizontalAlignment','center','FontWeight','bold');
hCloud = [];
if ~isempty(opp_rpm)
    ds = 1:12:numel(opp_rpm);
    hCloud = scatter(axm, opp_rpm(ds), opp_tq(ds), 7, [0.85 0.20 0.15], 'filled', 'MarkerFaceAlpha',0.18);
    % clean direction arrow: where a lower ratio (4.0:1) pushes the operating load
    Cx = median(opp_rpm); Cy = median(opp_tq); rs = 4.00 / p.gear_current;
    plot(axm, [Cx Cx*rs], [Cy Cy/rs], 'w-', 'LineWidth',3, 'HandleVisibility','off');
    hArr = plot(axm, Cx*rs, Cy/rs, 'w^', 'MarkerFaceColor','w', 'MarkerSize',11);
    text(axm, 2850, Cy-7, sprintf('median ~%.0f Nm (part-load)', Cy), ...
        'Color',[0.6 0.05 0.05],'FontWeight','bold');
    legend(axm, [hCloud hIsl hArr], {'as-driven operating points', ...
        sprintf('reachable island ~%.0f%%',EFF(im)), 'lower gearing (4.0:1) loads motor'}, ...
        'Location','southeast','FontSize',8, 'TextColor','w','Color',[0.15 0.15 0.15]);
end
yline(axm, p.T_flat_cap, 'w--', 'HandleVisibility','off');
xline(axm, p.redline, 'r:', 'HandleVisibility','off');
xlabel(axm,'Motor rpm'); ylabel(axm,'Motor torque (Nm)'); xlim(axm,[0 6000]); ylim(axm,[0 150]);
title(axm, 'Where we run (red) vs the reachable efficient island. Grey = torque the motor can''t make at that rpm.');

% -- Tab: efficiency vs LOAD (line) with the ACTUAL time-at-load distribution (bars).
%    The cliff below ~15 Nm is where efficiency collapses -- and it's where a big slice
%    of the lap actually sits. Lower gearing shifts the bars right, out of the cliff.
%    (Two single-axes tabs, not one tiled tab: save_tabfig exports one axes per tab.)
axa = axes(uitab(tg,'Title','Eff vs load'));
rpm0 = 3000; Tsw = 0:1:150; CLIFF = 15;
effT = emrax208_efficiency(rpm0*ones(size(Tsw)), Tsw, p) * 100;
yyaxis(axa,'left');
patch(axa, [0 CLIFF CLIFF 0], [60 60 95 95], [0.85 0.25 0.15], 'FaceAlpha',0.09, 'EdgeColor','none');
hold(axa,'on');
plot(axa, Tsw, effT, 'LineWidth', 2.4);
[peakE, ip] = max(effT);
plot(axa, Tsw(ip), peakE, 'k^', 'MarkerFaceColor','k');
text(axa, Tsw(ip), peakE+1.3, sprintf('peak %.0f%% @ %d Nm', peakE, Tsw(ip)), 'FontSize',9, 'HorizontalAlignment','center');
ylabel(axa,'motor + inverter eff (%)'); ylim(axa,[60 94]);
yyaxis(axa,'right'); cliff_pct = 0;
if ~isempty(opp_tq)
    histogram(axa, opp_tq, 0:5:150, 'Normalization','probability', ...
        'FaceColor',[0.45 0.5 0.55], 'FaceAlpha',0.45, 'EdgeColor','none');
    rs = 4.00 / p.gear_current;
    histogram(axa, opp_tq/rs, 0:5:150, 'Normalization','probability', ...
        'FaceColor',[0.15 0.35 0.7], 'FaceAlpha',0.30, 'EdgeColor','none');
    cliff_pct = 100*mean(opp_tq < CLIFF);
    ylabel(axa,'share of endurance time');
end
grid(axa,'on'); xlabel(axa,'Motor torque (Nm) at 3000 rpm'); xlim(axa,[0 150]);
title(axa, sprintf(['Efficiency vs LOAD (line) + where we actually spend time (bars): %.0f%% of the lap ' ...
    'is below %d Nm in the cliff.\nGrey = now, blue = lower gearing shifts it right, out of the cliff.'], cliff_pct, CLIFF));

% -- Tab: efficiency vs RPM at a fixed torque -- core loss (a*rpm + b*rpm^2) drags
%    the top end down: the OTHER way past the peak (revving high hurts, too).
axb = axes(uitab(tg,'Title','Eff vs rpm'));
T0 = 40; Rsw = 500:25:6000;
effR = emrax208_efficiency(Rsw, T0*ones(size(Rsw)), p) * 100;
plot(axb, Rsw, effR, 'LineWidth', 2.4); hold(axb,'on'); grid(axb,'on');
[peakR, ir] = max(effR);
plot(axb, Rsw(ir), peakR, 'k^', 'MarkerFaceColor','k');
text(axb, Rsw(ir), peakR-1.6, sprintf('peak %.0f%% @ %d rpm', peakR, Rsw(ir)), 'FontSize',9, 'HorizontalAlignment','center');
xline(axb, p.redline, 'r:', 'redline');
if ~isempty(opp_rpm)
    Rmed = median(opp_rpm); eMed = emrax208_efficiency(Rmed, T0, p)*100;
    plot(axb, Rmed, eMed, 'o', 'MarkerSize',9, 'MarkerFaceColor',[0.85 0.2 0.15],'MarkerEdgeColor','k');
    text(axb, Rmed, eMed-1.8, sprintf('endurance median ~%.0f rpm', Rmed), 'FontSize',8,'Color',[0.6 0.1 0.1],'HorizontalAlignment','center');
end
xlabel(axb,sprintf('Motor rpm (at a fixed %d Nm)', T0)); ylabel(axb,'motor + inverter eff (%)'); ylim(axb,[80 94]);
title(axb,'Efficiency vs RPM: past the peak it falls as core loss grows (\propto rpm^2) -- revving high past the sweet spot costs efficiency');

% -- Tab: where every GEAR RATIO puts the endurance operating points on the map --
% Endurance wheel speed is fixed (the car went as fast as it went), so changing the
% ratio just slides each operating point along a constant-shaft-power curve: a HIGHER
% ratio trades torque for rpm (down-and-right, toward redline and the low-torque
% cliff), a LOWER ratio trades rpm for torque (up-and-left, toward the load the motor
% likes). Same July 11 laps, re-geared -- shows where each candidate ratio would sit
% relative to the datasheet peak-power envelope and the efficient island. (Reuses the
% RG/TG/EFF map, Tavail envelope and island index im from the Efficiency-map tab.)
axG = axes(uitab(tg,'Title','Gear ratios on map'));
contourf(axG, RG, TG, EFF, [70 75 80 84 86 88 90 91 92], 'LineColor',[.6 .6 .6], 'HandleVisibility','off');
hold(axG,'on'); colormap(axG, parula); clim(axG,[70 92]);
cbG = colorbar(axG); cbG.Label.String = 'motor + inverter efficiency (%, clean physics)';
plot(axG, RG(1,:), Tavail(1,:), 'w-', 'LineWidth',2, 'HandleVisibility','off');   % datasheet peak envelope
hIslG = plot(axG, RG(im), TG(im), 'p', 'MarkerSize',16, 'MarkerFaceColor','w','MarkerEdgeColor','k','LineWidth',1.2);
text(axG, RG(im), TG(im)-10, 'peak island', 'HorizontalAlignment','center','FontWeight','bold','Color','w','FontSize',8);
if ~isempty(opp_rpm)
    ds = 1:20:numel(opp_rpm);
    scatter(axG, opp_rpm(ds), opp_tq(ds), 5, [0.6 0.6 0.62], 'filled', 'MarkerFaceAlpha',0.10, 'HandleVisibility','off');
    gset = sort(p.gears_to_test(:))';
    wgt  = opp_rpm .* opp_tq;                         % ~ shaft power: ratio-invariant weights
    cx = zeros(size(gset)); cy = cx; ceff = cx; fovr = cx;
    for i = 1:numel(gset)
        rs = gset(i)/p.gear_current; rg = opp_rpm*rs; tq = opp_tq/rs;
        cx(i) = sum(rg.*wgt)/sum(wgt);  cy(i) = sum(tq.*wgt)/sum(wgt);
        e = emrax208_efficiency(rg, tq, p);
        ceff(i) = sum(e.*wgt)/sum(wgt)*100;
        fovr(i) = 100*mean(rg > p.redline);
    end
    plot(axG, cx, cy, 'w-', 'LineWidth',1.5, 'HandleVisibility','off');   % constant-power locus
    hLoc = scatter(axG, cx, cy, 70, ceff, 'filled', 'MarkerEdgeColor','k');
    keyg = unique([min(gset) p.gear_current max(gset)]);   % lowest, current, highest
    aln = {'right','center','left'}; ddx = [-160 0 160]; ddy = [12 20 -14];
    for k = 1:numel(keyg)
        [~,j] = min(abs(gset - keyg(k))); s = min(k,3);
        lab = sprintf('%.2f:1  ~%.0f rpm  %.1f%%', gset(j), cx(j), ceff(j));
        if fovr(j) > 1, lab = sprintf('%s (%.0f%% >redline)', lab, fovr(j)); end
        text(axG, cx(j)+ddx(s), cy(j)+ddy(s), lab, 'HorizontalAlignment',aln{s}, ...
            'FontWeight','bold','Color','w','FontSize',8);
    end
    legend([hLoc hIslG], {'ratio operating centre (colour = its endurance eff)','efficient island'}, ...
        'Location','southeast','FontSize',8,'TextColor','w','Color',[0.15 0.15 0.15]);
end
xline(axG, p.redline, 'r:', 'redline', 'HandleVisibility','off');
xlabel(axG,'Motor rpm (endurance, same laps re-geared)'); ylabel(axG,'Motor torque (Nm)');
xlim(axG,[0 6000]); ylim(axG,[0 150]);
title(axG, ['Same endurance laps, every gear ratio: higher ratio -> more rpm / less torque (toward redline & cliff), ' ...
    'lower -> more torque. White line = datasheet peak envelope; endurance sits well below it.']);

save_tabfig(fW, fullfile(outdir,'DTeff_Drivetrain_efficiency'));
fprintf(['Saved 1 tabbed figure window to output/ (halfshaft sweep, levers ranked, efficiency by\n' ...
         '  stage, efficiency map, eff vs load, eff vs rpm, gear ratios on map).\n\n']);
fprintf(' MOTOR+INVERTER is a MAP, not one number: peak (loaded) ~%.0f%%, in efficient band %.0f%%,\n', ...
    emrax208_efficiency(2500,65,p)*100, eff_inband*100);
fprintf('   as-driven endurance AVERAGE %.0f%% (part-load, not a worn motor). Gearing lower loads it\n', eff_shaft*100);
fprintf('   toward the island; straightening halfshafts is a separate hardware gain (Tab: halfshaft).\n\n');

fprintf('Sources: [1] CFR26_DT_Efficiency.pdf v4.0 (stage table + straight/corner time split).\n');
fprintf('         Electrical end measured via freeman803 af/dteff method on July 11 telemetry.\n');
fprintf('         CV-joint loss coefficient cross-checked against the memo (see header).\n');

%% ============================== local functions ==============================
function s = setf(s, field, val)
    s.(field) = val;   % copy a struct with one field changed
end

function [out, msg] = split_battery_inverter(csv, eff_shaft)
%SPLIT_BATTERY_INVERTER  Separate battery-side losses from inverter-side losses.
%
%   Structured so the eventual DYNO data drops straight in. Three sources, in
%   descending order of trust:
%
%     1. DYNO      -- measured shaft power on a brake, against measured dc-bus
%                     and pack power. The real answer. Fill in DYNO below.
%     2. DC-BUS    -- PM100DX_dcBusVoltage/Current from track telemetry.
%                     pack power - dc-bus power = everything upstream.
%     3. NEITHER   -- report that the split is unavailable. Do NOT guess a
%                     number: an invented split is worse than no split, because
%                     it points the team at the wrong box to fix.
%
%   The DC-BUS path is GATED. Pack->inverter is a few metres of cable, a fuse
%   and two contactors: single-digit milliohms. If the channels imply a series
%   resistance far outside that, the channel is mis-scaled, not the car being
%   lossy, and we refuse the number instead of publishing it.

    out = struct('valid', false, 'source', 'none', 'upstream_frac', NaN, ...
                 'conv_frac', NaN, 'eta_battery', NaN, 'eta_converter', NaN, ...
                 'R_implied_mohm', NaN);

    % ---------- SOURCE 1: DYNO (fill this in when the sponsor run happens) ----
    % Set DYNO.have = true and fill the three power vectors (W). Everything
    % downstream already handles it -- no other edits needed anywhere.
    DYNO.have      = false;
    DYNO.P_pack    = [];   % W, measured at the pack terminals
    DYNO.P_dcbus   = [];   % W, measured at the inverter dc input
    DYNO.P_shaft   = [];   % W, measured on the brake (torque x speed)
    if DYNO.have
        Ppk = sum(DYNO.P_pack); Pdc = sum(DYNO.P_dcbus); Psh = sum(DYNO.P_shaft);
        out.valid = true; out.source = 'DYNO (measured shaft power)';
        out.upstream_frac = (Ppk - Pdc)/Ppk;
        out.conv_frac     = (Pdc - Psh)/Ppk;
        out.eta_battery   = Pdc/Ppk;
        out.eta_converter = Psh/Pdc;
        msg = sprintf('  source: %s -- this supersedes the telemetry estimate.', out.source);
        return;
    end

    % ---------- SOURCE 2: dc-bus telemetry -----------------------------------
    if ~isfile(csv)
        msg = '  [no telemetry file -- split unavailable]';
        return;
    end
    W = readtable(csv);  V = W.Properties.VariableNames;
    has_i = ismember('PM100DX_dcBusCurrent', V);
    has_v = ismember('PM100DX_dcBusVoltage', V);
    if ~has_i
        msg = ['  [PM100DX_dcBusCurrent not in this export -- split unavailable]' newline ...
               '   HOOK: re-export with the "Motor & inverter" channel group' newline ...
               '   (dcBusVoltage + dcBusCurrent) and this runs automatically.'];
        return;
    end

    Vpack = W.BMSB_packVoltage;  Ipack = W.BMSB_packCurrent;
    Idc   = W.PM100DX_dcBusCurrent;
    if has_v, Vdc = W.PM100DX_dcBusVoltage; else, Vdc = Vpack; end   % bus V ~ pack V
    rpm = abs(W.PM100DX_motorSpeed);  tq = abs(W.PM100DX_torqueFeedback);

    P_pack = abs(Vpack .* Ipack);
    P_dc   = abs(Vdc   .* Idc);
    mot = rpm>500 & tq>5 & P_pack>500;            % loaded, motoring points only
    if nnz(mot) < 100
        msg = '  [too few motoring points to split]';
        return;
    end

    Epack = sum(P_pack(mot));  Edc = sum(P_dc(mot));
    upstream = Epack - Edc;

    % ---- THE GATE: is the implied series resistance physically possible? -----
    % Upstream loss must be I^2*R through cable + fuse + contactors.
    R_implied = upstream / sum(Ipack(mot).^2);
    out.R_implied_mohm = R_implied*1000;
    R_MAX_OHM = 0.050;    % 50 mOhm -- already generous for HV cable+fuse+contactors
    if ~has_v
        vnote = sprintf('%s   note: no dcBusVoltage channel, so pack voltage was used for the\n         bus (fair -- they differ by an IR drop of millivolts).\n', '');
    else
        vnote = '';
    end

    if upstream <= 0
        msg = sprintf(['  [dc-bus power >= pack power -- impossible; channel sign/scale is wrong]\n' ...
                       '   dc-bus reads %.0f Wh vs pack %.0f Wh over the motoring points.'], ...
                       Edc/3600, Epack/3600);
        return;
    end
    if R_implied > R_MAX_OHM
        msg = sprintf([ ...
            '  REJECTED -- the dc-bus channel fails a physical sanity check.\n' ...
            '   Implied pack->inverter series resistance: %.0f mOhm.\n' ...
            '   Real HV cable + fuse + contactors is roughly 5-20 mOhm, so this is ~%.0fx\n' ...
            '   too high. Taken at face value the split would book %.0f%% of pack power\n' ...
            '   (%.0f Wh over this run, %.0f kW at peak current) as heat in the HV\n' ...
            '   cabling -- the cable would not survive the first lap.\n' ...
            '   DIAGNOSIS: PM100DX_dcBusCurrent reads about %.0f%% of pack current at ALL\n' ...
            '   load levels. A constant RATIO is a scale-factor error; a real accessory\n' ...
            '   draw would be a constant OFFSET of a few hundred watts. Check the CAN\n' ...
            '   scaling for this channel in the DBC before anyone uses it.\n' ...
            '   The split is therefore NOT reported -- a wrong split is worse than none.\n%s'], ...
            out.R_implied_mohm, out.R_implied_mohm/12.5, 100*upstream/Epack, ...
            upstream*median(diff(W.t_s))/3600, R_implied*max(abs(Ipack))^2/1000, ...
            100*sum(abs(Idc(mot)))/sum(abs(Ipack(mot))), vnote);
        return;
    end

    out.valid = true;  out.source = 'dc-bus telemetry (interim, no dyno)';
    out.upstream_frac = upstream/Epack;
    P_shaft = sum(tq(mot).*rpm(mot)*2*pi/60);
    out.conv_frac     = (Edc - P_shaft)/Epack;
    out.eta_battery   = Edc/Epack;
    out.eta_converter = P_shaft/Edc;
    msg = sprintf(['  source: %s\n   implied series resistance %.1f mOhm (plausible, gate passed)\n%s'], ...
        out.source, out.R_implied_mohm, vnote);
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

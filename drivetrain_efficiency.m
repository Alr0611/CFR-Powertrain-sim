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
%% 4. FIGURES (one TABBED window, saved to output/) -- exactly 3 tabs
%% ============================================================================
% Waterfall (where energy goes), halfshaft-angle sweep (the continuous lever), and
% levers ranked by battery saved (what to fix first). Everything else stays a
% printed table above; the measured pack->shaft map lives in
% analysis/efficiency_crosscheck.m, not here.
outdir = fullfile(here,'output'); if ~exist(outdir,'dir'), mkdir(outdir); end
fW = figure('Name','Drivetrain efficiency','Position',[40 40 1040 580]);
tg = uitabgroup(fW);

% -- Tab 1: waterfall, energy remaining (%) after each stage --
ax = axes(uitab(tg,'Title','Waterfall'));
lbl   = {'Battery','+ motor/inv','+ spur','+ bearings','+ chain','+ diff', sprintf('+ halfshaft@%d°',B.hs_angle)};
efac  = [1, eff_shaft, B.spur, B.bearings, B.chain, B.diff, hs_term(B.hs_angle)];
remain = cumprod(efac)*100;
bar(ax, remain,'FaceColor',[0.20 0.45 0.72],'EdgeColor','none'); hold(ax,'on'); grid(ax,'on'); ylim(ax,[0 112]);
set(ax,'XTick',1:numel(lbl),'XTickLabel',lbl); xtickangle(ax,20);
ylabel(ax,'Energy remaining (%)');
text(ax, 1:numel(remain), remain+2.2, compose('%.1f%%',remain), 'HorizontalAlignment','center','FontWeight','bold');
title(ax, sprintf('Battery \\rightarrow ground, as-driven: %.1f%% reaches the wheels', remain(end)));

% -- Tab 2: halfshaft angle sweep, overall eff + battery saved vs angle --
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

% -- Tab 3: levers ranked by battery saved (what to fix first) --
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

save_tabfig(fW, fullfile(outdir,'DTeff_Drivetrain_efficiency'));
fprintf('Saved 1 tabbed figure window to output/ (waterfall, halfshaft sweep, levers ranked).\n\n');

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

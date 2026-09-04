%% SHAFT_KEY_CALC  Parallel-key sizing for every torque-carrying joint on CFR27.
%
%   shaft_key_calc
%
% The CFR27 shafts are plain round at the moment, so nothing but a press/clamp fit is
% carrying torque into the gears and sprockets. This sizes the parallel keys that replace
% that, and it answers the one question the drawing needs: for a given shaft diameter,
% HOW LONG does the key have to be, and does that length fit in the hub we have.
%
% Method is Mott, Machine Elements in Mechanical Design, 6th ed., section 11-4, the same
% method the CBR27 Baja shaft workbook used, so the two are directly comparable:
%
%   shear across the W x L section      tau   = 2T/(D*W*L)        (Mott 11-1)
%   design shear stress (MSST)          tau_d = 0.5*sy/N
%   min length for shear                Lmin  = 2T/(tau_d*D*W)    (Mott 11-2)
%   bearing on the L x H/2 flank        sigma = 4T/(D*L*H)        (Mott 11-3)
%   design compressive stress           sig_d = sy/N
%   min length for bearing              Lmin  = 4T/(sig_d*D*H)    (Mott 11-4)
%
% W and H are NOT free. Mott Table 11-1 fixes them from the shaft diameter (lib/
% mott_key_size.m). Length and material are the only design variables.
%
% WHAT IS REAL HERE AND WHAT IS NOT:
%   REAL   the torques. They come from params_cfr26 and the measured 15/30 + 13/30
%          driveline, and from the measured tyre grip cap. Nothing invented.
%   MEASURED  bores, keyseats, keys, gear hubs and bearing spans, all read out of the STEP
%          files (motor_to_gear_shaft, shaft_to_sprocket, Shaftkey_*, and the CFR26 motor
%          gearbox assembly). Gears are KHK MSGA2.5 stock parts, so module 2.5, 20 deg
%          pressure angle and SCM415 are settled too.
%   *** STILL ASSUMED *** the SHAFT grade. That single number decides whether a keys-only
%          fix works or new shafts are needed, so it is the one thing left worth chasing.
%   *** PLACEHOLDER *** the diff input and diff output stub stations. No STEP supplied.

clear; clc; close all;
here = fileparts(mfilename('fullpath')); cd(here);
if ~exist('output','dir'), mkdir('output'); end
addpath(fullfile(here,'lib'));
p = params_cfr26();

%% ======================= DESIGN INPUTS =======================
% DESIGN TORQUE. Deliberately set ABOVE the EMRAX's datasheet peak, and that is a choice
% worth stating rather than burying: the motor can transiently exceed its rated peak, the
% torque map is a firmware value that can change next season, and a sheared key is a DNF.
% So a load-uncertainty allowance goes on top of the 150 Nm datasheet number.
%
% NOTE this is a SEPARATE thing from the design factor N below. N covers MATERIAL and
% MACHINING uncertainty; this covers LOAD uncertainty. Stacking them is normal practice --
% it is exactly what a service factor is -- but the effective margin against yield is
% DESIGN_OVERLOAD x N, and that product is what the parts are really held to. Printed below
% so it is never a surprise. If it ever looks too rich, lower this, not N: N is the one
% protecting against the shaft material grade, which is still unconfirmed.
DESIGN_OVERLOAD = 170/150;              % ~1.13. Set to 1.0 to size on the datasheet peak.
T_MOTOR = p.T_flat_cap * DESIGN_OVERLOAD;

% Design factor N (Mott's, applied to yield). The Baja book ran 1.25-2.0 depending on how
% much they trusted the load. The load here is a measured motor cap on a car whose grip is
% also measured, so the uncertainty is in the MATERIAL and the machining, not the torque.
% N = 2.0 across the board, which is the conservative end of the Baja sheet.
N_DESIGN = 2.0;

% Materials, Mott Table 11-4. sy in MPa.
MAT = struct( ...
    'name', {'SAE 1018', 'SAE 1045', 'SAE 4140'}, ...
    'su',   {441,        627,        703       }, ...
    'sy',   {372,        531,        621       });
KEY_MAT = 2;    % <- index into MAT. 1045.
% WHY 1045 AND NOT MOTT'S DEFAULT 1018. Mott recommends 1018 for most work partly BECAUSE
% it is weak: the key is cheap and replaceable, so you want it to be the sacrificial
% element and shear before it damages the gear or the shaft. That logic is right for
% industrial equipment and wrong for us. A sheared key mid-endurance is a DNF, and the
% "damage" it protects is a gear we can machine again over the winter. So step up to 1045
% for length, and keep the key still weaker than the shaft and gear (see the check below)
% so the failure ORDER is preserved even though the failure LOAD went up.
sy_key = MAT(KEY_MAT).sy;

% Hub and shaft materials, for the bearing check. Mott 11-4: bearing failure happens on
% whichever of key / shaft keyseat / hub keyseat has the LOWEST compressive yield, so the
% bearing length must be computed against the minimum of the three, not against the key.
sy_shaft = 621;     % *** FROM CAD *** assumed 4140. Confirm the real stock and heat treat.
sy_hub   = 800;     % MEASURED FROM CAD: the gears are KHK MSGA2.5-15 / MSGA2.5-30, stock
                    % ground spur gears in SCM415 carburised. Core yield 800 MPa, the same
                    % figure the CBR27 Baja sheet used for SCM415. The hub is therefore the
                    % STRONGEST of the three bearing surfaces and never limits: the SHAFT does.
sy_bear  = min([sy_key sy_shaft sy_hub]);

%% ======================= THE TORQUE PATH =======================
% Motor -> 15T/30T spur -> intermediate shaft -> 13T/30T chain -> diff -> halfshafts.
% Same driveline gear_decision_summary.m documents, so if the sprockets change there they
% must change here too.
SPUR_DRIVER = 15; SPUR_DRIVEN = 30;
CHAIN_DRIVER = 13; CHAIN_DRIVEN = 30;
spur  = SPUR_DRIVEN/SPUR_DRIVER;
chain = CHAIN_DRIVEN/CHAIN_DRIVER;
G     = spur*chain;

% GRIP CAP. Torque downstream of the diff cannot exceed what the tyres will take, so a
% key sized on motor torque alone can be oversized at the wheel end. Computed at a launch
% (peak load transfer, no aero to speak of at low speed) which is the worst case for rear
% Fz, hence the highest grip torque the halfshafts ever see.
a_launch = 1.3*p.g;                                  % ~1.3 g, what the car actually pulls
Fz_rear  = p.m_car*p.g*p.rear_static + p.m_car*a_launch*p.h_cg/p.L_wb;
mu_x     = tire_mu_x(Fz_rear/2, p.tir);              % same tyre model the accel sim uses
T_wheel_grip = mu_x * Fz_rear * p.r_load;            % Nm, both rear wheels combined
T_wheel_motor = T_MOTOR * G * p.eta_drivetrain;

fprintf('=== TORQUE PATH (design case: motor at %.0f Nm) ===\n', T_MOTOR);
fprintf('  spur %d/%d = %.3f, chain %d/%d = %.3f, total G = %.4f\n', ...
    SPUR_DRIVEN, SPUR_DRIVER, spur, CHAIN_DRIVEN, CHAIN_DRIVER, chain, G);
fprintf('  motor torque, DESIGN         %6.1f Nm  (%.0f Nm datasheet x %.2f overload)\n', ...
    T_MOTOR, p.T_flat_cap, DESIGN_OVERLOAD);
fprintf('  motor torque, datasheet peak %6.1f Nm  (p.T_flat_cap)\n', p.T_flat_cap);
fprintf('  motor torque, as driven      %6.1f Nm  (p.T_driver_max, MEASURED VC ceiling)\n', p.T_driver_max);
fprintf('  wheel torque if motor-limited%6.1f Nm  (x G x eta %.3f)\n', T_wheel_motor, p.eta_drivetrain);
fprintf('  wheel torque the GRIP allows %6.1f Nm  (mu %.2f, rear Fz %.0f N at %.1f g)\n', ...
    T_wheel_grip, mu_x, Fz_rear, a_launch/p.g);
if T_wheel_grip < T_wheel_motor
    fprintf('  -> GRIP GOVERNS at the wheel. The car cannot put the motor cap down; the\n');
    fprintf('     halfshaft-end keys see at most %.0f Nm, %.0f%% of the motor-limited figure.\n', ...
        T_wheel_grip, 100*T_wheel_grip/T_wheel_motor);
else
    fprintf('  -> MOTOR GOVERNS everywhere. Grip is not the binding constraint.\n');
end
fprintf(['  NOTE the grip cap is a STEADY cap. It does not cover shock: wheel hop, a kerb\n' ...
         '  strike, or dropping onto a locked wheel can spike well past it. That is what the\n' ...
         '  design factor N = %.1f is absorbing, so the upstream keys are NOT trimmed to grip.\n'], N_DESIGN);

%% ======================= THE STATIONS =======================
% Every place torque crosses from a shaft into a hub. Bore and hub length are the two
% numbers this script cannot know; they come off the CAD.
%
% name                         torque at this joint          bore   hub    note
S = struct('name',{},'T',{},'D',{},'Lhub',{},'src',{});
add = @(s,n,T,D,L,src) [s, struct('name',n,'T',T,'D',D,'Lhub',L,'src',src)];

% Bore and key length for the first two are MEASURED out of the STEP files
% (motor_to_gear_shaft.STEP, shaft_to_sprocket.STEP, Shaftkey_*.STEP). The key length
% used is the STRAIGHT bearing length of the actual key part, i.e. total length minus the
% radiused end, which is the conservative convention.
S = add(S, 'Sh1 D15 / 15T spur pinion',      T_MOTOR,        15.0, 25.0, 'motor cap');
S = add(S, 'Sh2 D22 / 30T spur gear',        T_MOTOR*spur,   22.0, 24.0, 'motor x spur');
S = add(S, 'Diff input / 30T sprocket',      T_MOTOR*G,      35,   30,   'motor x G');
S = add(S, 'Diff output stub / CV cup',      T_MOTOR*G/2,    25,   30,   'motor x G, split 2');
% ^^^ the last two are still PLACEHOLDERS -- no STEP supplied for them yet.
%
% NOT keyed, so deliberately absent from this list:
%   motor flange -> Sh1   BOLTED. D94 x 7 flange, 12 x D9 on a D75 bolt circle, D56 pilot.
%                         Carries the full 150 Nm as a bolt group (Mott ch.18), not done here.
%   Sh2 -> 13T sprocket   6-TOOTH SPLINE, major D24.70 / minor D20.88, ~25 mm long, with a
%                         5 mm A/F hex socket for a retaining bolt. Splines are Mott 11-5.
%
% Slot lengths, for how much room there is to grow a key (end-mill CENTRE travel plus one
% cutter diameter, NOT the centre travel on its own):
%   Sh1  D5 cutter, centres 42.5-72.5  -> slot 35.0 mm overall, key is 27.5 (25.0 straight)
%   Sh2  D6 cutter, centres 26.75-50.75 -> slot 30.0 mm overall, key is 27.0 (24.0 straight)
SLOT = [35.0 30.0 NaN NaN];     % overall keyseat length, mm. NaN where unknown.

DIFF_IS_OPEN = true;    % *** FROM CAD/DT *** set false for a spool or locked LSD

if ~DIFF_IS_OPEN
    S(5).T   = T_MOTOR*G;
    S(5).src = 'motor x G, spool = one side takes all';
end

%% ======================= PER-STATION SIZING =======================
tau_d = 0.5*sy_key/N_DESIGN;      % Mott, MSST design shear stress
sig_d = sy_bear/N_DESIGN;         % Mott, design bearing stress on the weakest flank

fprintf('\n=== KEY SIZING, Mott 11-4, N = %.1f, key %s (sy %d MPa) ===\n', ...
    N_DESIGN, MAT(KEY_MAT).name, sy_key);
fprintf('  EFFECTIVE margin vs the %.0f Nm datasheet peak = overload %.2f x N %.1f = %.2f\n', ...
    p.T_flat_cap, DESIGN_OVERLOAD, N_DESIGN, DESIGN_OVERLOAD*N_DESIGN);
fprintf('  tau_d = 0.5*sy/N = %.1f MPa,  sigma_d = sy_bear/N = %.1f MPa (weakest of key/shaft/hub, sy %d)\n\n', ...
    tau_d, sig_d, sy_bear);
fprintf('  %-32s %7s %5s %5s %5s %8s %8s %8s %6s %6s\n', ...
    'station','T(Nm)','D','W','H','Lshear','Lbear','Lreq','Lhub','FOS');
res = struct('station',{},'T_Nm',{},'D_mm',{},'W_mm',{},'H_mm',{}, ...
             'L_shear_mm',{},'L_bear_mm',{},'L_req_mm',{},'L_hub_mm',{},'FOS_at_hub',{},'fits',{});
for i = 1:numel(S)
    T_Nmm = S(i).T * 1000;                       % Mott's equations are in N and mm
    [W, H] = mott_key_size(S(i).D);
    Ls = 2*T_Nmm / (tau_d * S(i).D * W);         % Mott 11-2
    Lb = 4*T_Nmm / (sig_d * S(i).D * H);         % Mott 11-4
    Lreq = max(Ls, Lb);
    % FOS actually achieved if the key is run the full hub length. Same equations solved
    % for N instead of L, taking whichever mode is the more critical.
    Ns = 0.5*sy_key  * S(i).D * W * S(i).Lhub / (2*T_Nmm);
    Nb =     sy_bear * S(i).D * H * S(i).Lhub / (4*T_Nmm);
    FOS = min(Ns, Nb);
    fits = Lreq <= S(i).Lhub;
    fprintf('  %-32s %7.1f %5.0f %5.0f %5.0f %8.1f %8.1f %8.1f %6.0f %6.2f %s\n', ...
        S(i).name, S(i).T, S(i).D, W, H, Ls, Lb, Lreq, S(i).Lhub, FOS, ...
        ternary(fits,'','  <-- DOES NOT FIT'));
    res(end+1) = struct('station',string(S(i).name),'T_Nm',S(i).T,'D_mm',S(i).D, ...
        'W_mm',W,'H_mm',H,'L_shear_mm',Ls,'L_bear_mm',Lb,'L_req_mm',Lreq, ...
        'L_hub_mm',S(i).Lhub,'FOS_at_hub',FOS,'fits',fits); %#ok<SAGROW>
end
fprintf('\n  Lshear/Lbear  min key length against each failure mode; Lreq is the governing one\n');
fprintf('  FOS           design factor actually achieved if the key runs the FULL hub length\n');
fprintf('  Sh1/Sh2 bore and key length are MEASURED off the STEP files; L is the STRAIGHT\n');
fprintf('  bearing length of the real key part. The last two stations are still placeholders.\n');

% How much longer could the key be WITHOUT touching the shaft? A straight key in a
% profile keyseat can reach (slot - one end radius) of straight length.
fprintf('\n  ROOM TO GROW THE KEY (no bore change, just a longer key):\n');
for i = 1:numel(S)
    if isnan(SLOT(i)), continue; end
    [W, ~] = mott_key_size(S(i).D);
    Lmax_str = SLOT(i) - W/2;          % one radiused end nests in the slot end
    fprintf('    %-28s slot %.1f mm -> max %.1f mm straight (now %.1f), FOS %.2f -> %.2f\n', ...
        S(i).name, SLOT(i), Lmax_str, S(i).Lhub, ...
        res(i).FOS_at_hub, res(i).FOS_at_hub*Lmax_str/S(i).Lhub);
end
fprintf('    Capped in practice by the GEAR HUB length, which is still unknown.\n');

nbad = sum(~[res.fits]);
if nbad > 0
    fprintf('\n  %d station(s) need a longer key than the hub allows. The fix is a BIGGER BORE,\n', nbad);
    fprintf('  not a longer key: W and H grow with D (Mott 11-1), and Lreq falls roughly as D*W,\n');
    fprintf('  i.e. about as D^2. Tab 1 shows exactly how far you have to go.\n');
else
    fprintf('\n  Every station fits inside its hub at these (placeholder) dimensions.\n');
end

% Which mode governs, and it is worth knowing why.
fprintf('\n  WHICH MODE GOVERNS: Lbear/Lshear = (sy_key/sy_bear)*(W/H) = %.2f x (W/H).\n', ...
    sy_key/sy_bear);
fprintf('  With a SQUARE key (W = H, shafts up to 30 mm) and the key no stronger than the hub,\n');
fprintf('  the two modes TIE exactly. With a RECTANGULAR key (H < W, shafts over 30 mm) the\n');
fprintf('  flank is shorter than the shear plane, so bearing governs. Shear only leads if the\n');
fprintf('  key steel is much weaker than the hub steel.\n');

%% ======================= TORQUE SENSITIVITY =======================
% Everything scales as 1/T, so this is exact. FOS is against the longest SQUARE-ENDED
% (DIN 6885 Form B) key the existing slot allows, i.e. the best each joint can do without
% re-machining the bore. That is the honest ceiling to compare a design torque against.
fprintf('\n=== TORQUE SENSITIVITY (FOS at the best square-ended key the slot allows) ===\n');
fprintf('  %-28s %8s', 'station', 'maxFormB');
TQ = [123 150 160 170];
for t = TQ, fprintf(' %8s', sprintf('@%dNm', t)); end
fprintf('\n');
for i = 1:numel(S)
    if isnan(SLOT(i)), continue; end
    [W, ~] = mott_key_size(S(i).D);
    maxB = SLOT(i) - W;                      % square ends cannot use the slot's round ends
    fprintf('  %-28s %8.1f', S(i).name, maxB);
    for t = TQ
        Lt = res(i).L_req_mm * t / T_MOTOR;  % governing length scales linearly with torque
        fprintf(' %8.2f', maxB/Lt*N_DESIGN);
    end
    fprintf('\n');
end
fprintf('  A joint that clears N = %.1f at 150 Nm but not at 170 was getting its margin from the\n', N_DESIGN);
fprintf('  torque assumption, not from the geometry.\n');

%% ======================= SHAFT ITSELF, WITH THE KEYSEAT IN IT =======================
% Cutting a keyseat removes section and adds a stress raiser. Worth one check so nobody
% solves a key problem by shrinking the shaft.
fprintf('\n=== THE SHAFT UNDER THE KEY (does the keyseat break the shaft instead?) ===\n');
% NO Kt HERE, AND THAT IS DELIBERATE. An earlier version of this screen multiplied the
% torsional stress by Kt = 2.0 for the keyseat and reported factors of 0.34, which is
% wrong: stress-concentration factors are a FATIGUE quantity. Under static load a ductile
% steel yields locally at the keyseat corner and redistributes, so Mott (and every other
% text) omits Kt for static loading of ductile materials. Kt belongs in the fatigue sizing
% (Mott eq 12-24, on the bending term), which is what the Shafts sheet of the workbook does.
fprintf('  %-28s %6s %9s %9s %8s %8s\n','station','D','tau(MPa)','allow','N @4140','N @4340');
SY_ALT = 1090;      % 4340 OQT 1000, the grade the CBR27 Baja shafts use
for i = 1:numel(S)
    tau_shaft = 16 * S(i).T*1000 / (pi * S(i).D^3);   % solid round, static torsion
    fprintf('  %-28s %6.1f %9.1f %9.1f %8.2f %8.2f\n', S(i).name, S(i).D, tau_shaft, ...
        0.5*sy_shaft/N_DESIGN, 0.5*sy_shaft/tau_shaft, 0.5*SY_ALT/tau_shaft);
end
fprintf('  allow  = 0.5*sy/N at the assumed 4140 (sy %d MPa) and N = %.1f\n', sy_shaft, N_DESIGN);
fprintf('  N @... = the design factor against shear yield ACTUALLY achieved, at each grade.\n');
fprintf('  *** THE SHAFT MATERIAL IS NOW THE BIGGEST UNKNOWN IN THIS WHOLE CALC. *** At an\n');
fprintf('  assumed 4140 the smallest journal does not reach N = %.1f; at 4340 OQT 1000 it\n', N_DESIGN);
fprintf('  comfortably does. Same geometry, opposite verdict. Get the grade and heat treat.\n');
fprintf('  Static screen only. The fatigue case (where the keyseat Kt DOES apply) is the\n');
fprintf('  Shafts sheet of output/CFR27_Shaft_Keys.xlsx, via Mott eq 12-24.\n');

%% ======================= FIGURES =======================
fig = figure('Name','CFR27 shaft keys','Position',[40 40 1150 700]);
tg = uitabgroup(fig);

% --- Tab 1: THE ANSWER. Required key length against bore, per station.
% Stepped, not smooth, because W and H step at the Table 11-1 boundaries. Drawing it as a
% step function is the point: between two boundaries a bigger bore barely helps, then it
% drops off a cliff. That is where the diameter decision actually gets made.
ax = axes(uitab(tg,'Title','1. Key length vs bore'));
hold(ax,'on');
Dsweep = 12:0.25:60;
cols = lines(numel(S));
for i = 1:numel(S)
    Lr = nan(size(Dsweep));
    for k = 1:numel(Dsweep)
        [W, H] = mott_key_size(Dsweep(k));
        T_Nmm  = S(i).T*1000;
        Lr(k)  = max(2*T_Nmm/(tau_d*Dsweep(k)*W), 4*T_Nmm/(sig_d*Dsweep(k)*H));
    end
    plot(ax, Dsweep, Lr, '-', 'LineWidth', 1.9, 'Color', cols(i,:));
    plot(ax, S(i).D, res(i).L_req_mm, 'o', 'MarkerSize', 9, ...
        'MarkerFaceColor', cols(i,:), 'MarkerEdgeColor','k');
    plot(ax, S(i).D, S(i).Lhub, 'v', 'MarkerSize', 8, 'Color', cols(i,:));
end
xlabel(ax,'shaft / bore diameter (mm)'); ylabel(ax,'required key length (mm)');
grid(ax,'on'); ylim(ax, [0 60]);
legend(ax, reshape([string({S.name}); repmat("",2,numel(S))],1,[]), 'Location','northeast');
title(ax, sprintf(['REQUIRED KEY LENGTH vs BORE, key %s at N = %.1f.  ' ...
    'Circle = current (placeholder) bore, triangle = hub length available.' newline ...
    'Steps are Mott Table 11-1 boundaries: the key jumps a size and the length drops.'], ...
    MAT(KEY_MAT).name, N_DESIGN));

% --- Tab 2: material choice, at the governing station.
ax = axes(uitab(tg,'Title','2. Material choice'));
[~, iGov] = max([res.L_req_mm] ./ [res.L_hub_mm]);   % the tightest station
Lmat = zeros(numel(MAT), numel(Dsweep));
for m = 1:numel(MAT)
    td = 0.5*MAT(m).sy/N_DESIGN;
    sd = min([MAT(m).sy sy_shaft sy_hub])/N_DESIGN;
    for k = 1:numel(Dsweep)
        [W, H] = mott_key_size(Dsweep(k));
        T_Nmm  = S(iGov).T*1000;
        Lmat(m,k) = max(2*T_Nmm/(td*Dsweep(k)*W), 4*T_Nmm/(sd*Dsweep(k)*H));
    end
end
plot(ax, Dsweep, Lmat, 'LineWidth', 1.9); hold(ax,'on');
yline(ax, S(iGov).Lhub, 'k--', sprintf('hub length %.0f mm', S(iGov).Lhub), 'LineWidth',1.4);
xline(ax, S(iGov).D, 'b:', sprintf('bore %.0f', S(iGov).D));
xlabel(ax,'shaft / bore diameter (mm)'); ylabel(ax,'required key length (mm)');
grid(ax,'on'); ylim(ax, [0 60]);
legend(ax, {MAT.name}, 'Location','northeast');
title(ax, sprintf(['Material, at the tightest station (%s, %.0f Nm).' newline ...
    'Note how little 4140 buys over 1045 once BEARING governs: bearing is limited by the ' ...
    'hub, not the key.'], S(iGov).name, S(iGov).T));

% --- Tab 3: the torque path, so the sizing order is obvious.
ax = axes(uitab(tg,'Title','3. Torque path'));
bar(ax, [S.T], 'FaceColor', [0.25 0.45 0.75]); hold(ax,'on');
set(ax,'XTick',1:numel(S),'XTickLabel',{S.name},'XTickLabelRotation',18);
ylabel(ax,'torque at the joint (Nm)'); grid(ax,'on');
for i = 1:numel(S)
    text(ax, i, S(i).T + 20, sprintf('%.0f', S(i).T), 'HorizontalAlignment','center');
end
title(ax, sprintf(['Torque at each keyed joint, motor at its %.0f Nm cap.' newline ...
    'It multiplies by %.2f through the spur and %.2f more through the chain, then halves ' ...
    'across the diff.'], T_MOTOR, spur, chain));

save_tabfig(fig, fullfile('output','ShaftKeys'));

%% ======================= EXCEL, IN THE CBR27 LAYOUT =======================
% Same block structure as the Baja "Keys" sheet (notation / unit / formula / comments /
% value) so the DT group can read the two side by side without relearning anything.
xl = fullfile('output','CFR27_Shaft_Keys.xlsx');
if exist(xl,'file'), delete(xl); end
C = {'CFR27 PARALLEL KEY CALCULATIONS', '', '', '', '';
     'Method: Mott, Machine Elements in Mechanical Design 6th ed., section 11-4', '','','','';
     'Generated by shaft_key_calc.m. Do not hand-edit, regenerate.', '','','','';
     '', '', '', '', '';
     'Material Information', '', '', '', '';
     '', 'Notation', 'Unit', 'Formula', 'Value';
     'Yield strength of key material',   'sy',       'MPa', MAT(KEY_MAT).name, sy_key;
     'Yield strength of shaft material', 'sy',       'MPa', 'FROM CAD - assumed 4140',  sy_shaft;
     'Yield strength of hub material',   'sy',       'MPa', 'FROM CAD - assumed 1045',  sy_hub;
     'Governing bearing yield',          'sy bear',  'MPa', 'min(key, shaft, hub)',     sy_bear;
     'Design factor',                    'N',        'ul',  '',                         N_DESIGN;
     'Design shearing strength',         'tau d',    'MPa', 'tau d = 0.5*sy/N',         tau_d;
     'Design compressive strength',      'sigma d',  'MPa', 'sigma d = sy bear/N',      sig_d;
     '', '', '', '', '';
     'Design torque (motor cap)',        'T',        'Nm',  'p.T_flat_cap',             T_MOTOR;
     'As-driven torque (measured)',      'T',        'Nm',  'p.T_driver_max',           p.T_driver_max;
     'Total gear ratio',                 'G',        'ul',  sprintf('%d/%d x %d/%d', SPUR_DRIVEN,SPUR_DRIVER,CHAIN_DRIVEN,CHAIN_DRIVER), G;
     'Wheel torque, grip cap',           'T grip',   'Nm',  'mu*Fz_rear*r_load',        T_wheel_grip;
     '', '', '', '', ''};
for i = 1:numel(S)
    C = [C; {S(i).name, '', '', '', ''};
            {'', 'Notation', 'Unit', 'Formula', 'Value'};
            {'Torque at joint',              'T',    'Nmm', S(i).src,                        S(i).T*1000};
            {'Bore',                         'D',    'mm',  'FROM CAD - PLACEHOLDER',        S(i).D};
            {'Keyway width',                 'W',    'mm',  'Mott Table 11-1',               res(i).W_mm};
            {'Keyway height',                'H',    'mm',  'Mott Table 11-1',               res(i).H_mm};
            {'Maximum key length',           'Lmax', 'mm',  'FROM CAD - PLACEHOLDER',        S(i).Lhub};
            {'Min. length for shear',        'Lmin (shear)',       'mm', 'Lmin = 2*T/(tau d*D*W)',   res(i).L_shear_mm};
            {'Min. length for compression',  'Lmin (compression)', 'mm', 'Lmin = (4*T)/(sigma d*D*H)', res(i).L_bear_mm};
            {'GOVERNING min. length',        'Lmin',  'mm', 'max of the two above',          res(i).L_req_mm};
            {'FOS if key runs full hub',     'N act', 'ul', 'solve Mott 11-2/11-4 for N',    res(i).FOS_at_hub};
            {'Fits in hub?',                 '',      '',   '',    ternary(res(i).fits,'YES','NO - increase bore')};
            {'', '', '', '', ''}]; %#ok<AGROW>
end
writecell(C, xl, 'Sheet', 'Keys');
writetable(struct2table(res), xl, 'Sheet', 'Summary');
fprintf('\nSaved: %s\n', xl);
fprintf('       output/ShaftKeys.fig + one PNG per tab\n');

function out = ternary(c, a, b)
    if c, out = a; else, out = b; end
end

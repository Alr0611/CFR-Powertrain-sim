%% GEAR_CHECK  --  "we want ratio X. Which gears hit it, and do they survive?"
%
% THE POINT
%   gear_ratio_optimization.m tells you WHAT ratio to run. That means new
%   gears. This tells you whether those gears will actually live, using the
%   Shigley/AGMA strength check (Chapter 9) -- bending + contact stress.
%
% WHAT IT DOES
%   1. Reproduces our current gearbox to prove the math is right
%      (should spit out ~354 MPa bending / ~1610 MPa contact -- the same
%       numbers as the CFR24 Driveline Tool. If it doesn't, something broke.)
%   2. Sweeps every sensible pinion/gear combo, keeps the ones that land on
%      your target ratio, and reports whether each one passes -- including
%      what each one does to CHAIN TENSION (the chain stage doesn't change,
%      but the torque we feed it does).
%
% OUR DRIVELINE (unchanged for CFR27, just straight halfshafts)
%   motor -> 2:1 spur gearbox (15T/30T, module 2.5, 25 mm face) -> chain
%   13T:30T (= 2.3077:1, per "Sprocket Gearing and Forces.xlsx") -> diff.
%   2 x 2.3077 = 4.615 total ("4.61" around the shop is this, rounded).
%   Change the total ratio by changing EITHER the gearbox teeth (checked
%   here) OR the sprockets (chain -- tension reported here, wear/strength of
%   the chain itself is a different check, not this file).
%
% THE ONE THING TO KNOW ABOUT THE TORQUE
%   Gears are sized on the torque they see ALL DAY (continuous ~80 Nm), not
%   the once-a-lap peak. That's why our tool shows 354 MPa. The peak (140 Nm)
%   is reported too, because that's what actually breaks teeth if it's often.
%   Both are printed -- look at both.

clear; clc;
addpath(fullfile(fileparts(mfilename('fullpath')), 'lib'));  % works wherever MATLAB is pointed
p = params_cfr26();

%% ============== INPUTS FROM THE GEAR DRAWING (fill these in!) ==============
% Two numbers off the drawing end the J-factor argument documented below, and
% one answer from whoever ordered the gears ends the allowables argument.
% They live HERE, at the top, so the day you get them this is the only place
% you touch. NaN / 'baja-legacy' = "don't know yet" -> the script runs in
% BRACKETED mode and refuses to pretend it knows an absolute FOS.
drawing.PA       = NaN;   % pressure angle, deg (20 or 25) -- drawing title block
drawing.x_pinion = NaN;   % profile-shift coefficient of the 15T pinion
drawing.x_gear   = NaN;   % profile-shift coefficient of the 30T gear
% Material + heat treat. One of:
%   'baja-legacy'  SCM415 numbers inherited from Baja's sheet (PLACEHOLDER --
%                  not our steel; FOS printed with it is indicative only)
%   'grade1' | 'grade2' | 'grade3'  Shigley Tbl 14-3/14-6, carburized+hardened
material = 'baja-legacy';

mats.baja_legacy = struct('St',461,  'Sc',1627.9,'note','Baja SCM415 sheet (placeholder, not our steel)');
mats.grade1      = struct('St',379,  'Sc',1241,  'note','Shigley Grade 1 carburized');
mats.grade2      = struct('St',448,  'Sc',1551,  'note','Shigley Grade 2 carburized');
mats.grade3      = struct('St',517,  'Sc',1896,  'note','Shigley Grade 3 carburized');
mat         = mats.(strrep(material,'-','_'));
mat_is_real = ~strcmpi(material,'baja-legacy');

%% ---- design point + AGMA factors (matching the CFR24 Driveline Tool) ----
g.module   = 2.5;      % mm
g.face     = 25;       % mm face width
g.PA       = 20;       % deg -- used for the CONTACT factor I and the sweep;
if ~isnan(drawing.PA), g.PA = drawing.PA; end   % drawing wins once it's read
g.Ko       = 1.25;     % overload
g.Kv       = 1.2;      % dynamic
g.Ks       = 1.0;      % size
g.Km       = 1.129;    % load distribution
g.Kb       = 1.0;      % rim thickness
g.Cp       = 191;      % MPa, elastic coefficient (steel/steel)
g.T_cont   = 79.6;     % Nm  continuous motor torque (what gears live on)
g.T_peak   = p.T_flat_cap;   % Nm  peak (150, datasheet spec)
g.St_allow = mat.St;   % MPa bending allowable  (see material block above)
g.Sc_allow = mat.Sc;   % MPa contact allowable

%% ---- chain stage (from "Sprocket Gearing and Forces.xlsx", CFR24 driveline) ----
% 13T motor sprocket -> 30T diff sprocket, 5/8" (15.875 mm) pitch.
% Chain tension = gearbox OUTPUT torque / motor-sprocket pitch radius. A lower
% gearbox ratio feeds the chain LESS torque -> gearing down helps the chain.
chain.Np      = 13;  chain.Ng = 30;
chain.pitch   = 15.875;                            % mm
chain.ratio   = chain.Ng/chain.Np;                 % 2.3077
chain.d_motor = chain.pitch/sin(pi/chain.Np);      % 66.33 mm pitch dia (sheet's VLOOKUP)
chainT = @(T_box_out) T_box_out/(chain.d_motor/2); % Nm/mm = kN, same formula as the sheet

%% ---- the three candidate J values for our 15T pinion, with provenance ----
J_20std = 0.245;    % Shigley Fig 14-6 = Mott Fig 9-10a: 20 deg, UNSHIFTED, 15T
J_cfr24 = 0.325;    % what the CFR24 Driveline Tool used (= a 25 deg panel read)
J_25std = 0.345;    % Mott Fig 9-10b: 25 deg panel at 15T
% The saga, so nobody re-treads it:
%   - CFR24 DECLARES 20 deg ('1.1 v & Wt'!A1) and its I = 0.108 agrees.
%   - But its J = 0.325 is NOT the 20 deg value (that's ~0.245); 0.325 is a
%     read of Mott's 25 deg panel.
%   - Centre distance 56.25 mm is exactly standard -> net shift is zero, but
%     a 15T pinion at 20 deg UNSHIFTED would be undercut (limit 17.1 teeth),
%     so pinion +x / gear -x is the likely reality: it keeps centre distance
%     standard AND adds root material, pushing J from 0.245 toward ~0.325.
%   - So CFR24's number may be right for a reason nobody wrote down. Or it's
%     a chart misread. Both stories predict the same number.
% The drawing block above settles it. Until then: bracket, don't assert.

%% ---- 1. sanity check: reproduce our current 15/30 gearbox ----
fprintf('=== SANITY CHECK: our current gearbox (15T/30T, m2.5, 25mm face) ===\n');
r = check_pair(15, 30, g, g.T_cont, J_cfr24);
fprintf(' Using CFR24 J=%.3f -> bending %3.0f MPa | contact %.0f MPa\n', J_cfr24, r.st, r.sc);
fprintf(' CFR24 Driveline Tool says 354 / 1610 MPa. Stress math match? %s\n\n', ...
    ternary(abs(r.st-354)<25 && abs(r.sc-1610)<60, 'YES', 'NO - something is off'));

% What we report for the CURRENT gears depends on how much of the drawing we have:
know_PA = ~isnan(drawing.PA);  know_x = ~isnan(drawing.x_pinion);
if ~know_PA
    mode = 'BRACKETED (drawing not read yet)';
    J_lo = J_20std;  J_hi = J_cfr24;
elseif drawing.PA==20 && know_x && drawing.x_pinion==0
    mode = '20 deg UNSHIFTED per drawing -- but that geometry is UNDERCUT at 15T, re-read the drawing!';
    J_lo = J_20std;  J_hi = J_20std;
elseif drawing.PA==20 && know_x && drawing.x_pinion>0
    % Shift confirmed. Exact J for shifted teeth needs AGMA 908-B89 (or the
    % gear vendor's number). Until someone does that math, the honest window
    % is [unshifted chart .. CFR24's value]; shifted reality sits high in it.
    mode = sprintf('20 deg, x=+%.2f per drawing -- shifted, J near the top of the bracket', drawing.x_pinion);
    J_lo = J_20std;  J_hi = J_cfr24;
elseif drawing.PA==25
    mode = '25 deg per drawing -- CFR24''s 0.325 was nearly right, chart value 0.345';
    J_lo = J_cfr24;  J_hi = J_25std;
else
    mode = '20 deg, shift unknown -- bracketed';
    J_lo = J_20std;  J_hi = J_cfr24;
end
r_lo = check_pair(15, 30, g, g.T_cont, J_lo);
r_hi = check_pair(15, 30, g, g.T_cont, J_hi);
fprintf(' --- current gears, honest window [%s] ---\n', mode);
fprintf('   J=%.3f -> bending %3.0f MPa, FOS %.2f   (conservative end)\n', J_lo, r_lo.st, g.St_allow/r_lo.st);
if J_hi > J_lo
fprintf('   J=%.3f -> bending %3.0f MPa, FOS %.2f   (optimistic end)\n',   J_hi, r_hi.st, g.St_allow/r_hi.st);
fprintf('   that window is a %.0f%% swing -- the drawing shrinks it to a point.\n', 100*(r_lo.st/r_hi.st - 1));
end
if ~mat_is_real
fprintf('   allowables = %s -> FOS is INDICATIVE ONLY until material is known.\n', mat.note);
else
fprintf('   allowables = %s.\n', mat.note);
end

rp = check_pair(15, 30, g, g.T_peak, J_lo);
fprintf('\n At PEAK %.0f Nm (conservative J) -> bending %.0f MPa | contact %.0f MPa\n', ...
    g.T_peak, rp.st, rp.sc);
fprintf(' Allowable (%s): bending %.0f | contact %.0f MPa\n', material, g.St_allow, g.Sc_allow);
fprintf(' Chain tension today at peak: %.1f kN (sheet quotes 9.0 kN at 150 Nm motor)\n\n', ...
    chainT(g.T_peak*2));

%% ---- 2. which gearsets hit a target ratio, and do they pass? ----
target_total = 4.20;                 % <-- what the sim recommends
target_box = target_total / chain.ratio;   % what the GEARBOX must do
fprintf('=== GEARSETS FOR %.2f:1 TOTAL (chain stays %d:%d = %.4f -> gearbox needs %.3f) ===\n', ...
    target_total, chain.Np, chain.Ng, chain.ratio, target_box);
fprintf(' Np  Ng   box    total | bend@cont  FOS  | bend@peak  contact@peak | chain@peak | verdict\n');
% Np starts at 18: that's the undercut limit at 20 deg (17.1 teeth), so at 18+ the
% chart is real, unshifted, fanned data and there's no argument to have. Below that
% you need profile shift and this file doesn't model it.
found = false;
for Np = 18:24
    for Ng = 28:60
        box = Ng/Np;
        if abs(box - target_box) > 0.03, continue; end     % must hit the ratio
        found = true;
        rc = check_pair(Np, Ng, g, g.T_cont);
        rk = check_pair(Np, Ng, g, g.T_peak);
        FOS = g.St_allow / rc.st;
        Tch = chainT(g.T_peak*box);          % kN into the chain at motor peak
        ok  = FOS > 1.5 && rk.sc < g.Sc_allow;
        fprintf(' %2d  %2d  %.3f  %.3f  |  %4.0f MPa   %.2f  |  %4.0f MPa   %5.0f MPa    |  %5.1f kN   | %s\n', ...
            Np, Ng, box, box*chain.ratio, rc.st, FOS, rk.st, rk.sc, Tch, ternary(ok,'PASS','check it'));
    end
end
if ~found, fprintf(' (nothing lands within 0.03 of that ratio -- widen the tooth range)\n'); end
fprintf('\nFOS = allowable bending / actual bending at continuous torque. >1.5 = comfy.\n');
if ~mat_is_real
fprintf('    (still %s allowables -- FOS comparisons between rows are solid,\n', material);
fprintf('     absolute values are not. Ask what steel we''re buying.)\n');
end
fprintf('Contact stress at PEAK is the one that pits teeth -- keep it under %.0f MPa.\n', g.Sc_allow);
fprintf('Chain@peak = tension the chain sees at motor peak torque with that gearbox\n');
fprintf('    (today: %.1f kN). Lower box ratio -> lower chain tension, free bonus.\n', chainT(g.T_peak*2));
fprintf('J comes from the digitized AGMA chart (lib/spur_gear_J.m), 20 deg standard.\n');
fprintf('Shifted gears would read higher -- this file is conservative for those.\n');

%% ---- the actual Shigley/AGMA math ----
function r = check_pair(Np, Ng, g, T, J_override)
    r.Dp = Np * g.module;                 % mm pitch diameter (pinion)
    r.mG = Ng / Np;                       % gear ratio of the pair
    r.Wt = 2 * T / (r.Dp/1000);           % N tangential load at the pitch circle
    if nargin >= 5 && ~isempty(J_override)
        r.J = J_override;                 % hand-set (small pinion, chart-read)
    else
        r.J = spur_gear_J(Np, Ng);        % bending geometry factor (chart lookup)
    end
    phi  = deg2rad(g.PA);
    r.I  = (cos(phi)*sin(phi)/2) * (r.mG/(r.mG+1));    % contact geometry factor
    % AGMA bending (metric):  st = Wt*Ko*Kv*Ks/(b*m) * Km*Kb/J
    r.st = (r.Wt*g.Ko*g.Kv*g.Ks)/(g.face*g.module) * (g.Km*g.Kb/r.J);
    % AGMA contact:  sc = Cp*sqrt( Wt*Ko*Kv*Ks*Km / (b*Dp*I) )
    r.sc = g.Cp * sqrt( (r.Wt*g.Ko*g.Kv*g.Ks*g.Km) / (g.face*r.Dp*r.I) );
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

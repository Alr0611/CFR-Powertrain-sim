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
%      your target ratio, and reports whether each one passes.
%
% OUR DRIVELINE (unchanged for CFR27, just straight halfshafts)
%   motor -> 2:1 spur gearbox (15T/30T, module 2.5, 25 mm face) -> chain
%   ~2.3:1 -> diff. 2 x 2.3 = 4.61 total. Change the total ratio by changing
%   EITHER the gearbox teeth (checked here) OR the sprockets (chain, not a
%   gear -- different check, not this file).
%
% THE ONE THING TO KNOW ABOUT THE TORQUE
%   Gears are sized on the torque they see ALL DAY (continuous ~80 Nm), not
%   the once-a-lap peak. That's why our tool shows 354 MPa. The peak (140 Nm)
%   is reported too, because that's what actually breaks teeth if it's often.
%   Both are printed -- look at both.

clear; clc;
addpath(fullfile(fileparts(mfilename('fullpath')), 'lib'));  % works wherever MATLAB is pointed
p = params_cfr26();

%% ---- design point + AGMA factors (matching the CFR24 Driveline Tool) ----
g.module   = 2.5;      % mm
g.face     = 25;       % mm face width
g.PA       = 20;       % deg pressure angle
g.Ko       = 1.25;     % overload
g.Kv       = 1.2;      % dynamic
g.Ks       = 1.0;      % size
g.Km       = 1.129;    % load distribution
g.Kb       = 1.0;      % rim thickness
g.Cp       = 191;      % MPa, elastic coefficient (steel/steel)
g.T_cont   = 79.6;     % Nm  continuous motor torque (what gears live on)
g.T_peak   = p.T_flat_cap;   % Nm  peak (140)
% Allowables (SCM415 case-hardened, from the Baja Shigley sheet -- swap for
% whatever steel we actually buy). HEADS UP: these are BAJA'S numbers, not ours --
% the CFR24 Driveline Tool has no allowables at all, it computes stresses and stops.
% So absolute FOS here is Baja-flavoured. Comparisons between gearsets are fine
% (the allowable cancels). Shigley Table 14-3/14-6, carburized & hardened, for when
% someone finally tells us what our gears are made of:
%   Grade 1: St 379 MPa, Sc 1241 | Grade 2: St 448, Sc 1551 | Grade 3: St 517, Sc 1896
g.St_allow = 461;      % MPa bending  (Baja's -- roughly Grade 2 carburized)
g.Sc_allow = 1627.9;   % MPa contact  (Baja's)

%% ---- 1. sanity check: reproduce our current 15/30 gearbox ----
% This proves our STRESS MATH matches CFR24. Feed it CFR24's own J and we should
% land on their numbers. We do. That part is settled.
%
% What is NOT settled is the J itself, and we can't settle it from the spreadsheet:
%   - CFR24 DECLARES 20 deg pressure angle ('1.1 v & Wt'!A1)
%   - its I = 0.108 agrees -- that IS the 20 deg value
%   - but its J = 0.325 does NOT: the 20 deg chart reads ~0.245 at 15 teeth.
%     0.325 is roughly the 25 deg value (Mott Fig 9-10 has a separate 25 deg panel).
%   - its centre distance 56.25 mm is exactly standard, so net profile shift is zero
%
% Best guess: the gears ARE 20 deg but PROFILE SHIFTED (pinion +, gear -, which keeps
% centre distance standard). A 15T pinion at 20 deg would otherwise be undercut --
% the limit is 2/sin^2(20) = 17.1 teeth -- and shifting adds root material, pushing J
% up from 0.245 toward about the 0.325 CFR24 used. So 0.325 may be right for a reason
% nobody wrote down. Or it's a chart misread. Both stories predict the same number.
%
% TWO NUMBERS OFF THE GEAR DRAWING SETTLE IT: pressure angle, and profile shift x.
% Until then, don't quote an absolute FOS off this file.
J_cfr24 = 0.325;    % what the Driveline Tool used -- provenance unresolved, see above

fprintf('=== SANITY CHECK: our current gearbox (15T/30T, m2.5, 25mm face) ===\n');
r = check_pair(15, 30, g, g.T_cont, J_cfr24);
fprintf(' Using CFR24 J=%.3f -> bending %3.0f MPa | contact %.0f MPa\n', J_cfr24, r.st, r.sc);
fprintf(' CFR24 Driveline Tool says 354 / 1610 MPa. Stress math match? %s\n', ...
    ternary(abs(r.st-354)<25 && abs(r.sc-1610)<60, 'YES', 'NO - something is off'));

% How much the unresolved J is worth, so nobody mistakes this for precision:
J_20deg = 0.245;    % 20 deg standard chart at 15T (Shigley Fig 14-6 = Mott Fig 9-10a)
r2 = check_pair(15, 30, g, g.T_cont, J_20deg);
fprintf('\n --- how much the open J question is worth ---\n');
fprintf(' If the gears are 20 deg STANDARD (J=%.3f): bending %3.0f MPa, FOS %.2f\n', ...
    J_20deg, r2.st, g.St_allow/r2.st);
fprintf(' If CFR24''s J=%.3f is right:              bending %3.0f MPa, FOS %.2f\n', ...
    J_cfr24, r.st, g.St_allow/r.st);
fprintf(' That is a %.0f%% swing. A 15T pinion at 20 deg is below the undercut limit\n', ...
    100*(r2.st/r.st - 1));
fprintf(' (%.1f teeth), so it is almost certainly profile shifted -- which this file\n', ...
    2/sin(deg2rad(20))^2);
fprintf(' does NOT model. Get the pressure angle + shift off the drawing.\n');
fprintf(' Also: allowables below are BAJA''S steel, not ours. FOS is indicative only.\n');

rp = check_pair(15, 30, g, g.T_peak, J_cfr24);
fprintf('\n At PEAK %.0f Nm -> bending %.0f MPa | contact %.0f MPa\n', ...
    g.T_peak, rp.st, rp.sc);
fprintf(' Allowable (Baja''s): bending %.0f | contact %.0f MPa\n\n', g.St_allow, g.Sc_allow);

%% ---- 2. which gearsets hit a target ratio, and do they pass? ----
target_total = 4.20;                 % <-- what the sim recommends
chain = 2.305;                       % our chain/sprocket stage (unchanged)
target_box = target_total / chain;   % what the GEARBOX must do
fprintf('=== GEARSETS FOR %.2f:1 TOTAL (chain stays %.3f -> gearbox needs %.3f) ===\n', ...
    target_total, chain, target_box);
fprintf(' Np  Ng   box    total | bend@cont  cont-FOS | bend@peak  contact@peak | verdict\n');
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
        ok  = FOS > 1.5 && rk.sc < g.Sc_allow;
        fprintf(' %2d  %2d  %.3f  %.3f  |  %4.0f MPa    %.2f   |  %4.0f MPa   %5.0f MPa   | %s\n', ...
            Np, Ng, box, box*chain, rc.st, FOS, rk.st, rk.sc, ternary(ok,'PASS','check it'));
    end
end
if ~found, fprintf(' (nothing lands within 0.03 of that ratio -- widen the tooth range)\n'); end
fprintf('\nFOS = allowable bending / actual bending at continuous torque. >1.5 = comfy.\n');
fprintf('Contact stress at PEAK is the one that pits teeth -- keep it under %.0f MPa.\n', g.Sc_allow);
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

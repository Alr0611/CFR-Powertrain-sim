function p = params_cfr26()
%PARAMS_CFR26  Every number the sim uses. This is the ONLY place they come from.
%
%   Want to change something? Change it HERE. Every script reads from this
%   file, so you fix a number once and the whole sim updates. Please don't
%   permanently change numbers into the scripts, that's how you end up with the aero
%   value being right in one file and wrong in three others. yes ive done
%   that many times.
%
%   Each number says where it came from. Rough honesty scale:
%     MEASURED  = we physically measured it. Trust it.
%     DATASHEET = the manufacturer says so.
%     GUESSESTIMATE    = educated guess/estimate mostly estimate TM.

%% ---- THE BATTERY PACK ----
p.N_series   = 88;          % 88 cells in a row (22 per segment x 4 segments)
p.N_parallel = 4;           % 4 of those rows side by side. So 352 cells total.
p.Q_cell     = 4.4 * 3600;  % How much charge one cell holds, in amp-SECONDS.
                            % BAK 45D = 4.4 Ah. (DATASHEET, from our ESF)
                            % note: the real cells might hold a bit MORE
                            % than this -- see the "known warnings" note in README in the GitHub.

%% ---- GEAR RATIOS  ----
p.gear_current  = 4.61;                                  % what's on the car now
p.gears_to_test = unique(round([4.0:0.1:5.2, 4.61, 2.0*(26:34)/13], 4));
                            % everything we're trying. The 2.0*(26:34)/13 terms are the
                            % BUILDABLE sprocket ratios: fixed 15:30 gearbox (2.000) times
                            % driven/13, for driven 26T..34T. Added so the sweep lands exactly
                            % on ratios you can actually bolt on instead of near them. The old
                            % 4.0:0.1:5.2 grid is still in there, nothing was removed.
                            % See sprocket_configs.md and lib/sprocket_ratio.m.

%% ---- DRIVETRAIN (mechanical hardware, motor-independent) ----
p.eta_drivetrain = 0.794;   % Of the mechanical power the motor makes, ~79% reaches the
                            % ground; the rest is heat in the gears, bearings, chain, diff,
                            % and halfshafts. This is the CURRENT car:
                            %   spur x bearings x chain x diff x halfshaft@12deg
                            %   = 0.98 x 0.95 x 0.97 x 0.92 x 0.956 = 0.794
                            % (was 0.823 when we assumed STRAIGHT halfshafts; the real 12deg
                            % halfshaft angle costs the difference -- see drivetrain_efficiency.m
                            % for the full stack + per-stage breakdown). Straightening the
                            % halfshafts to 0-5deg raises this back toward ~0.82.
                            % NOTE: this value CANCELS in the SOC / gear-ratio math (wheel
                            % power is ratio-invariant, verify_math sec 7), so it does not move
                            % the recommendation; it only sets absolute accel/top-speed force.

%% ---- THE CAR ITSELF ----
p.m_car   = 294;            % kg, car + driver, on actual scales. (MEASURED)
p.r_wheel = 0.200;          % m, EFFECTIVE ROLLING radius. MEASURED ON THE CAR.
                            % Roll-out test, 2026-08-11: chalk mark on a rear tyre, car
                            % on the floor, pushed 2 full revolutions -> 99 in = 2.515 m.
                            % Circumference 1.2573 m -> r_eff = 0.2001 m.
                            %
                            % THIRD CHECK, off our tyre's own TTC cornering runs (Hoosier
                            % 43075 16x7.5-10, runs 2,4,5,6,7,8,9): loaded radius RL
                            % medians 0.1897-0.1944 m. The RE channel is corrupt on those
                            % runs (rig derivation goes singular at low speed), so take
                            % the donor's clean RE-RL offset of +6.7 mm and apply it:
                            % r_eff ~ 0.1988 m. tools/tyre_crosscheck_16x75.py.
                            % Three independent numbers: 0.2001 roll-out, 0.1988 TTC,
                            % 0.1975 log. All inside 1.3%.
                            %
                            % CROSS-CHECK, fully independent, agrees to 1.3%: the logged
                            % accel runs give r = 0.1975 from an energy balance at
                            % eta 0.794 (tools/radius_from_energy_balance.py). Turn that
                            % round and at r = 0.200 the log implies eta = 0.810 against
                            % the 0.794 this file models. 2% apart on a number nothing
                            % here was fitted to.
                            % Tape across an unloaded rear read 15-15.5 in OD, i.e. a
                            % nominal 16 in tyre. Consistent, but the least reliable of
                            % the three (curved tread, hand-held tape) so it does not set
                            % the value.
                            %
                            % *** THE CAR IS ON A 16 INCH TYRE, NOT AN 18. *** This was
                            % 0.221 and that was WRONG BY 11%. 0.221 is a real number but
                            % it is the TTC RE channel for the Hoosier 18.0x6.0-10, which
                            % is not what the car runs. Inheriting a measurement of the
                            % wrong part is how it survived three sessions.
                            % It accounts for essentially the whole 0-75 m gap: the sim
                            % was slower than the car because it thought each wheel
                            % revolution covered 11% more ground than it does.
                            %
                            % Firmware TIRE_RADIUS_M = 0.2032 was therefore about RIGHT
                            % (1.6% over), not 8% under as previously recorded. The
                            % earlier "firmware is badly wrong" finding was an artifact
                            % of the wrong radius here. Nothing to raise with embedded.
                            % The 1.6% is comfortably explained by tyre WEAR: 0.2032 is
                            % nominal 16 in OD / 2, i.e. a fresh tyre, and this roll-out
                            % is on worn rubber. 3 mm of tread off the radius is exactly
                            % that gap. Could also just be a round-number guesstimate on
                            % their side. Either way it is not a bug.
                            % NOTE this means r_eff DRIFTS with tread life. 0.200 is the
                            % current set. Re-run the roll-out on new tyres.
p.r_load  = 0.1901;         % m, LOADED radius. Ground to wheel centre with the tyre
                            % squashed. This is a DIFFERENT number from r_wheel above and
                            % they are not interchangeable:
                            %   r_wheel (0.2000) = distance per radian. Converts wheel
                            %                      speed to road speed, defines zero slip.
                            %   r_load  (0.1901) = the moment arm. Tyre force acts at the
                            %                      contact patch, so the wheel torque
                            %                      balance uses THIS.
                            % r_load < r_wheel always. A loaded tyre rolls further per rev
                            % than its squashed radius suggests, because the tread band is
                            % basically inextensible and walks over its own flat spot.
                            %
                            % MEASURED, TTC Round 9 cornering runs 2,4,5,6,7,8,9 (Hoosier
                            % 16x7.5-10, our tyre), RL channel at 68-74 kPa. RL falls with
                            % load, which is why the value is quoted AT the load the rears
                            % actually carry:
                            %    500-700 N  -> 0.1942     900-1100 N -> 0.1900
                            %    700-900 N  -> 0.1929    1100-1300 N -> 0.1898
                            % Rear load per tyre at launch is ~926 N (static 696 N plus
                            % transfer at 7.7 m/s2). TTC RL at 926 +/- 150 N = 0.1901.
                            %
                            % Using r_wheel for both, which this sim did until now,
                            % understates wheel force by r_wheel/r_load = 5.2% and cost
                            % ~0.10 s over 75 m. Sensitivity is -0.010 s per mm.
                            % NOT A FREE PARAMETER. It is measured, and it is only quoted
                            % to 4 dp because RL itself moves ~4 mm across the load range.
p.g       = 9.81;           % If this changes we have bigger problems.
p.rho_air = 1.225;          % air density at sea level-ish.

%% ---- TIRE GRIP ----
%  *** DERIVED, AND IT IS THE WRONG TYRE. READ THIS BEFORE QUOTING ANY OF IT. ***
%
%  OUR TYRE, confirmed on the car and against the TTC 'tireid' field:
%      Hoosier 43075 16x7.5-10 R20
%      cornering runs 2,4,5,6 (7in rim) and 7,8,9 (8in rim)
%      drive/brake runs: NONE. There are none. Never were.
%  THE DONOR this Fx set is fitted to:
%      Hoosier 43100 18.0x6.0-10 R20, drive/brake runs 68-73
%
%  So the set is fitted to real data, off a casing that is 1.5 in NARROWER and 2 in
%  LARGER in diameter than ours. Same maker, same R20 compound, same 10 in rim.
%  Provenance is DERIVED, not MEASURED. Do not present it as measured for this car.
%
%  HOW BIG IS THE TRANSFER ERROR? Both tyres have cornering data, so it is measurable
%  rather than a shrug. Peak lateral mu, ours vs donor, matched load, 68-74 kPa, zero
%  camber, like-for-like 7 in rim (tools/tyre_crosscheck_16x75.py):
%      Fz 500-700   0.950      Fz 900-1100  0.974
%      Fz 700-900   0.949      Fz 1100-1300 0.962     mean 0.959
%  Our tyre grips about 4% LESS than the donor, so this set mildly OVERSTATES our grip.
%  Small, and in the unsafe direction, so know about it. CAVEAT: that is a LATERAL ratio
%  judging a LONGITUDINAL set. It is an anchor, not a measurement.
%  Reproduced independently at 0.956 by tools/compare_teammate_tir.py using all rim
%  widths, so the ~4% is robust, not an artifact of which runs got picked.
%  NOT APPLIED. Applying it would mean PDX1 2.25161 -> 2.153, nominal mu 1.464 -> 1.400.
%  Left off because it stacks a lateral inference on top of an already-borrowed set.
%
%  WHAT IT DOES AND DOES NOT MOVE, measured not assumed:
%    accel time      0-75 m moves 0.001-0.011 s. Nothing.
%    gear ratio      optimum stays 5.20:1. Nothing.
%    TC ENGAGEMENT   FLIPS IT. At 150 Nm peak TC cut goes 0.00 -> 0.52. At 123 Nm on the
%                    test day's derived grip (mu_scale 0.853) it goes 0.00 -> 0.54.
%  So the "TC never engages" result is KNIFE-EDGE. A 4% grip change, which is exactly the
%  size of the known transfer bias, flips it. Do not treat "TC does nothing" as a settled
%  finding. The robust part is only the direction: more torque or less grip -> TC works.
%  Anyone doing TC work should run it BOTH ways and report the pair.
%
%  A TEAMMATE HAS A LATERAL FIT FOR OUR ACTUAL TYRE:
%  Hoosier_16x7_5_10_R20_MF52.tir, MF5.2, FY0/MZ0/MX fitted, all Fx coefficients zero.
%  It does NOT give us longitudinal data, but it is validated: checked against raw TTC
%  cornering for our tyre it is within 1.3% at every load bin. Two things taken from it:
%    - its DIMENSION block says UNLOADED_RADIUS 0.203, WIDTH 0.1905, RIM_RADIUS 0.127.
%      Fourth independent confirmation of the 16 in tyre and r_eff ~0.20.
%    - PDY1 2.5378, PDY2 -0.12884 at FNOMIN 700 N. Normalised that is -0.0508 per dfz
%      against our longitudinal -0.0383. Both negative, his stronger, which is the normal
%      lateral-vs-longitudinal relationship. So our PDX2 is CONSISTENT with our own
%      tyre's measured behaviour, which it had no way of being before.
%  Use his file for anything cornering. It is the right tyre and ours is not.
%
%  Survives the tyre-size change: the load-sensitivity METHOD, and the finding that a
%  free fit cannot identify PDX2 (see below). Those are about fitting, not casing. The
%  mu-slip SHAPE is mostly a compound property so it travels reasonably.
%  Does NOT survive: the absolute grip level and the exact peak slip for our tyre.
%
%  Fit details for the 18.0x6.0-10: 5467 samples, |SA| and |IA| under 0.5 deg,
%  P = 71 +/- 3 kPa, R^2 0.99708, RMS 85.9 N against an |Fx| p95 of ~2650 N.
%  tools/refit_mf_pdx2_constrained.py.
%
%  *** HIGH-SLIP TAIL STILL NOT MEASURED. *** Sweep reaches |SL| <= 0.186, a standing
%  start runs 5-7. Past 0.19 is extrapolated shape, and that's exactly what decides
%  whether a spinning tyre recovers. Fitted peak is at SL 0.16-0.20 which IS inside the
%  data (old fit peaked at 0.21-0.35, outside it).
%
%  PDX1/PDX2 are RAW BELT values, LMUX stays separate below, don't fold it in. Pressure
%  terms PPX1..4 and camber PDX3 are not fitted.
%
%  WHERE THIS UNCERTAINTY DOES *NOT* SHOW UP: the 0-75 m accel time at the
%  ratios we actually run. This file used to warn that "every accel time is a
%  RANGE" because of these numbers -- that is measurably NOT the case. At 4.61:1
%  the car is TORQUE-limited for the whole run: 0 of 3694 integration steps to
%  75 m hit the traction cap, and perturbing PDX1 by +/-20% or LMUX by +/-10%
%  moves 0-75 m by 0.000 s (tripling grip does nothing).
%  It DOES matter for: the traction-limit line in accel_model's tractive-effort
%  plot, launch/TC work, and much higher ratios where the flat torque region
%  starts to touch the cap.
%
%  The accel time's real uncertainty is p.eta_drivetrain: swinging it over
%  0.76-0.84 (i.e. the differential assumption) moves 0-75 m by 0.23 s, which is
%  ~10x every other parameter combined. Full budget at 4.61:1 -- numerical
%  +/-0.0003 s, all parameters ~+/-0.12 s, and a +0.40 s (+9%) bias against the
%  one real launch (4.40 s), which needs ~+19% torque/power to close and so
%  lives in the torque envelope or the measurement, not in grip.
p.tir.PDX1   =  2.25161;    % grip at normal load. MEASURED (was 2.1, derived).
p.tir.PDX2   = -0.08617;    % how grip drops as you squash the tire harder. MEASURED, but
                            % NOT by the curve fit. Read this before touching it.
                            %
                            % A free fit returns PDX2 ~ 0 ("grip is flat with load"),
                            % which is wrong. PDX2 is unidentifiable in force-space: pin
                            % it anywhere from 0 to -0.20, refit the other 13, and RMS
                            % moves 3.7 N out of 85. Watch PKX2 swing 6.3 -> 25.4 over
                            % that grid, that's the slip-stiffness terms soaking up the
                            % load sensitivity. (tools/pdx2_identifiability.py)
                            %
                            % The raw samples do show grip falling with load. mu at
                            % MATCHED SLIP, 600 N -> 1200 N, no fit and no peak-finding:
                            %    SL 0.04-0.07  -4.9%     SL 0.10-0.14  -4.3%
                            %    SL 0.07-0.10  -7.3%     SL 0.14-0.19  -3.4%
                            % Negative in every band. (tools/mu_load_model_vs_data.py)
                            %
                            % So this is solved to match the measured peak-mu slope of
                            % -0.1796 mu/kN instead of being fitted. Costs +0.9% RMS.
                            % Works out to -5% peak mu over 600-1200 N. The old DERIVED
                            % -0.40981 implied -25%, also not in the data.
                            % Valid Fz 500-1300 N, extrapolated outside that.
p.tir.FNOMIN = 667;         % N, the "normal load" the numbers above refer to
p.tir.LMUX   = 0.65;        % fudge factor: test-rig belt -> real pavement
% Shape of the mu-slip curve. Same fit, same samples as PDX1/PDX2 above (all 14
% coefficients come out of one least-squares solve, so they are only meaningful as a
% SET -- do not swap one in isolation). These replace two bare guesses that used to sit
% in accel_model_tc.m (s_peak 0.12, C 1.65) and, before that, a DERIVED set read off
% dt_bismillah/"16inx18in_R20 2 1.tir" whose longitudinal shape was itself assumed.
p.tir.PCX1   =  1.17006;    % shape factor C   (was 1.5112 derived, 1.65 guessed)
p.tir.PEX1   = -0.65042;    % curvature E, and its load dependence
p.tir.PEX2   = -2.13543;
p.tir.PEX3   =  1.33525;
p.tir.PEX4   =  0.06485;    % drive/brake asymmetry, near zero in the fit
p.tir.PKX1   = 45.97254;    % longitudinal slip stiffness at nominal load
p.tir.PKX2   = 25.35124;    % HIGH, and it is the price of pinning PDX2. This term is the
                            % one that was absorbing the load sensitivity; constraining
                            % PDX2 pushes some of it back here. It is a fit artifact of a
                            % 14-parameter model on a |SL| <= 0.19 sweep, not a measured
                            % slip-stiffness property. Do not quote PKX2 on its own.
p.tir.PKX3   = -0.70540;
p.tir.PHX1   = -0.00016;    % horizontal shift
p.tir.PHX2   = -0.00020;
p.tir.PVX1   =  0.01683;    % vertical shift
p.tir.PVX2   = -0.03129;
p.tir.P_kPa  = 71.0;        % kPa, the pressure this set was fitted at. 0.71 bar =
                            % 10.3 psi, matching the team's own reference plot
                            % "FX vs SL @ 0 Camber & 10.3psi.png". Pressure terms
                            % PPX1..4 are NOT fitted, so this set is only valid near
                            % 71 kPa. Refit with tools/refit_mf_pdx2_constrained.py if
                            % the car runs a different pressure.
                            % UNCONFIRMED: the team's LATERAL reference plots are
                            % labelled 8 psi (55 kPa), not 10.3. If the car actually runs
                            % 8 psi this set is fitted at the wrong pressure. Needs a
                            % gauge reading on a hot tyre to settle.

%% ---- AERO ----
%  Drag: our aero lead's current Cd (0.922) on the frontal area CFD implies.
%  Downforce: from the FORD WIND TUNNEL

q25          = 0.5 * 1.225 * 25^2;        % dynamic pressure at 25 m/s
A_ref        = (442.719/q25) / 1.14278;   % 1.012 m^2 frontal area (from CFD)
p.CdA        = 0.922 * A_ref;             % 0.933 m^2 "drag area"
p.ClA        = p.CdA * (577.8/359.7);     % 1.499 m^2 "downforce area" (MEASURED-ish)
p.Crr        = 0.015;                     % rolling resistance. 
%% ---- WHERE THE WEIGHT SITS (all from the tilt test = MEASURED) ----
p.L_wb        = 1.543;      % m, front axle to rear axle
p.h_cg        = 0.3134;     % m, how high the center of gravity sits
p.rear_static = 0.483;      % 48.3% of the weight is on the rear. (51.7 front)
p.rear_aero   = 0.564;      % 56.4% of the downforce lands on the rear.
                            % (Ford wind tunnel. Used to be a guess. Now it isn't.)

%% ---- THE MOTOR (EMRAX 208 HV -- all DATASHEET) ----
p.R_phase     = 0.012;      % ohms of copper in each winding. Makes heat when
                            % you push current. 
p.Nm_per_Arms = 0.83;       % torque per amp. Want 100 Nm? Push ~120 A.
p.redline     = 6000;       % rpm. Above this the motor gets unhappy.
p.core_loss_a = 0.10833;    % The motor wastes power just SPINNING, even with
p.core_loss_b = 2.7778e-5;  % no load (magnets dragging through iron). ~575 W at
                            % 3000 rpm, ~1650 W at 6000. This is the other half
                            % of the loss story, and it's why revving high hurts.
p.Prpm        = [0 1000 2000 3000 4000 5000 6000];   % peak power curve: rpm...
p.Pkw         = [0   24   40   50   56   62   68];   % ...and the kW at each
p.T_flat_cap  = 150;        % Nm. Max twist, low speed. (DATASHEET spec peak.)
                            % accel_fatigue treats 150 as "the command cap" when judging
                            % tooth loads, so accel and fatigue agree on the same motor.
                            % This cap binds from 0 to ~3300 rpm (~62 kph at 4.61:1),
                            % i.e. most of a 0-75 m run, so it sets the accel number.
p.eta_inverter = 0.95;      % REAL-WORLD haircut. The datasheet 96% is the motor
                            % ALONE at its best point, on a bench. The real car
                            % also runs power through the INVERTER (a whole second
                            % box the spec ignores), plus loses a bit more to
                            % switching harmonics, windage and heat that the clean
                            % physics skips. Measured from the car's own telemetry
                            % (measured pack-to-shaft efficiency: mechanical power out
                            % = motor torque x speed, divided by electrical power in
                            % = pack voltage x pack current, energy-weighted over the
                            % motoring points): real motor+inverter eff was ~0.86 vs our
                            % idealized ~0.91 -> everything we miss is ~5%. So this
                            % turns "motor spec efficiency" into "what actually
                            % reaches the shaft." PROVISIONAL: one run, ~175 steady
                            % points; a steady-state test would tighten it.

%% ---- HALFSHAFT CV-JOINT LOSS ----
%  A CV joint loses power in proportion to the angle it works at:
%      eta_shaft = 1 - 2*kloss*sin(beta)        (two joints per shaft)
%  These lived inside drivetrain_efficiency.m; they are here now because
%  accel_model.m needs the same model to answer "what would straightening the
%  halfshafts buy us?", and two copies of a constant is how they drift apart.
p.hs_kloss        = 0.090;  % friction-geometry coefficient. (DERIVED -- and read this
                            % before you quote it.) This is BACK-FITTED to the CFR26 DT
                            % memo v4.0's own two ASSUMED points (0.99@3deg, 0.94@20deg).
                            % Check: 1-2*0.09*sin(3deg)=0.9906, 1-2*0.09*sin(20deg)=0.9384.
                            % That is a ROUND-TRIP, not a cross-check -- we fit the memo's
                            % assumptions and then "confirm" we reproduce them. There is NO
                            % independent source for this number. Published CV-joint loss
                            % figures are generally LOWER than this, so this model is
                            % probably PESSIMISTIC about the current 12deg halfshafts --
                            % which biases the repackaging case in its own favour. Worth
                            % saying out loud when we present it.
                            % What would actually settle it: a back-to-back dyno pull or a
                            % coastdown at two different halfshaft angles.
p.hs_angle_is_measured = true;   % the angle below is off CAD, not a placeholder
p.hs_angle_deg    = 12;     % static halfshaft angle, diff-to-wheel, at ride height
                            % driving STRAIGHT. MEASURED from the suspension CAD at static
                            % ride height, driving straight.
                            % Note this IS the straight-line angle: the joints work at
                            % 12 deg even with the steering dead ahead. 0 deg is not a
                            % driving condition, it is a repackaging target.
p.hs_corner_deg   = 8;      % EXTRA articulation in a loaded corner, on top of static.
p.hs_frac_straight= 0.724;  % fraction of an ENDURANCE lap spent near the static angle
                            % (memo split). Lap-weighted -- a straight-line accel run
                            % never sees the cornering term, so accel_model reports the
                            % straight-only case alongside it.

%% ---- SPINNING BITS (only matters for accel model) ----
%  Accelerating isn't just car vroom vroom (eeee for electric ig) moving forward -- you also have to spin up
%  the rotor and the wheels. That costs real time.
p.I_rotor     = 0.0256;     % kg*m^2, the motor's rotor. (DATASHEET)
p.I_driveline = 5e-4;       % gears + shafts + sprockets. Tiny. Computed from
                            % the CFR24 driveline geometry.
p.m_wheel     = 5.6;        % kg, one whole wheel+tire+rotor+hub. (from the team)
p.kFactor     = 0.60;       % GUESS. How far out the wheel's mass sits, as a
                            % fraction of tire radius. Tires are heavy at the
                            % edge, hubs are light in the middle -> ~0.6.
p.I_wheel     = p.kFactor^2 * p.m_wheel * p.r_wheel^2;   % spin inertia per wheel
p.n_wheels    = 4;          % all four spin, even the lazy front ones
p.T_F         = 1.5;        % Nm of driveline friction. (GUESS, and a small one.)

%% ---- WHAT COUNTS AS "GOOD" ----
p.eff_sweet = 0.90;         % We call >=90% REAL (motor+inverter) efficiency the
                            % "sweet spot". Was 0.95 back when we quoted motor-only
                            % efficiency; since the number now includes the inverter
                            % (see p.eta_inverter), the same good operating region
                            % sits at ~90%. The headline metric is unchanged: how
                            % much of our driving energy gets delivered while we're
                            % in it? (0.95 motor x 0.95 inverter ~ 0.90 real.)

%% ---- BATTERY (from our own HPPC cell test) ----
%  This is the cell's electrical personality: how its voltage sags under load
%  and bounces back. Two RC pairs = fast sag + slow sag. Separate tables for
%  charging vs discharging because cells aren't symmetric.
%  These 11 numbers each = SOC from 0% to 100% in 10% steps. SOC, not DOD:
%  index 1 = empty, index 11 = full. OCV_lookup proves it (2.42 V empty ->
%  4.2 V full) and every table below shares this one grid.
%
%  *** KNOWN DATA ARTIFACT -- the last entry of every R and C table is a hard 0. ***
%  A cell does not have zero resistance or zero capacitance at 100% SOC; the HPPC
%  fit just ran out of data at the top of the grid and left a 0 behind. The DATA IS
%  LEFT AS-IS on purpose (this file is the record of what the test produced), but
%  every lookup GUARDS against it: run_open_loop and the Kalman filter drop the last
%  grid point and clamp instead of interpolating into the zero. If you add a real
%  100%-SOC number from a re-run, delete the guard along with the 0.
p.rc.SOC_lookupR = linspace(0,1,11);
p.rc.OCV_lookup  = [2.42,3.17577,3.36868,3.52009,3.62396,3.74948,3.84225,3.93877,4.05245,4.0853,4.2];  % resting voltage vs charge
p.rc.Ri_d = [0.0079,0.0066,0.0065,0.0056,0.0054,0.0062,0.0062,0.0063,0.0062,0.0064,0];   % instant resistance, discharging
p.rc.Ri_c = [0.0084,0.0062,0.0061,0.0057,0.0061,0.0058,0.0056,0.0032,7.10e-03,0.0081,0]; % ...charging
p.rc.R1_d = [0.0026,0.0023,0.0028,0.0024,0.0021,0.0019,0.0019,0.002,0.0032,0.0049,0];
p.rc.R1_c = [7.94e-06,0.0019,0.0018,0.0015,0.0014,0.0013,0.0013,0.0033,0.0102,0.011,0];
p.rc.R2_d = [0.0156,0.0091,0.0126,0.0142,0.0074,0.0098,0.012,0.0117,0.015,0.01,0];
p.rc.R2_c = [0.009,0.0058,0.0066,0.0066,0.0049,0.0046,0.0047,0.005,0.003,0.004,0];
p.rc.C1_d = [625.5498,1266.2,1.376e+03,671.7873,447.4289,1456.5,1587.1,1935.5,1748,697.3229,0];
p.rc.C1_c = [629.4704,653.2170,732.6093,516.2969,1.31e+03,707.6551,411.8151,13.8447,1.46e+03,898.8253,0];
p.rc.C2_d = [2047.4,3107.3,3200.6,2650.9,3273,3599.5,3368.7,2972.5,2234.9,1.25e+03,0];
p.rc.C2_c = [700.7608,2.574e+03,2.365e+03,2.09e+03,3.42e+03,2.54e+03,2.29e+03,1.93e+03,1.33e+04,6.06e+03,0];
p.rc.Q    = p.Q_cell;

% Driver torque ceiling the VC actually requests. MEASURED from today_test.csv:
% at full throttle (apps>95, n=707) VCFRONT_torqueRequest pins to exactly 123.0 Nm
% (p50 = p95). This matches NO compile-time TC map (100/130/150), which is the
% evidence that maxTorqueNm was written to NVM. The motor can make 150; the car
% never asks for it. Re-check this on any new log before reusing it.
p.T_driver_max = 123.0;
end

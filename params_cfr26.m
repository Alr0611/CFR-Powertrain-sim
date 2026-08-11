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
p.gears_to_test = unique(round([4.0:0.1:5.2, 4.61], 2)); % everything we're trying

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
p.r_wheel = 0.221;          % m, EFFECTIVE ROLLING radius. MEASURED, TTC Round 9
                            % drive/brake runs 69/70/72/73, Hoosier 18.0x6.0-10 R20
                            % (RawData: RunData_DriveBrake_Matlab_SI_Round9.zip).
                            % Channel RE, median by vertical load:
                            %    600-800 N  -> 0.2274      800-1000 N -> 0.2270
                            %   1000-1400 N -> 0.2208
                            % Loaded radius RL (the force lever arm) runs a little
                            % smaller, 0.2152-0.2196 over the same loads. 0.221 sits in
                            % the working band; the sim uses one radius for both the
                            % force arm and the speed conversion, so this is a
                            % compromise between RE and RL, not an exact either.
                            %
                            % HISTORY, so nobody redoes this: was 0.2286 (18" OD / 2,
                            % UNLOADED). Briefly set to 0.204 from OptimumLap
                            % CFR26.OLVeh + firmware TIRE_RADIUS_M 0.2032 -- BOTH OF
                            % THOSE ARE TOO SMALL, the measured data above overrules
                            % them. The firmware constant being ~8% under measured is a
                            % real finding: it biases VCFRONT_vehicleSpeed and every
                            % slip number derived from it. Flag it to the embedded team.
                            %
                            % VALID ONLY IF the car runs the 18.0x6.0-10. Round 9 also
                            % tested Hoosier 16.0x6.0-10 and 16.0x7.5-10, which have NO
                            % drive/brake runs. Confirm the tyre with a tape measure.
p.g       = 9.81;           % If this changes we have bigger problems.
p.rho_air = 1.225;          % air density at sea level-ish.

%% ---- TIRE GRIP ----
%  MEASURED now, superseding the derived set. This block used to say Calspan never tested
%  this tire for forward grip. Not true any more: TTC Round 9 ran drive/brake sweeps on
%  the Hoosier 18.0x6.0-10 R20 (runs 69/70/72/73) and tools/refit_mf_pdx2_constrained.py
%  fits to them. 5467 samples, |SA| and |IA| under 0.5 deg, P = 71 +/- 3 kPa.
%  R^2 0.99708, RMS 85.9 N against an |Fx| p95 of ~2650 N.
%
%  *** ONLY VALID IF WE RUN THE 18.0x6.0-10. *** Round 9 also tested the 16.0x6.0-10 and
%  16.0x7.5-10 and neither has drive/brake runs, so on 16s this whole block reverts to
%  estimate. UNCONFIRMED, needs a tape across an unloaded rear tyre. See HOW_TO_USE.md,
%  the log energy balance says 0.221 can't be right.
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

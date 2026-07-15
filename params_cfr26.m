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

%% ---- DRIVETRAIN ----
p.eta_drivetrain = 0.823;   % Of the power the motor makes, ~82% reaches the ground.
                            % The other 18% becomes heat and noise in the gears,
                            % bearings, chain, diff, and halfshafts. (From our own
                            % DT efficiency memo. Assumes STRAIGHT halfshafts.)

%% ---- THE CAR ITSELF ----
p.m_car   = 294;            % kg, car + driver, on actual scales. (MEASURED)
p.r_wheel = 0.2286;         % m, wheel radius = 18" tire OD / 2.
                            % Note: this is the tire just sitting there. A loaded
                            % tire squishes ~5% smaller.
p.g       = 9.81;           % If this changes we have bigger problems.
p.rho_air = 1.225;          % air density at sea level-ish.

%% ---- TIRE GRIP ----
%  READ THIS ONE. Calspan never tested this tire for FORWARD grip -- our tire
%  was too small. So the sideways numbers are real test data, but
%  these forward-grip numbers are basically a well-dressed estimate.
%  Works out to mu ~1.37.
%  Consequence: every accel time in this sim is a RANGE.
p.tir.PDX1   = 2.1;         % grip at normal load     (GUESS, see above)
p.tir.PDX2   = -0.40981;    % how grip drops as you squash the tire harder (GUESS)
p.tir.FNOMIN = 667;         % N, the "normal load" the numbers above refer to
p.tir.LMUX   = 0.65;        % fudge factor: test-rig belt -> real pavement

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
p.T_flat_cap  = 140;        % Nm. Max twist, low speed. (Spec says 150 peak.)

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
p.eff_sweet = 0.95;         % We call >=95% motor efficiency the "sweet spot".
                            % The headline metric is: how much of our driving
                            % energy gets delivered while we're in it?

%% ---- BATTERY (from our own HPPC cell test) ----
%  This is the cell's electrical personality: how its voltage sags under load
%  and bounces back. Two RC pairs = fast sag + slow sag. Separate tables for
%  charging vs discharging because cells aren't symmetric.
%  These 11 numbers each = SOC from 0% to 100% in 10% steps.
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
end

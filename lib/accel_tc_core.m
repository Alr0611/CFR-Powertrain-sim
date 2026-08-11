function R = accel_tc_core(p, tc, tyre, G)
%ACCEL_TC_CORE  Shared plant+controller for the TC accel sim.
%   Used by accel_model_tc.m AND by the Simulink build (build_accel_tc_simulink.m),
%   so the MATLAB and Simulink versions can never drift apart.
%   R = accel_tc_core(p, tc, tyre, G)
%
%RUN: Inertia accel run with a rear-wheel state and a firmware-shaped TC.
%   Two coupled rotational states plus the vehicle:
%     vehicle : m*dv/dt      = Fx - drag - rolling
%     rear whl: Iw*dwheel/dt = T_axle - Fx*r
%   Slip is then a real state-derived quantity, and the tyre decides how much
%   force it makes at that slip. Nothing is clamped.
%
%   Integrated in TIME (not over motor speed like accel_model.m) because a
%   discrete controller has to be stepped at a fixed rate. Same physics, the
%   independent variable is just different.
    n   = 1/G;
    dt  = 1/2000;                 % plant step, 2 kHz
    tc_every = round((1/tc.rate_hz)/dt);
    Iw  = p.I_wheel * 2;          % two driven wheels lumped into one rear axle
    Im  = p.I_rotor + p.I_driveline;   % motor-side inertia
    % TWO radii, and they are genuinely different physical quantities:
    %   r      EFFECTIVE ROLLING radius. Distance per radian. Converts wheel speed to
    %          road speed and defines zero slip. p.r_wheel, roll-out measured.
    %   r_load LOADED radius. Ground to wheel centre. The tyre force acts at the contact
    %          patch, so THIS is the moment arm in the wheel torque balance.
    % r_load < r always, because a loaded tyre rolls further per rev than its squashed
    % radius suggests (the tread band is inextensible and walks over the flat spot).
    % Using r for both underestimates wheel force by r/r_load, about 5%.
    % Falls back to r if p.r_load is absent, so old param files still run.
    r      = p.r_wheel;
    r_load = r;
    if isfield(p, 'r_load'), r_load = p.r_load; end

    v = 0; x = 0; wWheel = 0; t = 0; i_term = 0; d_prev = 0; y = 0;
    v_prev = 0; a_prev = 0;
    % m/s, regularises PHYSICAL slip at standstill (see slip_phys). NOT innocent:
    % flooring the denominator at 1.0 m/s UNDERSTATES slip through the whole launch,
    % so the tyre is modelled as far grippier than it is exactly where the real car
    % spun to 7.6. Overridable so the sensitivity can be measured.
    % Default was 1.0, which is INSIDE the distorted regime. Convergence check,
    % mu_scale 1.0, 123 Nm launch:
    %     V_EPS  1.00 -> peak slip 0.06, t75 5.068, TC saves 0.000 s
    %     V_EPS  0.25 -> peak slip 0.28, t75 5.068, TC saves 0.000 s
    %     V_EPS  0.10 -> peak slip 5.45, t75 5.096, TC saves 0.482 s
    %     V_EPS  0.05 -> peak slip 6.48, t75 5.096, TC saves 0.482 s
    % 0.10 and 0.05 agree to 3 decimals, so the answer is converged at 0.10 and
    % still moving at 0.25. At 1.0 the launch spike is erased entirely and TC looks
    % worthless, which contradicts the logged car (slip 7.58 on every standing start).
    V_EPS = 0.10;
    if isfield(tyre, 'v_eps'), V_EPS = tyre.v_eps; end
    N = round(12/dt);
    T = zeros(N,1); V=T; X=T; S=T; Y=T; TD=T; TC_=T; k = 0;
    t75 = NaN; t100 = NaN; vtrap = NaN;

    while t < 12
        k = k + 1;
        rpm    = wWheel * G * 60/(2*pi);           % motor rpm from wheel speed
        % NO min(rpm, p.redline) here. That clamped the lookup but not the result, so
        % the motor kept making redline torque past redline and the car accelerated
        % through the limiter. motor_peak_torque now returns 0 above redline; see the
        % header there for why this systematically favoured short gearing.
        T_peak = motor_peak_torque(rpm, p);
        % Full throttle, but the VC never asks for more than its NVM torque ceiling.
        % MEASURED at 123 Nm on today_test.csv (see p.T_driver_max). Without this the
        % sim launches on the motor's 150 Nm, 22% more than the car ever requested.
        T_driver = T_peak;
        if isfield(p, 'T_driver_max'), T_driver = min(T_driver, p.T_driver_max); end

        % ---- traction control, stepped at its own rate ----
        if mod(k-1, tc_every) == 0
            dtc = tc_every*dt;
            slip_meas = slip_of(wWheel, r, v, tc.speed_gate);   % what the CONTROLLER sees
            if tc.enabled && v > tc.speed_gate && ~isnan(slip_meas)
                % lib_pid_util_ileak  -> i_term *= (1 - kLeak*dt)
                kLeak  = 1/(tc.ileak_ms/1000);
                i_term = (1 - kLeak*dtc) * i_term;
                % lib_pi_typeb_calc   -> x = measure - setpoint
                xe     = slip_meas - tc.target_slip;
                p_term = tc.kp * xe;
                i_term = i_term + tc.ki * xe * dtc;
                % lib_pid_util_ilim
                i_term = min(max(i_term, 0), tc.ilim);
                % d_term: the firmware's PI variant NEVER writes it (see header).
                if tc.emulate_firmware_pure_p
                    d_term = 0;
                else
                    d_term = -tc.kd * (xe - d_prev)/dtc;
                end
                d_prev = xe;
                % lib_pid_typeb_sum
                y = min(max(p_term + i_term + d_term, 0), tc.maxlim);
            else
                y = 0; i_term = 0; d_prev = 0;     % lib_pid_init on the inactive branch
            end
        end
        T_cmd = T_driver * (1 - y);                 % torque.c: torque - reduction*torque

        % ---- tyre force from PHYSICAL slip ----
        % NOTE the two slips are deliberately different quantities:
        %   slip_meas (above) is the firmware's, gated below TC_VEHICLESPEED_THRESHOLD
        %                     -- the controller is genuinely blind down there
        %   s (here)  is PHYSICAL, regularised by V_EPS so it stays finite from a
        %                     standstill. A tyre makes force at zero road speed with a
        %                     spinning wheel; only the controller's signal is undefined.
        % Using the gated one for force would deadlock the sim: no slip -> no force
        % -> no speed -> no slip.
        Fdown   = 0.5*p.rho_air*p.ClA*v^2;
        Fz_rear = p.m_car*p.g*p.rear_static + p.m_car*max(a_prev,0)*p.h_cg/p.L_wb + Fdown*p.rear_aero;
        s       = slip_phys(wWheel, r, v, V_EPS);
        % Full MF6.1 pure-longitudinal, per tyre, then both rear tyres.
        % Was: mu_pk*sin(tyre.C*atan(tyre.B*s)) with C = 1.65 / s_peak = 0.12, both
        % GUESSESTIMATE. That shape has no E term so its tail is pinned at
        % sin(C*pi/2) = 0.52 of peak, which is what made this sim bistable. The .tir
        % set keeps ~0.77 of peak at s = 0.6. See lib/tire_fx_mf.m.
        [Fx_1, mu] = tire_fx_mf(s, Fz_rear/2, p.tir);
        Fx      = 2 * Fx_1 * tyre.mu_scale;

        % ---- integrate ----
        T_axle  = T_cmd * G * p.eta_drivetrain;             % motor torque -> axle
        % Fx acts at the contact patch, so the moment arm is the LOADED radius, not the
        % effective rolling radius used for speed and slip above.
        dwheel  = (T_axle - Fx*r_load - p.T_F*G) / (Iw + Im*G^2);
        Fdrag   = 0.5*p.rho_air*p.CdA*v^2;
        Froll   = p.Crr*(p.m_car*p.g + Fdown);
        dv      = (Fx - Fdrag - Froll)/p.m_car;

        wWheel  = max(wWheel + dwheel*dt, 0);
        v_prev  = v;
        v       = max(v + dv*dt, 0);
        a_prev  = (v - v_prev)/dt;
        x       = x + v*dt;
        t       = t + dt;

        T(k)=t; V(k)=v; X(k)=x; S(k)=s; Y(k)=y; TD(k)=T_driver; TC_(k)=T_cmd;
        if isnan(t75)  && x >= 75,       t75  = t; vtrap = v; end
        if isnan(t100) && v >= 100/3.6,  t100 = t; end
        if ~isnan(t75) && t > t75 + 0.5, break; end
    end
    R.t=T(1:k); R.v=V(1:k); R.x=X(1:k); R.slip=S(1:k); R.y=Y(1:k);
    R.T_driver=TD(1:k); R.T_cmd=TC_(1:k);
    R.t75=t75; R.t100=t100; R.vtrap=vtrap;
end

function s = slip_phys(wWheel, r, v, v_eps)
%SLIP_PHYS  Physical longitudinal slip, regularised so it is finite from rest.
%   Same numerator as the firmware; the denominator is floored at v_eps so a
%   spinning wheel against a stationary car gives a large-but-finite slip
%   instead of Inf/NaN. Only affects the TYRE model, never the controller.
    s = (wWheel*r - v) / max(v, v_eps);
end

function s = slip_of(wWheel, r, v, gate)
%SLIP_OF  (v_axle - v_vehicle)/v_vehicle, the firmware's definition.
    if v <= gate
        s = NaN;
    else
        s = (wWheel*r - v)/v;
    end
end


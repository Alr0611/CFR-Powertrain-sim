function t = accel_075m(ratio, tir, p)
%ACCEL_075M  Quick traction-limited 0-75 m time (RWD point mass).
%   Fast proxy used by the gear study's trade-off sweep. For the rigorous
%   inertia-based accel model (rotor + wheel inertia), see accel_model.m.
%   tir is passed separately so the +/-15% grip band can vary LMUX.
    dt = 0.005; v = 0; x = 0; t = 0; t_max = 10; a_x = 0;
    while x < 75 && t < t_max
        rpm = v / p.r_wheel * ratio * 60/(2*pi);
        F_wheel = motor_peak_torque(rpm, p) * ratio * p.eta_drivetrain / p.r_wheel;
        F_down  = 0.5 * p.rho_air * p.ClA * v^2;
        F_drag  = 0.5 * p.rho_air * p.CdA * v^2;
        F_roll  = p.Crr * (p.m_car * p.g + F_down);
        for iter = 1:3   % converge weight transfer <-> acceleration
            Fz_rear = p.m_car*p.g*p.rear_static + p.m_car*a_x*p.h_cg/p.L_wb + F_down*p.rear_aero;
            F_drive = min(F_wheel, tire_mu_x(Fz_rear/2, tir) * Fz_rear);
            a_x = (F_drive - F_drag - F_roll) / p.m_car;
        end
        v = max(v + a_x*dt, 0); x = x + v*dt; t = t + dt;
    end
    if x < 75, t = NaN; end   % did not reach 75 m within t_max
end

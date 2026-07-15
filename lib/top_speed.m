function v_top = top_speed(ratio, p)
%TOP_SPEED  Peak-torque-envelope top speed (m/s) for a given ratio.
%   Marches speed up until drive force can no longer overcome drag+rolling.
%   Uses the peak/transient torque envelope; at these ratios the result is
%   redline-limited, not drag-limited.
    v_rpm_limit = (p.redline/ratio) * (2*pi/60) * p.r_wheel;
    v_top = 0;
    for v = 0:0.1:v_rpm_limit
        rpm = v / p.r_wheel * ratio * 60/(2*pi);
        F_avail = motor_peak_torque(rpm, p) * ratio * p.eta_drivetrain / p.r_wheel;
        F_down  = 0.5*p.rho_air*p.ClA*v^2;
        F_need  = 0.5*p.rho_air*p.CdA*v^2 + p.Crr*(p.m_car*p.g + F_down);
        if F_avail < F_need, v_top = v; return; end
        v_top = v;
    end
end

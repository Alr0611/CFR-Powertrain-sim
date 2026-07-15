function T = motor_peak_torque(rpm, p)
%MOTOR_PEAK_TORQUE  EMRAX peak-torque envelope: flat cap then power-limited.
%   Below ~50 rpm the power-curve-derived torque is singular (P->0), so the
%   flat cap is used directly; above it, torque = min(flat cap, P(rpm)/omega).
    if rpm < 50
        T = p.T_flat_cap;
        return;
    end
    P_at_rpm_kw = interp1(p.Prpm, p.Pkw, min(rpm, p.redline), 'linear', 'extrap');
    T = min(p.T_flat_cap, P_at_rpm_kw * 9549 / rpm);
end

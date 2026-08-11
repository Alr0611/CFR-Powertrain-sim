function T = motor_peak_torque(rpm, p)
%MOTOR_PEAK_TORQUE  EMRAX peak-torque envelope: flat cap, then power-limited, then ZERO.
%   Below ~50 rpm the power-curve-derived torque is singular (P->0), so the
%   flat cap is used directly; above it, torque = min(flat cap, P(rpm)/omega).
%   ABOVE REDLINE THE MOTOR MAKES NO TORQUE.
%
%   *** THE ABOVE-REDLINE BEHAVIOUR IS A BUG FIX. READ BEFORE REVERTING. ***
%   Used to be interp1(..., min(rpm, p.redline), ...). That clamps the LOOKUP but
%   not the RESULT, so past redline the motor kept making redline torque forever.
%   Callers writing min(rpm, p.redline) at the call site had the same bug.
%
%   It only bites when a sim runs past redline, which happens at high ratios and
%   not at the 4.61:1 we run. So it quietly handed free torque to exactly the
%   ratios the gear study was evaluating and biased it toward short gearing. Proof
%   it was real: at 5.20:1, redline is ~96.7 kph at the wheel and the sim trapped
%   106.2. Can't happen.
%
%   Three call sites had it: lib/accel_tc_core.m, accel_model.m (recovery_40_80)
%   and lib/accel_075m.m (feeds the gear study). Fixing it here fixes all three.
%
%   Modelling choice, not a measurement: hard cut to zero is overspeed-protection
%   behaviour. A real inverter ramps down over a band. Nothing here measures that
%   band, so the hard cut stands, it's conservative and can't invent torque.
    if rpm > p.redline
        T = 0;
        return;
    end
    if rpm < 50
        T = p.T_flat_cap;
        return;
    end
    P_at_rpm_kw = interp1(p.Prpm, p.Pkw, rpm, 'linear', 'extrap');
    T = min(p.T_flat_cap, P_at_rpm_kw * 9549 / rpm);
end

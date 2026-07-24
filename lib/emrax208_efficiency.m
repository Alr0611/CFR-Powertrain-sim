function eff = emrax208_efficiency(rpm, torque_abs, p)
%EMRAX208_EFFICIENCY  REAL-WORLD drivetrain-electrical efficiency (battery->shaft).
%   Starts from physics (copper + iron loss, every term from the EMRAX 208 HV
%   datasheet -- reproduces the ~96% peak the spec quotes), then applies the
%   real-world haircut p.eta_inverter for the inverter + switching/windage/heat
%   losses the datasheet leaves out. So this returns what ACTUALLY reaches the
%   shaft in the car (~90% typical), not the bench-best motor-only number.
%   Cross-checked against measured telemetry -- see p.eta_inverter in params.
    Irms     = torque_abs / p.Nm_per_Arms;
    P_copper = 3 * Irms.^2 * p.R_phase;
    P_core   = p.core_loss_a*rpm + p.core_loss_b*rpm.^2;
    P_mech   = torque_abs .* rpm * (2*pi/60);
    eff = P_mech ./ max(P_mech + P_copper + P_core, 1e-6);   % motor alone (physics)
    if isfield(p, 'eta_inverter')
        eff = eff * p.eta_inverter;     % + inverter & real-world losses -> real
    end
    eff = min(max(eff, 0.05), 0.97);    % clip degenerate near-zero-load points
end

function eff = emrax208_efficiency(rpm, torque_abs, p)
%EMRAX208_EFFICIENCY  Physics-based motor efficiency (no fitted parameters).
%   eff = P_mech / (P_mech + P_copper + P_core). Every term traces to the
%   EMRAX 208 HV datasheet (phase resistance, Nm/Arms) plus the anchored
%   free-run (iron) loss curve. Reproduces the datasheet ~96% peak island.
    Irms     = torque_abs / p.Nm_per_Arms;
    P_copper = 3 * Irms.^2 * p.R_phase;
    P_core   = p.core_loss_a*rpm + p.core_loss_b*rpm.^2;
    P_mech   = torque_abs .* rpm * (2*pi/60);
    eff = P_mech ./ max(P_mech + P_copper + P_core, 1e-6);
    eff = min(max(eff, 0.05), 0.985);   % clip degenerate near-zero-load points
end

function P_out = motoring_regen_power(P_in, eff)
%MOTORING_REGEN_POWER  Signed mechanical -> electrical power conversion.
%   Motoring (P_in>=0): draws MORE electrical than mechanical (divide by eff).
%   Regen   (P_in<0):  returns LESS electrical than mechanical (multiply).
    if isscalar(eff), eff = eff * ones(size(P_in)); end
    P_out = zeros(size(P_in));
    fwd = P_in >= 0;
    P_out(fwd)  = P_in(fwd)  ./ eff(fwd);
    P_out(~fwd) = P_in(~fwd) .* eff(~fwd);
end

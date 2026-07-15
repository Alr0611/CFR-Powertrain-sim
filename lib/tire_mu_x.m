function mu = tire_mu_x(Fz_per_tire, tir)
%TIRE_MU_X  Pacejka peak longitudinal friction with load sensitivity.
%   mu = LMUX*(PDX1 + PDX2*dfz), dfz = (Fz - FNOMIN)/FNOMIN. Fz in N per tire.
%   Longitudinal coefficients are DERIVED (Calspan ran no long. sweep).
    dfz = (Fz_per_tire - tir.FNOMIN) / tir.FNOMIN;
    mu  = tir.LMUX * (tir.PDX1 + tir.PDX2 * dfz);
    mu  = max(mu, 0.5);   % guard degenerate extrapolation at extreme loads
end

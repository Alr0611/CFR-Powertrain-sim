function [Fx, mu] = tire_fx_mf(kappa, Fz, tir)
%TIRE_FX_MF  MF6.1 pure-longitudinal tyre force. Replaces the guessed sin/atan shape.
%   [Fx, mu] = tire_fx_mf(kappa, Fz, tir)
%     kappa = longitudinal slip ratio (-), Fz = normal load per tyre (N)
%     Fx    = longitudinal force (N), mu = Fx/Fz
%
%   WHY THIS EXISTS. accel_model_tc.m shaped the tyre as
%       mu = mu_peak * sin(C*atan(B*s))
%   with C = 1.65 and s_peak = 0.12, both GUESSESTIMATE. That form has no E term,
%   so its high-slip tail is pinned at sin(C*pi/2) = 0.522 of peak. That single
%   number is what made the sim bistable around mu_scale 0.97: once the tyre broke
%   away it lost 48% of its grip and could not recover, while the real car spun to
%   slip 7.6 and still ran ~4.4 s. The full MF form below keeps ~0.77 of peak at
%   kappa = 0.6, which is the recovery the car actually showed.
%
%   Coefficients come from params_cfr26.m (p.tir), which reads them off the MF6.1
%   .tir. DERIVED, not MEASURED: no longitudinal sweep was run for that fit, so this
%   is a fitted SHAPE, not measured data. Peak mu carries LMUX = 0.65 already.
%
%   Pacejka, 'Tyre and Vehicle Dynamics' 3rd ed, eq 4.E9-4.E18, pure longitudinal,
%   zero camber, nominal pressure.
    Fz  = max(Fz, 1);                       % guard: no force from a lifted wheel
    Fz0 = tir.FNOMIN;
    dfz = (Fz - Fz0) / Fz0;

    Cx  = tir.PCX1;
    mux = (tir.PDX1 + tir.PDX2*dfz) * tir.LMUX;      % peak mu, load sensitive
    mux = max(mux, 0.05);
    Dx  = mux * Fz;
    Kx  = Fz * (tir.PKX1 + tir.PKX2*dfz) * exp(tir.PKX3*dfz);
    Bx  = Kx / (Cx * Dx);

    SHx = tir.PHX1 + tir.PHX2*dfz;
    kx  = kappa + SHx;
    Ex  = (tir.PEX1 + tir.PEX2*dfz + tir.PEX3*dfz.^2) .* (1 - tir.PEX4*sign(kx));
    Ex  = min(Ex, 1);                       % MF requires E <= 1 or the curve inverts
    SVx = Fz * (tir.PVX1 + tir.PVX2*dfz) * tir.LMUX;

    bxk = Bx .* kx;
    Fx  = Dx .* sin(Cx .* atan(bxk - Ex.*(bxk - atan(bxk)))) + SVx;
    mu  = Fx ./ Fz;
end

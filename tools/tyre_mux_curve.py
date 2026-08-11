#!/usr/bin/env python3
"""Longitudinal mu-slip curve from the MF6.1 .tir, evaluated at our loads.

PURPOSE. accel_model_tc.m currently shapes the tyre with s_peak = 0.12 and C = 1.65,
both tagged GUESSESTIMATE. The .tir carries a full MF6.1 longitudinal set, so we can
at least replace a bare guess with the fitted structure and see how far apart they are.

HONESTY TAG: DERIVED, not MEASURED. lib/tire_mu_x.m records that Calspan ran no
longitudinal sweep for the tyre this .tir was fit from, so PCX1/PEX*/PKX* describe an
assumed shape, not a measured one. Peak mu carries LMUX = 0.65 (belt-to-pavement),
which is why PDX1 * LMUX = 2.1 * 0.65 = 1.365 matches params_cfr26.m.
Round 9 DID run a drive/brake sweep on Hoosier 18.0x6.0-10 R20. Getting that file
replaces this whole script with measured data.

Pure longitudinal, MF6.1 (Pacejka, 'Tyre and Vehicle Dynamics', eq 4.E9-4.E18):
    dfz  = (Fz - Fz0)/Fz0
    Cx   = PCX1*LCX
    mux  = (PDX1 + PDX2*dfz)*(1 - PDX3*gamma^2)*LMUX
    Dx   = mux*Fz
    Kx   = Fz*(PKX1 + PKX2*dfz)*exp(PKX3*dfz)*LKX
    Bx   = Kx/(Cx*Dx)
    SHx  = (PHX1 + PHX2*dfz)*LHX
    kx   = kappa + SHx
    Ex   = (PEX1 + PEX2*dfz + PEX3*dfz^2)*(1 - PEX4*sign(kx))*LEX
    SVx  = Fz*(PVX1 + PVX2*dfz)*LVX*LMUX
    Fx   = Dx*sin(Cx*atan(Bx*kx - Ex*(Bx*kx - atan(Bx*kx)))) + SVx
"""
import re
import numpy as np

TIR = r"C:\Users\Aboud\Downloads\dt_bismillah\16inx18in_R20 2 1.tir"


def load_tir(path):
    c = {}
    for ln in open(path, "r", errors="ignore"):
        m = re.match(r"\s*([A-Z0-9_]+)\s*=\s*([-+0-9.eE]+)\s*$", ln)
        if m:
            c[m.group(1)] = float(m.group(2))
    return c


def fx_pure(kappa, Fz, c, gamma=0.0):
    Fz0 = c["FNOMIN"] * c.get("LFZO", 1.0)
    dfz = (Fz - Fz0) / Fz0
    Cx  = c["PCX1"] * c.get("LCX", 1.0)
    mux = (c["PDX1"] + c["PDX2"] * dfz) * (1 - c["PDX3"] * gamma**2) * c.get("LMUX", 1.0)
    Dx  = mux * Fz
    Kx  = Fz * (c["PKX1"] + c["PKX2"] * dfz) * np.exp(c["PKX3"] * dfz) * c.get("LKX", 1.0)
    Bx  = Kx / (Cx * Dx)
    SHx = (c["PHX1"] + c["PHX2"] * dfz) * c.get("LHX", 1.0)
    kx  = kappa + SHx
    Ex  = (c["PEX1"] + c["PEX2"] * dfz + c["PEX3"] * dfz**2) \
          * (1 - c["PEX4"] * np.sign(kx)) * c.get("LEX", 1.0)
    Ex  = np.minimum(Ex, 1.0)          # MF requires E <= 1
    SVx = Fz * (c["PVX1"] + c["PVX2"] * dfz) * c.get("LVX", 1.0) * c.get("LMUX", 1.0)
    bxk = Bx * kx
    return Dx * np.sin(Cx * np.arctan(bxk - Ex * (bxk - np.arctan(bxk)))) + SVx


if __name__ == "__main__":
    c = load_tir(TIR)
    print(f"FNOMIN {c['FNOMIN']:.0f} N   LMUX {c.get('LMUX')}   "
          f"PDX1*LMUX = {c['PDX1']*c.get('LMUX',1):.3f}  (params mu = 1.365)")
    print(f"PCX1 (shape C) = {c['PCX1']:.4f}   vs accel_model_tc.m guess C = 1.65\n")

    k = np.linspace(0.0, 0.60, 3001)
    print(f"{'Fz/tyre':>8} {'mu_peak':>8} {'s_peak':>7} {'mu@0.30':>8} "
          f"{'mu@0.60':>8} {'tail/peak':>9}")
    print("-" * 54)
    for Fz in (500, 667, 800, 1000, 1200, 1400):
        fx = fx_pure(k, float(Fz), c)
        mu = fx / Fz
        i = int(np.argmax(mu))
        tail = mu[-1] / mu[i]
        print(f"{Fz:8.0f} {mu[i]:8.3f} {k[i]:7.3f} "
              f"{mu[np.argmin(abs(k-0.30))]:8.3f} {mu[np.argmin(abs(k-0.60))]:8.3f} "
              f"{tail:9.3f}")

    print("\naccel_model_tc.m assumes s_peak = 0.12 and a tail falling to ~0.52 of peak.")

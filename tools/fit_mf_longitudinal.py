#!/usr/bin/env python3
"""Fit MF6.1 pure-longitudinal coefficients to MEASURED TTC Round 9 drive/brake data.

Hoosier 18.0x6.0-10 R20, runs 69/70/72/73 (tire9, tire10).
Source: dt_bismillah/TYRE STUFF/RunData_DriveBrake_Matlab_SI_Round9.zip

This replaces coefficients that were DERIVED (no longitudinal sweep existed when the
.tir was fit) with ones fitted to real slip-ratio sweeps. No scaling from 13 inch, no
borrowed shape: this is the 10 inch tyre's own data.

Deliberately NOT fitted here:
  - pressure terms PPX1..4  (fit is restricted to a narrow pressure band instead)
  - camber term PDX3        (restricted to |IA| < 0.5 deg)
  - combined-slip RBX/RCX   (pure longitudinal only)
so the fitted set is only valid near the fitted pressure and at ~zero camber.

Raw TTC force is BELT force. LMUX is NOT applied here and must not be folded in:
it stays a separate, visible belt-to-pavement factor in params_cfr26.m.
"""
import io
import zipfile

import numpy as np
import scipy.io as sio
from scipy.optimize import least_squares

ZIP = (r"C:\Users\Aboud\Downloads\dt_bismillah\TYRE STUFF"
       r"\RunData_DriveBrake_Matlab_SI_Round9.zip")
RUNS = (69, 70, 72, 73)
FNOMIN = 667.0          # N, keep consistent with params_cfr26.m


def load():
    z = zipfile.ZipFile(ZIP)
    cols = {k: [] for k in ("FX", "FZ", "SL", "SA", "IA", "P", "RE", "RL")}
    for r in RUNS:
        d = sio.loadmat(io.BytesIO(z.read(f"B2356run{r}.mat")), squeeze_me=True)
        for k in cols:
            cols[k].append(d[k])
    return {k: np.concatenate(v) for k, v in cols.items()}


def mf_fx(par, kappa, Fz):
    """MF6.1 pure longitudinal, no pressure/camber terms. Returns Fx in N."""
    PCX1, PDX1, PDX2, PEX1, PEX2, PEX3, PEX4, PKX1, PKX2, PKX3, PHX1, PHX2, PVX1, PVX2 = par
    dfz = (Fz - FNOMIN) / FNOMIN
    Cx = PCX1
    mux = PDX1 + PDX2 * dfz
    mux = np.maximum(mux, 0.05)
    Dx = mux * Fz
    Kx = Fz * (PKX1 + PKX2 * dfz) * np.exp(PKX3 * dfz)
    Bx = Kx / np.maximum(Cx * Dx, 1e-6)
    SHx = PHX1 + PHX2 * dfz
    kx = kappa + SHx
    Ex = (PEX1 + PEX2 * dfz + PEX3 * dfz**2) * (1 - PEX4 * np.sign(kx))
    Ex = np.minimum(Ex, 1.0)
    SVx = Fz * (PVX1 + PVX2 * dfz)
    bxk = Bx * kx
    return Dx * np.sin(Cx * np.arctan(bxk - Ex * (bxk - np.arctan(bxk)))) + SVx


if __name__ == "__main__":
    d = load()
    Fz = -d["FZ"]                       # TTC logs Fz negative
    m = (np.abs(d["SA"]) < 0.5) & (np.abs(d["IA"]) < 0.5) & (Fz > 150)
    m &= np.isfinite(d["FX"]) & np.isfinite(d["SL"])
    # Narrow pressure band so the omitted PPX terms cannot bias the fit.
    # 71 kPa = 0.71 bar = 10.3 psi, matching the team's own reference plot
    # "FX vs SL @ 0 Camber & 10.3psi.png". An earlier fit used the data median
    # (82.5 kPa / 12 psi), which is NOT the pressure the team works at.
    pmed = 71.0
    m &= np.abs(d["P"] - pmed) < 3.0
    kap, FzM, FxM = d["SL"][m], Fz[m], d["FX"][m]
    print(f"fitting {m.sum()} samples | P = {pmed:.1f} +/- 3 kPa "
          f"| Fz {FzM.min():.0f}-{FzM.max():.0f} N | SL {kap.min():+.3f}..{kap.max():+.3f}")

    p0 = np.array([1.5112, 2.1, -0.40981, -0.41317, -0.69452, 0.53218, 0.37979,
                   34.4429, 5.2286, -0.42253, 0.0043847, -0.0053187, -0.067304, 0.064691])
    lo = np.array([0.8,  0.5, -3.0, -10, -10, -10, -2.0,  1.0, -50, -5, -0.1, -0.1, -0.5, -0.5])
    hi = np.array([2.5,  5.0,  1.0,  1.0,  10,  10,  2.0, 200,  50,  5,  0.1,  0.1,  0.5,  0.5])

    res = least_squares(lambda q: mf_fx(q, kap, FzM) - FxM, p0, bounds=(lo, hi),
                        loss="soft_l1", f_scale=100.0, max_nfev=6000)
    q = res.x
    resid = mf_fx(q, kap, FzM) - FxM
    rms = float(np.sqrt(np.mean(resid**2)))
    ss = 1 - np.sum(resid**2) / np.sum((FxM - FxM.mean())**2)
    print(f"converged: {res.success} | RMS residual {rms:.1f} N | R^2 {ss:.4f}")
    print(f"  (for scale, |Fx| p95 = {np.percentile(np.abs(FxM),95):.0f} N)\n")

    names = ["PCX1","PDX1","PDX2","PEX1","PEX2","PEX3","PEX4",
             "PKX1","PKX2","PKX3","PHX1","PHX2","PVX1","PVX2"]
    print("MEASURED fit (raw belt, LMUX NOT applied):")
    for n, v, s in zip(names, q, p0):
        print(f"  p.tir.{n:<5s} = {v: .5f};   % was {s: .5f} (derived)")

    print(f"\n{'Fz':>6} {'mu_peak':>9} {'s_peak':>8}")
    ks = np.linspace(0.0, 0.35, 1401)
    for F in (400, 667, 800, 1000, 1200, 1400):
        mu = mf_fx(q, ks, float(F)) / F
        i = int(np.argmax(mu))
        print(f"{F:6.0f} {mu[i]:9.3f} {ks[i]:8.3f}")

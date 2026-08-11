#!/usr/bin/env python3
"""Is PDX2 identifiable from the fit, or is the optimiser free to park it anywhere?

The raw samples say peak mu falls with load. The fit says flat. One is wrong.

Method: profile it. Pin PDX2 to each value on a grid, refit the other 13 freely, record
the best residual. Sharp minimum means the data really does say flat. Flat residual means
PDX2 is unidentifiable and other coefficients are absorbing the load sensitivity.

Also refits in mu-space (residual on Fx/Fz instead of Fx). The default fit minimises
newtons, so a 1400 N sample outweighs a 500 N one 3:1, and load sensitivity lives in the
light-load samples.
"""
import io
import zipfile

import numpy as np
import scipy.io as sio
from scipy.optimize import least_squares

ZIP = (r"C:\Users\Aboud\Downloads\dt_bismillah\TYRE STUFF"
       r"\RunData_DriveBrake_Matlab_SI_Round9.zip")
RUNS = (69, 70, 72, 73)
FNOMIN = 667.0

NAMES = ["PCX1", "PDX1", "PDX2", "PEX1", "PEX2", "PEX3", "PEX4",
         "PKX1", "PKX2", "PKX3", "PHX1", "PHX2", "PVX1", "PVX2"]
P0 = np.array([1.5112, 2.1, -0.40981, -0.41317, -0.69452, 0.53218, 0.37979,
               34.4429, 5.2286, -0.42253, 0.0043847, -0.0053187, -0.067304, 0.064691])
LO = np.array([0.8, 0.5, -3.0, -10, -10, -10, -2.0, 1.0, -50, -5, -0.1, -0.1, -0.5, -0.5])
HI = np.array([2.5, 5.0, 1.0, 1.0, 10, 10, 2.0, 200, 50, 5, 0.1, 0.1, 0.5, 0.5])


def load():
    z = zipfile.ZipFile(ZIP)
    cols = {k: [] for k in ("FX", "FZ", "SL", "SA", "IA", "P")}
    for r in RUNS:
        d = sio.loadmat(io.BytesIO(z.read(f"B2356run{r}.mat")), squeeze_me=True)
        for k in cols:
            cols[k].append(d[k])
    return {k: np.concatenate(v) for k, v in cols.items()}


def mf_fx(par, kappa, Fz):
    """MF6.1 pure longitudinal, no pressure/camber terms. Identical to fit_mf_longitudinal."""
    PCX1, PDX1, PDX2, PEX1, PEX2, PEX3, PEX4, PKX1, PKX2, PKX3, PHX1, PHX2, PVX1, PVX2 = par
    dfz = (Fz - FNOMIN) / FNOMIN
    Cx = PCX1
    mux = np.maximum(PDX1 + PDX2 * dfz, 0.05)
    Dx = mux * Fz
    Kx = Fz * (PKX1 + PKX2 * dfz) * np.exp(PKX3 * dfz)
    Bx = Kx / np.maximum(Cx * Dx, 1e-6)
    SHx = PHX1 + PHX2 * dfz
    kx = kappa + SHx
    Ex = np.minimum((PEX1 + PEX2 * dfz + PEX3 * dfz**2) * (1 - PEX4 * np.sign(kx)), 1.0)
    SVx = Fz * (PVX1 + PVX2 * dfz)
    bxk = Bx * kx
    return Dx * np.sin(Cx * np.arctan(bxk - Ex * (bxk - np.arctan(bxk)))) + SVx


def fit(kap, FzM, FxM, pin=None, mu_space=False):
    """Fit; if pin is not None, PDX2 is held there and the other 13 float."""
    free = [i for i in range(14) if not (pin is not None and i == 2)]
    p0, lo, hi = P0[free].copy(), LO[free], HI[free]
    if pin is not None:
        p0 = np.clip(p0, lo + 1e-9, hi - 1e-9)

    def expand(q):
        full = np.empty(14)
        full[free] = q
        if pin is not None:
            full[2] = pin
        return full

    if mu_space:
        # Residual on mu = Fx/Fz. f_scale in mu units: 100 N at ~800 N nominal ~ 0.12.
        def resid(q):
            return (mf_fx(expand(q), kap, FzM) - FxM) / FzM
        fs = 0.12
    else:
        def resid(q):
            return mf_fx(expand(q), kap, FzM) - FxM
        fs = 100.0

    res = least_squares(resid, p0, bounds=(lo, hi), loss="soft_l1",
                        f_scale=fs, max_nfev=6000)
    full = expand(res.x)
    r_force = mf_fx(full, kap, FzM) - FxM
    rms = float(np.sqrt(np.mean(r_force**2)))
    r2 = 1 - np.sum(r_force**2) / np.sum((FxM - FxM.mean())**2)
    rms_mu = float(np.sqrt(np.mean((r_force / FzM) ** 2)))
    return full, rms, r2, rms_mu


if __name__ == "__main__":
    d = load()
    Fz = -d["FZ"]
    m = ((np.abs(d["SA"]) < 0.5) & (np.abs(d["IA"]) < 0.5) & (Fz > 150)
         & np.isfinite(d["FX"]) & np.isfinite(d["SL"]) & (np.abs(d["P"] - 71.0) < 3.0))
    kap, FzM, FxM = d["SL"][m], Fz[m], d["FX"][m]
    print(f"{m.sum()} samples | Fz {FzM.min():.0f}-{FzM.max():.0f} N\n")

    print("=== PROFILE: pin PDX2, refit the other 13, see what it costs ===")
    print(f"{'PDX2':>8} {'RMS (N)':>10} {'R^2':>9} {'RMS mu':>9} {'PDX1':>8} {'PKX2':>9} {'PEX2':>9}")
    grid = [-0.40, -0.30, -0.20, -0.15, -0.12, -0.08, -0.04, 0.0, 0.00248, 0.05]
    best = None
    for v in grid:
        full, rms, r2, rmu = fit(kap, FzM, FxM, pin=v)
        if best is None or rms < best[1]:
            best = (v, rms)
        print(f"{v:8.4f} {rms:10.1f} {r2:9.5f} {rmu:9.4f} "
              f"{full[1]:8.4f} {full[8]:9.3f} {full[9]:9.3f}")
    print(f"\n  best RMS on the grid at PDX2 = {best[0]:+.4f} ({best[1]:.1f} N)")

    print("\n=== free fits, force-space vs mu-space weighting ===")
    for label, mus in (("force-space (as shipped)", False), ("mu-space", True)):
        full, rms, r2, rmu = fit(kap, FzM, FxM, mu_space=mus)
        print(f"  {label:26s} PDX2 = {full[2]:+.5f} | RMS {rms:6.1f} N | "
              f"R^2 {r2:.5f} | RMS mu {rmu:.4f}")

    print("\n=== full coefficient set, mu-space free fit ===")
    full, rms, r2, rmu = fit(kap, FzM, FxM, mu_space=True)
    for n, v, s in zip(NAMES, full, P0):
        print(f"  p.tir.{n:<5s} = {v: .5f};   % was {s: .5f}")
    print(f"  RMS {rms:.1f} N | R^2 {r2:.5f} | RMS mu {rmu:.4f}")
    ks = np.linspace(0.0, 0.35, 1401)
    print(f"\n  {'Fz':>6} {'mu_peak':>9} {'s_peak':>8}")
    for F in (400, 600, 667, 800, 1000, 1200, 1400):
        mu = mf_fx(full, ks, float(F)) / F
        i = int(np.argmax(mu))
        print(f"  {F:6.0f} {mu[i]:9.3f} {ks[i]:8.3f}")

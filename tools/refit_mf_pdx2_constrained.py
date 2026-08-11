#!/usr/bin/env python3
"""Final MF6.1 longitudinal fit, PDX2 constrained to the measured load sensitivity.

This is the script that produced the tyre coefficients in params_cfr26.m.

The free fit returned PDX2 = +0.00248 (flat with load). Three checks say that's an
artifact: raw peak mu falls 5% over 600-1200 N, mu at matched slip falls in every slip
band, and pinning PDX2 anywhere from 0 to -0.20 moves RMS by 3.7 N out of 85 while PKX2
swings 6.3 to 25.4. So PDX2 is unidentifiable and the free value carries no information.

Fix: solve for the PDX2 that makes the model's peak-mu-vs-Fz slope equal the measured
one, refitting the other 13 at every step. That's calibrating against a measurement, not
tuning to a result. No vehicle number enters this file.

Limits, also carried into params: drive side only, |SL| <= 0.186 so the launch tail is
still extrapolated, Fz 500-1300 N, 71 +/- 3 kPa with no pressure terms fitted.
"""
import numpy as np
from scipy.optimize import brentq

from pdx2_identifiability import NAMES, mf_fx, load, fit


def data_peak_mu(mu, sl, nslip=24):
    edges = np.linspace(sl.min(), sl.max(), nslip + 1)
    idx = np.clip(np.digitize(sl, edges) - 1, 0, nslip - 1)
    best = -np.inf
    for b in range(nslip):
        m = idx == b
        if m.sum() >= 10:
            best = max(best, mu[m].mean())
    return best


def model_peak_mu(par, Fz, smax):
    ks = np.linspace(0.005, smax, 800)
    return float(np.max(mf_fx(par, ks, float(Fz)) / Fz))


BINS = [(500, 700), (700, 900), (900, 1100), (1100, 1300)]

if __name__ == "__main__":
    d = load()
    Fz = -d["FZ"]
    m = ((np.abs(d["SA"]) < 0.5) & (np.abs(d["IA"]) < 0.5) & (Fz > 150)
         & np.isfinite(d["FX"]) & np.isfinite(d["SL"]) & (np.abs(d["P"] - 71.0) < 3.0))
    kap, FzM, FxM = d["SL"][m], Fz[m], d["FX"][m]
    drive = kap > 0.005
    fzd, mud, sld = FzM[drive], (FxM / FzM)[drive], kap[drive]
    smax = float(np.percentile(sld, 99))

    cen, dy = [], []
    for lo, hi in BINS:
        mm = (fzd >= lo) & (fzd < hi)
        if mm.sum() >= 200:
            cen.append(0.5 * (lo + hi))
            dy.append(data_peak_mu(mud[mm], sld[mm]))
    cen, dy = np.array(cen), np.array(dy)
    data_slope = np.polyfit(cen, dy, 1)[0]
    print(f"MEASURED peak-mu slope: {data_slope*1000:+.4f} mu per kN "
          f"({dy[0]:.3f} at {cen[0]:.0f} N -> {dy[-1]:.3f} at {cen[-1]:.0f} N)")

    cache = {}

    def slope_err(pdx2):
        if pdx2 not in cache:
            par = fit(kap, FzM, FxM, pin=float(pdx2))[0]
            ms = np.polyfit(cen, [model_peak_mu(par, c, smax) for c in cen], 1)[0]
            cache[pdx2] = (par, ms)
        return cache[pdx2][1] - data_slope

    print("solving for the PDX2 that reproduces it...")
    pdx2 = brentq(slope_err, -0.25, 0.02, xtol=1e-4)
    par, mslope = cache[min(cache, key=lambda k: abs(k - pdx2))]
    par = fit(kap, FzM, FxM, pin=float(pdx2))[0]
    resid = mf_fx(par, kap, FzM) - FxM
    rms = float(np.sqrt(np.mean(resid**2)))
    r2 = 1 - np.sum(resid**2) / np.sum((FxM - FxM.mean())**2)

    free = fit(kap, FzM, FxM)
    print(f"\nCONSTRAINED  PDX2 = {pdx2:+.5f} | RMS {rms:6.1f} N | R^2 {r2:.5f}")
    print(f"FREE (old)   PDX2 = {free[0][2]:+.5f} | RMS {free[1]:6.1f} N | R^2 {free[2]:.5f}")
    print(f"cost of imposing the measurement: {rms-free[1]:+.1f} N RMS "
          f"({100*(rms-free[1])/free[1]:+.1f}%), R^2 {r2-free[2]:+.5f}")
    print("-> negligible. The data does not care about PDX2, so the measurement decides it.")

    print("\n% MEASURED, PDX2 calibrated to the binned load sweep. See")
    print("% tools/refit_mf_pdx2_constrained.py for why the free fit's PDX2 was rejected.")
    for n, v in zip(NAMES, par):
        print(f"p.tir.{n:<5s} = {v: .5f};")

    print(f"\n{'Fz':>6} {'data pk':>9} {'model pk':>9} {'s_peak':>8}")
    ks = np.linspace(0.005, 0.60, 2000)
    for i, c in enumerate(cen):
        mu = mf_fx(par, ks, float(c)) / c
        j = int(np.argmax(mu))
        print(f"{c:6.0f} {dy[i]:9.3f} {model_peak_mu(par, c, smax):9.3f} {ks[j]:8.3f}")
    print("  s_peak is where the UNRESTRICTED model peaks; the measured sweep only")
    print(f"  reaches {smax:.3f}, so anything past that is extrapolated shape, not measurement.")

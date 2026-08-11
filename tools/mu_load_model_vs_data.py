#!/usr/bin/env python3
"""Compare MODEL peak mu against DATA peak mu, like for like.

The -0.12 "PDX2 equivalent" from mu_vs_load_nonparametric.py isn't directly comparable to
PDX2. PDX1/PDX2 set Dx, the amplitude of the sin(C*atan(..)) term, but realised peak mu is
(Dx*sin(..) + SVx)/Fz, so C, E and SVx all move it. Comparing a data slope against the
bare coefficient is how you end up fixing the wrong one.

So TEST 1 pulls peak mu out of each candidate set the same way the data estimator does,
and compares those.

TEST 2 is cleaner: mu at MATCHED SLIP vs Fz. The sweep only reaches |SL| ~0.19 and the
fits want their peak at 0.21-0.35, so "peak mu" off the data might just be "mu at the end
of the sweep". Comparing at the same slip needs no peak-finding at all.

TEST 3 checks whether the sweep was long enough to find a real peak.
"""
import io
import zipfile

import numpy as np
import scipy.io as sio

from pdx2_identifiability import ZIP, RUNS, FNOMIN, NAMES, mf_fx, load, fit

# Candidate sets, all fitted to the same 5467 samples at 71 +/- 3 kPa.
CANDIDATES = {}


def data_peak_mu(mu, sl, nslip=24):
    edges = np.linspace(sl.min(), sl.max(), nslip + 1)
    idx = np.clip(np.digitize(sl, edges) - 1, 0, nslip - 1)
    best, at = -np.inf, np.nan
    for b in range(nslip):
        m = idx == b
        if m.sum() < 10:
            continue
        v = mu[m].mean()
        if v > best:
            best, at = v, sl[m].mean()
    return best, at


def model_peak_mu(par, Fz, smax):
    """Peak mu the same way the data estimator sees it: max over the MEASURED slip range."""
    ks = np.linspace(0.005, smax, 800)
    mu = mf_fx(par, ks, float(Fz)) / Fz
    i = int(np.argmax(mu))
    return mu[i], ks[i]


if __name__ == "__main__":
    d = load()
    Fz = -d["FZ"]
    m = ((np.abs(d["SA"]) < 0.5) & (np.abs(d["IA"]) < 0.5) & (Fz > 150)
         & np.isfinite(d["FX"]) & np.isfinite(d["SL"]) & (np.abs(d["P"] - 71.0) < 3.0))
    kap, FzM, FxM = d["SL"][m], Fz[m], d["FX"][m]

    drive = kap > 0.005
    fzd, fxd, sld = FzM[drive], FxM[drive], kap[drive]
    mud = fxd / fzd
    smax = float(np.percentile(sld, 99))
    print(f"{m.sum()} samples, {drive.sum()} on the drive side")
    print(f"measured slip range on the drive side: 0 .. {sld.max():.3f} "
          f"(p99 {smax:.3f})\n")

    print("fitting candidates (this takes a moment)...")
    CANDIDATES["shipped (free, force-space)"] = fit(kap, FzM, FxM)[0]
    CANDIDATES["free, mu-space"] = fit(kap, FzM, FxM, mu_space=True)[0]
    for v in (-0.08, -0.12, -0.20):
        CANDIDATES[f"pinned PDX2 = {v:+.2f}"] = fit(kap, FzM, FxM, pin=v)[0]

    bins = [(500, 700), (700, 900), (900, 1100), (1100, 1300)]

    print("\n=== TEST 1: peak mu vs Fz, data against each candidate ===")
    hdr = f"{'Fz bin':>12} {'DATA':>8}"
    for name in CANDIDATES:
        hdr += f" {name[:14]:>15}"
    print(hdr)
    dat, mods = [], {k: [] for k in CANDIDATES}
    for lo, hi in bins:
        mm = (fzd >= lo) & (fzd < hi)
        if mm.sum() < 200:
            continue
        c = 0.5 * (lo + hi)
        pk, _ = data_peak_mu(mud[mm], sld[mm])
        dat.append((c, pk))
        row = f"{lo:5.0f}-{hi:<6.0f} {pk:8.3f}"
        for name, par in CANDIDATES.items():
            v, _ = model_peak_mu(par, c, smax)
            mods[name].append(v)
            row += f" {v:15.3f}"
        print(row)

    cen = np.array([r[0] for r in dat])
    dy = np.array([r[1] for r in dat])
    dslope = np.polyfit(cen, dy, 1)[0] * 1000
    print(f"\n{'slope (mu per kN)':>21} {dslope:+7.3f}", end="")
    for name in CANDIDATES:
        s = np.polyfit(cen, np.array(mods[name]), 1)[0] * 1000
        print(f" {s:+15.3f}", end="")
    print("\n  (want the candidate whose slope matches DATA)")

    print("\n=== TEST 2: mu at MATCHED slip vs Fz (no peak-finding at all) ===")
    print("mean mu in each (slip, Fz) cell, straight off the samples")
    slip_bands = [(0.04, 0.07), (0.07, 0.10), (0.10, 0.14), (0.14, 0.19)]
    print(f"{'Fz bin':>12}" + "".join(f"{f'SL {a:.2f}-{b:.2f}':>14}" for a, b in slip_bands))
    tbl = {}
    for lo, hi in bins:
        row = f"{lo:5.0f}-{hi:<6.0f}"
        for a, b in slip_bands:
            mm = (fzd >= lo) & (fzd < hi) & (sld >= a) & (sld < b)
            if mm.sum() < 20:
                row += f"{'-':>14}"
                tbl[(lo, a)] = np.nan
            else:
                v = mud[mm].mean()
                row += f"{v:14.3f}"
                tbl[(lo, a)] = v
        print(row)
    print(f"{'change 600->1200':>12}", end="")
    for a, b in slip_bands:
        v0, v1 = tbl.get((500, a), np.nan), tbl.get((1100, a), np.nan)
        if np.isfinite(v0) and np.isfinite(v1):
            print(f"{100*(v1-v0)/v0:13.1f}%", end="")
        else:
            print(f"{'-':>14}", end="")
    print("\n  a consistently NEGATIVE row is load sensitivity, measured with no model.")

    print("\n=== TEST 3: is the sweep long enough to have found a real peak? ===")
    print("mean mu in the top slip bins -- if still RISING, the sweep truncated")
    top = [(0.14, 0.17), (0.17, 0.20), (0.20, 0.24)]
    print(f"{'Fz bin':>12}" + "".join(f"{f'SL {a:.2f}-{b:.2f}':>14}" for a, b in top))
    for lo, hi in bins:
        row = f"{lo:5.0f}-{hi:<6.0f}"
        for a, b in top:
            mm = (fzd >= lo) & (fzd < hi) & (sld >= a) & (sld < b)
            row += f"{mud[mm].mean():14.3f}" if mm.sum() >= 20 else f"{'-':>14}"
        print(row)

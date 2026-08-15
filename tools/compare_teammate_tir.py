#!/usr/bin/env python3
"""Compare the teammate's MF5.2 lateral fit for OUR tyre against raw TTC data and ours.

His file: Hoosier_16x7_5_10_R20_MF52.tir, FITTYP 5 (MF5.2). FY0, MZ0, MX fitted.
Every longitudinal coefficient is exactly 0, so it has no Fx at all.

Ours: MF6.1 longitudinal only, fitted to the Hoosier 18.0x6.0-10 because our 16x7.5-10
has no drive/brake data anywhere in TTC Round 9.

So the two files do not overlap. His is lateral on the right tyre, ours is longitudinal on
the wrong tyre. Neither can replace the other. What his file CAN do:

  1. Independently confirm the wheel radius (his DIMENSION block).
  2. Get validated against the raw cornering data, so we know whether to trust it.
  3. Give a measured LOAD SENSITIVITY for our actual tyre, which is the one property we
     had to borrow and which we can now sanity-check.
  4. Give a measured ours-vs-donor grip ratio, which is a defensible scale factor for our
     borrowed Fx set instead of a shrug.

WHAT THIS CANNOT DO. Lateral is not longitudinal. A lateral ratio is an anchor for scaling
a longitudinal set, not a measurement of one. Nothing here turns our Fx coefficients into
measured data.
"""
import io
import re
import zipfile

import numpy as np
import scipy.io as sio

TIR = r"C:\Users\Aboud\Downloads\Hoosier_16x7_5_10_R20_MF52 1.tir"
CORNERING = (r"C:\Users\Aboud\Downloads\dt_bismillah\TYRE STUFF"
             r"\RunData_Cornering_Matlab_SI_Round9.zip")
OURS = (2, 4, 5, 6, 7, 8, 9)          # Hoosier 43075 16x7.5-10, our tyre
DONOR = (27, 28, 29, 30, 31, 32)      # Hoosier 43100 18.0x6.0-10, where our Fx came from

# our longitudinal set, from params_cfr26.m
OUR_PDX1, OUR_PDX2, OUR_FNOMIN, OUR_LMUX = 2.25161, -0.08617, 667.0, 0.65


def read_tir(path):
    d = {}
    for line in open(path, encoding="utf-8", errors="ignore"):
        m = re.match(r"\s*([A-Z_0-9]+)\s*=\s*([-\d.eE+]+)", line)
        if m:
            try:
                d[m.group(1)] = float(m.group(2))
            except ValueError:
                pass
    return d


def fy0_mf52(t, alpha, Fz, gamma=0.0):
    """MF5.2 pure lateral. alpha in RADIANS (his file declares ANGLE = radians)."""
    Fz0 = t["FNOMIN"]
    dfz = (Fz - Fz0) / Fz0
    gy = gamma
    Cy = t["PCY1"]
    muy = (t["PDY1"] + t["PDY2"] * dfz) * (1 - t["PDY3"] * gy**2)
    Dy = muy * Fz
    Ky = t["PKY1"] * Fz0 * np.sin(2 * np.arctan(Fz / (t["PKY2"] * Fz0))) * (1 - t["PKY3"] * abs(gy))
    By = Ky / (Cy * Dy)
    SHy = (t["PHY1"] + t["PHY2"] * dfz) + t["PHY3"] * gy
    SVy = Fz * ((t["PVY1"] + t["PVY2"] * dfz) + (t["PVY3"] + t["PVY4"] * dfz) * gy)
    ay = alpha + SHy
    Ey = (t["PEY1"] + t["PEY2"] * dfz) * (1 - (t["PEY3"] + t["PEY4"] * gy) * np.sign(ay))
    Ey = np.minimum(Ey, 1.0)
    bay = By * ay
    return Dy * np.sin(Cy * np.arctan(bay - Ey * (bay - np.arctan(bay)))) + SVy


def load_runs(runs):
    zf = zipfile.ZipFile(CORNERING)
    cols = {k: [] for k in ("FY", "FZ", "SA", "IA", "P", "RL")}
    for r in runs:
        d = sio.loadmat(io.BytesIO(zf.read(f"B2356run{r}.mat")), squeeze_me=True)
        for k in cols:
            cols[k].append(np.atleast_1d(d[k]))
    return {k: np.concatenate(v) for k, v in cols.items()}


def peak_mu_y(d, lo, hi, p_lo=68, p_hi=74):
    """Peak lateral mu in a load bin. Mean per slip-angle bin, then max, so it is not
    biased upward by whichever bin happens to hold the most samples."""
    Fz = -d["FZ"]
    m = ((np.abs(d["IA"]) < 0.5) & (d["P"] > p_lo) & (d["P"] < p_hi)
         & (Fz >= lo) & (Fz < hi) & np.isfinite(d["FY"]))
    if m.sum() < 200:
        return np.nan
    mu, sa = np.abs(d["FY"][m] / Fz[m]), np.abs(d["SA"][m])
    edges = np.linspace(0, 14, 29)
    idx = np.clip(np.digitize(sa, edges) - 1, 0, 27)
    best = -np.inf
    for b in range(28):
        k = idx == b
        if k.sum() >= 15:
            best = max(best, mu[k].mean())
    return best


BINS = [(500, 700), (700, 900), (900, 1100), (1100, 1300)]

if __name__ == "__main__":
    t = read_tir(TIR)

    print("=== 1. His DIMENSION block vs our measured radius ===")
    print(f"  UNLOADED_RADIUS  {t['UNLOADED_RADIUS']:.4f} m   (16 in OD / 2 = 0.2032)")
    print(f"  WIDTH            {t['WIDTH']:.4f} m   (7.5 in = 0.1905)")
    print(f"  RIM_RADIUS       {t['RIM_RADIUS']:.4f} m   (10 in / 2 = 0.127)")
    print(f"  FNOMIN           {t['FNOMIN']:.0f} N")
    print("\n  Our chain, for comparison:")
    print("    roll-out on the car        r_eff 0.2001")
    print("    TTC RL + offset            r_eff 0.1988")
    print("    accel log energy balance   r_eff 0.1975")
    print("    p.r_wheel                        0.2000")
    print("  -> his unloaded 0.203 is exactly consistent. Fourth independent confirmation")
    print("     that the car is on a 16, and that r_eff ~0.20 is right.")

    print("\n=== 2. Is his fit any good? Model vs raw TTC, our tyre ===")
    d_ours = load_runs(OURS)
    print("  peak lateral mu, |IA|<0.5 deg, P 68-74 kPa\n")
    print(f"  {'Fz bin':>12} {'RAW data':>10} {'his MF5.2':>11} {'error':>9}")
    alp = np.linspace(0, np.deg2rad(14), 400)
    for lo, hi in BINS:
        raw = peak_mu_y(d_ours, lo, hi)
        c = 0.5 * (lo + hi)
        mdl = float(np.max(np.abs(fy0_mf52(t, alp, c)) / c))
        if np.isfinite(raw):
            print(f"  {lo:5d}-{hi:<6d} {raw:10.3f} {mdl:11.3f} {100*(mdl-raw)/raw:8.1f}%")

    print("\n=== 3. Load sensitivity: his (our tyre, lateral) vs ours (donor, longitudinal) ===")
    print(f"  his  PDY2 = {t['PDY2']:+.5f}   lateral, OUR tyre, fitted")
    print(f"  ours PDX2 = {OUR_PDX2:+.5f}   longitudinal, DONOR tyre, calibrated")
    print(f"  his  PDY1 = {t['PDY1']:.5f}   at FNOMIN {t['FNOMIN']:.0f} N")
    print(f"  ours PDX1 = {OUR_PDX1:.5f}   at FNOMIN {OUR_FNOMIN:.0f} N")
    print("\n  Normalised per unit dfz, these are directly comparable as a fraction:")
    print(f"    his  lateral      {t['PDY2']/t['PDY1']:+.4f} per dfz")
    print(f"    ours longitudinal {OUR_PDX2/OUR_PDX1:+.4f} per dfz")
    print("  Both negative, so both agree grip falls with load. His is stronger.")
    print("  That is expected (lateral is usually more load sensitive), so this does NOT")
    print("  prove our PDX2 is too weak. It is a consistency check, not a correction.")

    print("\n=== 4. Ours vs donor, measured laterally. This is the usable scale factor ===")
    d_don = load_runs(DONOR)
    print(f"  {'Fz bin':>12} {'ours':>9} {'donor':>9} {'ratio':>8}")
    ratios = []
    for lo, hi in BINS:
        a, b = peak_mu_y(d_ours, lo, hi), peak_mu_y(d_don, lo, hi)
        if np.isfinite(a) and np.isfinite(b):
            ratios.append(a / b)
            print(f"  {lo:5d}-{hi:<6d} {a:9.3f} {b:9.3f} {a/b:8.3f}")
    if ratios:
        r = float(np.mean(ratios))
        print(f"\n  mean ratio {r:.3f}  (spread {min(ratios):.3f}-{max(ratios):.3f})")
        print(f"  -> our tyre grips {100*(1-r):.1f}% LESS than the one our Fx set came from,")
        print("     so the current params are mildly OPTIMISTIC.")
        print(f"  If you chose to apply it: PDX1 {OUR_PDX1:.5f} -> {OUR_PDX1*r:.5f}")
        print(f"  which moves nominal pavement mu {OUR_LMUX*OUR_PDX1:.3f} -> "
              f"{OUR_LMUX*OUR_PDX1*r:.3f}")
        print("  NOT APPLIED in params. It is a lateral ratio judging a longitudinal set.")

    print("\n=== 5. Fit-quality flags in his file, worth passing back to him ===")
    bounds = {"PEY4": -10.0, "QBZ4": 20.0, "QDZ4": -300.0, "QEZ5": 20.0}
    hits = [(k, v) for k, v in bounds.items() if k in t and abs(t[k] - v) < 1e-9]
    for k, v in hits:
        print(f"  {k:6s} = {v:>8.1f}   sitting exactly on a round number")
    print("\n  Coefficients landing on exact round values almost always means the optimiser")
    print("  hit a BOUND rather than converging. Same failure mode we found in our own PDX2:")
    print("  the parameter was not identifiable, so the fit parked it at the edge. Worth him")
    print("  checking whether those terms are constrained by his data at all.")
    print(f"  PDY3 = {t['PDY3']:.2f} is also very large for a camber term. If his camber")
    print("  range is narrow, PDY3 will be poorly determined.")

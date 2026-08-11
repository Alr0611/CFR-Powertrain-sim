#!/usr/bin/env python3
"""Does peak mu drop with load? Answered off the raw samples, no model involved.

The MF fit returned PDX2 = +0.00248, i.e. peak mu flat with load. This bins raw TTC
drive/brake samples by Fz and reads peak mu = max(FX/FZ) straight off the measurements.

Three estimators per bin because raw max is upward-biased and the bias grows with sample
count, so a bin with 3x the samples wins 3x the lottery tickets:
  max     raw max. Don't compare across bins without comparing N too.
  p99     same idea, less tail-sensitive.
  binned  mean mu per slip bin, then max over slip bins. Averaging kills the noise
          before the max so it isn't count-biased. Believe this one.

Conditions match the fit (|SA|<0.5, |IA|<0.5, P = 71 +/- 3 kPa). All-pressure case is
printed too, to check the answer isn't an artifact of the narrow pressure window.
"""
import io
import zipfile

import numpy as np
import scipy.io as sio

ZIP = (r"C:\Users\Aboud\Downloads\dt_bismillah\TYRE STUFF"
       r"\RunData_DriveBrake_Matlab_SI_Round9.zip")
RUNS = (69, 70, 72, 73)
FNOMIN = 667.0


def load():
    z = zipfile.ZipFile(ZIP)
    cols = {k: [] for k in ("FX", "FZ", "SL", "SA", "IA", "P", "RE", "RL")}
    for r in RUNS:
        d = sio.loadmat(io.BytesIO(z.read(f"B2356run{r}.mat")), squeeze_me=True)
        for k in cols:
            cols[k].append(d[k])
    return {k: np.concatenate(v) for k, v in cols.items()}


def peak_mu(mu, sl, nslip=24):
    """Slip-binned peak mu: mean within each slip bin, then max over bins.

    Bins with fewer than 10 samples are dropped -- their mean is still noisy enough to
    win the max on luck alone, which is the exact bias this estimator exists to avoid.
    """
    edges = np.linspace(sl.min(), sl.max(), nslip + 1)
    idx = np.clip(np.digitize(sl, edges) - 1, 0, nslip - 1)
    best = -np.inf
    at = np.nan
    for b in range(nslip):
        m = idx == b
        if m.sum() < 10:
            continue
        v = mu[m].mean()
        if v > best:
            best, at = v, sl[m].mean()
    return best, at


def report(d, mask, label):
    Fz = -d["FZ"]
    fz, fx, sl = Fz[mask], d["FX"][mask], d["SL"][mask]
    # Drive side only. Braking gives negative FX; mixing signs makes max(FX/FZ)
    # meaningless. The drive/brake asymmetry term PEX4 fitted near zero anyway.
    drive = sl > 0.005
    fz, fx, sl = fz[drive], fx[drive], sl[drive]
    mu = fx / fz

    print(f"\n=== {label} ===")
    print(f"{'Fz bin (N)':>14} {'N':>7} {'max':>8} {'p99':>8} {'binned':>8} {'@slip':>7}")
    edges = [300, 500, 700, 900, 1100, 1300, 1600]
    rows = []
    for lo, hi in zip(edges[:-1], edges[1:]):
        m = (fz >= lo) & (fz < hi)
        n = int(m.sum())
        if n < 200:
            print(f"{lo:6.0f}-{hi:<7.0f} {n:>7d}    too few samples, skipped")
            continue
        pk, at = peak_mu(mu[m], sl[m])
        print(f"{lo:6.0f}-{hi:<7.0f} {n:>7d} {mu[m].max():8.3f} "
              f"{np.percentile(mu[m], 99):8.3f} {pk:8.3f} {at:7.3f}")
        rows.append((0.5 * (lo + hi), pk, n))

    if len(rows) >= 3:
        c = np.array([r[0] for r in rows])
        y = np.array([r[1] for r in rows])
        # Straight line through the binned peaks, then expressed the way MF does it:
        # mu = PDX1 + PDX2*dfz with dfz = (Fz-FNOMIN)/FNOMIN. So d(mu)/d(dfz) = slope*FNOMIN.
        slope = np.polyfit(c, y, 1)[0]
        pdx2_equiv = slope * FNOMIN
        mu_at_nom = np.polyval(np.polyfit(c, y, 1), FNOMIN)
        print(f"\n  linear trend over binned peaks: {slope*1000:+.4f} mu per kN")
        print(f"  -> non-parametric PDX2 equivalent = {pdx2_equiv:+.4f}")
        print(f"  -> non-parametric PDX1 equivalent = {mu_at_nom:.4f} (mu at Fz = {FNOMIN:.0f} N)")
        drop = 100 * (y[-1] - y[0]) / y[0]
        print(f"  -> peak mu {y[0]:.3f} at {c[0]:.0f} N -> {y[-1]:.3f} at {c[-1]:.0f} N "
              f"({drop:+.1f}%)")


if __name__ == "__main__":
    d = load()
    Fz = -d["FZ"]
    base = ((np.abs(d["SA"]) < 0.5) & (np.abs(d["IA"]) < 0.5) & (Fz > 150)
            & np.isfinite(d["FX"]) & np.isfinite(d["SL"]))

    report(d, base & (np.abs(d["P"] - 71.0) < 3.0), "P = 71 +/- 3 kPa (the fitted band)")
    report(d, base, "all pressures (artifact check)")

    # Pressure is a confounder: if the low-Fz samples sit at a different pressure than
    # the high-Fz ones, a load trend and a pressure trend are indistinguishable.
    print("\n=== confound check: pressure distribution within each Fz bin ===")
    fz, P = Fz[base], d["P"][base]
    print(f"{'Fz bin (N)':>14} {'N':>8} {'P median':>10} {'P p10':>8} {'P p90':>8}")
    for lo, hi in zip([300, 500, 700, 900, 1100, 1300], [500, 700, 900, 1100, 1300, 1600]):
        m = (fz >= lo) & (fz < hi)
        if m.sum() < 200:
            continue
        print(f"{lo:6.0f}-{hi:<7.0f} {int(m.sum()):>8d} {np.median(P[m]):10.1f} "
              f"{np.percentile(P[m],10):8.1f} {np.percentile(P[m],90):8.1f}")

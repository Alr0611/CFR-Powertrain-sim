#!/usr/bin/env python3
"""Cross-check our actual tyre (Hoosier 16x7.5-10) against the donor the Fx fit came from.

Confirmed from the TTC 'tireid' field in every run file:
  OUR TYRE   Hoosier 43075 16x7.5-10 R20   cornering runs 2,4,5,6 (7in rim), 7,8,9 (8in)
                                           drive/brake runs: NONE
  DONOR      Hoosier 43100 18.0x6.0-10 R20 cornering runs 27-32
                                           drive/brake runs 68-73  <- the Fx fit uses these

So there is genuinely no longitudinal data for the tyre we run, and the MF Fx set in
params_cfr26.m is borrowed off a narrower, larger-diameter casing (6.0 in wide vs our
7.5, 18 in OD vs our 16).

Both tyres DO have cornering data though, at the same facility in the same round. That
gives two things this script measures:

  1. RADIUS. RE/RL straight off our own tyre, as an independent check on the roll-out
     that set p.r_wheel = 0.200.
  2. A GRIP RATIO. Peak lateral mu of our tyre against the donor's, at matched load,
     pressure and camber. If the two casings differ in grip by X%, that is a measured,
     defensible scale factor for the borrowed longitudinal set, instead of pretending
     the transfer is free.

WHAT THIS DOES NOT DO. Lateral and longitudinal grip are not the same thing and a
lateral ratio is not proof of a longitudinal one. This is a better-than-nothing anchor
and it should be quoted as exactly that. It does not turn the Fx set into measured data.
"""
import io
import zipfile

import numpy as np
import scipy.io as sio

BASE = r"C:\Users\Aboud\Downloads\dt_bismillah\TYRE STUFF"
CORNERING = rf"{BASE}\RunData_Cornering_Matlab_SI_Round9.zip"

OURS = {"16x7.5-10, 7in rim": (2, 4, 5, 6), "16x7.5-10, 8in rim": (7, 8, 9)}
DONOR = {"18.0x6.0-10, 6in rim": (27, 28, 29), "18.0x6.0-10, 7in rim": (30, 31, 32)}


def load(runs):
    zf = zipfile.ZipFile(CORNERING)
    cols = {k: [] for k in ("FY", "FZ", "SA", "IA", "P", "RE", "RL")}
    for r in runs:
        d = sio.loadmat(io.BytesIO(zf.read(f"B2356run{r}.mat")), squeeze_me=True)
        for k in cols:
            cols[k].append(np.atleast_1d(d[k]))
    return {k: np.concatenate(v) for k, v in cols.items()}


def peak_mu_y(d, fz_lo, fz_hi, p_lo=68, p_hi=74):
    """Peak lateral mu in a load bin: bin by slip angle, mean per bin, then max.

    Mean-then-max rather than raw max, so the estimate is not biased upward by whichever
    bin happens to hold the most samples. Same estimator used for the longitudinal work.
    """
    Fz = -d["FZ"]
    m = ((np.abs(d["IA"]) < 0.5) & (d["P"] > p_lo) & (d["P"] < p_hi)
         & (Fz >= fz_lo) & (Fz < fz_hi) & np.isfinite(d["FY"]))
    if m.sum() < 200:
        return np.nan, int(m.sum())
    mu = np.abs(d["FY"][m] / Fz[m])
    sa = np.abs(d["SA"][m])
    edges = np.linspace(0, 14, 29)
    idx = np.clip(np.digitize(sa, edges) - 1, 0, 27)
    best = -np.inf
    for b in range(28):
        k = idx == b
        if k.sum() >= 15:
            best = max(best, mu[k].mean())
    return best, int(m.sum())


if __name__ == "__main__":
    print("=== 1. RADIUS, straight off our own tyre's TTC runs ===")
    print("TTC logs RL (loaded radius) and RE (effective rolling radius) in cm.")
    print("RL is the one to trust here. On OUR tyre's runs the RE channel is garbage")
    print("(p5 -417227, p95 +403790) because the rig's RE derivation goes singular at")
    print("low speed and zero slip. On the donor's runs RE is clean. So RL is used for")
    print("both, and RE is shown only where it survives a sanity filter.\n")
    print(f"{'tyre':>24} {'Fz N':>12} {'n':>7} {'RL (m)':>9} {'RE (m)':>9}")
    rl_store = {}
    for label, runs in {**OURS, **DONOR}.items():
        d = load(runs)
        Fz = -d["FZ"]
        for lo, hi in ((600, 900), (900, 1200)):
            m = ((Fz >= lo) & (Fz < hi) & (np.abs(d["IA"]) < 0.5)
                 & (d["P"] > 68) & (d["P"] < 74))
            if m.sum() < 100:
                continue
            rl = np.median(d["RL"][m]) / 100
            sane = m & (d["RE"] > 5) & (d["RE"] < 40)
            re = np.median(d["RE"][sane]) / 100 if sane.sum() > 100 else np.nan
            rl_store.setdefault(label, []).append((rl, re))
            print(f"{label:>24} {lo:5d}-{hi:<6d} {int(m.sum()):>7d} {rl:9.4f} "
                  + (f"{re:9.4f}" if np.isfinite(re) else f"{'corrupt':>9}"))

    # RE - RL offset measured on the donor, where both channels are clean, then applied
    # to our tyre's RL to estimate its effective rolling radius.
    off = [re - rl for lab, v in rl_store.items() if lab in DONOR
           for rl, re in v if np.isfinite(re)]
    ours_rl = [rl for lab, v in rl_store.items() if lab in OURS for rl, re in v]
    if off and ours_rl:
        o = float(np.mean(off))
        est = float(np.mean(ours_rl)) + o
        print(f"\n  donor RE - RL offset (both channels clean there): {o*1000:+.1f} mm")
        print(f"  our tyre mean RL {np.mean(ours_rl):.4f} + that offset -> "
              f"r_eff ~ {est:.4f} m")
    print("\n  Independent estimates of our effective rolling radius:")
    print("    roll-out on the car, 2 revs = 99 in      0.2001   <- sets p.r_wheel")
    print("    log energy balance at eta 0.794          0.1975")
    print("    TTC RL for our tyre + donor RE-RL offset  see above")
    print("  Note the TTC rows are at 68-74 kPa on a fresh tyre; the car's is worn.")

    print("\n=== 2. PEAK LATERAL MU, ours vs the donor, matched conditions ===")
    print("|IA| < 0.5 deg, P = 68-74 kPa (our ~10 psi), mean-per-slip-angle then max.\n")
    print(f"{'tyre':>24} {'Fz 500-700':>12} {'700-900':>10} {'900-1100':>10} {'1100-1300':>11}")
    bins = [(500, 700), (700, 900), (900, 1100), (1100, 1300)]
    res = {}
    for label, runs in {**OURS, **DONOR}.items():
        d = load(runs)
        row, vals = f"{label:>24}", []
        for lo, hi in bins:
            v, n = peak_mu_y(d, lo, hi)
            vals.append(v)
            row += f"{v:10.3f}   " if np.isfinite(v) else f"{'-':>10}   "
        res[label] = np.array(vals)
        print(row)

    print("\n=== 3. THE GRIP RATIO (ours / donor), per load bin ===")
    print("This is the number that would scale the borrowed longitudinal set.\n")
    print(f"{'ours':>22} {'vs donor':>24} " + "".join(f"{f'{a}-{b}':>11}" for a, b in bins)
          + f"{'mean':>9}")
    for o in OURS:
        for dn in DONOR:
            r = res[o] / res[dn]
            ok = np.isfinite(r)
            print(f"{o.split(',')[1].strip():>22} {dn.split(',')[1].strip():>24} "
                  + "".join(f"{x:11.3f}" if np.isfinite(x) else f"{'-':>11}" for x in r)
                  + f"{np.nanmean(r):9.3f}")

    print("\n  > 1.0 means our tyre grips MORE than the one the Fx set came from, so the")
    print("  current params UNDERSTATE our grip. < 1.0 means the opposite.")
    print("\n  CAVEAT, say this out loud when quoting it: this is a LATERAL ratio being")
    print("  used to judge a LONGITUDINAL set. Same compound and construction family, so")
    print("  it is a reasonable anchor, but it is not a measurement of longitudinal grip")
    print("  and it does not make the Fx coefficients measured data for our tyre.")

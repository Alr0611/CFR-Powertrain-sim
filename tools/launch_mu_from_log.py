#!/usr/bin/env python3
"""Effective grip on the test day, DERIVED from the logged launches. Not picked.

WHY. In the sim TC never engages: peak slip 1.39, peak reduction y = 0.00 at every gain.
The real car spun to 7.58 on every standing start. The model's tyre hooks up when the
real one did not. Prime suspect is grip level, since the tyre model is clean Calspan belt
data and the test was a hot, dirty parking lot with debris.

That is a real effect but it must not be invented. This derives it from the car's own
acceleration and nothing else.

METHOD, and the two traps avoided:
  - vehicle speed from the UNDRIVEN FRONT wheels, never from motor speed. The rears are
    slipping, that is the whole point.
  - acceleration by fitting a local straight line to v(t) over a window, not by
    np.gradient on raw 10 Hz quantised data. Differentiating this log directly gives
    a_max = 1.10 g, which is noise, and it is a mistake that has already been made once.

mu_eff = (m*a + drag + rolling) / Fz_rear, with Fz_rear carrying the load transfer at
that same a. This is a LOWER BOUND: it only equals available grip in the instants the
car is actually traction limited. Where TC was cutting torque the car was torque limited
and this understates grip.
"""
import numpy as np
import pandas as pd

CSV = r"C:\Users\Aboud\Downloads\today_test.csv"
RUN_STARTS = (15554, 15741, 15914, 16151)

R_WHEEL = 0.200          # p.r_wheel, roll-out measured
M, G_ACC = 294.0, 9.81
CDA, CLA, RHO, CRR = 0.933, 1.499, 1.225, 0.015
REAR_STATIC, REAR_AERO, H_CG, L_WB = 0.483, 0.564, 0.3134, 1.543
# model grip at nominal load, for the ratio at the end
LMUX, PDX1, PDX2, FNOMIN = 0.65, 2.25161, -0.08617, 667.0


def slope(t, v, i, half=0.25):
    """Local least-squares slope of v(t) in a +/-half second window. Robust to 10 Hz."""
    m = (t >= t[i] - half) & (t <= t[i] + half)
    if m.sum() < 4:
        return np.nan
    return float(np.polyfit(t[m], v[m], 1)[0])


def model_mu(Fz_per_tyre):
    return LMUX * (PDX1 + PDX2 * (Fz_per_tyre - FNOMIN) / FNOMIN)


if __name__ == "__main__":
    d = pd.read_csv(CSV)
    d["wF"] = 0.5 * (d["VCFRONT_wheelSpeedFL"] + d["VCFRONT_wheelSpeedFR"])
    d["wR"] = 0.5 * (d["VCREAR_wheelSpeedRL"] + d["VCREAR_wheelSpeedRR"])

    print(f"r_wheel = {R_WHEEL} m, front wheels for vehicle speed, "
          "local line fit for acceleration\n")
    print(f"{'run':>8} {'a_peak':>8} {'g':>6} {'mu_eff':>8} {'model mu':>9} "
          f"{'ratio':>7} {'slip@peak':>10}")
    ratios, mus = [], []
    for t0 in RUN_STARTS:
        seg = d[(d["t_s"] >= t0 - 5) & (d["t_s"] <= t0 + 25)]
        t = seg["t_s"].to_numpy()
        v = seg["wF"].to_numpy() * 2 * np.pi / 60 * R_WHEEL
        vr = seg["wR"].to_numpy() * 2 * np.pi / 60 * R_WHEEL
        if v.max() < 20:
            continue
        i0 = int(np.argmax(v > 0.5))
        t, v, vr = t[i0:] - t[i0], v[i0:], vr[i0:]

        # launch window only, and only while genuinely accelerating
        best = None
        for i in range(len(t)):
            if not (0.2 <= t[i] <= 2.0) or v[i] < 1.0:
                continue
            a = slope(t, v, i)
            if not np.isfinite(a) or a <= 0:
                continue
            Fdown = 0.5 * RHO * CLA * v[i] ** 2
            Fz_rear = M * G_ACC * REAR_STATIC + M * a * H_CG / L_WB + Fdown * REAR_AERO
            Fx = M * a + 0.5 * RHO * CDA * v[i] ** 2 + CRR * (M * G_ACC + Fdown)
            mu = Fx / Fz_rear
            if best is None or mu > best[1]:
                best = (a, mu, Fz_rear, vr[i] / max(v[i], 0.1) - 1)
        if best is None:
            continue
        a, mu, Fzr, sl = best
        mm = model_mu(Fzr / 2)
        ratios.append(mu / mm)
        mus.append(mu)
        print(f"{t0:>8} {a:8.2f} {a/G_ACC:6.2f} {mu:8.3f} {mm:9.3f} "
              f"{mu/mm:7.3f} {sl:10.2f}")

    print(f"\n  measured effective mu, mean of runs: {np.mean(mus):.3f}")
    print(f"  model mu at the same load          : {np.mean(mus)/np.mean(ratios):.3f}")
    print(f"  -> mu_scale = {np.mean(ratios):.3f}  (spread "
          f"{min(ratios):.3f}-{max(ratios):.3f})")
    print("\n  This is the DERIVED grip haircut for that surface, on that day, on those")
    print("  tyres. It is a lower bound: where TC was cutting, the car was torque limited")
    print("  and the real available grip was higher than this.")
    print("\n  Feed it in as tyre.mu_scale in accel_model_tc / sweep_accel_tc_sim.")
    print("  Do NOT bake it into params_cfr26.m as a tyre property. It is a surface")
    print("  condition for one test session, not a property of the tyre.")

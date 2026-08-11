#!/usr/bin/env python3
"""The radius-free test: MOTOR RPM vs TIME from launch, sim against log.

Every other comparison of the 0-75 m gap runs through p.r_wheel, which is the one number
still in dispute. This one does not, on the measurement side: PM100DX_motorSpeed is a
direct inverter reading and 'time since launch' is a clock. Neither involves a radius.

So if the sim's motor rpm climbs more slowly than the logged motor rpm, there is a real
force deficit in the model, and no amount of arguing about the tyre size makes it go away.
(The radius still enters the MODEL, through reflected inertia and road load, so this tests
the model as configured -- but the yardstick it is measured against is radius-free.)

Three sim variants are compared so the size of each candidate lever is visible:
  base    as shipped: eta 0.794, driver torque capped at 123 Nm
  eta088  eta raised to 0.88, the top of any defensible range
  T150    torque cap lifted to the motor's 150 Nm datasheet peak
"""
import numpy as np
import pandas as pd

CSV = r"C:\Users\Aboud\Downloads\today_test.csv"
SCRATCH = (r"C:\Users\Aboud\AppData\Local\Temp\scratch\c--Users-Aboud-Downloads"
           r"\30ada796-de09-4c1f-8abd-23e713218785\scratchpad")
RUN_STARTS = (15554, 15741, 15914, 16151)
GRID = np.arange(0.0, 5.01, 0.25)


def logged_runs():
    d = pd.read_csv(CSV)
    out = []
    for t0 in RUN_STARTS:
        seg = d[(d["t_s"] >= t0 - 5) & (d["t_s"] <= t0 + 25)]
        t = seg["t_s"].to_numpy()
        rpm = seg["PM100DX_motorSpeed"].to_numpy()
        if rpm.max() < 4000:
            continue
        # Launch = last sample at rest before rpm takes off, so t=0 means the same
        # instant in every run and in the sim.
        i0 = int(np.argmax(rpm > 100))
        while i0 > 0 and rpm[i0 - 1] > 20:
            i0 -= 1
        out.append((t0, t[i0:] - t[i0], rpm[i0:]))
    return out


if __name__ == "__main__":
    runs = logged_runs()
    print(f"{len(runs)} standing starts found\n")

    print("=== MOTOR RPM vs TIME SINCE LAUNCH (no radius anywhere in the measurement) ===")
    hdr = f"{'t (s)':>7}" + "".join(f"{f'run{t0}':>10}" for t0, _, _ in runs) + f"{'LOG mean':>11}"
    sims = {}
    for name in ("base", "eta088", "T150"):
        s = pd.read_csv(f"{SCRATCH}\\sim_{name}.csv")
        sims[name] = np.interp(GRID, s["t"], s["rpm"])
        hdr += f"{name:>10}"
    print(hdr)

    logmat = np.full((len(runs), len(GRID)), np.nan)
    for i, (t0, t, rpm) in enumerate(runs):
        logmat[i] = np.interp(GRID, t, rpm, right=np.nan)
    logmean = np.nanmean(logmat, axis=0)

    for j, g in enumerate(GRID):
        row = f"{g:7.2f}"
        for i in range(len(runs)):
            row += f"{logmat[i, j]:10.0f}"
        row += f"{logmean[j]:11.0f}"
        for name in sims:
            row += f"{sims[name][j]:10.0f}"
        print(row)

    print("\n=== sim deficit against the logged mean, in rpm and in %% ===")
    print(f"{'t (s)':>7}" + "".join(f"{n:>18}" for n in sims))
    for j, g in enumerate(GRID):
        if g < 0.5 or not np.isfinite(logmean[j]):
            continue
        row = f"{g:7.2f}"
        for name in sims:
            d_ = sims[name][j] - logmean[j]
            row += f"{d_:11.0f} ({100*d_/logmean[j]:+5.1f}%)"
        print(row)

    print("\n=== average rpm deficit over 1.0-4.0 s ===")
    w = (GRID >= 1.0) & (GRID <= 4.0) & np.isfinite(logmean)
    for name in sims:
        d_ = 100 * (sims[name][w] - logmean[w]) / logmean[w]
        print(f"  {name:8s} {d_.mean():+6.1f}%")
    print("\nA rpm deficit is a FORCE deficit: at matched speed the same road load applies,")
    print("so falling behind in rpm means the model is not making the tractive force the")
    print("car made. This is the 0-75 m gap seen without the radius in the way.")

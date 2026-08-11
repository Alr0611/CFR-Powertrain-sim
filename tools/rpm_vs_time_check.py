#!/usr/bin/env python3
"""Sim vs log speed against time since launch.

*** READ THIS FIRST, IT IS THE POINT OF THE FILE. ***
Comparing MOTOR rpm to MOTOR rpm looks radius-free and tempting, and it is WRONG. Logged
motor rpm carries the rear wheelspin, which runs 3-6% through this window and 12-22% at
1.0 s. The sim barely spins. A motor-to-motor comparison therefore charges the sim for
slip it never had and reports a ~14% deficit when the real one is ~8.7%.

The right comparison is WHEEL to WHEEL: sim wheel speed against the UNDRIVEN FRONT
wheels. Both columns are printed so the size of the mistake stays visible.

If the sim's wheel speed climbs more slowly than the front wheels, the model is short on
force as configured. The radius still enters the MODEL through reflected inertia and road
load, so this tests the model at whatever p.r_wheel is set to.

Three sim variants, so the size of each candidate lever is visible:
  base    as shipped: eta 0.794, driver torque capped at 123 Nm
  eta088  eta raised to 0.88, the top of any defensible range
  T150    torque cap lifted to the motor's 150 Nm datasheet peak

FIRST run tools/dump_sim_traces.m in MATLAB to write the three sim traces into output/.
"""
import os
import sys

import numpy as np
import pandas as pd

CSV = r"C:\Users\Aboud\Downloads\today_test.csv"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "output")
RUN_STARTS = (15554, 15741, 15914, 16151)
GRID = np.arange(1.0, 4.51, 0.5)
G_RATIO = 4.6154


def logged_runs():
    d = pd.read_csv(CSV)
    d["wF"] = 0.5 * (d["VCFRONT_wheelSpeedFL"] + d["VCFRONT_wheelSpeedFR"])
    out = []
    for t0 in RUN_STARTS:
        seg = d[(d["t_s"] >= t0 - 5) & (d["t_s"] <= t0 + 25)]
        rpm = seg["PM100DX_motorSpeed"].to_numpy()
        if rpm.max() < 4000:
            continue
        # Launch = last sample at rest before rpm takes off, so t=0 is the same instant
        # in every run and in the sim.
        i0 = int(np.argmax(rpm > 100))
        while i0 > 0 and rpm[i0 - 1] > 20:
            i0 -= 1
        t = seg["t_s"].to_numpy()[i0:] - seg["t_s"].to_numpy()[i0]
        out.append((t0, t, rpm[i0:], seg["wF"].to_numpy()[i0:]))
    return out


if __name__ == "__main__":
    runs = logged_runs()
    if not runs:
        sys.exit("no standing starts found")
    logM = np.nanmean([np.interp(GRID, t, m) for _, t, m, _ in runs], axis=0)
    logF = np.nanmean([np.interp(GRID, t, f) for _, t, _, f in runs], axis=0)

    sims = {}
    for name in ("base", "eta088", "T150"):
        p = os.path.join(OUT, f"sim_{name}.csv")
        if not os.path.isfile(p):
            sys.exit(f"missing {p}\nrun tools/dump_sim_traces.m in MATLAB first")
        sims[name] = pd.read_csv(p)
    r_wheel = float(sims["base"].attrs.get("r", 0)) or None

    print(f"{len(runs)} standing starts\n")
    print("=== rear wheelspin in the log, which is why motor-to-motor is wrong ===")
    print(f"{'t':>6} {'motor/G':>9} {'front':>9} {'slip':>8}")
    for i, g in enumerate(GRID):
        print(f"{g:6.1f} {logM[i]/G_RATIO:9.1f} {logF[i]:9.1f} "
              f"{logM[i]/G_RATIO/logF[i]-1:+8.1%}")

    print("\n=== WHEEL vs WHEEL (correct) and MOTOR vs MOTOR (inflated) ===")
    print("deficit = sim below log. Negative means the model is short on force.")
    hdr = f"{'t':>6}"
    for n in sims:
        hdr += f"{n+' whl':>12}{n+' mot':>12}"
    print(hdr)
    avg = {n: ([], []) for n in sims}
    for i, g in enumerate(GRID):
        row = f"{g:6.1f}"
        for n, s in sims.items():
            simW = np.interp(g, s["t"], s["wheel_rpm"])
            simM = np.interp(g, s["t"], s["rpm"])
            dw = 100 * (simW - logF[i]) / logF[i]
            dm = 100 * (simM - logM[i]) / logM[i]
            avg[n][0].append(dw)
            avg[n][1].append(dm)
            row += f"{dw:11.1f}%{dm:11.1f}%"
        print(row)

    print(f"\n=== average over {GRID[0]:.1f}-{GRID[-1]:.1f} s ===")
    print(f"{'variant':>10} {'wheel (real)':>14} {'motor (inflated)':>18}")
    for n in sims:
        print(f"{n:>10} {np.mean(avg[n][0]):13.1f}% {np.mean(avg[n][1]):17.1f}%")
    print("\nThe wheel column is the one to quote. The motor column is kept only to show")
    print("how much rear wheelspin inflates it.")

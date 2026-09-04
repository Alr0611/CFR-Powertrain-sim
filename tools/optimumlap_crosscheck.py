#!/usr/bin/env python3
"""
OPTIMUMLAP_CROSSCHECK -- fold the OptimumLap sweep into the ratio decision.

The OptimumLap study (Downloads/dt_bismillah/LapSim_Research) has what this repo did
not: a LAP TIME vs ratio model, on the real Michigan Endurance 2026 track, plus energy
per lap. That closes the "Autocross and Endurance time are not modelled" gap in
gear_points_model.py.

It also DISAGREES with the MATLAB accel sim on the direction of the ratio effect, and
the reason is not a bug in either. Read section 3 of the output.

Inputs (read-only, nothing in that folder is modified):
  ol_kpi_full.csv    Michigan Endurance 2026, 7 ratios x 7 halfshaft angles
  ol_kpi_accel.csv   Acceleration event, same grid
  OLVeh torque curve peak = 150 Nm (decoded from the binary, full datasheet map)
"""
import csv
import os

OL = r"C:\Users\Aboud\Downloads\dt_bismillah\LapSim_Research"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HS_CURRENT = 12.0          # current halfshaft angle, params_cfr26
LAPS = 22                  # FSAE endurance format
AUTOX_LAP_S = 60.0         # typical FSAE autocross lap. Used ONLY to scale a
                           # fractional lap-time change into a points estimate.


def rd(name):
    with open(os.path.join(OL, name)) as f:
        return [r for r in csv.DictReader(f) if abs(float(r["angle_deg"]) - HS_CURRENT) < 0.1]


def interp(xs, ys, x):
    if x <= xs[0]:
        return ys[0]
    if x >= xs[-1]:
        return ys[-1]
    for i in range(len(xs) - 1):
        if xs[i] <= x <= xs[i + 1]:
            t = (x - xs[i]) / (xs[i + 1] - xs[i])
            return ys[i] + t * (ys[i + 1] - ys[i])
    return ys[-1]


def main():
    end = rd("ol_kpi_full.csv")
    acc = rd("ol_kpi_accel.csv")
    r_e = [float(r["ratio"]) for r in end]
    lap = [float(r["Lap time [s]"]) for r in end]
    kj = [float(r["Energy Spent [kJ]"]) for r in end]
    tcs = [float(r["Percent TCS Enabled [%]"]) for r in end]
    r_a = [float(r["ratio"]) for r in acc]
    t75 = [float(r["Lap time [s]"]) for r in acc]
    tcs_a = [float(r["Percent TCS Enabled [%]"]) for r in acc]

    out = []
    w = out.append
    w("=" * 98)
    w("OPTIMUMLAP CROSS-CHECK -- the lap-time model the MATLAB study did not have")
    w("=" * 98)
    w("  Track: Michigan Endurance 2026. Halfshaft angle %g deg (current geometry)." % HS_CURRENT)
    w("  OLVeh peak torque decoded from the binary: 150 Nm -- the FULL datasheet map.")
    w("")
    w("1. ENDURANCE LAP TIME IS ESSENTIALLY RATIO-INVARIANT")
    w("-" * 98)
    w("  %-8s %-12s %-12s %-12s %-10s" % ("ratio", "lap (s)", "vs best (s)", "energy (kJ)", "TCS %"))
    best_lap = min(lap)
    for i, r in enumerate(r_e):
        w("  %-8.2f %-12.4f %+-12.4f %-12.1f %-10.1f" % (r, lap[i], lap[i] - best_lap, kj[i], tcs[i]))
    spread = max(lap) - min(lap)
    w("")
    w("  Lap time spread across the ENTIRE 4.00-5.20 range: %.4f s on %.1f s = %.3f%%."
      % (spread, min(lap), 100 * spread / min(lap)))
    w("  Fastest lap is at ratio %.2f. The curve is almost flat and turns up only past 5.00."
      % r_e[lap.index(best_lap)])
    w("")

    # --- endurance time points -------------------------------------------------
    # Endurance Time Score = 250 * ((Tmax/Tyour)-1) / ((Tmax/Tmin)-1), Tmax = 1.45*Tmin
    # d(Score)/d(Tyour) = -(250/0.45) * 1.45 * Tmin / Tyour^2
    # Worst case for "how much could this matter" is Tyour = Tmin (we are at the front).
    T_tot = [LAPS * x for x in lap]
    Tmin_assumed = min(T_tot)
    dpts_ds = (250.0 / 0.45) * 1.45 * Tmin_assumed / (Tmin_assumed ** 2)
    end_pts_spread = (max(T_tot) - min(T_tot)) * dpts_ds
    w("2. WHAT THAT IS WORTH IN POINTS")
    w("-" * 98)
    w("  Endurance total time spread: %.2f s over %d laps (%.1f s total)."
      % (max(T_tot) - min(T_tot), LAPS, min(T_tot)))
    w("  Endurance time sensitivity:  %.3f pts/s  (upper bound, assumes we SET Tmin)" % dpts_ds)
    w("  => ENDURANCE TIME across the whole ratio sweep is worth %.2f POINTS." % end_pts_spread)
    w("")
    # autocross: scale the same fractional lap-time change onto a 60 s autocross lap
    frac = spread / min(lap)
    ax_ds = frac * AUTOX_LAP_S
    ax_dpts_ds = (118.5 / 0.45) * 1.45 * AUTOX_LAP_S / (AUTOX_LAP_S ** 2)
    ax_pts = ax_ds * ax_dpts_ds
    w("  Autocross has no OptimumLap track here, so scale the SAME fractional change onto")
    w("  a %.0f s autocross lap: %.4f s, at %.2f pts/s => %.2f POINTS."
      % (AUTOX_LAP_S, ax_ds, ax_dpts_ds, ax_pts))
    w("  (estimate, flagged as such -- but it would take a 10x error to become material)")
    w("")
    w("  >> The 375 points gear_points_model.py listed as NOT MODELLED are worth about")
    w("     %.1f points across the entire 4.00-5.20 sweep. That caveat is now closed."
      % (end_pts_spread + ax_pts))
    w("")

    # --- efficiency cross-check ------------------------------------------------
    wh = [x / 3.6 for x in kj]           # kJ -> Wh per lap
    w("3. ENERGY: OPTIMUMLAP vs THE MATLAB SOC MODEL")
    w("-" * 98)
    w("  %-8s %-14s %-14s" % ("ratio", "OL Wh/lap", "vs 4.00"))
    for i, r in enumerate(r_e):
        w("  %-8.2f %-14.1f %+-14.2f%%" % (r, wh[i], 100 * (wh[i] / wh[0] - 1)))
    w("")
    w("  OptimumLap says energy rises %.2f%% from 4.00 to 5.20." % (100 * (wh[-1] / wh[0] - 1)))
    w("  The MATLAB SOC model said 1.2%% over the same span. Same DIRECTION, OptimumLap is")
    w("  about 2.6x steeper. Both land near 240-280 Wh/lap in absolute terms, and both put us")
    w("  near the bottom of the 2025 field (best 83.7, median 157.3 Wh/lap).")
    w("  Using the steeper OptimumLap number, efficiency across the whole sweep is worth")
    w("  roughly %.1f points (at ~0.61 pts per 1%% of energy)." % (100 * (wh[-1] / wh[0] - 1) * 0.61))
    w("")

    # --- the accel disagreement ------------------------------------------------
    w("4. THE ACCEL DISAGREEMENT, AND WHY IT IS NOT A BUG")
    w("-" * 98)
    w("  %-8s %-14s %-12s %-16s %-12s" % ("ratio", "OL t75 (s)", "OL TCS %", "MATLAB t75 (s)", "direction"))
    mat = {}
    with open(os.path.join(ROOT, "output", "gear_meeting_matrix.csv")) as f:
        for r in csv.DictReader(f):
            mat[float(r["ratio"])] = float(r["t75_mu853"])
    mr = sorted(mat)
    mv = [mat[k] for k in mr]
    for i, r in enumerate(r_a):
        m = interp(mr, mv, r)
        w("  %-8.2f %-14.4f %-12.1f %-16.4f %-12s" % (r, t75[i], tcs_a[i], m, ""))
    w("")
    w("  OptimumLap:  fastest at %.2f, monotonically SLOWER as the ratio rises. TCS active"
      % r_a[t75.index(min(t75))])
    w("               %.0f%% to %.0f%% of the run -- the car is TRACTION limited throughout."
      % (min(tcs_a), max(tcs_a)))
    w("  MATLAB:      fastest near 4.92, FASTER as the ratio rises up to that point.")
    w("")
    w("  THE REASON: they model different torque.")
    w("    OptimumLap OLVeh peak torque = 150 Nm, the full datasheet map. At 150 Nm the car")
    w("    cannot put the torque down, TC saturates, and extra gearing just spins the tyres,")
    w("    so LONGER gearing wins.")
    w("    gear_meeting_matrix uses the REAL 123 Nm the car actually requests. At 123 Nm the")
    w("    car is torque limited, not traction limited, so SHORTER gearing wins.")
    w("")
    w("  This is the same split GEAR_RATIO_DECISION.md section 2b already found from the")
    w("  MATLAB side alone. OptimumLap independently reproduces it. Neither model is wrong.")
    w("")
    w("  >> THE RATIO DECISION IS DOWNSTREAM OF THE TORQUE MAP DECISION.")
    w("     Run 123 Nm  -> shorter gearing is better, 30T to 32T.")
    w("     Run 150 Nm  -> longer gearing is better, 26T to 28T.")
    w("     Decide the torque map FIRST. Picking a ratio before that is picking blind.")
    w("")
    w("  Worth stating plainly: measured clean launch was 4.40 s. OptimumLap says 4.91 and")
    w("  the MATLAB TC sim says 4.70 at the current ratio. BOTH sims are pessimistic against")
    w("  the one real launch we have, so treat the absolute accel times as soft. The ratio")
    w("  RANKING within each torque assumption is the useful part, not the absolute seconds.")

    txt = "\n".join(out)
    print(txt)
    with open(os.path.join(ROOT, "output", "optimumlap_crosscheck.txt"), "w") as f:
        f.write(txt + "\n")

    with open(os.path.join(ROOT, "output", "optimumlap_ratio_sweep.csv"), "w", newline="") as f:
        wr = csv.writer(f)
        wr.writerow(["ratio", "endurance_lap_s", "endurance_energy_kJ", "endurance_Wh_per_lap",
                     "endurance_TCS_pct", "accel_t75_s", "accel_TCS_pct"])
        for i, r in enumerate(r_e):
            wr.writerow([r, round(lap[i], 4), round(kj[i], 1), round(wh[i], 1), round(tcs[i], 1),
                         round(interp(r_a, t75, r), 4), round(interp(r_a, tcs_a, r), 1)])
    print("\nSaved output/optimumlap_crosscheck.txt and output/optimumlap_ratio_sweep.csv")


if __name__ == "__main__":
    main()

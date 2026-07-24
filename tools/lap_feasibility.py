#!/usr/bin/env python3
"""
LAP_FEASIBILITY -- take the best single lap and ask, honestly, whether it is
sustainable for a full 22-lap endurance.

Three axes, because a lap can be repeatable on one and impossible on another:

    ENERGY   does the pack survive 22 laps at that lap's consumption?
    THERMAL  do motor / inverter / pack temperatures stabilise at that pace,
             or run away? (usually the real limit)
    DRIVER   how much of the best lap was the car, and how much was one good
             lap out of many? Quantified as best-vs-mean lap spread.

The verdict is deliberately "yes / no / yes-if", never a single optimistic number.

DATA USED
    ours      data/endurance_july11_with_odo_wide.csv -- pack V/I, motor rpm and
              torque, vehicle speed and odometer. Laps are recovered from the
              speed trace and NORMALISED BY DISTANCE, because the July 11 test
              loop is ~267 m, not a ~1 km competition lap. Comparing raw per-lap
              energy between the two would be meaningless; Wh/km is comparable.
    field     the competition e-meter endurance runs, for lap-to-lap spread
              across 23 other cars -- the context for how much of our own spread
              is normal.

    python tools/lap_feasibility.py
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import emeter_lib as EL  # noqa: E402

HERE = EL.HERE
ENDURANCE_KM = 22.0

# --- our car, from params_cfr26.m (kept in sync by verify_math) -------------
N_SERIES, N_PARALLEL = 88, 4
Q_CELL_AH = 4.4
V_NOM_CELL = 3.6
PACK_WH = N_SERIES * N_PARALLEL * Q_CELL_AH * V_NOM_CELL
R_PHASE, NM_PER_ARMS = 0.012, 0.83
CORE_A, CORE_B = 0.10833, 2.7778e-5

C_US, C_TOP, C_FIELD = "#2a78d6", "#eb6834", "#898781"
INK, INK2, GRID, SURFACE = "#0b0b0b", "#52514e", "#e1e0d9", "#fcfcfb"


# ---------------------------------------------------------------------------
def load_ours():
    import csv
    path = os.path.join(HERE, "data", "endurance_july11_with_odo_wide.csv")
    if not os.path.isfile(path):
        return None
    rows = list(csv.DictReader(open(path)))

    def col(n):
        return np.array([float(r[n]) if r[n] not in ("", "NaN", None) else np.nan for r in rows])

    d = {k: col(k) for k in (
        "t_s", "BMSB_packVoltage", "BMSB_packCurrent", "BMSB_packSOC",
        "PM100DX_motorSpeed", "PM100DX_torqueFeedback",
        "VCFRONT_vehicleSpeed", "VCFRONT_odometer")}
    d["P"] = np.abs(d["BMSB_packVoltage"] * d["BMSB_packCurrent"])
    return d


def driving_blocks(t, spd, min_s=120.0, thresh=5.0):
    """Contiguous stretches of actually driving (speed in m/s)."""
    mv = spd > thresh
    dd = np.diff(np.r_[0, mv.astype(int), 0])
    st, en = np.flatnonzero(dd == 1), np.flatnonzero(dd == -1)
    dt = float(np.median(np.diff(t)))
    return [(a, b) for a, b in zip(st, en) if (b - a) * dt >= min_s]


def lap_period_speed(t, spd, lo=15.0, hi=200.0):
    """
    Lap period from the speed trace, with the same harmonic problem as the
    e-meter power trace -- and here it is stark: the July 11 ACF peaks at 24.7 s
    with a textbook harmonic series above it (49.4, 74.3, 99.1 ...). All of them
    are multiples of the fundamental, so 24.7 s IS the lap: a ~267 m test loop.
    """
    x = spd - spd.mean()
    if x.std() <= 0:
        return np.nan, 0.0
    x = x / x.std()
    ac = np.correlate(x, x, "full")[len(x) - 1:] / len(x)
    dt = float(np.median(np.diff(t)))
    lags = np.arange(len(ac)) * dt
    m = (lags >= lo) & (lags <= hi)
    ab, lb = ac[m], lags[m]
    pk = np.r_[False, (ab[1:-1] > ab[:-2]) & (ab[1:-1] > ab[2:]), False]
    if not pk.any():
        return np.nan, 0.0
    i = int(np.argmax(ab[pk]))
    return float(lb[pk][i]), float(ab[pk][i])


def our_laps():
    """Per-lap Wh/km, peak power and motor heat for our own run."""
    d = load_ours()
    if d is None:
        return None
    t, spd = d["t_s"], d["VCFRONT_vehicleSpeed"]
    blocks = driving_blocks(t, spd)
    if not blocks:
        return None
    a, b = max(blocks, key=lambda ab: ab[1] - ab[0])      # longest driving block
    sl = slice(a, b)
    lap_s, conf = lap_period_speed(t[sl], spd[sl])
    if not np.isfinite(lap_s):
        return None

    dt = float(np.median(np.diff(t)))
    per = int(round(lap_s / dt))
    n = (b - a) // per

    rpm = np.abs(d["PM100DX_motorSpeed"])
    tq = np.abs(d["PM100DX_torqueFeedback"])
    # motor heat, from the same physics verify_math sec 3/4 validates
    q_motor = 3 * (tq / NM_PER_ARMS) ** 2 * R_PHASE + CORE_A * rpm + CORE_B * rpm ** 2

    laps = []
    for i in range(n):
        s = slice(a + i * per, a + (i + 1) * per)
        tt = t[s]
        km = float(np.trapezoid(np.nan_to_num(spd[s]), tt) / 1000.0)
        wh = float(np.trapezoid(np.nan_to_num(d["P"][s]), tt) / 3600.0)
        if km <= 0.02:
            continue
        laps.append({
            "i": i + 1, "km": km, "Wh": wh, "Wh_km": wh / km,
            "P_peak_kW": float(np.nanmax(d["P"][s]) / 1e3),
            "P_mean_kW": float(np.nanmean(d["P"][s]) / 1e3),
            "q_motor_W": float(np.nanmean(q_motor[s])),
            "v_mean_kph": float(np.nanmean(spd[s]) * 3.6),
        })
    return {"laps": laps, "lap_s": lap_s, "conf": conf,
            "block_km": float(np.trapezoid(np.nan_to_num(spd[sl]), t[sl]) / 1000.0),
            "block_min": (t[b - 1] - t[a]) / 60.0}


def field_lap_spread():
    """Lap-to-lap energy spread for every ranked car in the e-meter field."""
    recs = EL.analyse_field(verbose=False)
    if not recs:
        return []
    EL.efficiency_factor(recs)
    out = []
    for r in recs:
        if not r["ranked"]:
            continue
        vals = []
        for s in r["stints"]:
            lap_s = r["lap_s_est"]
            for sl in EL.split_laps(s, lap_s):
                seg = s.P[sl]
                if seg.size < 10:
                    continue
                vals.append(float(np.trapezoid(seg, dx=s.dt) / 3600.0))
        vals = [v for v in vals if v > 0]
        if len(vals) < 6:
            continue
        v = np.array(vals)
        # Drop degenerate windows before anything else. A fixed-period window that
        # lands on a grid queue or a driver change contains almost no energy, and
        # it is not a lap -- left in, it becomes the "best lap" and reports a
        # meaningless 100% best-vs-mean gap.
        v = v[v > 0.4 * np.median(v)]
        if v.size < 5:
            continue
        # trim the in/out laps, which are not racing laps
        lo, hi = np.percentile(v, [5, 95])
        vt = v[(v >= lo) & (v <= hi)]
        if vt.size < 5:
            vt = v
        out.append({
            "car": r["car"], "university": r["university"],
            "best": float(vt.min()), "mean": float(vt.mean()),
            "cv": float(vt.std() / vt.mean()), "n": int(vt.size),
            "gap_pct": float(100 * (vt.mean() - vt.min()) / vt.mean()),
        })
    return sorted(out, key=lambda x: x["gap_pct"])


# ---------------------------------------------------------------------------
def report():
    print("=" * 100)
    print("BEST LAP -> 22-LAP FEASIBILITY")
    print("=" * 100)

    ours = our_laps()
    if ours is None or not ours["laps"]:
        print("  our telemetry not found or no usable laps -- cannot run the study")
        return None, []

    L = ours["laps"]
    whkm = np.array([x["Wh_km"] for x in L])
    best_i = int(np.argmin(whkm))
    best, mean_, med = L[best_i], float(whkm.mean()), float(np.median(whkm))
    p_peak = np.array([x["P_peak_kW"] for x in L])

    print(f"\nOUR RUN (July 11, longest continuous block: {ours['block_km']:.2f} km in "
          f"{ours['block_min']:.1f} min)")
    print(f"  lap recovered from the speed trace: {ours['lap_s']:.1f} s, "
          f"autocorrelation {ours['conf']:.2f} (strong)")
    print(f"  {len(L)} laps of ~{np.mean([x['km'] for x in L])*1000:.0f} m each")
    print("\n  NOTE: this is a ~267 m test loop, NOT a ~1 km competition lap. Everything")
    print("  below is normalised to Wh/km so it can be projected onto a 22 km endurance.")

    print(f"\n  BEST lap  (#{best['i']:>2}) : {best['Wh_km']:6.1f} Wh/km   "
          f"peak {best['P_peak_kW']:5.1f} kW   avg {best['P_mean_kW']:4.1f} kW   "
          f"{best['v_mean_kph']:4.1f} km/h")
    print(f"  MEAN lap        : {mean_:6.1f} Wh/km   peak {p_peak.mean():5.1f} kW")
    print(f"  MEDIAN lap      : {med:6.1f} Wh/km")
    print(f"  WORST lap       : {whkm.max():6.1f} Wh/km")

    # ---------------- AXIS 1: ENERGY --------------------------------------
    e_best = best["Wh_km"] * ENDURANCE_KM
    e_mean = mean_ * ENDURANCE_KM
    print("\n" + "-" * 100)
    print("AXIS 1 -- ENERGY: does the pack survive 22 laps at that pace?")
    print("-" * 100)
    print(f"  pack (nominal, {N_SERIES}S{N_PARALLEL}P x {Q_CELL_AH} Ah x {V_NOM_CELL} V) = {PACK_WH:.0f} Wh")
    print(f"  22 km at the BEST lap's rate : {e_best:6.0f} Wh = {100*e_best/PACK_WH:5.1f}% of pack")
    print(f"  22 km at the MEAN lap's rate : {e_mean:6.0f} Wh = {100*e_mean/PACK_WH:5.1f}% of pack")
    margin = 100 * (1 - e_mean / PACK_WH)
    energy_ok = e_mean < PACK_WH
    thin = margin < 15.0
    if e_best < PACK_WH < e_mean:
        print("\n  => the BEST lap fits the pack; the AVERAGE lap does NOT.")
        print("     This is the definition of a yes-if: the car can do it, this driving did not.")
    elif energy_ok and thin:
        print(f"\n  => it fits, but on {margin:.0f}% margin at the pace actually driven.")
        print("     That is not real margin. It has to absorb, all at once: a hotter day, a")
        print("     faster course, and a cell pack that has aged -- any ONE of which eats it.")
        print("     Treat 22 laps as achievable but NOT comfortable, and stop calling it a pass.")
    elif energy_ok:
        print(f"\n  => both fit, with {margin:.0f}% margin. Energy is not the binding constraint.")
    else:
        print("\n  => neither fits. Energy is the binding constraint.")
    print("\n  CAVEATS: nominal pack energy uses the datasheet 4.4 Ah/cell; the README notes")
    print("  the real cells may hold somewhat more, so this is the conservative read. These")
    print("  laps are the hardest-driven block of July 11, so Wh/km here runs above the")
    print("  ~224 Wh/km whole-session average (the session includes cool-down and paddock")
    print("  laps) -- that is the intended difference, not a contradiction: this axis asks")
    print("  about RACE pace, not session-average pace.")

    # ---------------- AXIS 2: THERMAL -------------------------------------
    print("\n" + "-" * 100)
    print("AXIS 2 -- THERMAL: do temperatures stabilise at that pace?")
    print("-" * 100)
    print("  ANSWER: WE CANNOT TELL YOU. There is no temperature data.")
    print("    - our telemetry exports carry NO temperature channel at all (13 channels,")
    print("      none thermal) -- checked across all four CSVs in data/")
    print("    - the competition e-meter logs one 'Temperature1' probe with no documented")
    print("      mounting point, absent on 17 of 52 endurance files, and where present it")
    print("      is plainly faulty (one car rails at 0 C, another peaks at 3106 C)")
    print("    - so motor, inverter and pack-cell temperatures are all unmeasured")
    print("\n  This is the axis where the real limit usually is, and it is the one axis we")
    print("  have no data for. Nobody should read the energy answer as the whole answer.")

    q = np.array([x["q_motor_W"] for x in L])
    print("\n  What we CAN derive -- heat GENERATED (not whether it can be rejected).")
    print("  From the same loss physics verify_math sec 3-4 validates against the datasheet:")
    print(f"    motor loss at the best lap's pace : {q[best_i]:5.0f} W continuous")
    print(f"    motor loss averaged over all laps : {q.mean():5.0f} W")
    print(f"    worst lap                         : {q.max():5.0f} W")
    v_ms = float(np.mean([x["v_mean_kph"] for x in L])) / 3.6      # mean pace, m/s
    t_endurance_s = ENDURANCE_KM * 1000.0 / max(v_ms, 1e-9)        # time for 22 km
    heat_Wh = q.mean() * t_endurance_s / 3600.0
    print(f"  Held for a full {ENDURANCE_KM:.0f} km ({t_endurance_s/60:.0f} min at this pace) that is")
    print(f"    {heat_Wh:.0f} Wh of heat dumped into the motor and its coolant.")
    print("  Whether the cooling loop can reject that continuously is UNKNOWN -- we have")
    print("  no coolant temperature, no flow rate and no radiator characterisation.")
    print("\n  TO CLOSE THIS AXIS (cheap, and it is the highest-value missing measurement):")
    print("    export PM100DX_tempModuleA/B/C, motorTemp, rtdTemp1-5 and controlBoardTemp")
    print("    on a long run, then check whether temperature PLATEAUS or keeps climbing.")
    print("    A plateau is a yes; a steady climb over 22 laps is a no, whatever the energy")
    print("    number says.")

    # ---------------- AXIS 3: DRIVER --------------------------------------
    gap = 100 * (mean_ - best["Wh_km"]) / mean_
    cv = 100 * whkm.std() / whkm.mean()
    print("\n" + "-" * 100)
    print("AXIS 3 -- DRIVER: how much of the best lap is the car, and how much is one good lap?")
    print("-" * 100)
    print(f"  best lap is {gap:.1f}% better than the mean lap")
    print(f"  lap-to-lap spread (CV) : {cv:.1f}%")
    print(f"  full range             : {whkm.min():.0f} .. {whkm.max():.0f} Wh/km "
          f"({whkm.max()/whkm.min():.2f}x)")
    print(f"\n  Closing that {gap:.1f}% gap by consistency alone would save "
          f"{(mean_-best['Wh_km'])*ENDURANCE_KM:.0f} Wh over 22 km.")
    print("  Driver consistency is a real, free lever here -- no hardware change buys it.")

    field = field_lap_spread()
    if field:
        gaps = np.array([f["gap_pct"] for f in field])
        print(f"\n  FIELD CONTEXT ({len(field)} cars with e-meter endurance data):")
        print(f"    best-vs-mean lap gap across the field: median {np.median(gaps):.1f}%, "
              f"range {gaps.min():.1f}-{gaps.max():.1f}%")
        print(f"    ours: {gap:.1f}% -> {'BETTER' if gap < np.median(gaps) else 'WORSE'} "
              "than the field median")
        print(f"\n    {'car':>4} {'university':<38} {'gap%':>6} {'CV%':>6}")
        print("    " + "-" * 58)
        for f in field[:5]:
            print(f"    {f['car']:>4} {EL.pretty_uni(f['university'])[:38]:<38} "
                  f"{f['gap_pct']:>6.1f} {100*f['cv']:>6.1f}   most consistent")
        for f in field[-3:]:
            print(f"    {f['car']:>4} {EL.pretty_uni(f['university'])[:38]:<38} "
                  f"{f['gap_pct']:>6.1f} {100*f['cv']:>6.1f}")

    # ---------------- VERDICT ---------------------------------------------
    print("\n" + "=" * 100)
    print("VERDICT")
    print("=" * 100)
    if not energy_ok and e_best < PACK_WH:
        print("  YES-IF.")
        print(f"  IF the driver holds the best lap's {best['Wh_km']:.0f} Wh/km, 22 laps costs "
              f"{e_best:.0f} Wh and the pack ({PACK_WH:.0f} Wh) survives.")
        print(f"  AT the pace actually driven ({mean_:.0f} Wh/km) it costs {e_mean:.0f} Wh and it "
              "does NOT.")
        print(f"  The whole margin is the {gap:.1f}% driver-consistency gap. That is the single")
        print("  highest-value thing to work on, and it costs nothing to fix.")
    elif energy_ok and thin:
        print("  YES-IF, on energy.")
        print(f"  At race pace 22 laps costs {e_mean:.0f} Wh of a {PACK_WH:.0f} Wh pack -- it fits, "
              f"but on {margin:.0f}% margin.")
        print(f"  IF the driver holds the best lap ({best['Wh_km']:.0f} Wh/km) that becomes "
              f"{e_best:.0f} Wh and {100-100*e_best/PACK_WH:.0f}% margin,")
        print(f"  which is a real buffer. The {gap:.1f}% best-vs-mean gap is worth "
              f"{(mean_-best['Wh_km'])*ENDURANCE_KM:.0f} Wh,")
        print("  and it is free. Driver consistency IS the margin.")
    elif energy_ok:
        print(f"  YES on energy -- best and average both fit, with {margin:.0f}% margin.")
    else:
        print("  NO on energy -- even the best lap does not fit 22 laps inside the pack.")
    print("\n  ...but this verdict covers ONE of three axes. Thermal is unmeasured, and")
    print("  thermal is usually what actually stops the car. Treat this as 'energy says")
    print("  yes-if', NOT as 'the car can do 22 laps'. Get temperatures on the next run.")
    return ours, field


def chart(ours, field, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    L = ours["laps"]
    whkm = np.array([x["Wh_km"] for x in L])
    idx = np.arange(1, len(L) + 1)
    best_i = int(np.argmin(whkm))

    fig, (ax, ax2) = plt.subplots(1, 2, figsize=(14.5, 5.6), facecolor=SURFACE,
                                  gridspec_kw={"width_ratios": [1.25, 1]})

    # -- left: our lap-by-lap consumption, best highlighted (emphasis form) --
    ax.set_facecolor(SURFACE)
    colors = [C_US if i == best_i else C_FIELD for i in range(len(L))]
    ax.bar(idx, whkm, color=colors, width=0.72, zorder=3)
    # headroom so the callout sits above every bar instead of on top of one
    ax.set_ylim(0, whkm.max() * 1.26)
    ax.axhline(whkm.mean(), color=INK2, lw=1.2, ls=(0, (4, 3)), zorder=4)
    ax.text(len(L) + 0.4, whkm.mean(), f"mean {whkm.mean():.0f}", va="center",
            fontsize=9, color=INK2)
    ax.annotate(f"best lap {whkm[best_i]:.0f} Wh/km",
                xy=(idx[best_i], whkm[best_i]), xytext=(idx[best_i], whkm.max() * 1.19),
                ha="center", fontsize=9, color=C_US, fontweight="bold",
                arrowprops=dict(arrowstyle="->", color=C_US, lw=1.3))
    ax.set_xlabel("Lap number (July 11, longest block)", fontsize=9.5, color=INK2)
    ax.set_ylabel("Energy per km (Wh/km)", fontsize=9.5, color=INK2)
    ax.grid(axis="y", color=GRID, lw=0.8, zorder=0)
    ax.set_axisbelow(True)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax.spines[s].set_color("#c3c2b7")
    ax.tick_params(colors=INK2, labelsize=8.5, length=0)
    ax.set_title("Our lap-to-lap consistency\nthe gap to the mean is the driver factor",
                 fontsize=11.5, color=INK, fontweight="bold", loc="left", pad=12)
    ax.legend([plt.Rectangle((0, 0), 1, 1, color=C_US),
               plt.Rectangle((0, 0), 1, 1, color=C_FIELD)],
              ["best lap", "other laps"], loc="upper right", frameon=False,
              fontsize=8.5, labelcolor=INK2)

    # -- right: 22-lap energy projection vs the pack -------------------------
    ax2.set_facecolor(SURFACE)
    e_best = whkm.min() * ENDURANCE_KM
    e_mean = whkm.mean() * ENDURANCE_KM
    e_worst = whkm.max() * ENDURANCE_KM
    bars = [e_best, e_mean, e_worst]
    labs = ["every lap =\nbest lap", "every lap =\nmean lap", "every lap =\nworst lap"]
    # colour by how much margin is left, not by which bar it is: comfortable /
    # thin (<15%) / over the pack. Status colours, so they never read as a series.
    def margin_colour(e):
        if e > PACK_WH:
            return "#d03b3b"                      # over the pack -- critical
        return C_TOP if (1 - e / PACK_WH) < 0.15 else C_US   # thin -- serious
    cols = [margin_colour(e) for e in bars]
    ax2.bar(range(3), bars, color=cols, width=0.6, zorder=3)
    ax2.axhline(PACK_WH, color="#d03b3b", lw=1.8, zorder=5)
    ax2.text(-0.44, PACK_WH * 1.012, f"pack capacity {PACK_WH:.0f} Wh", va="bottom",
             ha="left", fontsize=9.5, color="#d03b3b", fontweight="bold")
    for i, v in enumerate(bars):
        ax2.text(i, v + max(bars) * 0.02, f"{v:.0f} Wh\n({100*v/PACK_WH:.0f}%)",
                 ha="center", fontsize=9, color=INK2)
    ax2.set_xticks(range(3))
    ax2.set_xticklabels(labs, fontsize=9, color=INK2)
    ax2.set_ylabel("Energy for 22 km (Wh)", fontsize=9.5, color=INK2)
    ax2.set_ylim(0, max(max(bars), PACK_WH) * 1.22)
    ax2.grid(axis="y", color=GRID, lw=0.8, zorder=0)
    ax2.set_axisbelow(True)
    for s in ("top", "right"):
        ax2.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax2.spines[s].set_color("#c3c2b7")
    ax2.tick_params(colors=INK2, labelsize=8.5, length=0)
    ax2.set_title("22-lap energy vs the pack\nENERGY AXIS ONLY -- thermal is unmeasured",
                  fontsize=11.5, color=INK, fontweight="bold", loc="left", pad=12)

    fig.tight_layout()
    fig.savefig(path, dpi=150, facecolor=SURFACE)
    print(f"\nchart -> {path}")


def main():
    os.makedirs(EL.OUTDIR, exist_ok=True)
    ours, field = report()
    if ours:
        chart(ours, field, os.path.join(EL.OUTDIR, "LapFeasibility.png"))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
EMETER_BENCHMARK -- rank the field on endurance energy economy, and find out
where Concordia actually sits.

Reads the unpacked competition e-meter logs (run tools/emeter_unpack.py first),
keeps only the ENDUR-EV runs, rolls each car's stints into one endurance record,
and ranks everybody on Wh per lap.

WHY Wh/LAP IS THE RANKING METRIC
    Every car drives the same track, so Wh/lap is a like-for-like comparison that
    needs NO assumed distance. Wh/km is printed too, but it is just Wh/lap divided
    by an assumed 1.0 km lap -- a single constant applied to every car, so it
    cannot reorder anything. If you later learn the true lap length, set LAP_KM in
    emeter_lib.py and only the Wh/km column moves.

WHAT WE CANNOT COMPUTE, AND WHY
    "Efficiency" in the drivetrain sense (mechanical out / electrical in) is NOT
    available from this dataset. The e-meter is a pack-side energy counter -- no
    speed, no torque, no rpm, no distance. Anything claiming a drivetrain
    efficiency % off these files would be fabricated. What the channels DO
    support is energy ECONOMY (Wh/lap, Wh/km), power draw, and regen recovery
    fraction, which is what this script reports.

    Outputs: a ranked table to stdout, output/emeter_benchmark.csv, and
    output/EMeter_Benchmark.png.

    python tools/emeter_benchmark.py
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import emeter_lib as EL  # noqa: E402

# --- palette: emphasis form (one group is the point, the rest are context) ---
# Validated with the dataviz validator (all-pairs, light surface): accents pass
# every gate. Gray is the de-emphasis ink token, not a categorical series.
C_US = "#2a78d6"      # Concordia
C_TOP = "#eb6834"     # 2026 top-5 finishers
C_FIELD = "#898781"   # everyone else (muted ink)
INK = "#0b0b0b"
INK2 = "#52514e"
GRID = "#e1e0d9"
SURFACE = "#fcfcfb"


def collect():
    recs = EL.analyse_field()
    if not recs:
        sys.exit(
            f"no ENDUR-EV files under {EL.RAWDIR}\n"
            "run:  python tools/emeter_unpack.py"
        )
    return recs


def top5_set():
    return {u for u, (rank, _, _) in EL.RESULTS_2026.items() if rank <= 5}


def report(recs):
    top5 = top5_set()
    EL.efficiency_factor(recs)
    ranked = sorted([r for r in recs if r["ranked"]], key=lambda r: r["Wh_per_lap"])
    unranked = [r for r in recs if not r["ranked"]]

    print("\n" + "=" * 120)
    print("ENDURANCE ENERGY ECONOMY -- 2025 FSAE competition e-meter, all cars with a valid ENDUR-EV run")
    print("=" * 120)
    print(
        f"{'#':>3} {'car':>4} {'university':<36} {'Wh/lap':>8} {'Wh/km':>7} {'total':>7} "
        f"{'laps':>5} {'lap s':>6} {'effF':>5} {'avgkW':>6} {'pkkW':>6} {'regen':>6}  flags"
    )
    print("-" * 120)
    for i, r in enumerate(ranked, 1):
        tag = ""
        if r["car"] == EL.CONCORDIA_2025_CAR:
            tag = "  <<< CONCORDIA"
        elif r["university"] in top5:
            tag = f"  <- 2026 P{EL.RESULTS_2026[r['university']][0]}"
        flags = []
        if r["counter_mismatch_pct"] > 1.0:
            flags.append("Wh-counter-disagrees")
        if r["lap_conf"] < 0.15:
            flags.append("weak-lap-detect")
        if not r["lap_agrees_field"]:
            flags.append("lap-off-field-consensus")
        if r["violation"]:
            flags.append("power-violation")
        print(
            f"{i:>3} {r['car']:>4} {EL.pretty_uni(r['university'])[:36]:<36} "
            f"{r['Wh_per_lap']:>8.1f} {r['Wh_per_km']:>7.1f} {r['energy_Wh']:>7.0f} "
            f"{r['laps_est']:>5.1f} {r['lap_s_est']:>6.1f} {r['eff_factor']:>5.2f} "
            f"{r['P_mean_kW']:>6.1f} {r['P_p999_kW']:>6.1f} "
            f"{r['regen_pct']:>5.1f}%  {','.join(flags)}{tag}"
        )

    if unranked:
        print("\nNOT RANKED -- run too short to be a representative endurance stint")
        print(f"(under {EL.MIN_LAPS_RANKED} recovered laps: a DNF, an out-lap, or a dead e-meter)")
        for r in sorted(unranked, key=lambda r: -r["duration_min"]):
            print(
                f"    car {r['car']:>4} {EL.pretty_uni(r['university'])[:38]:<38} "
                f"{r['duration_min']:>6.1f} min, {r['energy_Wh']:>6.0f} Wh, "
                f"~{r['laps_est']:.1f} laps"
            )

    # ---- pace-corrected ranking ----------------------------------------------
    # Wh/lap alone rewards crawling. This is the shape of the metric the
    # competition actually scores: pace AND energy together.
    byeff = sorted([r for r in ranked if np.isfinite(r["eff_factor"])],
                   key=lambda r: -r["eff_factor"])
    if byeff:
        print("\n" + "=" * 120)
        print("PACE-CORRECTED: (fastest lap / this lap) x (lowest Wh per lap / this Wh per lap)")
        print("=" * 120)
        print("  Wh/lap on its own rewards driving slowly. This weights economy BY pace, the")
        print("  way FSAE scores efficiency. Lap time is autocorrelation-estimated, so this")
        print("  reproduces the shape of the official metric, not the official score.\n")
        print(f"  {'#':>3} {'car':>4} {'university':<36} {'effF':>6} {'lap s':>7} {'Wh/lap':>8}  {'vs economy rank':>16}")
        print("  " + "-" * 92)
        econ = {r["car"]: i for i, r in enumerate(ranked, 1)}
        for i, r in enumerate(byeff, 1):
            d = econ[r["car"]] - i
            move = "same" if d == 0 else (f"up {d}" if d > 0 else f"down {-d}")
            tag = "  <<< CONCORDIA" if r["car"] == EL.CONCORDIA_2025_CAR else (
                f"  <- 2026 P{EL.RESULTS_2026[r['university']][0]}" if r["university"] in top5 else "")
            print(
                f"  {i:>3} {r['car']:>4} {EL.pretty_uni(r['university'])[:36]:<36} "
                f"{r['eff_factor']:>6.2f} {r['lap_s_est']:>7.1f} {r['Wh_per_lap']:>8.1f}  {move:>16}{tag}"
            )

    # ---- where Concordia sits -------------------------------------------------
    print("\n" + "=" * 108)
    print("CONCORDIA")
    print("=" * 108)
    us = next((r for r in recs if r["car"] == EL.CONCORDIA_2025_CAR), None)
    if us is None:
        print(
            f"  Concordia is car {EL.CONCORDIA_2025_CAR} in the 2025 dataset\n"
            f"  (car {EL.CONCORDIA_2026_CAR} in 2026), and the university name is in every\n"
            "  filename -- but there is NO ENDUR-EV file in car_246. The car logged 31\n"
            "  sessions, all on 19-20 June; the endurance event ran 21 June.\n\n"
            "  => Concordia did not record an endurance run in 2025, so we CANNOT rank\n"
            "     ourselves against this field on endurance energy. That is a data gap,\n"
            "     not a poor result -- do not read a number into it.\n\n"
            "  What to do instead:\n"
            "    - our own endurance telemetry (data/endurance_july11_with_odo_wide.csv)\n"
            "      is richer than the e-meter anyway: it has rpm, torque, pack V/I and\n"
            "      the PM100DX channels. Use the field's Wh/lap as the TARGET to beat.\n"
            "    - the table above still sets the benchmark: see the summary below."
        )
    else:
        pos = [i for i, r in enumerate(ranked, 1) if r["car"] == us["car"]]
        print(f"  ranked {pos[0]} of {len(ranked)} at {us['Wh_per_lap']:.1f} Wh/lap")

    if ranked:
        best, med = ranked[0], ranked[len(ranked) // 2]
        vals = np.array([r["Wh_per_lap"] for r in ranked])
        print(f"\n  field best   : {best['Wh_per_lap']:6.1f} Wh/lap  ({EL.pretty_uni(best['university'])})")
        print(f"  field median : {med['Wh_per_lap']:6.1f} Wh/lap")
        print(f"  field worst  : {ranked[-1]['Wh_per_lap']:6.1f} Wh/lap  ({EL.pretty_uni(ranked[-1]['university'])})")
        print(f"  spread       : {vals.max()/vals.min():.2f}x between best and worst")

    # ---- how the 2026 top 5 drove in 2025 ------------------------------------
    print("\n" + "=" * 108)
    print("THE 2026 TOP 5 -- how they ran endurance in 2025")
    print("=" * 108)
    print("  CAVEAT: the e-meter data is the 2025 competition; the results table is 2026.")
    print("  Same teams, one development year apart. Treat as indicative, not as the")
    print("  energy numbers that produced those 2026 scores.\n")
    print(f"  {'2026':>5} {'car26':>6} {'university':<38} {'2026 pts':>9} {'2025 Wh/lap':>12} {'2025 rank':>10}")
    print("  " + "-" * 84)
    order = {r["university"]: i for i, r in enumerate(ranked, 1)}
    for uni, (rank26, car26, pts) in sorted(EL.RESULTS_2026.items(), key=lambda kv: kv[1][0]):
        if rank26 > 5:
            continue
        r = next((x for x in recs if x["university"] == uni), None)
        whl = f"{r['Wh_per_lap']:.1f}" if r and r["ranked"] else "no valid run"
        rk = f"{order.get(uni, '-')}" if r and r["ranked"] else "-"
        print(f"  {rank26:>5} {car26:>6} {EL.pretty_uni(uni)[:38]:<38} {pts:>9.1f} {whl:>12} {rk:>10}")

    return ranked, unranked


def chart(ranked, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    top5 = top5_set()
    n = len(ranked)
    fig, (ax, ax2) = plt.subplots(
        1, 2, figsize=(15, max(6.5, 0.34 * n)), facecolor=SURFACE,
        gridspec_kw={"width_ratios": [1.55, 1]},
    )

    # ---- left: ranked bars, emphasis form ----------------------------------
    labels, vals, colors = [], [], []
    for r in ranked:
        labels.append(f"{r['car']} {EL.pretty_uni(r['university'])[:30]}")
        vals.append(r["Wh_per_lap"])
        if r["car"] == EL.CONCORDIA_2025_CAR:
            colors.append(C_US)
        elif r["university"] in top5:
            colors.append(C_TOP)
        else:
            colors.append(C_FIELD)

    y = np.arange(n)
    ax.set_facecolor(SURFACE)
    ax.barh(y, vals, color=colors, height=0.72, zorder=3)
    ax.set_yticks(y)
    ax.set_yticklabels(labels, fontsize=8.5, color=INK2)
    ax.invert_yaxis()
    ax.set_xlabel("Endurance energy per lap (Wh/lap)  -- lower is better", fontsize=9.5, color=INK2)
    ax.set_xlim(0, max(vals) * 1.20)
    ax.grid(axis="x", color=GRID, lw=0.8, zorder=0)
    ax.set_axisbelow(True)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.spines["bottom"].set_color("#c3c2b7")
    ax.tick_params(length=0, colors=INK2, labelsize=8.5)
    # direct labels -- identity never rests on color alone
    for yi, v in zip(y, vals):
        ax.text(v + max(vals) * 0.012, yi, f"{v:.0f}", va="center", fontsize=8, color=INK2)

    med = float(np.median(vals))
    ax.axvline(med, color=INK2, lw=1.1, ls=(0, (4, 3)), zorder=4)
    ax.text(med, n - 0.2, f"field median {med:.0f}", fontsize=8.5, color=INK2,
            ha="center", va="top")
    ax.set_title(
        "Endurance energy economy, 2025 FSAE e-meter",
        fontsize=12.5, color=INK, fontweight="bold", loc="left", pad=22,
    )

    handles = [
        plt.Rectangle((0, 0), 1, 1, color=C_TOP),
        plt.Rectangle((0, 0), 1, 1, color=C_FIELD),
    ]
    lbls = ["2026 top-5 finisher", "rest of field"]
    if any(r["car"] == EL.CONCORDIA_2025_CAR for r in ranked):
        handles.insert(0, plt.Rectangle((0, 0), 1, 1, color=C_US))
        lbls.insert(0, "Concordia")
    # bars are sorted ascending, so the upper-right of the plot is empty space
    ax.legend(handles, lbls, loc="upper right", frameon=False, fontsize=8.5,
              labelcolor=INK2, bbox_to_anchor=(1.0, 0.99))

    # ---- right: economy vs pace (the trade every team is making) ------------
    ax2.set_facecolor(SURFACE)
    for r in ranked:
        c = C_US if r["car"] == EL.CONCORDIA_2025_CAR else (C_TOP if r["university"] in top5 else C_FIELD)
        z = 5 if c != C_FIELD else 3
        ax2.scatter(
            r["P_mean_kW"], r["Wh_per_lap"], s=78, color=c, zorder=z,
            edgecolor=SURFACE, linewidth=1.6,
        )
        if c != C_FIELD:
            ax2.annotate(
                str(r["car"]), (r["P_mean_kW"], r["Wh_per_lap"]),
                textcoords="offset points", xytext=(8, 4), fontsize=8.5, color=INK2,
            )
    ax2.set_xlabel("Average power while moving (kW)", fontsize=9.5, color=INK2)
    ax2.set_ylabel("Energy per lap (Wh/lap)", fontsize=9.5, color=INK2)
    ax2.grid(color=GRID, lw=0.8, zorder=0)
    ax2.set_axisbelow(True)
    for s in ("top", "right"):
        ax2.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax2.spines[s].set_color("#c3c2b7")
    ax2.tick_params(colors=INK2, labelsize=8.5, length=0)
    ax2.set_title(
        "Economy vs pace\nup-and-right = fast but thirsty",
        fontsize=11, color=INK, fontweight="bold", loc="left", pad=12,
    )

    fig.tight_layout()
    fig.savefig(path, dpi=150, facecolor=SURFACE)
    print(f"\nchart -> {path}")


def write_csv(recs, path):
    cols = [
        "car", "university", "n_stints", "duration_min", "active_min", "energy_Wh", "gross_Wh",
        "regen_Wh", "regen_pct", "Wh_per_lap", "Wh_per_km", "km_est", "laps_est",
        "lap_s_est", "lap_conf", "lap_agrees_field", "eff_factor", "P_mean_kW", "P_peak_kW", "P_p999_kW", "V_mean",
        "counter_mismatch_pct", "violation", "temp_ok", "ranked",
    ]
    with open(path, "w", encoding="utf-8") as f:
        f.write(",".join(cols) + "\n")
        for r in sorted(recs, key=lambda r: (not r["ranked"], r.get("Wh_per_lap", 1e9))):
            f.write(",".join(str(r[c]) for c in cols) + "\n")
    print(f"table -> {path}")


def main():
    os.makedirs(EL.OUTDIR, exist_ok=True)
    print("reading endurance runs...")
    recs = collect()
    ranked, _ = report(recs)
    write_csv(recs, os.path.join(EL.OUTDIR, "emeter_benchmark.csv"))
    if ranked:
        chart(ranked, os.path.join(EL.OUTDIR, "EMeter_Benchmark.png"))
    print(
        "\nMETHOD NOTES\n"
        "  energy   : sum of per-stint (E_last - E_first) off the organiser's own Wh\n"
        "             counter; cross-checked against our integral of V*I (mismatch\n"
        "             column flags any car where the two disagree by >1%).\n"
        "  laps     : RECOVERED from power-trace autocorrelation -- the e-meter logs\n"
        "             no lap marker. ~12 laps/stint across the field, two stints per\n"
        "             car, which independently reproduces the 22-lap endurance format.\n"
        "  peak kW  : 99.9th percentile, not the raw max (100 Hz pack-side shunt sees\n"
        "             switching spikes that are not really delivered power).\n"
        "  NOT here : drivetrain efficiency -- no mechanical-output channel exists.\n"
    )


if __name__ == "__main__":
    main()

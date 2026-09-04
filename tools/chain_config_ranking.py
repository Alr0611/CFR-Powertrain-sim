#!/usr/bin/env python3
"""
CHAIN_CONFIG_RANKING -- every driver/driven combo in the 4.3-4.4 band, ranked on
what actually matters: chain efficiency, chain life, driveability and redline.

Envelope cap and all chain geometry are MEASURED (chain.STEP, cfr_sprocket.STEP,
DT-P2120.STEP, SolidWorks centre-distance measure). Accel and SOC are interpolated
from the MATLAB sweep at these ratios.

Writes output/chain_config_ranking.csv
"""
import csv
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

P = 15.875          # MEASURED-CAD chain.STEP
PLATE_H = 7.2517    # MEASURED-CAD, half plate height
R_PIN = 2.54        # MEASURED-CAD, pin radius feature
C0 = 152.08         # MEASURED-CAD centre distance
GB = 2.000          # from-SHEET 15:30
T_SHAFT = 300.0     # 150 Nm OWNER x 2.000 gearbox
ENV_CAP = 171.4     # what the chassis lead was given, envelope DIAMETER
REDLINE = 6000
W_MAX = 6083 / 4.61     # wheel rpm at the measured peak motor rpm
# Motor rpm at a GIVEN ROAD SPEED scales with ratio alone:
#     rpm_new = rpm_measured * g_new / g_measured
# Wheel rpm = motor rpm / ratio, which is exact and has NO rolling radius in it, so
# the radius CANCELS. An earlier version of this file multiplied by 0.200/0.190 and
# called it a "loaded radius" case; that was a double count and it wrongly killed the
# entire 4.40-4.45 band. Radius only sets what ROAD SPEED a given rpm corresponds to.
BAND = (4.28, 4.44)     # practical 4.3-4.4 band, slightly widened so the 14T
                        # options are visible rather than silently excluded
import sys as _sys
if len(_sys.argv) == 3:                      # override: python ... 4.40 4.45
    BAND = (float(_sys.argv[1]), float(_sys.argv[2]))


def D(N):
    return P / math.sin(math.pi / N)


def env_dia(N):
    return 2 * (D(N) / 2 + PLATE_H)


def chain_len(a, b, C=C0):
    return 2 * C / P + (a + b) / 2 + ((b - a) / (2 * math.pi)) ** 2 * P / C


def C_for(a, b, Lt):
    A = 2 / P
    B = (a + b) / 2 - Lt
    Cc = ((b - a) / (2 * math.pi)) ** 2 * P
    return (-B + math.sqrt(B * B - 4 * A * Cc)) / (2 * A)


def loss_pct(a, b, mu=0.10):
    """Articulation friction loss. mu is a GUESS; the RANKING is mu-independent
    because mu multiplies every row identically."""
    return 100 * mu * (2 * math.pi * R_PIN / P) * (1 / a + 1 / b)


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
    with open(os.path.join(ROOT, "output", "gear_meeting_matrix.csv")) as f:
        M = sorted([{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)],
                   key=lambda r: r["ratio"])
    mr = [r["ratio"] for r in M]
    t75 = [r["t75_mu853"] for r in M]
    soc = [r["SOC98"] for r in M]

    base = (13, 30)
    base_loss = loss_pct(*base)

    rows = []
    for a in range(10, 21):
        for b in range(18, 50):
            g = GB * b / a
            if not (BAND[0] <= g <= BAND[1]):
                continue
            e = env_dia(b)
            L = chain_len(a, b)
            ev = 2 * round(L / 2)
            Cn = C_for(a, b, ev)
            rpm_at_same_v = W_MAX * g
            rows.append({
                "driver": a, "driven": b, "ratio": g,
                "env_dia_mm": e,
                "fits": "YES" if e <= ENV_CAP + 0.05 else "NO",
                "chain_tension_N": T_SHAFT / (D(a) / 2 / 1000),
                "chordal_pct": 100 * (1 - math.cos(math.pi / a)),
                "chain_loss_pct": loss_pct(a, b),
                "chain_loss_vs_now_pct": 100 * (loss_pct(a, b) / base_loss - 1),
                "max_rpm_at_same_speed": rpm_at_same_v,
                "redline_ok": "YES" if rpm_at_same_v <= REDLINE else "NO",
                "chain_pitches": ev,
                "axle_move_mm": Cn - C0,
                "t75_s": interp(mr, t75, g),
                "SOC98": interp(mr, soc, g),
                "keeps_30T_driven": "YES" if b == 30 else "no",
                "driver_is_13T": "YES" if a == 13 else "no",
            })

    # verdict: hard gates first, then rank
    for r in rows:
        why = []
        if r["fits"] == "NO":
            why.append("driven too big for the envelope")
        if r["redline_ok"] == "NO":
            why.append("still over redline at the same road speed")
        if r["driver"] < 13:
            why.append("driver below 13T, chain life and chordal get worse")
        r["blockers"] = "; ".join(why) if why else ""
        r["viable"] = "YES" if not why else "NO"

    viable = [r for r in rows if r["viable"] == "YES"]
    viable.sort(key=lambda r: r["chain_loss_pct"])
    rows.sort(key=lambda r: (r["viable"] != "YES", r["chain_loss_pct"]))

    print("=" * 108)
    print("CHAIN + SPROCKET CONFIGS IN THE %.2f-%.2f BAND" % BAND)
    print("envelope cap %.1f mm dia | redline %d | current 13T/30T = %.4f" % (ENV_CAP, REDLINE, GB * 30 / 13))
    print("=" * 108)
    print("%-9s %-8s %-8s %-6s %-9s %-8s %-9s %-8s %-8s %-7s" % (
        "combo", "ratio", "envDIA", "fits", "chainLoss", "vs now", "rpm@same v", "chain", "axle", "OK?"))
    for r in rows:
        print("%-9s %-8.4f %-8.1f %-6s %-9.4f %+-8.1f%% %-9.0f %-8s %+-8.2f %-7s" % (
            "%dT/%dT" % (r["driver"], r["driven"]), r["ratio"], r["env_dia_mm"], r["fits"],
            r["chain_loss_pct"], r["chain_loss_vs_now_pct"], r["max_rpm_at_same_speed"],
            "%dp" % r["chain_pitches"], r["axle_move_mm"], r["viable"]))
    print()
    if viable:
        w = viable[0]
        print("BEST VIABLE: %dT/%dT at %.4f" % (w["driver"], w["driven"], w["ratio"]))
        print("  chain loss %.4f%% (%+.1f%% vs the 13T/30T on the car)"
              % (w["chain_loss_pct"], w["chain_loss_vs_now_pct"]))
        print("  chain tension %.0f N, chordal ripple %.2f%%" % (w["chain_tension_N"], w["chordal_pct"]))
        print("  max rpm %.0f at the same road speed, under %d" % (w["max_rpm_at_same_speed"], REDLINE))
        print("  %d-pitch chain, axle moves %+.2f mm, keeps the 30T driven: %s"
              % (w["chain_pitches"], w["axle_move_mm"], w["keeps_30T_driven"]))
    print()
    print("BLOCKED:")
    for r in rows:
        if r["viable"] == "NO":
            print("  %dT/%dT %.4f -- %s" % (r["driver"], r["driven"], r["ratio"], r["blockers"]))

    tag = "" if abs(BAND[0]-4.28) < 1e-9 else "_%.2f_%.2f" % BAND
    out = os.path.join(ROOT, "output", "chain_config_ranking%s.csv" % tag)
    with open(out, "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        wr.writeheader()
        for r in rows:
            wr.writerow({k: (round(v, 4) if isinstance(v, float) else v) for k, v in r.items()})
    print("\nSaved", out)


if __name__ == "__main__":
    main()

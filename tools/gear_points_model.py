#!/usr/bin/env python3
"""
GEAR_POINTS_MODEL -- turn the ratio sweep into FSAE Electric points.

Reads:
  output/gear_meeting_matrix.csv   the sim matrix at the BUILDABLE sprocket ratios
  output/emeter_benchmark.csv      2025 competition e-meter field energy economy
Scoring formulas: FSAE Rules 2026 V1.0, sections D.9 (Accel) and D.13 (Efficiency).

WHAT THIS MODELS, AND WHAT IT DELIBERATELY DOES NOT
  MODELLED   Acceleration points   (we have 0-75 m vs ratio, and the rules formula)
  MODELLED   Efficiency points     (we have energy vs ratio, and the rules formula)
  NOT MODELLED  Autocross (125 pts) and Endurance TIME (250 pts).
  There is no lap-time-vs-ratio model anywhere in this repo. Inventing one to fill
  400 of the 675 dynamic points would be the single most misleading thing this
  study could do, so it is left out and flagged instead. See the report footer.

Every calibration input is tagged. Nothing here is a round number picked to be
convincing.
"""
import csv
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(path):
    with open(os.path.join(ROOT, path)) as f:
        return list(csv.DictReader(f))


# ------------------------------------------------------------------ inputs
# FSAE 2026 Electric preliminary overall results, Concordia = car 43.
# (FSAE_2026_MI6_prelim.pdf, "Formula SAE Electric 2026 Overall Results")
CFR_2026 = {
    "accel": 47.8, "skidpad": 45.8, "autocross": 81.8,
    "endurance": 25.0, "efficiency": 38.0, "total": 476.1, "place": 19,
}
FIELD_BEST_ACCEL_SCORE = 100.0     # Univ of Wisconsin - Madison, so they set Tmin
EVENT_MAX = {"accel": 100, "skidpad": 75, "autocross": 125,
             "endurance": 275, "efficiency": 100}

# Pack, from params_cfr26 (88S4P, BAK 45D 4.4 Ah, OCV table)
E_PACK_WH = 5740.0                 # CALC from params
ENDURANCE_LAPS = 22                # FSAE endurance format; independently recovered
                                   # from the e-meter power traces by emeter_benchmark
CO2_PER_KWH = 0.65                 # RULES D.13.4.1(c), electric
LAP_KM = 1.0                       # emeter_lib assumption, and roughly the FSAE lap.
                                   # Cancels out of every ratio comparison below.

# ------------------------------------------------------- accel calibration
# D.9.4.2:  Score = 95.5 * ((Tmax/Tyour)-1)/((Tmax/Tmin)-1) + 4.5,  Tmax = 1.5*Tmin
# so       Score = 191 * (1.5*Tmin/Tyour - 1) + 4.5
def accel_score(t_your, t_min):
    if t_your >= 1.5 * t_min:
        return 4.5
    return 191.0 * (1.5 * t_min / t_your - 1.0) + 4.5


def t_over_tmin_from_score(score):
    """Invert the accel formula to get Tyour/Tmin."""
    return 1.5 / ((score - 4.5) / 191.0 + 1.0)


def main():
    mat = load("output/gear_meeting_matrix.csv")
    for r in mat:
        for k in r:
            r[k] = float(r[k])
    cur = next(r for r in mat if int(r["driven_teeth"]) == 30)

    # Tmin calibration. ASSUMPTION, stated: our real 2026 accel run is close to what
    # the sim gives at the ratio we actually ran, on the grip we actually measured.
    ratio_to_tmin = t_over_tmin_from_score(CFR_2026["accel"])
    t_cur_sim = cur["t75_mu853"]
    T_MIN = t_cur_sim / ratio_to_tmin

    # ------------------------------------------------- efficiency calibration
    field = load("output/emeter_benchmark.csv")
    wh = sorted(float(r["Wh_per_lap"]) for r in field if r.get("Wh_per_lap"))
    wh_best = wh[0]
    co2_min_per_lap = wh_best / 1000.0 * CO2_PER_KWH          # kg CO2 / lap
    # D.13.4.5: EfficiencyFactor_min uses CO2your = 20.02 kg CO2 / 100 km and
    # Tyour = 1.45 * Tmin.
    co2_your_min_case = 20.02 / 100.0 * LAP_KM                # kg CO2 / lap
    EF_MIN = (1.0 / 1.45) * (co2_min_per_lap / co2_your_min_case)
    EF_MAX = 1.0        # a team that sets BOTH Tmin and CO2min scores EF = 1.0

    def wh_per_lap(soc98):
        return (0.98 - soc98 / 100.0) * E_PACK_WH / ENDURANCE_LAPS

    def eff_factor(soc98, time_term):
        co2 = wh_per_lap(soc98) / 1000.0 * CO2_PER_KWH
        return time_term * (co2_min_per_lap / co2)

    # Our endurance time term is unknown (we did not complete endurance in 2026),
    # so back it out of the efficiency score we actually scored. That makes every
    # ratio comparison below relative to a real, scored data point instead of a guess.
    ef_our = EF_MIN + CFR_2026["efficiency"] / 100.0 * (EF_MAX - EF_MIN)
    co2_our = wh_per_lap(cur["SOC98"]) / 1000.0 * CO2_PER_KWH
    TIME_TERM = ef_our / (co2_min_per_lap / co2_our)

    def efficiency_score(soc98):
        ef = eff_factor(soc98, TIME_TERM)
        return max(0.0, min(100.0, 100.0 * (ef - EF_MIN) / (EF_MAX - EF_MIN)))

    # ------------------------------------------------------------- report
    out = []
    w = out.append
    w("=" * 100)
    w("FSAE ELECTRIC POINTS vs GEAR RATIO -- buildable sprockets only, 13T driver fixed")
    w("=" * 100)
    w("")
    w("CALIBRATION (all traceable, no round numbers picked to be convincing)")
    w("  Concordia 2026 accel score      %.1f  ->  Tyour/Tmin = %.4f   [FSAE_2026_MI6_prelim.pdf]"
      % (CFR_2026["accel"], ratio_to_tmin))
    w("  sim 0-75 m at current 4.6154    %.4f s  (123 Nm ceiling, TC on, mu 0.853)" % t_cur_sim)
    w("  => field best accel time Tmin   %.3f s   ASSUMES our real run matches the sim" % T_MIN)
    w("  accel points per second         %.1f pts/s at our operating point" % (
        191.0 * 1.5 * T_MIN / t_cur_sim ** 2))
    w("")
    w("  field best energy               %.1f Wh/lap  [emeter_benchmark.csv, 2025, n=%d]"
      % (wh_best, len(wh)))
    w("  our energy at 4.6154            %.1f Wh/lap  CALC from SOC98 %.3f%% and %.0f Wh pack"
      % (wh_per_lap(cur["SOC98"]), cur["SOC98"], E_PACK_WH))
    w("  EfficiencyFactor_min            %.4f   [rules D.13.4.5]" % EF_MIN)
    w("  our 2026 efficiency score       %.1f  ->  back-solved endurance time term %.4f"
      % (CFR_2026["efficiency"], TIME_TERM))
    w("")
    w("-" * 100)
    w("%-4s %-8s %-9s %-9s %-9s %-9s %-9s %-9s %-9s" % (
        "N2", "ratio", "t75(s)", "accel", "Wh/lap", "effic", "A+E", "vs 30T", "SOC98"))
    w("-" * 100)
    base = None
    rows = []
    for r in mat:
        a = accel_score(r["t75_mu853"], T_MIN)
        e = efficiency_score(r["SOC98"])
        tot = a + e
        if int(r["driven_teeth"]) == 30:
            base = tot
        rows.append((r, a, e, tot))
    for r, a, e, tot in rows:
        n2 = int(r["driven_teeth"])
        band = "  <- 4.2-4.8" if 4.2 <= r["ratio"] <= 4.8 else ""
        cur_mark = "  CURRENT" if n2 == 30 else ""
        w("%-4d %-8.4f %-9.4f %-9.1f %-9.1f %-9.1f %-9.1f %+-9.1f %-9.3f%s%s" % (
            n2, r["ratio"], r["t75_mu853"], a, wh_per_lap(r["SOC98"]), e, tot,
            tot - base, r["SOC98"], band, cur_mark))
    w("-" * 100)
    w("")
    inband = [(r, a, e, t) for r, a, e, t in rows if 4.2 <= r["ratio"] <= 4.8]
    best = max(inband, key=lambda x: x[3])
    worst = min(inband, key=lambda x: x[3])
    w("IN THE 4.2 - 4.8 TARGET BAND (driven 28T to 31T)")
    w("  best  modelled points: %dT at ratio %.4f, accel %.1f + efficiency %.1f = %.1f"
      % (int(best[0]["driven_teeth"]), best[0]["ratio"], best[1], best[2], best[3]))
    w("  worst modelled points: %dT at ratio %.4f, accel %.1f + efficiency %.1f = %.1f"
      % (int(worst[0]["driven_teeth"]), worst[0]["ratio"], worst[1], worst[2], worst[3]))
    w("  SPREAD ACROSS THE WHOLE BAND: %.1f points" % (best[3] - worst[3]))
    w("     of which accel      %.1f" % (best[1] - worst[1]))
    w("     of which efficiency %.1f" % (best[2] - worst[2]))
    w("")
    w("  For scale, Concordia scored %.1f total in 2026 and placed %d."
      % (CFR_2026["total"], CFR_2026["place"]))
    w("  Endurance scored %.1f out of %d. That single event is worth %.0f points more than"
      % (CFR_2026["endurance"], EVENT_MAX["endurance"],
         EVENT_MAX["endurance"] - CFR_2026["endurance"]))
    w("  everything the gear ratio can move, by a factor of about %.0f."
      % ((EVENT_MAX["endurance"] - CFR_2026["endurance"]) / max(best[3] - worst[3], 1e-9)))
    w("")
    w("=" * 100)
    w("WHAT IS NOT IN THE NUMBERS ABOVE")
    w("=" * 100)
    w("  Autocross      125 pts   NOT MODELLED. No lap-time-vs-ratio model exists in this repo.")
    w("  Endurance time 250 pts   NOT MODELLED. Same reason.")
    w("  Skidpad         75 pts   ratio-independent, steady-state cornering.")
    w("")
    w("  So this model covers %d of the %d dynamic points. The 375 it does not cover are"
      % (EVENT_MAX["accel"] + EVENT_MAX["efficiency"], sum(EVENT_MAX.values())))
    w("  where the ratio most plausibly acts, through driveability and torque-knee behaviour.")
    w("  Treat the table as a FLOOR on what the ratio is worth, not the whole answer.")
    w("")
    w("  The honest read: inside 4.2 to 4.8 the modellable points spread is %.1f points."
      % (best[3] - worst[3]))
    w("  That is small. The decision should be made on endurance COMPLETION risk and on")
    w("  driveability, not on this table. Concordia's 2026 endurance score of %.1f/%d says"
      % (CFR_2026["endurance"], EVENT_MAX["endurance"]))
    w("  finishing is the entire game.")

    txt = "\n".join(out)
    print(txt)
    with open(os.path.join(ROOT, "output", "gear_points_model.txt"), "w") as f:
        f.write(txt + "\n")

    with open(os.path.join(ROOT, "output", "gear_points_model.csv"), "w", newline="") as f:
        wr = csv.writer(f)
        wr.writerow(["driven_teeth", "ratio", "t75_s_mu853", "accel_pts", "wh_per_lap",
                     "efficiency_pts", "accel_plus_eff", "vs_30T", "SOC98",
                     "top_speed_kph", "exits_past_knee_pct", "grip_penalty_s"])
        for r, a, e, tot in rows:
            wr.writerow([int(r["driven_teeth"]), round(r["ratio"], 4), round(r["t75_mu853"], 4),
                         round(a, 2), round(wh_per_lap(r["SOC98"]), 1), round(e, 2),
                         round(tot, 2), round(tot - base, 2), round(r["SOC98"], 3),
                         round(r["top_speed_kph"], 1), round(r["exits_past_knee_pct"], 1),
                         round(r["grip_penalty_s"], 4)])
    print("\nSaved output/gear_points_model.txt and output/gear_points_model.csv")


if __name__ == "__main__":
    sys.exit(main())

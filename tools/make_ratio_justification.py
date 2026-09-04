#!/usr/bin/env python3
"""Builds docs/RATIO_4p3_JUSTIFICATION.md -- the hand-over for the mech tech."""
import csv
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P, PH, C0, GB, T = 15.875, 7.2517, 152.08, 2.000, 300.0
W = 6083 / 4.61
ROLLER = 10.16


def D(N):
    return P / math.sin(math.pi / N)


def OD(N):
    return P * (0.6 + 1 / math.tan(math.pi / N))


def env(N):
    return D(N) + 2 * PH


def L(a, b, C=C0):
    return 2 * C / P + (a + b) / 2 + ((b - a) / (2 * math.pi)) ** 2 * P / C


def Cfor(a, b, Lt):
    A = 2 / P
    B = (a + b) / 2 - Lt
    Cc = ((b - a) / (2 * math.pi)) ** 2 * P
    return (-B + math.sqrt(B * B - 4 * A * Cc)) / (2 * A)


def wrap(a, b, C):
    return 180 - 2 * math.degrees(math.asin((D(b) - D(a)) / (2 * C)))


def tens(a):
    return T / (D(a) / 2 / 1000)


def chordal(a):
    return 100 * (1 - math.cos(math.pi / a))


def loss(a, b):
    return 100 * 0.10 * (2 * math.pi * 2.54 / P) * (1 / a + 1 / b)


with open(os.path.join(ROOT, "output", "gear_meeting_matrix.csv")) as f:
    M = sorted([{k: float(v) for k, v in r.items()} for r in csv.DictReader(f)], key=lambda r: r["ratio"])
mr = [r["ratio"] for r in M]


def ip(x, k):
    ys = [r[k] for r in M]
    if x <= mr[0]:
        return ys[0]
    if x >= mr[-1]:
        return ys[-1]
    for i in range(len(mr) - 1):
        if mr[i] <= x <= mr[i + 1]:
            t = (x - mr[i]) / (mr[i + 1] - mr[i])
            return ys[i] + t * (ys[i + 1] - ys[i])
    return ys[-1]


L_ = []
w = L_.append
w("# Why the final drive is going to 4.3")
w("")
w("Hand-over note for the mech tech. Every number here is either measured off our own car")
w("and our own logs, or computed from measured inputs. Nothing is a catalogue guess.")
w("")
w("## The one-sentence version")
w("")
w("**We are running the motor past its rev limiter, and at our 150 Nm map longer gearing is")
w("faster and more efficient at the same time.** 4.3 is the longest ratio we can actually build")
w("with the 13T driver we already own.")
w("")
w("## 1. The actual problem")
w("")
w("From our own June 20 competition log, motor speed channel:")
w("")
w("| | Value |")
w("|---|---|")
w("| Redline | 6000 rpm |")
w("| **Measured peak motor speed** | **6083 rpm** |")
w("| p99 motor speed | 5715 rpm |")
w("| Share of motoring time over 6000 | 0.43% |")
w("")
w("This is not a simulation result. It is the logged motor speed channel. We built a second,")
w("independent estimate from the four wheel-speed sensors scaled by the gear ratio and it")
w("agrees with the measured peak to **0.1%**, so it is not a sensor glitch either.")
w("")
w("At 4.6154 we are **83 rpm over the limiter**, repeatedly.")
w("")
w("## 2. What longer gearing does to the rpm")
w("")
w("Motor rpm at a given road speed scales with the ratio alone:")
w("")
w("```")
w("rpm_new = 6083 x (new ratio / 4.6154)")
w("```")
w("")
w("Wheel rpm is motor rpm divided by ratio, which is exact, so the rolling radius cancels out")
w("of this. Radius only sets what ROAD SPEED a given rpm corresponds to, not how rpm moves when")
w("you change the gearing.")
w("")
w("| Ratio | rpm at the same road speed | vs 6000 |")
w("|---|---|---|")
w("| 4.6154 (now) | **6083** | **+83 over** |")
w("| 4.4615 | 5880 | -120 |")
w("| 4.4286 | 5837 | -163 |")
w("| 4.4000 | 5799 | -201 |")
w("| **4.3077** | **5677** | **-323** |")
w("| 4.2857 | 5648 | -352 |")
w("")
w("**Correction on the record.** An earlier version of this study claimed a redline ceiling of")
w("4.3197 based on a loaded rolling radius, and used it to rule out the whole 4.40 to 4.45 band.")
w("That was wrong: it multiplied a wheel speed that had already been derived from the measured")
w("motor rpm by a radius correction, double counting. **4.40 and 4.44 do not break the redline.**")
w("Anyone who saw the earlier number should drop it.")
w("")
w("One caveat that does survive, and it cuts the other way: at 6000 to 6200 rpm the car is still")
w("making **35 to 40 Nm**, so it is not sitting on a soft limiter, it ran out of straight. That")
w("means with longer gearing the car will reach a **higher road speed** at that point and the rpm")
w("will partially recover. The real reduction is smaller than the table above suggests. We do not")
w("have a model of that specific straight to say by how much.")
w("")
w("## 3. So why 4.3 and not 4.4")
w("")
w("Not the redline. **Buildability.**")
w("")
w("**4.40 does not exist with our 13T driver.** 4.40 x 13 / 2 = 28.6 teeth. The nearest we can")
w("make is 28T at 4.3077 or 29T at 4.4615. There is no 4.40 to buy.")
w("")
w("Every combination that does reach 4.40 needs either a new driving sprocket or more rear room")
w("than the chassis has:")
w("")
w("| Combo | Ratio | Blocker |")
w("|---|---|---|")
w("| 15T/33T | 4.4000 | driven needs 181.5 mm, chassis cap is 171.4 |")
w("| 20T/44T | 4.4000 | driven needs 237.0 mm |")
w("| 10T/22T | 4.4000 | fits, but a 10T driver is +32% chain loss and 4.89% chordal ripple |")
w("| 14T/31T | 4.4286 | **viable**, but needs a 14T in the splined bore and uses the full envelope with zero margin |")
w("")
w("So the choice is between things we can actually build: **13T/28T at 4.3077**, which needs no")
w("new driving sprocket, and **14T/30T or 14T/31T**, which both depend on sourcing a 14T in the")
w("6-lobe spline bore that nobody has confirmed exists.")
w("")
w("**We took 13T/28T because it carries no sourcing risk on a freeze decision.** It also pulls")
w("the most rpm out of the top end and frees the most rear envelope. If purchasing finds a 14T")
w("before anything is cut, 14T/31T at 4.4286 is the better drive on chain loss and is worth")
w("reopening.")
w("")
w("## 4. It costs us nothing on performance")
w("")
w("This is the part people assume is a trade, and at our torque map it is not.")
w("")
w("We run **150 Nm**, with 160 to 170 Nm bursts on accel. At that torque the car is")
w("**traction limited, not torque limited** -- the tyre gives up before the motor does. Both")
w("our MATLAB sim and the independent OptimumLap model agree: with the car traction limited,")
w("gearing shorter just spins the tyre harder. Longer gearing is **faster and more efficient at")
w("the same time**.")
w("")
w("| | 4.6154 now | 4.3077 | change |")
w("|---|---|---|---|")
w("| 0-75 m (150 Nm map) | 4.9083 s | 4.8772 s | **0.031 s quicker** |")
w("| Energy per lap | 271.0 Wh | 270.0 Wh | **0.4% less** |")
w("| Final SOC | 5.98% | 6.25% | **+0.27 pts** |")
w("| Top speed | 98.0 kph | 105.0 kph | **+7 kph** |")
w("| Corner exits past the torque knee | 37.2% | 30.0% | **better driveability** |")
w("")
w("Note the top speed line. Today we are **on the limiter at the trap**, so the extra gearing")
w("is not buying acceleration, it is just running out of revs earlier.")
w("")
w("## 5. It helps the thing that actually broke")
w("")
w("The 2026 endurance DNF was a **battery pack overheat**. Motor and inverter temps were fine.")
w("")
w("Pack heating goes as pack current squared. Mechanical power at the wheel does not change")
w("with gear ratio, so pack current only moves through motor efficiency:")
w("")
w("| Ratio | Pack heat vs now |")
w("|---|---|")
w("| **4.3077** | **-0.69%** |")
w("| 4.6154 (now) | 0 |")
w("| 4.7692 | +1.24% |")
w("| 5.2308 | +9.28% |")
w("")
w("**Be straight about this in the room: 0.69% does not fix a pack cooling problem. Cooling")
w("does.** But the direction matters. Gearing *shorter* would have made the pack worse by 1 to")
w("9%, so this decision at least does not fight the fix.")
w("")
w("The cost of gearing longer is **+14.8% copper loss in the motor windings**. That is real, and")
w("it lands in the one place we have measured thermal margin.")
w("")
w("## 6. It is not about points")
w("")
w("Worth saying before someone asks. Across the whole 4.2 to 4.8 band the FSAE points swing is")
w("about **6 points**, and 4.3 is worth roughly **+1.7** against what we run now. For scale, we")
w("scored 476.1 total in 2026 and lost **250 points** on the endurance DNF.")
w("")
w("**We are not changing the ratio for points. We are changing it because we are over the rev")
w("limiter.** If the points had gone the other way the answer would still be 4.3.")
w("")
w("## 7. The two buildable configs")
w("")
w("Both keep the existing diff mounting (45.60 bore, 6 x dia 6.31 on a 92.69 BCD) and both fit")
w("inside the 171.4 mm envelope given to chassis.")
w("")
hdr = ["", "**13T / 28T**", "**14T / 30T**", "current 13T/30T"]
w("| " + " | ".join(hdr) + " |")
w("|---|---|---|---|")
rows = [
    ("Total ratio", lambda a, b: "%.4f" % (GB * b / a)),
    ("Driver pitch dia", lambda a, b: "%.3f mm" % D(a)),
    ("Driver OD", lambda a, b: "%.3f mm" % OD(a)),
    ("Driven pitch dia", lambda a, b: "%.3f mm" % D(b)),
    ("Driven OD", lambda a, b: "%.3f mm" % OD(b)),
    ("Driven root dia", lambda a, b: "%.3f mm" % (D(b) - ROLLER)),
    ("Chain envelope dia", lambda a, b: "%.1f mm" % env(b)),
    ("Envelope margin", lambda a, b: "%+.1f mm" % (171.4 - env(b))),
    ("Chain length", lambda a, b: "%.2f -> %d pitches" % (L(a, b), 2 * round(L(a, b) / 2))),
    ("Centre distance needed", lambda a, b: "%.2f mm" % Cfor(a, b, 2 * round(L(a, b) / 2))),
    ("**Axle move from 152.08**", lambda a, b: "**%+.2f mm**" % (Cfor(a, b, 2 * round(L(a, b) / 2)) - C0)),
    ("Wrap on driver", lambda a, b: "%.1f deg" % wrap(a, b, Cfor(a, b, 2 * round(L(a, b) / 2)))),
    ("Chain tension @150 Nm", lambda a, b: "%.0f N" % tens(a)),
    ("Chordal ripple", lambda a, b: "%.2f%%" % chordal(a)),
    ("Chain friction loss", lambda a, b: "%.4f%%" % loss(a, b)),
    ("Max rpm free / loaded", lambda a, b: "%.0f / %.0f" % (W * GB * b / a, W * GB * b / a * 0.2 / 0.19)),
    ("0-75 m", lambda a, b: "%.4f s" % ip(GB * b / a, "t75_mu853")),
    ("Final SOC", lambda a, b: "%.3f%%" % ip(GB * b / a, "SOC98")),
    ("Top speed", lambda a, b: "%.1f kph" % ip(GB * b / a, "top_speed_kph")),
]
for lbl, f in rows:
    w("| %s | %s | %s | %s |" % (lbl, f(13, 28), f(14, 30), f(13, 30)))
w("")
w("### DECISION: 13T driver / 28T driven, ratio 4.3077")
w("")
w("**The 13T DRIVING sprocket stays.** It is the one on the splined gearbox output shaft")
w("(`DT-P2127`). No change, no new part, no spline sourcing risk.")
w("")
w("**The DRIVEN sprocket on the diff goes 30T to 28T.** That is the only part being made.")
w("")
w("| Action | Detail |")
w("|---|---|")
w("| Make | 28T driven sprocket, 520 chain, OD 150.420 mm, bore 45.60, 6 x dia 6.31 on 92.69 BCD |")
w("| Shorten | chain from 42 to 40 pitches, two links out |")
w("| Move | diff in 2.09 mm, centre distance 152.08 to 149.99 |")
w("| Keep | 13T driver, splined shaft, diff carrier, bolt pattern, chain tension, wrap |")
w("")
w("This was chosen over 14T/30T because 14T/30T depends on sourcing a 14T in the 6-lobe spline")
w("bore, which is an unresolved supply question, and because 13T/28T frees 15.1 mm of rear")
w("envelope against 5.0 mm. The cost is that chain tension and chordal ripple stay exactly where")
w("they are today rather than improving 7% and 14%. That is a fair trade for removing a")
w("single-point supply risk from a freeze decision.")
w("")
w("### The alternative, for the record")
w("")
w("**14T / 30T at 4.2857** keeps the 30T driven and the 42-pitch chain, moves the axle 1.34 mm,")
w("and cuts chain tension 7% and chordal ripple 14%. It is mechanically the better drive. It is")
w("NOT the pick only because it needs a 14T in the 6-lobe 21.0 / 25.0 / 5.0 spline bore and")
w("nobody has confirmed that part exists. If purchasing finds one before anything is cut, it is")
w("worth reopening.")
w("")
w("Everything else in the band is blocked: a 15T or bigger driver forces a driven sprocket too")
w("big for the chassis, and a 12T or smaller driver makes chain tension and chordal action worse")
w("than the 13T we already call a compromise.")
w("")
w("## 8. The spline, for whoever orders the driver")
w("")
w("Measured off `DT-P2120.STEP` (the sprocket) and `DT-P2127.STEP` (the shaft):")
w("")
w("| Feature | Sprocket bore (female) | Shaft (male) |")
w("|---|---|---|")
w("| Minor diameter | 21.000 mm | 20.873 mm |")
w("| Major diameter | 25.000 mm | 24.700 mm |")
w("| Form | 6 lobes at 60 deg, 5.000 mm slot | — |")
w("| Sprocket thickness | 5.850 mm | — |")
w("")
w("The diameters mate with normal spline clearance (0.13 to 0.30 mm). **Before ordering a 14T,")
w("confirm the flank form against a physical part.** We resolved the female bore as straight")
w("sided flat flanks, but the flank geometry on the shaft file did not come through cleanly")
w("enough to state it as fact, and a spline that is right on diameter and wrong on form will")
w("not go on.")
w("")
w("## 9. What is still open")
w("")
w("| # | Item | Who |")
w("|---|---|---|")
w("| 1 | Confirm the motor/inverter rpm rating -- is 6000 hard? | electrical |")
w("| 2 | Confirm a 14T exists in the 6-lobe spline bore | purchasing |")
w("| 3 | Confirm the spline flank form off a physical part | mech |")
w("| 4 | Pack cooling, which is the real endurance fix | not a drivetrain job |")
w("")
w("Item 2 is the one that could still change the build: if a 14T exists in the spline bore,")
w("14T/31T at 4.4286 is a better drive than what we picked (6.0% less chain loss against 2.2%")
w("more) and is worth reopening before anything is cut.")

qa = os.path.join(ROOT, "docs", "_ratio_qa_block.md")
if os.path.exists(qa):
    with open(qa, encoding="utf-8") as f:
        L_.append(f.read().rstrip())

path = os.path.join(ROOT, "docs", "RATIO_4p3_JUSTIFICATION.md")
with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(L_) + "\n")
print("wrote", path, len(L_), "lines")

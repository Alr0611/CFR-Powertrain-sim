"""Builds CFR27_Sprocket_Study.xlsx -- live formulas, PASS/FAIL, custom tooth input.

Every input cell traces to the CFR24 sheets, the Emrax 208, or Mott. Nothing invented.
Centre distance and packaging clearance are NOT in any CFR24 sheet, so they are left
blank and every check that depends on them says so instead of guessing.
"""
import csv
import os

import openpyxl
from openpyxl.formatting.rule import FormulaRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side

HDR = PatternFill("solid", fgColor="1F3864")
SUB = PatternFill("solid", fgColor="D9E2F3")
INP = PatternFill("solid", fgColor="FFF2CC")   # yellow = type here
UNK = PatternFill("solid", fgColor="FCE4D6")   # orange = measure this
CUR = PatternFill("solid", fgColor="E2EFDA")   # green = on the car now
WF = Font(color="FFFFFF", bold=True)
B = Font(bold=True)
IT = Font(italic=True, size=9, color="555555")
_t = Side(style="thin", color="B0B0B0")
BOX = Border(left=_t, right=_t, top=_t, bottom=_t)
WRAP = Alignment(wrap_text=True, vertical="top")
CTR = Alignment(horizontal="center", vertical="center")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
wb = openpyxl.Workbook()


def widths(ws, spec):
    for col, val in spec.items():
        ws.column_dimensions[col].width = val


def banner(ws, row, text, span):
    c = ws.cell(row, 1, text)
    c.font = WF
    c.fill = HDR
    c.alignment = Alignment(vertical="center", horizontal="left")
    ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=span)
    ws.row_dimensions[row].height = 20


# ============================ SHEET 1: CALC ============================
ws = wb.active
ws.title = "Sprocket Calc"
widths(ws, {"A": 30, "B": 12, "C": 13, "D": 13, "E": 13, "F": 13,
            "G": 11, "H": 12, "I": 17, "J": 18, "K": 15, "L": 34})

banner(ws, 1, "CFR27 FINAL DRIVE SPROCKET STUDY   |   chain geometry per Mott Ch.7", 12)
n = ws.cell(2, 1, "Yellow = inputs, type in them. Orange = UNKNOWN, must be measured before the fit check means "
                  "anything. Green row = what is on the car now. Driver stays 13T, only the driven sprocket changes.")
n.font = IT
n.alignment = WRAP
ws.merge_cells("A2:L2")
ws.row_dimensions[2].height = 28

banner(ws, 4, "FIXED INPUTS", 12)
inputs = [
    ("Chain number", 520, "", "from-SHEET", "KHK Sheet1!B11 / Euro Sheet1!B11"),
    ("Chain pitch P", 0.625, "in", "from-SHEET", "Sprocket Gearing and Forces!C9"),
    ("Chain pitch P", 15.875, "mm", "from-SHEET", "Sprocket Gearing and Forces!C11"),
    ("Driver teeth N1", 13, "T", "from-SHEET", "Sprocket...!M8   KEEP THIS, do not sweep it"),
    ("Gearbox ratio", 2.000, "", "from-SHEET", "15:30, Gear Design!D15/D16/D17"),
    ("Motor peak torque", 150, "Nm", "OWNER", "Emrax 208"),
    ("Motor transient torque", 170, "Nm", "OWNER", "steps up to 160-170 in enduro/accel"),
    ("Motor peak power", 68, "kW", "OWNER", "Emrax 208"),
    ("Max motor speed", 6500, "rpm", "from-SHEET", "Sprocket...!M21"),
    ("Chain avg tensile", 27.134, "kN", "DATASHEET", "Mott T7-12 no.50 = 6100 lb, stand-in for 520"),
    ("Service factor", 1.3, "", "DATASHEET", "Mott T7-17, electric motor + moderate shock"),
    ("Min wrap angle", 120, "deg", "DATASHEET", "Mott guidance, flag below this"),
]
r = 5
for lbl, val, unit, tag, src in inputs:
    ws.cell(r, 1, lbl).font = B
    c = ws.cell(r, 2, val)
    c.fill = INP
    c.border = BOX
    c.alignment = CTR
    ws.cell(r, 3, unit).alignment = CTR
    ws.cell(r, 4, tag).font = IT
    ws.cell(r, 5, src).font = IT
    ws.merge_cells(start_row=r, start_column=5, end_row=r, end_column=12)
    r += 1

P, N1, GB = "$B$7", "$B$8", "$B$9"
TPK, TTR, PWR = "$B$10", "$B$11", "$B$12"
TENS, SF, WMIN = "$B$14", "$B$15", "$B$16"

r += 1
banner(ws, r, "MEASURE THESE   |   the fit check is meaningless until they are filled in", 12)
mr = r + 1
for lbl, note in [
    ("Centre distance C", "13T centre to driven sprocket centre. NOT in any CFR24 sheet. Tape measure or CAD."),
    ("Radial clearance available", "From the 30T outer edge to the nearest hard point (chassis rail / floor / upright)."),
]:
    ws.cell(mr, 1, lbl).font = B
    c = ws.cell(mr, 2, None)
    c.fill = UNK
    c.border = BOX
    c.alignment = CTR
    ws.cell(mr, 3, "mm").alignment = CTR
    ws.cell(mr, 4, note).font = IT
    ws.merge_cells(start_row=mr, start_column=4, end_row=mr, end_column=12)
    mr += 1
C, CLR = "$B$" + str(r + 1), "$B$" + str(r + 2)

# ---------------------------- config table ----------------------------
tr = mr + 1
banner(ws, tr, "CONFIGS   |   driven sprocket sweep, 26T to 34T. Last row is yours to type into.", 12)
hr = tr + 1
heads = ["Driven teeth", "Total ratio", "Pitch dia D2 (mm)", "Outside dia OD2 (mm)",
         "Radius growth vs 30T (mm)", "Chain length (pitches)", "Pitches vs 30T",
         "Wrap on 13T (deg)", "Wrap check", "Fit check", "Chain parity", "VERDICT"]
for i, h in enumerate(heads, 1):
    c = ws.cell(hr, i, h)
    c.font = WF
    c.fill = HDR
    c.alignment = Alignment(wrap_text=True, horizontal="center", vertical="center")
    c.border = BOX
ws.row_dimensions[hr].height = 46

D30 = "(%s/SIN(PI()/30))" % P
D1F = "(%s/SIN(PI()/%s))" % (P, N1)
first = hr + 1
teeth = list(range(26, 35))


def fill_row(rr, acell, guard):
    """guard: extra blank-check prefix for the custom row."""
    g = guard
    ws.cell(rr, 2, "=IF(%s\"\",\"\",%s*%s/%s)" % (g, GB, acell, N1))
    ws.cell(rr, 3, "=IF(%s\"\",\"\",%s/SIN(PI()/%s))" % (g, P, acell))
    ws.cell(rr, 4, "=IF(%s\"\",\"\",%s*(0.6+1/TAN(PI()/%s)))" % (g, P, acell))
    ws.cell(rr, 5, "=IF(%s\"\",\"\",(C%d-%s)/2)" % (g, rr, D30))
    ws.cell(rr, 6, "=IF(OR(%s\"\",%s=\"\"),\"NEED C\",2*%s/%s+(%s+%s)/2+((%s-%s)/(2*PI()))^2*%s/%s)"
            % (g, C, C, P, N1, acell, acell, N1, P, C))
    ws.cell(rr, 7, "=IF(%s\"\",\"\",(%s-30)/2)" % (g, acell))
    ws.cell(rr, 8, "=IF(OR(%s\"\",%s=\"\"),\"NEED C\",180-2*DEGREES(ASIN(MIN(1,(C%d-%s)/(2*%s)))))"
            % (g, C, rr, D1F, C))
    ws.cell(rr, 9, "=IF(OR(%s\"\",%s=\"\"),\"NEED C\",IF(H%d>=%s,\"PASS\",\"FAIL\"))" % (g, C, rr, WMIN))
    ws.cell(rr, 10, "=IF(OR(%s\"\",%s=\"\"),\"NEED CLEARANCE\",IF(E%d<=%s,\"PASS\",\"FAIL\"))" % (g, CLR, rr, CLR))
    ws.cell(rr, 11, "=IF(%s\"\",\"\",IF(MOD(%s,2)=0,\"OK even\",\"OFFSET LINK\"))" % (g, acell))
    ws.cell(rr, 12, "=IF(%s\"\",\"type a tooth count in %s\",IF(OR(%s=\"\",%s=\"\"),"
                    "\"UNKNOWN - measure C and clearance\",IF(OR(I%d=\"FAIL\",J%d=\"FAIL\"),\"FAIL\","
                    "IF(K%d=\"OFFSET LINK\",\"PASS (needs offset link)\",\"PASS\"))))"
            % (g, acell, C, CLR, rr, rr, rr))
    for cc in range(1, 13):
        ws.cell(rr, cc).border = BOX
        ws.cell(rr, cc).alignment = CTR
    ws.cell(rr, 2).number_format = "0.0000"
    for cc in (3, 4, 5, 6, 8):
        ws.cell(rr, cc).number_format = "0.00"


for i, N in enumerate(teeth):
    rr = first + i
    ws.cell(rr, 1, N)
    fill_row(rr, "A%d" % rr, "A%d=" % rr)
    if N == 30:
        for cc in range(1, 13):
            ws.cell(rr, cc).fill = CUR
        ws.cell(rr, 1).font = B
        ws.cell(rr, 1, 30)

lbl_row = first + len(teeth)
c = ws.cell(lbl_row, 1, "TYPE YOUR OWN TOOTH COUNT IN THE YELLOW CELL BELOW  ->")
c.font = B
c.fill = SUB
ws.merge_cells(start_row=lbl_row, start_column=1, end_row=lbl_row, end_column=12)

cr = lbl_row + 1
ws.cell(cr, 1, 31).fill = INP
fill_row(cr, "A%d" % cr, "A%d=" % cr)
ws.cell(cr, 1).border = BOX
ws.cell(cr, 1).alignment = CTR

fn = cr + 1
c = ws.cell(fn, 1, "Chain length must come out to an EVEN whole number of pitches. The column above gives the raw "
                   "value, round it and take up the difference on the tensioner. Even driven counts shift by a whole "
                   "pitch from the current 30T so they keep the same parity. Odd counts land on a half pitch, which "
                   "means an offset (half) link or pulling C in about 2 mm. Offset links are the weakest part of a "
                   "chain, so avoid them if an even sprocket gets you the same ratio band.")
c.font = IT
c.alignment = WRAP
ws.merge_cells(start_row=fn, start_column=1, end_row=fn + 2, end_column=12)

rng = "I%d:L%d" % (first, cr)
for txt, bg, fg in [("FAIL", "FFC7CE", "9C0006"), ("OFFSET", "FFEB9C", "9C6500"),
                    ("NEED", "FCE4D6", "974706"), ("UNKNOWN", "FCE4D6", "974706"),
                    ("PASS", "C6EFCE", "006100")]:
    ws.conditional_formatting.add(rng, FormulaRule(
        formula=['ISNUMBER(SEARCH("%s",I%d))' % (txt, first)],
        fill=PatternFill("solid", fgColor=bg), font=Font(color=fg, bold=True)))
ws.freeze_panes = "A%d" % first

# --------------------------- chain strength ---------------------------
sr = cr + 5
banner(ws, sr, "CHAIN STRENGTH   |   driver is 13T in every config, so tension does NOT change across the sweep", 12)
for j, h in enumerate(["Case", "Motor T (Nm)", "T at 13T (Nm)", "Tension (kN)", "Margin vs tensile", "Check"], 1):
    c = ws.cell(sr + 1, j, h)
    c.font = WF
    c.fill = HDR
    c.alignment = Alignment(wrap_text=True, horizontal="center", vertical="center")
    c.border = BOX
ws.row_dimensions[sr + 1].height = 30
for k, (lbl, src) in enumerate([("Nominal peak", TPK), ("Transient (enduro/accel)", TTR)]):
    rr = sr + 2 + k
    ws.cell(rr, 1, lbl)
    ws.cell(rr, 2, "=%s" % src)
    ws.cell(rr, 3, "=B%d*%s" % (rr, GB))
    ws.cell(rr, 4, "=2*C%d/(%s/1000)/1000" % (rr, D1F))
    ws.cell(rr, 5, "=%s/D%d" % (TENS, rr))
    ws.cell(rr, 6, '=IF(E%d>=2,"PASS","REVIEW")' % rr)
    for cc in range(1, 7):
        ws.cell(rr, cc).border = BOX
        ws.cell(rr, cc).alignment = CTR
    for cc in (3, 4, 5):
        ws.cell(rr, cc).number_format = "0.00"
ws.cell(sr + 2, 1).alignment = Alignment(horizontal="left", vertical="center")
ws.cell(sr + 3, 1).alignment = Alignment(horizontal="left", vertical="center")
ws.conditional_formatting.add("F%d:F%d" % (sr + 2, sr + 3), FormulaRule(
    formula=['F%d="PASS"' % (sr + 2)], fill=PatternFill("solid", fgColor="C6EFCE"),
    font=Font(color="006100", bold=True)))

pr = sr + 5
ws.cell(pr, 1, "Design power (SF x kW)").font = B
c = ws.cell(pr, 2, "=%s*%s" % (SF, PWR))
c.number_format = "0.0"
c.border = BOX
c.alignment = CTR
ws.cell(pr, 3, "kW").alignment = CTR
note = ws.cell(pr, 4, "Mott has NO no.50 power rating table (only 40 / 60 / 80). Bracketing 13T at 3000 rpm gives "
                      "~3.3 hp, versus a design power near 119 hp, so this chain does NOT pass Mott's power rating. "
                      "It is justified by tensile margin plus short FSAE duty life, not by the table. Mott's ratings "
                      "assume 15 000 h of industrial duty. Full write-up in sprocket_configs.md section 4.3.")
note.font = IT
note.alignment = WRAP
ws.merge_cells(start_row=pr, start_column=4, end_row=pr + 3, end_column=12)

wr = pr + 5
ws.cell(wr, 1, "13T driver, known compromise").font = B
c = ws.cell(wr, 2, "=100*(1-COS(PI()/%s))" % N1)
c.number_format = "0.0"
c.border = BOX
c.alignment = CTR
ws.cell(wr, 3, "% ripple").alignment = CTR
n2 = ws.cell(wr, 4, "Mott flags chordal action below ~17 teeth. 13T is under that line. That is the chordal speed "
                    "variation, peak to peak. We are keeping 13T because changing the driver is the only way to get "
                    "between-step ratios and that was ruled out. Inherited compromise, not a design win.")
n2.font = IT
n2.alignment = WRAP
ws.merge_cells(start_row=wr, start_column=4, end_row=wr + 2, end_column=12)

CALC_FIRST, CALC_CR = first, cr

# ========================== SHEET 2: SIM MAP ==========================
ws2 = wb.create_sheet("Sim Cross-Map")
widths(ws2, {"A": 14, "B": 13, "C": 13, "D": 13, "E": 15, "F": 22, "G": 46})
banner(ws2, 1, "SIM CROSS-MAP   |   each buildable ratio against the sweep we already ran", 7)
n = ws2.cell(2, 1, "HEADS UP: the sprocket ratios do NOT line up with the CSV rows the way the handoff assumed. "
                   "gear_ratio_results.csv steps 0.1, accel_results.csv steps 0.05. Only 26T (4.0000) is an exact row "
                   "in both. 34T (5.2308) is past the end of both sweeps (max 5.20) so it has no data at all. "
                   "Everything else is linear interpolation between the two bracketing rows.")
n.font = IT
n.alignment = WRAP
ws2.merge_cells("A2:G2")
ws2.row_dimensions[2].height = 46

for j, h in enumerate(["Driven teeth", "Total ratio", "0-75 m (s)", "Trap (kph)",
                       "Endurance final SOC (%)", "Sim provenance", "Note"], 1):
    c = ws2.cell(4, j, h)
    c.font = WF
    c.fill = HDR
    c.alignment = Alignment(wrap_text=True, horizontal="center", vertical="center")
    c.border = BOX
ws2.row_dimensions[4].height = 34


def load(path, cols):
    out = []
    with open(path) as f:
        for d in csv.DictReader(f):
            row = {}
            for k in cols:
                try:
                    row[k] = float(d[k])
                except ValueError:
                    row[k] = None
            out.append(row)
    return sorted(out, key=lambda x: x["ratio"])


def interp(rows, col, x):
    xs = [r["ratio"] for r in rows]
    ys = [r[col] for r in rows]
    if x < xs[0] - 1e-9 or x > xs[-1] + 1e-9:
        return None, "OUT OF SWEEP"
    for i in range(len(xs) - 1):
        if xs[i] - 1e-9 <= x <= xs[i + 1] + 1e-9:
            if abs(xs[i] - x) < 1e-9:
                return ys[i], "exact"
            if abs(xs[i + 1] - x) < 1e-9:
                return ys[i + 1], "exact"
            t = (x - xs[i]) / (xs[i + 1] - xs[i])
            if ys[i] is None or ys[i + 1] is None:
                return None, "no data"
            return ys[i] + t * (ys[i + 1] - ys[i]), "interp %g-%g" % (xs[i], xs[i + 1])
    return None, "OUT OF SWEEP"


out = os.path.join(ROOT, "output")
gr = load(os.path.join(out, "gear_ratio_results.csv"), ["ratio", "SOC98"])
ac = load(os.path.join(out, "accel_results.csv"), ["ratio", "t0_75m", "trap_kph"])

rr = 5
for N in teeth:
    ratio = 2.0 * N / 13.0
    soc, sp = interp(gr, "SOC98", ratio)
    t75, tp = interp(ac, "t0_75m", ratio)
    trap, _ = interp(ac, "trap_kph", ratio)
    ws2.cell(rr, 1, N)
    ws2.cell(rr, 2, ratio).number_format = "0.0000"
    ws2.cell(rr, 3, t75 if t75 is not None else "no data").number_format = "0.000"
    ws2.cell(rr, 4, trap if trap is not None else "no data").number_format = "0.0"
    ws2.cell(rr, 5, soc if soc is not None else "no data").number_format = "0.00"
    ws2.cell(rr, 6, "exact in both CSVs" if tp == "exact" and sp == "exact" else
             ("OUT OF SWEEP" if t75 is None else "interpolated"))
    note = ""
    if N == 30:
        note = "CURRENT, on the car"
    elif N == 26:
        note = "only exact row in both CSVs, best SOC, slowest accel"
    elif N == 32:
        note = "quickest 0-75 m of the whole set"
    elif N == 34:
        note = "past the 5.20 sweep limit, rerun the sweep to 5.25 before trusting anything here"
    elif N % 2:
        note = "odd count, needs an offset link"
    ws2.cell(rr, 7, note).alignment = WRAP
    for cc in range(1, 8):
        ws2.cell(rr, cc).border = BOX
        if cc < 7:
            ws2.cell(rr, cc).alignment = CTR
    if N == 30:
        for cc in range(1, 8):
            ws2.cell(rr, cc).fill = CUR
    if N == 34:
        for cc in range(1, 8):
            ws2.cell(rr, cc).fill = UNK
    rr += 1

ws2.cell(rr + 1, 1, "SOC98 = endurance final state of charge from a 98% start, per gear_ratio_optimization.m:204. "
                    "Higher is better. 0-75 m lower is better. t0_100kph is NaN above ratio 4.5 in the CSV because "
                    "the car never reaches 100 kph, which is why 0-75 m is the accel column that matters.").font = IT
ws2.cell(rr + 1, 1).alignment = WRAP
ws2.merge_cells(start_row=rr + 1, start_column=1, end_row=rr + 3, end_column=7)

# ========================== SHEET 3: README ==========================
ws3 = wb.create_sheet("README")
widths(ws3, {"A": 30, "B": 100})
banner(ws3, 1, "READ THIS FIRST", 2)
lines = [
    ("What this is", "Final-drive sprocket study for CFR27. The final drive is a FIXED 15:30 gearbox (2.000) times a "
                     "chain reduction (driven/13). Only the driven sprocket is a free choice. Total ratio = 2.000 x N/13."),
    ("How to use it", "Go to the Sprocket Calc tab. Fill in the two ORANGE cells (centre distance and radial "
                      "clearance). Every PASS/FAIL then resolves. Type any tooth count into the yellow cell in the "
                      "custom row at the bottom of the config table and it gives you the ratio and a verdict."),
    ("Why cells say UNKNOWN", "Chain centre distance and packaging clearance are not in ANY of the five CFR24 "
                              "workbooks. I searched all of them. Guessing either one would decide feasibility, which "
                              "the handoff rules forbid, so they are blank and flagged instead."),
    ("Validation gate", "The sheet's pitch diameter column is =$C$11/SIN(PI()/N), which is Mott's D = P/sin(180/N). "
                        "Reproduced the 13/30 exactly: 66.3349808182 mm and 151.8725092069 mm, ratio 4.615384615384615, "
                        "error 0 to machine precision. Gate PASSED before anything was changed."),
    ("Provenance tags", "from-SHEET = read out of a CFR24 workbook. DATASHEET = Mott table or motor data. "
                        "OWNER = told to me directly. CALC = computed from tagged inputs. UNKNOWN = not available, "
                        "not measured, not guessed."),
    ("Sheet disagreement", "Gear Design!D4 and KHK!B2 say peak torque 140 Nm. Sprocket Gearing and Forces!C7 says "
                           "150 Nm. Owner says 150 Nm with 160-170 Nm transients (Emrax 208), so this workbook uses "
                           "150 nominal and 170 worst case."),
    ("Sheet mislabel", "KHK Sheet1!B13 is labelled Roller Diameter but the formula RIGHT(520,2)/10/8 returns the 520 "
                       "roller INNER WIDTH, not the roller diameter. Does not affect this study, worth knowing."),
    ("Chain caveat", "520 motorcycle chain is not ANSI no. 50. Same 5/8 in pitch, different plate and pin spec. Mott's "
                     "no. 50 tensile (6100 lb) is used as a conservative stand-in. Get the real 520 datasheet and the "
                     "margin goes up, not down."),
    ("Gear pair flag", "The fixed 15:30 pair needs Sac 1813.9 MPa at SF=1 (Gear Design!I45). Grade 2 carburised steel "
                       "is about 1550 MPa, so contact stress is MARGINAL. Pre-existing in the CFR24 sheet, does not "
                       "move across this sweep, but somebody should own it separately."),
    ("Not edited", "params_cfr26.m and gear_ratio_optimization.m were NOT touched. params_cfr26.m stays the single "
                   "source of truth for ratios. Changing the recommended ratio is a one-line edit the owner makes."),
    ("Full write-up", "sprocket_configs.md in the repo root has the full geometry, the Mott strength work, the "
                      "combined mech+sim table, and the ranked buildable verdict."),
]
r = 3
for k, v in lines:
    c = ws3.cell(r, 1, k)
    c.font = B
    c.alignment = WRAP
    c.border = BOX
    c.fill = SUB
    v2 = ws3.cell(r, 2, v)
    v2.alignment = WRAP
    v2.border = BOX
    ws3.row_dimensions[r].height = max(30, 13 * (len(v) // 95 + 1))
    r += 1

path = os.path.join(ROOT, "CFR27_Sprocket_Study.xlsx")
wb.save(path)
print("wrote", path)
print("config rows %d-%d, custom row %d" % (CALC_FIRST, CALC_CR - 1, CALC_CR))

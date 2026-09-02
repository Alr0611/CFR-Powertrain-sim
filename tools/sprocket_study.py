"""
Final-drive sprocket study, CFR27. Chain geometry per Mott Ch.7.
Fixed 15:30 gearbox (2.000) x chain (driven/13).
Inputs come from the CFR24 sheets. Nothing here is invented.
"""
import csv, math, os

# ---------------- from-SHEET inputs ----------------
P_IN   = 0.625      # Sprocket Gearing and Forces!C9  / KHK Sheet1!B12
P_MM   = 15.875     # Sprocket Gearing and Forces!C11
CHAIN  = "520"      # KHK Sheet1!B11 and Euro Sheet1!B11
N_DRV  = 13         # driver, Sprocket sheet M8 / KHK B15
N_DEN0 = 30         # current driven, Sprocket sheet M10
GBOX   = 2.000      # 15:30, Gear Design D17
T_PEAK_GEAR = 140.0 # Gear Design D4, KHK B2  [Nm]
T_PEAK_SPRK = 150.0 # Sprocket sheet C7       [Nm]  <-- disagrees with 140
N_MAX  = 6500       # Sprocket sheet M21 [rpm]
N_RATED= 6000       # Gear Design D2     [rpm]

# UNKNOWN, not in any sheet:
C_MM = None         # chain centre distance, driver->driven. MUST BE MEASURED.

def pitch_dia(N, P=P_MM):
    return P / math.sin(math.pi / N)

def outside_dia(N, P=P_MM):
    # Mott: OD = P*(0.6 + cot(180/N))
    return P * (0.6 + 1.0 / math.tan(math.pi / N))

def chain_len_pitches(N1, N2, C, P=P_MM):
    return 2*C/P + (N1+N2)/2.0 + ((N2-N1)/(2*math.pi))**2 * P/C

def wrap_small(N1, N2, C, P=P_MM):
    D1, D2 = pitch_dia(N1,P), pitch_dia(N2,P)
    return 180 - 2*math.degrees(math.asin(min(1.0,(D2-D1)/(2*C))))

def min_C_for_wrap(N1, N2, deg=120.0, P=P_MM):
    # theta = 180 - 2*asin((D2-D1)/(2C)) >= deg  ->  C >= (D2-D1)/(2*sin((180-deg)/2))
    D1, D2 = pitch_dia(N1,P), pitch_dia(N2,P)
    return (D2-D1) / (2*math.sin(math.radians((180-deg)/2.0)))

# ---------------- validation gate: reproduce the sheet's 13/30 ----------------
SHEET = {13: 66.3349808181585, 30: 151.87250920690184}
print("VALIDATION vs 'Sprocket Gearing and Forces'!B28:C71  (D = P/sin(pi/N))")
ok = True
for N, want in SHEET.items():
    got = pitch_dia(N)
    err = abs(got-want)
    ok &= err < 1e-9
    print(f"  {N:2d}T  sheet={want:.10f}  calc={got:.10f}  err={err:.2e}")
r_sheet = 4.615384615384615   # Sprocket sheet M12
r_calc  = GBOX * N_DEN0 / N_DRV
print(f"  ratio sheet={r_sheet:.15f} calc={r_calc:.15f} err={abs(r_calc-r_sheet):.2e}")
ok &= abs(r_calc-r_sheet) < 1e-12
print("  GATE:", "PASS" if ok else "FAIL")
if not ok:
    raise SystemExit("cannot reproduce sheet, stopping per handoff section 2A")

# ---------------- sim data ----------------
def load(path, keys):
    rows=[]
    with open(path) as f:
        for d in csv.DictReader(f):
            try: rows.append({k: float(d[k]) for k in keys})
            except ValueError: rows.append({k: (float(d[k]) if d[k]!='NaN' else float('nan')) for k in keys})
    return sorted(rows, key=lambda r: r['ratio'])

def interp(rows, col, x):
    xs=[r['ratio'] for r in rows]; ys=[r[col] for r in rows]
    if x < xs[0] or x > xs[-1]: return None, 'OUT-OF-RANGE'
    for i in range(len(xs)-1):
        if xs[i] <= x <= xs[i+1]:
            if abs(xs[i]-x)<1e-9: return ys[i],'exact'
            if abs(xs[i+1]-x)<1e-9: return ys[i+1],'exact'
            t=(x-xs[i])/(xs[i+1]-xs[i])
            return ys[i]+t*(ys[i+1]-ys[i]), f'interp {xs[i]}-{xs[i+1]}'
    return None,'OUT-OF-RANGE'

base = r"C:\Users\Aboud\CFR-Powertrain\output"
gr = load(os.path.join(base,'gear_ratio_results.csv'), ['ratio','SOC98','avg_eff'])
ac = load(os.path.join(base,'accel_results.csv'), ['ratio','t0_75m','trap_kph'])

# ---------------- the nine configs ----------------
D1 = pitch_dia(N_DRV)
rows=[]
for N2 in range(26,35):
    ratio = GBOX * N2 / N_DRV
    D2, OD2 = pitch_dia(N2), outside_dia(N2)
    dL = (N2-N_DEN0)/2.0                     # pitch-count shift at fixed C, dominant term
    parity = 'even pitches' if abs(dL-round(dL))<1e-9 else 'HALF PITCH -> offset link or move C'
    dC = -P_MM*(N2-N_DEN0)/4.0               # approx axle move to keep same chain length
    soc,socn = interp(gr,'SOC98',ratio)
    eff,_    = interp(gr,'avg_eff',ratio)
    t75,t75n = interp(ac,'t0_75m',ratio)
    trap,_   = interp(ac,'trap_kph',ratio)
    rows.append(dict(N2=N2, ratio=ratio, D2=D2, OD2=OD2, dD=D2-pitch_dia(N_DEN0),
        Cmin120=min_C_for_wrap(N_DRV,N2), dL=dL, parity=parity, dC=dC,
        m_rel=(D2/pitch_dia(N_DEN0))**2, I_rel=(D2/pitch_dia(N_DEN0))**4,
        soc=soc, socn=socn, eff=eff, t75=t75, t75n=t75n, trap=trap))

print("\n--- geometry ---")
print(f"{'N2':>3} {'ratio':>7} {'D2':>8} {'OD2':>8} {'dD':>7} {'Cmin120':>8} {'dL':>5} {'dC':>7} {'I/I30':>6}")
for r in rows:
    print(f"{r['N2']:>3} {r['ratio']:>7.4f} {r['D2']:>8.2f} {r['OD2']:>8.2f} {r['dD']:>7.2f} "
          f"{r['Cmin120']:>8.1f} {r['dL']:>5.1f} {r['dC']:>7.2f} {r['I_rel']:>6.3f}")

print("\n--- sim cross-map ---")
print(f"{'N2':>3} {'ratio':>7} {'t0-75m':>8} {'trap':>7} {'SOC98':>7}  prov")
for r in rows:
    t = f"{r['t75']:.3f}" if r['t75'] else 'UNKNOWN'
    s = f"{r['soc']:.2f}" if r['soc'] else 'UNKNOWN'
    tr= f"{r['trap']:.1f}" if r['trap'] else '  --  '
    print(f"{r['N2']:>3} {r['ratio']:>7.4f} {t:>8} {tr:>7} {s:>7}  {r['t75n']} / {r['socn']}")

import json
json.dump(rows, open(os.path.join(os.path.dirname(__file__),'sprocket_rows.json'),'w'), indent=1)
print("\nrows -> tools/sprocket_rows.json")

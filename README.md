# CFR27 Powertrain Sim

MATLAB + Python model for the CFR27 (Concordia FSAE electric): final-drive gear ratio,
drivetrain efficiency, acceleration, battery/SOC, and driveline loads — all built from
real 2026 telemetry.

---

## Install on Windows

You need this once. Takes ~10 minutes.

### 1. Prerequisites

| Tool | Why | Notes |
|---|---|---|
| **MATLAB** (R2024a or newer; built on R2026a) | runs all the `.m` scripts | **base MATLAB is enough** for every `.m` script. **Simulink** is only needed if you want to open `accel_sim.slx`. |
| **Git** ([git-scm.com](https://git-scm.com/download/win)) | to clone + pull updates | Git GUI or command line, either works. |
| **Python 3** ([python.org](https://www.python.org/downloads/windows/)) | only for pulling NEW telemetry | **Optional.** The repo already ships the telemetry CSVs, so you can run every analysis without Python. |

> Tick **"Add Python to PATH"** in the Python installer if you'll use the telemetry exporter.

### 2. Get the code

**Option A — Git (recommended, so you can pull updates):**
```powershell
cd %USERPROFILE%\Documents
git clone https://github.com/Alr0611/CFR-Powertrain.git
```
That drops the repo in `Documents\CFR-Powertrain`.

**Option B — no Git:** on the GitHub page click **Code ▸ Download ZIP**, then extract it anywhere.

### 3. Run the MATLAB scripts

1. Open MATLAB.
2. **File ▸ Open** → pick `START.m` from the repo folder.
3. Hit **Run** (green ▶, or F5).

`START.m` finds itself, sets every path, and prints the menu. **No "Current Folder" fiddling.**
Then type any script name at the MATLAB prompt, e.g.:

```matlab
drivetrain_efficiency     % battery->ground efficiency + every design lever (NEW)
gear_ratio_optimization   % the main study — efficiency + pack charge sweep, 4 figures
accel_model               % accel — 0-75m, 0-100kph, tyre-weight sensitivity
verify_math               % 35 checks that recompute everything from scratch
```

More:
```matlab
open_system('accel_sim')  % the accel model in Simulink (needs Simulink)
fatigue_spectrum          % endurance driveline torque spectrum
accel_fatigue             % accel spectrum — the one that fatigues the driveline
brake_analysis            % friction/no-regen energy check
efficiency_crosscheck     % our model vs MEASURED efficiency (freeman803 af/dteff method)
gear_check                % Shigley/AGMA gear strength (WIP — see Warnings)
```

Figures and CSVs land in `output/`.

### 4. (Optional) Pull fresh telemetry from the car

Only if you want new data — the repo already has the CSVs the scripts use.

```powershell
cd CFR-Powertrain\tools
python export_influx_chunked.py
```
It's guided: paste your Influx API token once (it's saved, gitignored), type a Montreal
time range off your phone, pick channels by subsystem. First run auto-installs its one
dependency. **You must be on the car's DAQ network** for it to reach the box.
Then `convert_to_matlab.py` turns any export into a `.mat`/CSV the scripts read.

### Troubleshooting

- **"Undefined function" / scripts can't find each other** → you didn't start from `START.m`. Open and run it first; it sets the paths.
- **MATLAB license error in the terminal** (`matlab -batch`) → run scripts from the open MATLAB desktop instead; batch-mode licensing can be flaky.
- **`python` not recognized** → reinstall Python with "Add to PATH" ticked, or use `py` instead of `python`.

---

## The study — what it answers

What final drive best balances **motor efficiency**, **endurance pack charge**, and
**acceleration**? We currently run **4.61:1**. The sweep covers **4.00–5.20**.

Everything here is a range, not a solid number — the tyre data alone puts accel inside a
±15% band. Read these as "which direction is better," not "we locked in this number."

- **Efficiency + pack charge want a LOWER ratio (~4.2).** More drive energy stays in the
  motor's efficient band, and the pack ends endurance with a bit more left.
- **Acceleration wants a HIGHER ratio (~5.2)**, but our launch is grip-limited, so gearing
  down to 4.2 only costs ~0.19 s over 75 m.
- **4.61 is the compromise** (why CFR24 moved 5.2 → 4.61); **4.3–4.5 is the safe lean.**

If we go 4.2, a **21T/38T** gearbox on the existing chain gets 4.17, and the gears come out
stronger than what we run now.

**Drivetrain efficiency (new):** `drivetrain_efficiency.m` builds the whole battery→ground
stack — motor+inverter (MEASURED from telemetry, freeman803's method) × gearbox × bearings
× chain × diff × halfshaft angle — and prices every design lever in efficiency and battery
Wh. Headline: the halfshafts run at ~12° static, which alone costs ~2.4% of drivetrain
efficiency vs straight; getting them to 0–5° is free endurance range.

## Layout

```
START.m                  open this, hit Run — sets paths, prints the menu
params_cfr26.m           every constant, with a comment saying where it came from
drivetrain_efficiency.m  battery->ground efficiency + design levers
gear_ratio_optimization.m  the main ratio study
accel_model.m            acceleration study (+ accel_sim.slx in Simulink)
verify_math.m            35 independent checks
lib/                     shared physics (motor eff, tyre mu, peak torque, RC battery model)
analysis/                measured-efficiency-map tools (freeman803 af/dteff method)
data/                    the telemetry CSVs the scripts read
tools/                   InfluxDB exporter + CSV->MATLAB converter
output/                  generated results (gitignored)
```

## Where the numbers come from

| | |
|---|---|
| Efficiency / operating points | comp June 20 endurance (real race pace) |
| Pack charge + battery validation | July 11; a complete run, comp DNF'd |
| Accel validation | comp June 19 launches, real 0-75 m = 4.40 s at 4.61 |
| Drivetrain efficiency stack | CFR26 DT efficiency memo v4.0 + measured telemetry |
| Aero | Ford wind tunnel (downforce) + aero lead (drag) |
| Chassis | tilt test, with driver |
| Motor / cells | EMRAX 208 datasheet / HPPC test + ESF |
| Tyre | TTC Pacejka file (lateral only — see Warnings) |

## How much to trust it

- Battery model tracks the real pack to **~5 mV/cell** over 80 minutes.
- Motor efficiency is built from datasheet physics and lands on the datasheet's ~96% peak
  by itself, then takes a measured inverter haircut to the real ~86–90%. Never fitted.
- Accel model says 4.72 s where the real launch was **4.40 s** (conservative).
- Starting SOC from rest voltage (94.7%) matches the BMS (94.3%).
- `verify_math.m` — **35 checks** against the source documents, all pass in R2026a.

## Warnings

- **Tyre longitudinal grip is derived, not measured** — accel times are a ±15% band.
- **`gear_check.m` is unfinished** — it reproduces the CFR24 Driveline Tool's stress math,
  but that tool contradicts itself on the J factor. Closing it needs two numbers off the
  gear drawing (**pressure angle + profile shift**) and our real material allowables. Gearset
  vs gearset comparisons are fine; absolute factors of safety are indicative only.
- **Halfshaft angle (12°) is a placeholder** in `drivetrain_efficiency.m` until it's read
  off the suspension CAD at static ride height — it's the one input the whole halfshaft
  study keys off.
- Rolling resistance and wheel inertia are estimates.
- Comp endurance DNF'd on a hot cell, so its "final SOC" is charge at the red light.

None of these change which ratio is better or worse.

## Things worth flagging to other sub-teams

- **Accel fatigues the driveline, not endurance.** Endurance barely exceeds 120 Nm; accel
  peaks 152 Nm and spends ~23% of its time above 120.
- **The car has no regen** (confirmed from brake telemetry) — ~25% of traction energy
  leaves as brake heat.

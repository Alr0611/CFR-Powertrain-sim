# CFR27 Gear Ratio Optimization

MATLAB model that picks the final-drive ratio for the CFR27 electric FSAE car, built
from real telemetry — two 2026 comp sessions and one test day. No hand-tuned fudge
factors; every constant has a source.

## The question

What final drive best balances **motor efficiency**, **endurance pack charge**, and
**acceleration**? We currently run **4.61:1**. The sweep covers **4.00–5.20**.

## The answer

Everything here is a range, not a promise — the tyre data alone puts accel inside a
±15% band. Treat these as "which direction is better", not gospel numbers.

- **Efficiency + pack charge want a LOWER ratio (~4.2).** More of the drive energy stays
  in the motor's ≥95% efficiency band (+7 points vs 4.61), and the pack ends endurance
  with a bit more left.
- **Acceleration wants a HIGHER ratio (~5.2)** — more wheel torque. But our launch is
  grip-limited, not motor-limited, so gearing down to 4.2 only costs ~0.19 s over 75 m.
  In the low-grip end of the band that cost basically vanishes.
- **4.61 is the compromise**, which is exactly why CFR24 moved 5.2 → 4.61.
- **4.4–4.5 is the safe lean:** most of the efficiency, almost no accel given up. 4.2
  commits harder to endurance.

If we do go to 4.2, a **21T/38T** gearbox on the existing 2.305 chain gets 4.17, and the
gears come out stronger than what we run now (bigger pinion, less tooth load).

## How to run

Open MATLAB in this folder, then:

```matlab
gear_ratio_optimization   % the main study — efficiency + pack charge sweep, 4 figures
accel_model               % accel — 0-75m, 0-100kph, tyre-weight sensitivity
verify_math               % 24 checks that recompute everything from scratch
```

Also here:

```matlab
open_system('accel_sim')  % the accel model in Simulink (agrees with MATLAB to ~0.02 s)
fatigue_spectrum          % endurance driveline torque spectrum
accel_fatigue             % accel spectrum — this is the one that fatigues the driveline
brake_analysis            % friction/no-regen energy check
gear_check                % Shigley/AGMA gear strength (WIP — see warnings)
```

Figures and CSVs land in `output/`. Scripts add `lib/` to the path themselves, so it
doesn't matter where MATLAB is pointed.

## Layout

```
params_cfr26.m   every constant, with a comment saying where it came from
lib/             shared physics (motor efficiency, tyre mu, peak torque, RC battery model)
data/            the telemetry CSVs the scripts read
tools/           InfluxDB exporter + the scripts that build the Excel/Word deliverables
output/          generated results (gitignored)
```

The report and the Excel tools live in **Teams** (`CFR27 > Simulation > Gear Ratio Study`),
not here. This repo is the code.

## Where the numbers come from

| | |
|---|---|
| Efficiency / operating points | comp June 20 endurance (real race pace) |
| Pack charge + battery validation | July 11 test — the only complete run, comp DNF'd |
| Accel validation | comp June 19 launches, real 0-75 m = 4.40 s at 4.61 |
| Torque load spectra | comp June 20 + June 19 |
| Aero | Ford wind tunnel (downforce) + aero lead (drag) |
| Chassis | tilt test, with driver |
| Motor / cells | EMRAX 208 datasheet / HPPC test + ESF |
| Tyre | TTC Pacejka file (lateral only — see warnings) |

## How much to trust it

- Battery model tracks the real pack to **~5 mV/cell** over 80 minutes.
- Motor efficiency is built from datasheet physics and lands on the datasheet's own ~96%
  peak by itself. It was never fitted to look right.
- Accel model says 4.72 s where the real launch was **4.40 s** — runs slightly slow,
  never optimistic.
- Starting SOC from rest voltage (94.7%) matches the BMS (94.3%).
- `verify_math.m` — 24 checks against the source documents, all pass.

## Warnings

- **Tyre longitudinal grip is derived, not measured** — Calspan never ran a longitudinal
  sweep on our tyre. Accel times are a ±15% band.
- **`gear_check.m` is unfinished.** It reproduces the CFR24 Driveline Tool's stress math,
  but that tool doesn't add up: it declares 20° pressure angle and its I factor agrees,
  while its J factor is a 25° value. The gears are probably fine anyway (a 15T pinion at
  20° has to be profile-shifted or it'd be undercut, which raises J to about where CFR24
  has it) — but that's inference. Closing it out needs two numbers off the gear drawing:
  **pressure angle and profile shift**. The material allowables in there are Baja's steel,
  not ours, so absolute factors of safety are indicative only. Comparing gearsets is fine;
  the allowable cancels.
- Drivetrain efficiency (0.823), rolling resistance and wheel inertia are estimates.
- Comp endurance DNF'd on a hot cell, so its "final SOC" is charge at the red light.
- Assumes July 11 / comp pace is competition pace.

None of these change which ratio wins. They move the absolute numbers.

## Things we found that matter elsewhere

- **Accel fatigues the driveline, not endurance.** Endurance peaks 132 Nm and basically
  never exceeds 120. Accel peaks 152 Nm and spends 23% of its time above 120. The old
  fatigue sheet stopped at 140 Nm so it couldn't see this.
- **CFD over-predicts downforce ~65%.** Ford tunnel measured L/D 1.61; CFD implied 2.68.
  If CFD downforce is used anywhere else, it's too high.
- **No regen**, confirmed from brake telemetry. ~25% of traction energy leaves as brake heat.
- **Drag barely matters** at our speeds — top speed is redline-limited, not drag-limited.

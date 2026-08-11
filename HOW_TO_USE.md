# How to use the sim — quick navigation

A task-first cheat sheet: *"I want to know X"* → which script, and where to look.
(For install/setup see [README.md](README.md).)

---

## Step 0 — open it (do this once per MATLAB session)

1. Open **MATLAB**.
2. **File ▸ Open** → pick **`START.m`** in the repo folder → hit **Run** (green ▶ / F5).

`START.m` sets every path and prints the menu. You do **not** need to fiddle with the
"Current Folder". After that, just type a script name at the `>>` prompt and press Enter.

> If you ever see *"Undefined function"* — you skipped `START.m`. Run it first.

Everything a script produces (figures + CSVs) lands in the **`output/`** folder.

---

## "I want to know…" → run this

| I want to know… | Type this | What you get |
|---|---|---|
| **How efficient is the drivetrain, and what to fix** | `drivetrain_efficiency` | Printed battery→ground breakdown + a **7-tab figure** (see below) |
| **Which gear ratio is best** (efficiency + pack charge) | `gear_ratio_optimization` | Ranked ratio table + a dashboard + an operating-points map |
| **How quick is the car** (0–75 m / 0–100 kph) | `accel_model` | Accel times, tractive-effort and inertia plots |
| **Are the numbers trustworthy** | `verify_math` | 50 independent checks vs the source documents — all should say `[PASS]` |
| **How much is traction control worth, and at what gains** | `accel_model_tc` | One run + gain sweep + per-map sweeps, 4-tab figure |
| **Sweep TC gains and gear ratio together, per torque map** | `sweep_accel_tc_sim` | One page per map (150 Nm, 130 Nm) + a comparison page |
| Endurance driveline torque spectrum | `fatigue_spectrum` | Load spectrum for fatigue |
| Accel driveline torque spectrum (the fatigue case) | `accel_fatigue` | Launch load spectrum |
| Braking / no-regen energy check | `brake_analysis` | Brake heat + energy lost with no regen |
| Physics model vs MEASURED efficiency | `efficiency_crosscheck` | Model-vs-telemetry comparison |

---

## Reading `drivetrain_efficiency` — the 7 tabs

Run `drivetrain_efficiency`, then click across the tabs in the figure window. Two groups:

**The hardware chain** (the fixed mechanical path: motor → spur gears → chain → diff → halfshafts → wheels):

| Tab | Shows |
|---|---|
| **Efficiency by stage** | One bar per stage (motor+inverter, spur, bearings, chain, diff, halfshaft). The shortest bar is the weakest link. Overall = all of them multiplied. |
| **Halfshaft angle sweep** | Overall efficiency vs halfshaft angle — how much straightening the shafts (12° → 0–5°) buys. |
| **Levers ranked** | Every fixable stage ranked by battery saved — **what to fix first.** |

**The motor** (how the motor is *used*, which is where the gearing/driving levers live):

| Tab | Shows |
|---|---|
| **Efficiency map** | Motor+inverter efficiency over every rpm×torque. Bright island = most efficient; red dots = where we actually run (part-load, off the island). |
| **Eff vs load** | Efficiency vs torque + a histogram of where we spend time. The point: ~31% of the lap sits in the low-torque **cliff**. |
| **Eff vs rpm** | Efficiency vs rpm — how it falls off if you rev past the sweet spot. |
| **Gear ratios on map** | The **same endurance laps under every gear ratio** — where each ratio puts the operating point (rpm & torque) vs the datasheet peak envelope. Lower ratio → more torque (better); higher → more rpm (toward redline). |

**The one-line takeaway the script prints:** ~62% battery→ground as-driven, ~68% ceiling
for the car as it sits; the motor+inverter is healthy (91% peak) — the losses are the
mechanical path plus running the motor part-loaded, **not** a worn motor.

---

## Reading `gear_ratio_optimization`

Prints a ranked table (efficiency, high-efficiency fraction, final SOC for each ratio
4.00–5.20) and opens two figure windows: a **dashboard** (battery validation, SOC vs
ratio, efficiency vs ratio) and an **operating-points map** (one panel per ratio).
Set the ratios it tests in `params_cfr26.m` (`p.gears_to_test`) — a single ratio or a
custom pair both work.

---

## The Simulink accel models (needs Simulink)

There are three. They do different jobs, don't mix them up.

| Model | What it's for | Build it with |
|---|---|---|
| `accel_sim.slx` | Baseline accel, no traction control | `build_accel_simulink` |
| `accel_tc_sim.slx` | One TC run, one ratio, one map | `build_accel_tc_simulink` |
| `accel_tc_sweep_sim.slx` | TC sweeps: ratio × gain, per map | `build_accel_tc_sweep_simulink` |

- **Baseline, one ratio:** open `accel_sim.slx`, hit **Run**. Change ratio by setting
  `G_ratio` in the workspace (defaults to 4.61).
- **Baseline, all ratios:** double-click the green **RUN SWEEP** block, or `sweep_accel_sim`.
- **TC sweeps:** `sweep_accel_tc_sim`. Gives you the 150 Nm and 130 Nm maps on separate
  pages, plus a comparison page. Separate pages on purpose: a map bundles kp *and* the
  output clamp *and* the torque ceiling, so comparing gains across maps is comparing
  three changes at once.
- After changing `params_cfr26.m`, rebuild whichever model you're using.

> **Opening a `.slx` directly and getting "Undefined function"?** `lib/` isn't on the
> path. Run `START.m`, or `addpath('lib')` from the repo folder. `accel_tc_sweep_sim.slx`
> fixes its own path on load; the other two don't.

> **Don't quote an absolute 0-75 m from any of these yet.** The logged accel runs don't
> reconcile with `p.r_wheel = 0.221` (see the tyre-size note at the bottom). Relative
> comparisons are fine, absolutes carry a ~10% scale error.

---

## Python tools (run in a terminal at the repo root, not MATLAB)

Only needed for data etc; the MATLAB analyses don't require them.

| Command | What it does |
|---|---|
| `python tools/emeter_unpack.py` | Unpack the FSAE competition e-meter archive + list what it logs |
| `python tools/emeter_benchmark.py` | Rank the field on endurance energy economy |
| `python tools/lap_feasibility.py` | Best-lap → 22-lap feasibility (energy / thermal / driver) |

### Tyre and log analysis

| Command | What it does |
|---|---|
| `python tools/mu_vs_load_nonparametric.py` | Peak mu vs vertical load, read straight off raw TTC samples, no model |
| `python tools/pdx2_identifiability.py` | Shows PDX2 is unidentifiable from a free curve fit |
| `python tools/mu_load_model_vs_data.py` | Model peak mu vs measured, plus mu at matched slip |
| `python tools/refit_mf_pdx2_constrained.py` | The fit that produced the current tyre coefficients |
| `python tools/log_force_path_audit.py` | Gear ratio, radius, 0-75 m, torque envelope, grip, all from the log |
| `python tools/radius_from_energy_balance.py` | Solves for the rolling radius the log implies |
| `python tools/rpm_vs_time_check.py` | Sim vs logged motor rpm, the radius-free comparison |
| `python tools/kt_per_torque_bin.py` | Kt / power balance binned across the torque range |

---

## Change a number?

Every constant lives in **`params_cfr26.m`**, each with a comment saying where it came
from. Change it there once and every script picks it up. After a change, run
`verify_math` — it should still be all `[PASS]`.

---

## Open question that affects a lot of numbers

**Which tyre is actually on the car.** `p.r_wheel = 0.221` is a real measurement, but of
the Hoosier 18.0x6.0-10. It's only our radius if that's what we run, and that's never
been confirmed with a tape measure.

It matters because the log says 0.221 can't be right. Over the four standing starts the
energy the car put into the road at that radius exceeds the energy the motor produced,
which needs `eta_drivetrain > 1`. At 0.221 the implied eta is 1.07. Run
`python tools/radius_from_energy_balance.py` to see it.

Gearing and torque are both confirmed good (G measured at 4.6133 against 4.6154 nominal,
delivered torque 122-124 Nm flat against the 123 Nm the sim assumes), so the radius is
what's left. Tape an unloaded rear tyre and that closes it.

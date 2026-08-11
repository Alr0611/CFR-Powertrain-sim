# CFR27 Powertrain Sim — Handoff

*Living doc for whoever picks this up next (including future-me). Written to be read cold.*

Repo: `github.com/Alr0611/CFR-gear-ratio-optimizations`
Car: **CFR27** — Concordia FSAE electric. Motor: EMRAX 208 HV (water-cooled). Inverter: Cascadia PM100DX. Pack: 88S×4P of BAK 45D cells, ~370 V HV.

---

## 1. The goal — what we're building

One question drives the whole thing: **what final-drive gear ratio should CFR27 run?**

We currently run **4.61:1** (a 2.0:1 spur gearbox × a 2.305:1 chain). The study sweeps **4.00 → 5.20** and scores each ratio against four things the team actually cares about:

1. **Motor efficiency** — keep the motor in its efficient operating region as much of a lap as possible.
2. **Endurance pack charge** — how much charge is left after the ~22 km endurance run.
3. **Acceleration** — don't wreck straight-line speed or corner-exit punch.
4. **Launch torque** — enough for a competitive 0–75 m.

Everything is built from **real 2026 telemetry** (two comp sessions + a July 11 test day), not hand-tuned numbers. Over time the scope grew to include an acceleration model (MATLAB + Simulink), driveline fatigue load spectra, a gear-strength check, a battery SOC model, an InfluxDB telemetry export tool, and a cross-validation against a teammate's separate full-car sim.

**The bottom-line recommendation (stable all along):**
- Efficiency + pack charge want a **lower** ratio (~4.2).
- Acceleration wants a **higher** ratio (~5.2), but the launch is grip-limited so the accel cost of gearing down is small (~0.19 s over 75 m).
- **4.4–4.5 is the low-risk lean** toward efficiency; 4.2 is the endurance bet; 4.61 is the status quo.
- If we go ~4.2, a **21T/38T** gearset on the existing chain hits 4.17 and the gears come out *stronger* than today's 15T/30T.

---

## 2. Current state — where the work stands

**Core sim: done, validated, live on GitHub.** Runs end-to-end. Open `START.m` in MATLAB, hit Run, it sets paths and prints a menu.

Validation that gives it credibility:
- Battery model tracks the real pack to **~5 mV/cell** over 80 minutes.
- Motor efficiency **physics** reproduces the datasheet's ~96% peak with no fitted parameters.
- Accel model predicts **4.72 s** where the real clean launch was **4.40 s** (conservative, never optimistic); Simulink and MATLAB agree to ~0.02 s.
- `verify_math.m` runs **25 independent checks** against the source documents — all pass.

**Most recent work — efficiency is now real-world, not spec-sheet.** We cross-checked our physics efficiency model against a teammate's *measured* efficiency map (see §6) and found ours was optimistic: it reported the motor-only datasheet ~96%, but the real car — motor **plus inverter** plus switching/windage/heat losses — runs closer to **~90%**. We added `p.eta_inverter = 0.95` to fold that in. Reported efficiency dropped from ~94.6% to ~90%; **pack charge and the ratio ranking did not change** (SOC was always anchored to measured battery current, and a uniform efficiency factor cancels in the ratio math).

**July 18: the af/dteff method is now IN our repo, not just referenced by it.** Their measured-map approach (100 hand-written masks on the branch) was reimplemented vectorized as `analysis/measured_efficiency_map.m`, plus `analysis/efficiency_crosscheck.m` (the full comparison, promoted from scratch) and `analysis/efficiency_calibration.m` (rescued from the temp dir; auto-upgrades when the rich DAQ export lands). Verified in Python against the June 20 CSV: measured motor:axle ratio **4.623** (their 4.6 cancels ✓), steady-state fit **η(motor+inverter) = 0.862, accessory draw ≈ 116 W**, and our physics × 0.95 lands at **0.8619 vs measured 0.8622** — the calibration closes to 3×10⁻⁴. `verify_math.m` now has a **section 15** (3 new checks, 27 total) that re-derives all of that from the raw CSV on every run, so nobody can drift the physics constants or the haircut away from what the car measured without a FAIL. *Caveat noted in-file: that's a consistency check against the calibration session, not independent validation — the steady-state run is still the locker.*

**Two things are parked, both waiting on physical inputs, neither blocking the recommendation:**
- **Gear-strength check** (`gear_check.m`) — now restructured so the drawing numbers (pressure angle, profile shift, material) are a fill-in block at the top; until they're filled it runs in bracketed mode and refuses to print absolute FOS. Still needs those numbers (see §5).
- **Efficiency cross-validation** — a strong *preliminary* is done, but finishing it needs a richer telemetry export we couldn't get (DAQ box unreachable from the dev machine).

---

## 3. Files in flight — what's actively being worked

| File | Status | Notes |
|---|---|---|
| `tools/export_influx_chunked.py` | **actively iterated** | The telemetry export tool. Interactive menu, subsystem channel picker (~397 channels grouped), auto-installs its dependency, forgiving Montreal-time input. Works, but not yet run successfully against the live box (token/network). |
| `tools/convert_to_matlab.py` | just added (July 19) | The parser — third link in the chain (export → parse → sim). Rebuilt from the old Downloads version: handles BOTH the export tool's wide CSVs and Influx-UI long exports, survives duplicate timestamps (`pivot_table`, not `pivot`), keeps ALL channels instead of a hardcoded list, ZOH gap-fill like `parse_influx.m` (`--fill none` to opt out), writes `.mat` and/or a repo-style wide CSV, auto-installs pandas/scipy. Tested on the June 20 CSV + a synthetic nasty long file. The Downloads original is now redundant. |
| `params_cfr26.m` | just changed | Added `eta_inverter`, moved `eff_sweet` 0.95 → 0.90. |
| `lib/emrax208_efficiency.m` | just changed | Now returns real-world (motor+inverter) efficiency. |
| `verify_math.m` | just changed | Check #3 now validates both the physics (96%) and real-world (~90%) layers. |
| `gear_check.m` | restructured, awaiting drawing | Drawing inputs (PA, profile shift, material preset) are now a fill-in block at the top; runs bracketed until filled. Also: chain stage corrected to 13T:30T = 2.3077 (from the Sprocket Gearing Excel) and candidate gearsets now report chain tension too. J-factor question still unresolved — do not quote absolute FOS yet. |
| `analysis/` (new) | just added | `measured_efficiency_map.m` (af/dteff method, vectorized), `efficiency_crosscheck.m` (model-vs-measured comparison + figure), `efficiency_calibration.m` (rescued from temp scratch; awaits rich DAQ export). The old scratch copies in the Temp dir are now redundant. |

---

## 4. Changed — what's been touched (and why)

**Recently, in the repo:**
- **af/dteff measured-efficiency method implemented** (July 18) — new `analysis/` folder (see §3), verify_math section 15, START menu entries. The chain stage is confirmed **13T:30T = 2.3077** from the CFR24 "Sprocket Gearing and Forces.xlsx" (lives in Aboud's Downloads, two identical copies) — the "2.305" quoted before was a rounding; gearing down to ~4.2 via a 21T/38T gearbox also **drops peak chain tension ~10%** (less output torque into an unchanged chain), which gear_check now prints per candidate.
- **Efficiency made real-world** — `params_cfr26.m`, `lib/emrax208_efficiency.m`, `verify_math.m`. The physics still matches the datasheet; the real-world haircut sits on top and is what the sim reports.
- **`START.m` added** — one-file entry point so nobody fights the MATLAB path.
- **`tools/` trimmed to just the export tool** — the Excel/Word builder scripts were removed (personal tooling; deliverables live in Teams). Only the InfluxDB exporter remains, and it was rewritten with an interactive mode, a subsystem-grouped channel picker, auto-install, and forgiving time parsing.
- **README rewritten** in the team's voice; deliverables (report, Excel tools) moved to Teams so the repo is code-only.

**Earlier, foundational:**
- `gear_ratio_optimization.m` — the main study (efficiency from comp June 20, SOC from July 11, four figures + a comparison table).
- `accel_model.m` + `accel_sim.slx` — inertia-based acceleration, MATLAB and Simulink, cross-validated against each other.
- `fatigue_spectrum.m`, `accel_fatigue.m`, `brake_analysis.m` — driveline load spectra and the no-regen check.
- `lib/` — the shared physics (motor efficiency, RC battery model, tyre μ, peak torque, etc.).
- `data/` — the four telemetry CSVs the scripts read.

---

## 5. Failed attempts / dead ends — what didn't work and why

**This section is the whole point of a handoff. Read it before re-treading anything.**

### The gear J-factor saga (the big one — resolved into "needs the drawing")
This flip-flopped several times and cost real hours. The honest chain:
1. Flagged the 15T pinion as borderline (factor of safety ~1.0).
2. Retracted it after being told Baja's J-table "floors at 15 teeth."
3. Re-flagged it after reading **Shigley Fig 14-6**, which gives J ≈ **0.245** at 15 teeth (not the 0.325 the CFR24 tool used).
4. Then found **Mott Fig 9-10 has *two* panels** — a 20° chart (matches Shigley, ~0.245) *and* a **25° chart** (~0.345). CFR24's 0.325 is a read of the **25°** panel.
5. Finally: the CFR24 tool **declares 20° pressure angle** and its contact factor `I = 0.108` agrees with 20° — but its bending factor `J = 0.325` is a 25° value. **The tool contradicts itself**, and its centre distance is standard (56.25 mm).

**Conclusion:** a 15T pinion at 20° *standard* would be undercut, so the real gears are almost certainly **profile-shifted** (which raises J toward ~0.325 legitimately) — but we can't confirm that from the spreadsheet. **Two numbers off the gear drawing settle everything: pressure angle and profile-shift coefficient.** The gear-strength check is parked until we have them.
**Lesson:** don't trust a geometry factor read off a chart when you don't know the actual tooth geometry (pressure angle + shift). Get it from the drawing, not the textbook.

### Live telemetry export — couldn't reach the box
The InfluxDB DAQ box is at `192.168.100.115` — a LAN address on the car's network. It's **unreachable from the dev machine** (no route; confirmed HTTP 000). The `ApiException` seen when running on-network was almost certainly an **expired/wrong saved token**, not a code bug. Also fixed along the way: a 240-channel filter built as chained `OR`s would likely have been rejected by Influx — switched to `contains(set: [...])`, which handles any number of channels.
**To export: you must be on the car's DAQ network, with a fresh token** (`tools/influx_token.txt`).

### Excel workbooks — repeatedly ugly, then removed
Rebuilding the fatigue + Shigley workbooks hit: PowerShell double-encoding CSV/text to cp1252 mojibake, Baja's fill colors surviving under our text, and cell-collision bugs (writing over cells another sheet read by address). All eventually fixed — then the whole builder toolset was **removed from the repo** anyway (personal tooling; the finished workbooks live in Teams).

### Branch on the teammate's repo — prepared, then scrapped
We staged a `user/ka/gearopt` branch with a self-contained `powertrain/` MATLAB module in a clone of freeman803's repo. **Nothing was ever pushed.** The plan was paused ("keep it cautious, cross-reference the calcs instead"). The module *did* run correctly and reproduce our numbers, so it's a known-good starting point if the collaboration reopens.

### Efficiency cross-check — preliminary only
Race telemetry is almost all transients; only **~1.8%** of it is genuine steady-state (constant speed + torque). That's enough for a strong preliminary — filtering to steady points **halved** the model-vs-measured gap — but not enough to lock it. A deliberate steady-state run is what finishes it.

---

## 6. The efficiency cross-validation (context for §5 and §7)

A former mech tech's repo, **`freeman803/Full-Car-Simulation`**, is a Python vehicle-dynamics sim (suspension, tire, forces, roll) — the *complement* to our powertrain work. One MATLAB branch, `af/dteff`, builds a **measured** efficiency map from telemetry, which is the empirical twin of our physics model.

What we found comparing them on our comp data:
- Their "drivetrain efficiency" map is really **motor+inverter** (their gear-ratio term cancels in the math — verified: real motor:axle ratio is 4.62).
- Measured motor+inverter ≈ **0.86**; our physics motor-only ≈ **0.91**. On **steady-state** points the gap halves — confirming most of the apparent disagreement was a transient artifact, and that our model was a mild optimistic bound.
- That's what motivated the `eta_inverter = 0.95` real-world correction.
- Their vehicle parameters independently match ours (wheelbase 1545 vs 1543 mm, CG height 315 vs 313 mm) — a nice unplanned cross-check.

---

## 7. Next steps

**To finish the efficiency cross-validation** (nice-to-have, not blocking):
1. On the car's DAQ network, with a fresh Influx token, export the July 11 window (~11:15–12:00 Montreal) with the **Motor & inverter** + **Cooling & temps** channel groups — specifically `dcBusVoltage/Current` (separates accessory draw), `motorTemp` + module temps (temperature correction), and `currentPhaseA/B/C` (cross-checks the torque signal).
2. Point `efficiency_calibration.m` (scratch) at the resulting CSV — it auto-detects those channels and runs the cleaned comparison.
3. Ideally, a **deliberate steady-state run** (hold constant speed at a few points for ~5–10 s each, or a dyno) — the one thing that turns the preliminary into a locked answer.

**To close the gear-strength check** (needed before cutting new gears):
1. From the **gear drawing**: pressure angle and profile-shift coefficient (settles the J contradiction).
2. From whoever spec'd the gears: **material + heat treat** (replaces Baja's allowables with ours — until then, absolute factors of safety are indicative only; gearset-vs-gearset comparisons are fine because the allowable cancels).
3. When you have them: they go in the `drawing.*` / `material` block at the **top of `gear_check.m`** — it's now a two-minute fill-in, the script does the rest (including flagging a contradictory drawing, e.g. "20° unshifted" at 15T, which would be undercut).

**Small open item:** the July 18 code (verify_math §15, gear_check rework, analysis/ scripts) hasn't been executed in MATLAB yet — `matlab -batch` fails with license error 5201 even after signing in. Diagnosis: the **MathWorks Service Host** (which online licensing routes through in batch mode) is crashed/broken on this machine — there's a live MathWorksCrashReporter process and two MSH versions installed; the open desktop session is unaffected. Fix when MATLAB is next CLOSED: kill the `MathWorksServiceHost*` processes, delete `%LOCALAPPDATA%\MathWorks\ServiceHost`, relaunch MATLAB (it reinstalls MSH fresh). Until then, run things in the open desktop session — one-liner that logs to `output\matlab_run_log.txt`:
`cd('C:\Users\Aboud\CFR-gear-ratio-optimizations'); addpath(genpath(pwd)); diary(fullfile('output','matlab_run_log.txt')); verify_math; efficiency_crosscheck; gear_check; diary off`
Expect 27/27 from verify_math (all numbers already replicated in Python against the same CSV).

**Documents to grab** (asked for, still open):
- Cascadia **PM100DX manual**: how `torqueFeedback` is derived and its accuracy (if the torque signal is biased, it caps how well the efficiency cross-check can ever converge).
- Confirm the exact **EMRAX 208 variant** (voltage/cooling) so the physics constants are for the right motor.

**Collaboration:** the branch into `freeman803/Full-Car-Simulation` is on hold pending a conversation. If it reopens, the first contribution should be the **efficiency cross-check** (cross-team validation reads better than a code dump), and the staged `powertrain/` module is ready to go.

**Also worth flagging to other sub-teams** (found along the way, unrelated to gearing):
- **CFD over-predicts downforce ~65%** vs the Ford wind tunnel (L/D 2.68 sim vs 1.61 measured). If CFD downforce is used elsewhere, it's too high.
- **The car has no regen** (confirmed from brake telemetry). ~25% of traction energy leaves as brake heat.
- **Accel is the driveline fatigue case, not endurance** — endurance barely exceeds 120 Nm; accel peaks 152 Nm and spends ~23% of its time above 120.

---

*Questions → Aboud. The README has the short version; `params_cfr26.m` documents where every constant came from.*

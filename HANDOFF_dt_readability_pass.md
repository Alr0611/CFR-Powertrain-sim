# HANDOFF — Readability + data-integrity pass (drivetrain / gear-ratio / analysis)

**Status: INCOMPLETE and NOT independently verified. Do not trust these edits — re-verify everything below.**
All changes are **LOCAL and UNCOMMITTED**. Do NOT commit or push until the repo owner
(Abdulkarim) gives the signal. When committing: author solely as the repo owner —
**no Co-Authored-By, no self-attribution, no CONTRIBUTORS entry.**

The previous agent (me) was flagged by the owner for making mistakes mid-task and told
to stop and hand off. Treat everything here as *claimed done*, not *confirmed done*.

---

## 0. The task (verbatim scope)

Readability + data-integrity pass on **gear_ratio_optimization.m**, **drivetrain_efficiency.m**,
and **analysis/*.m** only. **Leave accel_model.m and the accel/Simulink files alone.** Plus
design-review fixes. Full task had parts A (descriptive variable renames), B (prefer real
data / label sources), C (remove dead calcs), D1–D5 (design-review fixes). Rules: never
fabricate a number; run every affected script + verify_math (all-pass); confirm figures render.

Owner added mid-task guardrails (CRITICAL — see §2):
1. The "line-1 artifact" was NOT real — only CFR26→CFR27 on line 1.
2. **D2 must be STUBBED, not implemented** — driver-intent channels are absent; do not fake them.
3. Don't over-rename the EKF/Kalman matrices — keep conventional notation + a comment block.
4. Local only; owner-only authorship.

---

## 1. MY MISTAKES (read this first)

1. **Invented a "line-1 corruption."** I claimed `gear_ratio_optimization.m` line 1 had a
   `> d%%` prefix, based on a `head -1 | cat -A` output. That `> d` was almost certainly a
   **terminal/scrollback rendering artifact, not file content** — the owner looked and the
   line was clean. I "fixed" a phantom. The only real change was the title **CFR26 → CFR27**
   (done). **Lesson for you: verify an artifact byte-for-byte before touching it; never invent
   a change to a clean line.**

2. **Implemented D2 instead of stubbing it (reverted).** I created `lib/is_motoring.m` that
   defined "motoring" as driver demanding >15% torque, and — because
   `VCFRONT_acceleratorPosition` / `VCFRONT_torqueRequest` are NOT in the efficiency/SOC
   exports — it **fell back to `torqueFeedback > 15%`**, i.e. it *approximated* driver intent
   from achieved torque. The owner explicitly forbade this. **I reverted it fully**: deleted
   `lib/is_motoring.m`, restored the original filters, and added TODO stubs. **Verify the
   revert is complete (see §5).** Original filters:
   - gear_ratio: `shaftPower_comp > 1000` (and `shaftPower_atRatio > 1000`)
   - drivetrain / analysis: `motorSpeed>500 & motorTorque>5 & ...`

3. **Changed a pinned constant on literature alone (reverted).** For D4 I first set
   `baselineStages.differential = 0.90`. That broke internal consistency: `params_cfr26.eta_drivetrain`
   (0.794) and `verify_math` are **pinned to 0.92**, so the header started printing
   `77.7% hardware vs params 79.4%`. **I reverted to 0.92** and instead documented it as the
   *optimistic end of a sourced 0.88–0.93 range* with a "measure via coastdown" note. **Confirm
   diff is 0.92 everywhere and the header no longer shows a mismatch.**

4. **Very large wholesale rewrites = high risk of a silent transcription error.** I rewrote
   `gear_ratio_optimization.m` and `drivetrain_efficiency.m` in full (hundreds of lines each),
   plus two analysis files. A rename that runs clean can still have quietly changed a number or
   a plot. **The renames are supposed to be 100% behavior-preserving. YOU MUST PROVE THAT (§4).**

---

## 2. Intended net effect (what SHOULD have changed vs the committed baseline)

The committed baseline is git HEAD (commit `4879f92`, pre-task). After this pass, the
**headline NUMBERS should be essentially IDENTICAL to the baseline**, because:
- Renames are behavior-preserving (no logic change).
- D2 was stubbed → original filters → **same numbers**.
- D4 kept 0.92 → **same hardware/overall numbers**.
- D1 disabled the battery/inverter split, but that split was already being **REJECTED** at
  runtime (bad dc-bus channel), so it never contributed a headline number.
- D3 only **adds a printed line** (count/fraction + low-confidence flag).
- D5 is a **comment-only** TODO.
- B is **labels/comments** only.

**So: if any core number moved vs baseline, it is a BUG introduced by the rename, not an
intended change. That is the single most important thing to check.**

---

## 3. What changed, file by file

### gear_ratio_optimization.m — FULL REWRITE
- Line 1 title: `CFR26` → `CFR27`.
- Descriptive renames per the owner's table (D→enduranceData, Dc→compData, Ps_c→shaftPower_comp,
  Pe_c→electricalPower_comp, eff_c→efficiency_comp, rpm_c→motorSpeed_comp, tq_c→motorTorque_comp,
  rs→ratioScale, Ps_new→shaftPower_atRatio, Pe_new→electricalPower_atRatio, eff_new→efficiency_atRatio,
  rpm_new→motorSpeed_atRatio, tq_new→motorTorque_atRatio, P_shaft_old→shaftPower_baseline,
  P_elec_old→electricalPower_baseline, eff_old→efficiency_baseline, P_wheel→wheelPower,
  act_c→motoringMask_comp, dt_vec_c→timeStep_comp, dt_vec→timeStep, insw→inSweetSpotMask,
  icur→currentRatioIndex, mech→mechanicalEnergy, ng→numGears, g→gearRatio,
  scale→currentScaleFactor, I_new→packCurrent_atRatio, rmse_c→wheelVsMotorRmse) plus unlisted
  cryptic ones (motor_rpm→motorSpeed_endurance, torque_fb→motorTorque_endurance,
  wheel_rpm→wheelSpeed_endurance, I→cellCurrent, voltage→cellVoltage, N→numSamples,
  bms_soc→bmsSOC, SOC_openloop→socOpenLoop, Vs_kf→voltageKalman, SOC_kf→socKalman,
  R→resultsByRatio, op_points→operatingPoints, soc_curves→socCurves, gears→gearRatios,
  rc98→rcFullCharge, active→motoringMask_endurance, etc.).
- **EKF loop: matrices KEPT conventional** (A, X, B, Pcov, R1/R2, C1/C2, Ri, tao1/2, V_R1/2,
  VOCV, dOCV, H, K1, Q_noise, R_noise, Ut) with a **defining comment block** above the loop.
- **MOTORING filter STUBBED**: `motoringMask_comp = shaftPower_comp > 1000` (unchanged logic),
  `motoringMask_endurance = shaftPower_atRatio > 1000`, with a TODO comment block explaining the
  driver-intent version needs `VCFRONT_acceleratorPosition` (DAQ access; not in current exports).
- `struct2table` field names (avg_eff, hi_eff, SOC, SOC98, infeas_T, infeas_rpm, ratio) were
  KEPT so `lib_figs.m` (out of scope, unchanged) still works via positional args.

### drivetrain_efficiency.m — FULL REWRITE
- Descriptive renames per table (eff_shaft→motorInverterEfficiency, eff_steady→steadyStateEfficiency
  [and main-body eff_inband→inBandEfficiency], E_batt_Wh→batteryEnergyWh, eff0→overallEfficiencyCurrent,
  mech→mechanicalStackEfficiency, pct→toPercent, hs_term→halfshaftEfficiency,
  eff_hs→halfshaftJointEfficiency, cur/best→currentEfficiency/bestEfficiency, p_hw→overallHardwareOnly,
  p_hw5/0→overallHardwarePlus5deg/0deg, St→stageTable, Vpack/Ipack→packVoltage/packCurrent) + the
  **B struct → baselineStages** with fields spur→spurGear, bearings→bearings, chain→chain,
  diff→differential, hs_angle→halfshaftAngleDeg. Local-fn internals renamed (V/I/tq/rpm/pack/mechP/e →
  packVoltage/packCurrent/motorTorque/motorSpeed/packPower/mechanicalPower/instantEfficiency). Figure
  vars renamed for physical quantities; plot handles/loop indices (ax, tg, fW, hb, y, i, k, idx) kept short.
- **B (source labels):** each mechanical stage tagged `ASSUMED (memo) / dyno-measurable`.
- **Halfshaft angle:** `baselineStages.halfshaftAngleDeg = 12` marked **`*** MEASURE FROM CAD ***
  PLACEHOLDER`**; angle-sweep tab/axis relabeled "MEASURE FROM CAD" / "placeholder".
- **D1 (split disabled):** `split_battery_inverter()` gutted to return DISABLED + keeps only the
  DYNO hook. Section 1b prints the disabled message. All dc-bus computation removed.
- **D3:** `measured_pack_to_shaft` now also returns `steadyCount, steadyPct`; header prints the
  in-band count + fraction and a **`[LOW CONFIDENCE]`** line when `steadyCount < 100`.
- **D4:** `baselineStages.differential = 0.92` KEPT, but documented as the optimistic end of a
  sourced **0.88–0.93** range (refs: x-engineer.org drivetrain-losses, RoyMech gear efficiency,
  bevel-diff system-eff guides). Stage-table "best" for diff = 0.93 (top of range).
- **D5:** rear-axle TODO comment added above `mechanicalPower = ...` in `measured_pack_to_shaft`
  ("DO NOT IMPLEMENT YET, pending Andrew").
- **D2 STUBBED:** `measured_pack_to_shaft` and the section-5 operating-points load both use the
  original `motorSpeed>500 & motorTorque>5` gate with a TODO. `measured_pack_to_shaft` signature
  reverted to `(csvPath)` (the temporary `maxTorqueNm` arg for is_motoring was removed).

### analysis/efficiency_calibration.m — REWRITE
- Renames. **D1:** dc-bus accessory-removal path DISABLED (dcBusCurrent untrustworthy);
  `electricalInput = packPower` always, with a note. **D2 stub** on the motoring gate.
  **D3** low-confidence flag when steady < 100.

### analysis/efficiency_crosscheck.m — REWRITE
- Renames (D→crosscheckData, V/I/elec/mech → packVoltage/packCurrent/packPower/mechanicalPower,
  Mall/Mst → measuredMapAll/measuredMapSteady, A/x/eta_mi/P0 → fitDesignMatrix/fitCoeffs/
  measuredMotorInverterEff/accessoryDraw, etc.). **D2 stub note. D3** low-confidence flag < 100.

### analysis/measured_efficiency_map.m — EDITED (compute block)
- Renames (rpm/tq/elec/mech/eff → motorSpeed/motorTorque/packPower/mechanicalPower/instantEfficiency;
  keep→motoringMask; it/is→torqueBin/speedBand; lin/cnt/esum/map → linearIndex/binCount/binEffSum/binEffMean).
  **D2 stub TODO** on the `keep = motorSpeed>500 & motorTorque>5 & ...` gate.

### lib/is_motoring.m — CREATED then DELETED
- Was the D2 approximation. Deleted during the revert. **Confirm it does not exist.**

### NOT TOUCHED (must stay untouched)
- `accel_model.m`, `accel_sim.slx`, `accel_sim.slxc`, `build_accel_simulink.m`, `sweep_accel_sim.m`,
  `accel_fatigue.m`, `fatigue_spectrum.m`, `brake_analysis.m`, `gear_check.m`, `START.m`, `README.md`,
  `HOW_TO_USE.md`, `params_cfr26.m`, `verify_math.m`, `lib/*` (except is_motoring create+delete),
  `lib/lib_figs.m` (relies on positional args + kept field names).

---

## 4. TRIPLE-CHECK PROCEDURE (do all of this before trusting anything)

**A. Prove numbers are unchanged vs the committed baseline.**
1. Stash the working changes and run the baseline:
   `git stash` → run `verify_math`, `gear_ratio_optimization`, `drivetrain_efficiency`,
   `efficiency_crosscheck`, `efficiency_calibration`; save each stdout.
2. `git stash pop` → run the same five; save each stdout.
3. **Diff the stdout.** Expected differences ONLY: (a) diff-source/label text, (b) D3's new
   count/fraction/low-confidence lines, (c) D1's "DISABLED" split message replacing the old
   "REJECTED" split message, (d) CFR27 title. **Any moved efficiency/SOC/hardware NUMBER is a
   rename bug — find and fix it.**

**B. Reference baseline values (from earlier this session — sanity anchors):**
- verify_math: **37/37 PASS, 0 FAIL.**
- gear_ratio (original `Ps>1000` filter): AvgEff **89.2–90.5%**, HiEff **61.3–82.3%**,
  FinalSOC **2.11–3.20%**, 98%-start SOC **5.4–6.5%**. **⚠ If you instead see AvgEff ~90.1–91.1%
  / HiEff ~65–88%, the D2 revert did NOT take and it is still filtering on torque — FIX IT.**
- drivetrain: hardware **79.4%**, motor as-driven **78.2%**, in-band **85.2%**, overall as-driven
  **~62.1%**, in-band ceiling **~67.6%**. **⚠ If hardware shows 77.7% / overall ~60.8%, diff is
  still 0.90 — set it back to 0.92.**

**C. Confirm the reverts/stubs literally:**
- `grep -rn is_motoring .` → must be EMPTY. `ls lib/is_motoring.m` → must NOT exist.
- `grep -n "motorSpeed>500 & motorTorque>5" drivetrain_efficiency.m analysis/*.m` → present (stub).
- `grep -n "shaftPower_comp > 1000\|shaftPower_atRatio > 1000" gear_ratio_optimization.m` → present.
- `grep -n "differential = 0.92" drivetrain_efficiency.m` → present.
- `grep -n "MEASURE FROM CAD" drivetrain_efficiency.m` → present.
- `grep -n "DO NOT IMPLEMENT YET" drivetrain_efficiency.m` → present (rear-axle TODO).
- `head -1 gear_ratio_optimization.m` → `%% CFR27 GEAR RATIO OPTIMIZATION  --` (clean, no `> d`).

**D. Eyeball every figure** (batch renders them into output/):
- drivetrain: 7 tabs — HalfshaftAngleSweep, LeversRanked, EfficiencyByStage, EfficiencyMap,
  EffVsLoad, EffVsRpm, GearRatiosOnMap. Check labels/numbers look right, nothing NaN/blank.
- gear_ratio: GearStudyDashboard*, OperatingPointsOnEfficiencyMap*.
- efficiency_crosscheck: efficiency_crosscheck.png (3 surf panels).

**E. Confirm D3 actually fires and reports** (count + fraction, and the LOW CONFIDENCE line if
the comp steady-state sample is thin) in the drivetrain header and both analysis scripts.

**F. verify_math must be 37/37.** It imports nothing from these scripts, so a FAIL means a
params/constant drifted — investigate immediately (should not happen; I did not touch params/verify_math).

---

## 5. GUARDRAILS for the next agent

- **Behavior-preserving renames only.** If a number changes, you broke it. Diff against baseline (§4A).
- **Never approximate an absent channel.** Driver-intent (accelerator/torqueRequest) is NOT in
  comp_june20 / endurance_july11. Keep the stub + TODO. Do not use torqueFeedback as a proxy.
- **Don't move pinned constants alone.** `differential` 0.92 is pinned across params + verify_math +
  drivetrain. Changing it means changing all three together — otherwise leave 0.92 + the range doc.
- **Verify artifacts byte-for-byte** before "fixing" them (see mistake #1).
- **Keep EKF/estimator matrices conventional** (A, X, R1/R2, Ri, VOCV, dOCV, P, K, H).
- **Do not touch** accel_model / Simulink / params / verify_math / lib_figs / START / README.
- **Local only.** No commit/push until the owner says so. **Owner-only authorship — no
  Co-Authored-By / self-attribution / CONTRIBUTORS.**
- The last full test run reported all five scripts `<<<OK` and verify_math 37/37, but that run was
  NOT diffed against baseline and figures were NOT eyeballed. **Treat as unverified.**

---

## 6. What is genuinely NOT done / open

- **§4A baseline diff has NOT been run** — the core "did any number move?" check is outstanding.
- **Figures NOT eyeballed** after the final edits.
- **D3 low-confidence output NOT confirmed** to fire on the actual comp steady count.
- **Analysis-file renames** were done by rewrite but not diffed against baseline behavior.
- **Owner decision needed on D4:** keep 0.92 (current, pinned) or adopt ~0.90 across
  params + verify_math + drivetrain together. Currently 0.92 + documented range.
- **D2 remains stubbed by design** — real fix needs a re-export with `VCFRONT_acceleratorPosition`
  (DAQ access). Not a code task until the channel exists.
- Rename completeness: I applied the owner's tables + the "rename if cryptic" rule, but I did not
  exhaustively audit every remaining short name. Do a final `grep` sweep for leftover 1–3 char
  physical-quantity names in the four in-scope files.

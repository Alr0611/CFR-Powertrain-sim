# HANDOFF — traction-control analysis + TC accel sim

Written at the end of the session that analysed the test-day log and built the
TC-aware accel sim. Read this before touching anything TC-related.

---

## 0. State of the world

| | |
|---|---|
| Repo | `github.com/Alr0611/CFR-dt-sim` |
| Local | `C:\Users\Aboud\CFR-Powertrain` (folder name still says CFR-Powertrain; remote is CFR-dt-sim) |
| `main` pushed at | `2e281b8` |
| **TC work is NOT pushed** | all new files are untracked. Owner asked to hold. |
| Author for all commits | `Alr0611 <aboud.alrefae@gmail.com>`. **Never add a co-author or self-attribution.** |

Untracked TC files, all new, nothing existing was modified:

```
accel_model_tc.m            TC accel sim + gain sweep + figures
lib/accel_tc_core.m         shared plant + controller (ONE implementation)
lib/accel_tc_sample.m       scalar sampler so Simulink can call the core
build_accel_tc_simulink.m   generates accel_tc_sim.slx and runs it
accel_tc_sim.slx            generated, regenerable, don't hand-edit
HANDOFF_tc_tuning.md        this file
```

`accel_model.m`, `verify_math.m`, `params_cfr26.m` are **untouched**. `accel_model.m`
still carries its documented traction-cap unit bug on purpose.

---

## 1. Things that will waste your time if you don't know them

**The firmware is not in this repo.** It was read from another session's scratchpad:

```
C:\Users\Aboud\AppData\Local\Temp\scratch\c--Users-Aboud-Downloads\
    d70ec6a6-a5d5-4090-b16d-01e9378fe590\scratchpad\firmware\
```

That is a **temp directory and will eventually vanish.** If it's gone, re-clone
`concordia-fsae/firmware`. Files that matter:
`components/vc/front/src/torque.c`, `components/vc/front/include/torque.h`,
`components/shared/code/libs/lib_pid.c`,
`components/shared/code/app/app_vehicleSpeed.c`.
**Do not modify the firmware.** It belongs to the embedded team; we analyse against it.

**Data:** `C:\Users\Aboud\Downloads\today_test.csv` — 75,208 rows, 6.13 h, **10 Hz**,
one ~6,550 s gap (lunch). Has `VCFRONT_torqueRequest` and
`VCFRONT_acceleratorPosition`, which older exports lacked.

**Parser:** `C:\Users\Aboud\Downloads\parse_accel_test.py` — **lives in Downloads, not
in the repo.** Decide whether to move it into `tools/`. It is not covered by
`verify_math` and nothing tests it.

### Four data gotchas that produce wrong answers silently

1. **Motoring torque is NEGATIVE** in this log and the request is POSITIVE
   (`corr(req, fb) = −0.99`). Any `torque > 0` gate silently matches nothing.
   The parser takes magnitudes.
2. **`VCFRONT_odometer` has 0.1 km (= 100 m) resolution.** It cannot resolve a 75 m
   run. Integrate `VCFRONT_vehicleSpeed` instead. The old parser used the odometer
   and produced "0–75 m" times like 0.60 s.
3. **`VCFRONT_torqueRequest` is already POST-TC.** The VC applies the reduction
   before the request leaves. To see the cut, compare against driver demand
   (`apps/100 × torque_max`), never against `PM100DX_torqueFeedback`.
4. **`req − out` at high rpm is NOT traction control.** Above ~5,500 rpm the motor
   is power-limited and delivered torque falls away from the request while slip is
   *below* target. Gate on rpm or compare against the motor envelope.

---

## 2. The finding that matters most

**The shipped traction controller is pure proportional.**

`calc_traction_control_reduction` (torque.c:624) calls **`lib_pi_typeb_calc`**, which
writes only `p_term` and `i_term` — it never writes `d_term`. The variant that
computes a derivative is `lib_pid_typeb_calc` (lib_pid.c:52), which the TC does
**not** call. So `d_term` stays 0 from `lib_pid_init` and the LPF filters zero.

Both gain maps also ship `ki = 0.0` **and** `ilim = 0.0`, so the integral is disabled
twice over (even a non-zero `ki` would be clamped to `[0,0]`).

```
Actual control law:   y = clamp( kp · (slip − target), 0, maxlim )
Applied as:           T_out = T_driver · (1 − y)      (torque.c:1411-1412)
```

`kd = 0.110` (150 Nm) / `0.070` (100 Nm) is defined, converted and passed in, and has
**no effect on the car.** Do not spend test time tuning it.

Shipped values, `components/vc/front/include/torque.h`:

| map | kp | ki | kd | ilim | maxlim | ileak |
|---|---|---|---|---|---|---|
| 150 Nm | 0.470 | 0.0 | 0.110 | 0.0 | 0.75 | 500 ms |
| 100 Nm | 0.591 | 0.0 | 0.070 | 0.0 | 0.70 | 500 ms |

### 2a. Re-verified against source, and one premise above is wrong

Checked line by line against `firmware/` on 2026-08-11. The pure-P finding holds
exactly. Two things in the table above do not.

**Confirmed, no change:**

- `calc_traction_control_reduction` (torque.c:633) calls `lib_pi_typeb_calc`.
  That function writes `p_term` and `i_term` only (lib_pid.c:44-50). `d_term` is
  never touched, so it stays 0 from `lib_pid_init`, and `lib_pid_util_lpf_dTerm`
  filters zero into zero. `lib_pid_typeb_sum` then adds p + i + 0.
- `lib_pid_util_ilim(pid, TC_MIN, percentILim)` with `TC_MIN = 0.0f` and every
  map shipping `ILIM = 0.0` pins `i_term` to exactly 0. Integral disabled twice, as stated.
- Output clamp is `[TC_MIN, percentMaxTcLimit]` = `[0, maxlim]`. Reduction only,
  never negative. This is the clamp your elec tech asked about.
- `lib_pid_typeb_calc` (lib_pid.c:52) really does compute `kd * (x / dt)`, which
  is error over dt, not d(error)/dt. The warning stands.

**New, and it changes the numbers:**

1. **There is a third gain map.** `TC_130NM_*`: kp 0.591, ki 0.0, kd 0.070,
   maxlim 0.70, ilim 0.0. Same as the 100 Nm map. The table in section 2 lists
   only 150 and 100.
2. **The 130 Nm map is the DEFAULT.** `TC_SET_DEFAULT_PID` expands to `TC_130NM_*`
   (torque.h:48-56). So "shipped" is kp 0.591 / clamp 0.70, not kp 0.470 / clamp 0.75.
3. **`kd` is passed negated**: `.kd = TC_PID_CONV_THOU_F32(-pid->thousandthKd)`
   (torque.c:632). Harmless today because `d_term` is dead. If the embedded team
   switches to `lib_pid_typeb_calc`, they get a NEGATIVE gain on a quantity that
   is already not a derivative. Two bugs stacked.

**And the premise that breaks everything downstream:**

`tc_getActivePid()` returns `&tcPid_data`, and `tcPid_data` is
`LIB_NVM_MEMORY_REGION(nvm_tcPid_S)` (lib_nvm_componentSpecific.c:116). **The live
gains come from NVM, not from the header.** The header maps are only the defaults
written in if NVM is blank or fails its version check.

So the header values are NOT evidence of what the car ran. The log agrees: at full
throttle the request sits on a hard ceiling of **exactly 123.0 Nm** (p50 = p95 = 123.0
over 707 full-throttle samples). No compile-time map produces 123. Either
`maxTorqueNm` in NVM was set to 123, or something downstream derates. Either way
**NVM had been written**, so the kp / clamp the car actually used are UNKNOWN.

Consequences, all of them real:

- `parse_accel_test.py` builds its pure-P check from `TC_150_KP = 0.470` and
  `TC_150_MAXLIM = 0.75`. Unfounded. The `r_P` column is comparing against a gain
  the car may never have had.
- `accel_model_tc.m`'s "TC shipped kp 0.47" case is the same guess. The timing
  table in section 4 is still valid as a *gain sweep* (relative comparison), but
  the row labelled "shipped" is not necessarily the car.
- Section 6 step 3, "kp 0.47 to 0.94", is written against a number we cannot
  confirm. The car may already sit at 0.591.
- `torque_getSlipTarget()` returns `torque_data.slip_request`, a variable. The
  parser hardcodes the 0.10 `TC_TARGET_SLIP` constant. Also worth reading back.

**Fix, and it is cheap.** There are getters for the live values already
(`percentMaxTcLimit`, `percentILim`, `thousandthKp/Ki/Kd`, torque.c:1060-1080 region,
alongside `torque_getSlipErrorP/I/D`, `torque_getSlipTarget`, `torque_getTorqueReduction`).
Read them back over CAN once at key-on and log them with the run. Until that
happens every gain number in this document is DEFAULT-ASSUMED, not MEASURED.

Add to the section 6 step 1 logging list: the five gain readbacks plus
`torque_getSlipTarget()`. `torque_getSlipErrorD()` is a free check on all of the
above, it must read a flat 0.0 forever. If it ever does not, someone switched
`lib_pi_typeb_calc` to `lib_pid_typeb_calc` and section 2's warning just went live.

### 2b. One more data gotcha

`VCFRONT_torqueRequest` contains **200.0** as a sentinel. It is above every map
maximum and sits at the 99th percentile, so a naive `max()` or a high-percentile
statistic returns 200 and means nothing. Filter it before using the channel. The
real full-throttle value is the 123.0 ceiling above.

Slip definition (`app_vehicleSpeed_getAxleSlip(AXLE_REAR)`):
`slip = (v_rear_axle − v_vehicle) / v_vehicle`, with `v_rear_axle` from rear axle rpm
through `TIRE_RADIUS_M`. **Not** rear/front. TC is gated off below
`TC_VEHICLESPEED_THRESHOLD_MPS`. Loop runs at **100 Hz**.

**If the embedded team ever switches to `lib_pid_typeb_calc` to get D:** its D term is
`kd · x / dt`, i.e. proportional to *error over dt*, not `d(error)/dt`. That is not a
derivative and will misbehave. Flag it before they enable it.

---

## 3. What the log showed

63 hard-accel segments; **4 with TC actually active** (t ≈ 15554.7, 15914.2, 16151.1,
21821.2). The rest of the session TC was off or never engaged.

Best launch is **t = 15554.7** (full throttle, demand 123 Nm, 0→97.8 kph):

- slip spikes to **7.58** at the launch instant, *before* the speed gate opens
- TC then cuts the request 123 → **42 Nm** (y ≈ 0.66)
- slip settles into **0.08–0.15 by ~0.8 s**, then holds with mild ±0.03 ringing
- steady state sits **below** target (~0.08 vs 0.10) — under-uses grip, and there is
  no integrator to remove it

The "36× slip outlier" at t ≈ 15555 that the brief flagged is **a genuine
standing-start wheelspin, not a sensor dropout**: rears at 251 rpm, fronts at 6.7,
car not moving. Divide-by-almost-zero. The firmware already ignores this region; the
parser now gates it the same way.

**Effective launch grip, back-figured from vehicle acceleration** over 3 TC-active
standing starts: μ ≈ **1.20–1.27** (0.77–0.82 g against transferred rear load), vs the
params tyre's 1.365. About 10% lower — enough to flip the car from "just holds" to
"lights them up". MEASURED, 3 samples.

---

## 4. The sim

`accel_model_tc.m` is a **second, separate** sim. It does not replace `accel_model.m`.

Structure: two coupled rotational states plus the vehicle —
```
vehicle : m·dv/dt      = Fx − drag − rolling
rear whl: Iw·dω/dt     = T_axle − Fx·r
slip    = (ω·r − v)/v      -> tyre makes force from it
```
There is **no torque cap anywhere**, which is how it sidesteps `accel_model.m`'s cap
bug: a wheel spinning too fast simply makes less force. The launch comes out
traction-limited by physics rather than by a clamp.

Two slips on purpose, don't merge them:
- `slip_of()` — the firmware's, gated below the speed threshold (controller is
  genuinely blind down there)
- `slip_phys()` — regularised by `V_EPS = 1.0 m/s` so it is finite from rest.
  **Using the gated one for tyre force deadlocks the sim** (no slip → no force → no
  speed → no slip). That bug was hit and fixed; don't reintroduce it.

`emulate_firmware_pure_p = true` reproduces the shipped behaviour exactly (kd
ignored). Keep it true when comparing against logged data. The full PI(D) is
implemented so you can explore what enabling ki/kd *would* do.

Simulink: `build_accel_tc_simulink` generates `accel_tc_sim.slx`. Both the `.m` and
the Simulink model call `lib/accel_tc_core.m`, so they cannot drift. Both give
**4.665 s** at `mu_scale = 1.0` (vs `accel_model.m`'s 4.669 — good agreement).

### Timing results (0–75 m at 4.61:1)

| case | time | vs no TC |
|---|---|---|
| grippy (μ 1.37), no TC | 4.664 | — |
| grippy, TC shipped | 4.665 | 0.00 |
| grip-limited (μ ≈ 1.24), no TC | 6.851 | — |
| grip-limited, TC shipped kp 0.47 | 6.022 | −0.83 |
| kp → 0.94 | 5.471 | −1.38 |
| kp → 1.50 | 5.000 | −1.85 |
| kp 0.47 + ki 2.0 / ilim 0.5 | 5.094 | −1.76 |

Having TC ≈ 0.83 s; tuning it ≈ 0.55–1.0 s more. **Both worth nothing on a grippy day.**
Ringing appears at kp ≥ 1.5 (oscillation count 3 → 7), so the useful band is kp 0.9–1.5.

---

## 5. Known limitations — do not quote around these

**The sim is bistable around `mu_scale ≈ 0.97`.** Above it the tyre hooks up (4.67 s,
TC idle); below it breaks away and limit-cycles (5.7–6.0 s). The real car did **both**
— spun to slip 7.6 *and* still ran ~4.4 s, because TC caught it in ~0.3 s. The assumed
tyre tail (μ falls to ~0.52 of peak at high slip) is too pessimistic to recover like
that. Consequence: **the absolute 0–75 m in the breakaway regime is unvalidated.** Use
the sim for *comparing gains*, where the tyre model is common and largely cancels.
Fix = a measured longitudinal μ-slip curve, which we do not have.

**Because the model breaks away harder than the car, the timing gains above are upper
bounds.** Expect less on track.

**10 Hz log vs 100 Hz controller.** Settling, steady-state error and gross overshoot
survive that. Ringing above 5 Hz does not. **Gains cannot be identified from this
data** — closed-loop lag makes a naive fit return a *negative* kp. `p_term`, `i_term`
and `slipRear` are already exposed via CAN getters (torque.c:1031-1046); log them at
100 Hz and identification becomes possible.

**`TIRE_RADIUS_M = 0.2032` (firmware) vs `p.r_wheel = 0.2286` (params)** — an 11%
disagreement. It cancels in slip when vehicle speed is front-wheel-referenced, but not
when GPS/IMU drives the estimate. Could not be resolved from this log: there is no GPS
channel, and `vehicleSpeed` is derived from the same constant, so measuring radius
from it is circular. **Needs a GPS-vs-wheel-rpm comparison to settle.**

**The tyre shape constants are GUESSESTIMATEs** (`s_peak = 0.12`, `C = 1.65`). The
structure is honest; the curve is not measured.

---

## 6. Recommended next steps, in order

1. **Log TC internals at 100 Hz** (`p_term`, `i_term`, `slipRear`, `torqueReduction`,
   plus driver demand). Without this, no further gain identification is possible and
   everything stays sim-only.
2. **Enable the integral**: `ki ≈ 2.0` **with `ilim ≈ 0.5`**. `ki` alone does nothing
   while `ilim = 0`. Biggest single sim gain and it fixes the below-target steady error.
3. **kp 0.47 → 0.94.** Low risk, no ringing until 1.5.
4. **Shrink the unmanaged launch window.** Slip of 7.6–8.6 happens on every standing
   start *before* the speed gate opens, unmanaged by any gain. Launch control or a
   lower gate is likely worth more than steps 2 and 3 combined. No number available —
   there is no logged example of the car managing that phase.
5. **Measure loaded rolling radius** (GPS/odo distance vs integrated wheel rpm). Settles
   both the firmware-vs-params radius question and a 5% correction to every
   tractive-force number in the repo.
6. Decide whether `parse_accel_test.py` moves into `tools/`.

---

## 6b. Three ideas to evaluate (came in as a design suggestion)

Owner wants these on the list. All three have real engineering behind them, but
each has a catch. Ranked by value. Read the catch before you write any code — one of
them shipped with a broken code sample.

### (a) TC clamp as a real traction measurement — do this first, best idea

The TC holds slip near peak grip, so **the torque where the PID clamps is an empirical
measurement of the traction-limited torque** — the one thing we've never had (no
measured longitudinal μ, see section 5). Back out grip at that operating point:

    mu ≈ (T_clamp * gear_ratio / r_wheel) / N_rear

and check it against what the tyre model predicts at that slip. If they agree, the
derived curve is validated at a real point, which partly closes the "±unvalidated
breakaway regime" hole.

- **Catch:** you need the **rear normal load** at that instant (static + weight transfer
  + downforce), not just the torque. Compute it from the measured longitudinal accel.
  Without `N_rear` you can't turn the clamp torque into a μ.
- Needs the 100 Hz internals log from step 1 to see the clamp instant clean. On the
  10 Hz log the clamp point is smeared.

### (b) Discrete PID loop inside the accel sim — sound, mostly already the plan

This is the second, TC-aware accel sim. Structure is right: run the controller on a
**fixed 100 Hz clock** (accumulate time, fire every 0.01 s — the solver steps by `dw`
so `dt` varies, don't run it per solver step), then
`T_use = min(T_motor_peak, T_driver_request, T_TC_cap)`.

- **Catch 1:** regulate **slip ratio** `(v_rear - v_veh)/v_veh` to 0.10, NOT slip
  velocity `(w_rear - w_front)`. The suggestion used velocity. Wrong quantity, wrong tune.
- **Catch 2:** the firmware is **type-b PI with integral leak + limit**, not a textbook
  parallel PID. `kd` is not connected to anything (section 4). Mirror the real structure
  or the sim tune won't transfer to the car.

### (c) Dynamic Kt for saturation — right physics, DON'T paste their code

Constant `Nm_per_Arms` underestimates copper loss at high torque and biases the ratio
pick low (this is the constant-Kt bias already flagged in the earlier audit). Modelling
Kt droop is legitimate. And we can now **fit the droop from data** — today's launch log
has pack current and torque together, so calibrate it, don't guess.

- **Their code sample is broken. Do not paste it.** It (1) swaps the argument order to
  `emrax208_efficiency(torque_abs, rpm, p)` — ours is `(rpm, torque_abs, p)`, so every
  caller would feed rpm as torque; (2) drops the `eta_inverter` haircut, silently
  undoing the real-world 0.90 correction; (3) drops the `1e-6` divide guard.
**TRIED IT 2026-08-11. The droop is NOT identifiable from this log. Do not add a
droop constant.** Probe kept at
`tools/kt_droop_probe.py`. What happened:

- Gate `|T|>10 Nm, rpm>500, P_dc>500 W` leaves 2207 samples, 1333 of them steady
  enough to use at 10 Hz. Torque coverage is fine on paper (447 samples above
  120 Nm), so sample count is not the problem.
- Sweeping `alpha` from 0.00 to 0.30 (a 30% droop, far bigger than anything real)
  moves the loss residual from 2897 W rms to 2704 W rms. That is a 7% move on the
  residual for an absurd droop. The fit is flat in alpha. Nothing to identify.
- Reason it is flat: measured pack-to-shaft loss averages 2964 W, while modelled
  copper loss at the 95th-percentile torque is only 795 W. Copper is a small
  slice of the loss budget here, so bending Kt barely moves the total. The
  residual is dominated by inverter and other losses that `eta_inverter`
  currently absorbs as a flat multiplier, and a flat multiplier is exactly what a
  droop term would have to be separated from.
- **The circularity that kills it anyway:** `PM100DX_torqueFeedback` is the
  inverter's own torque *estimate*, derived from measured current through its
  internal motor model. So regressing pack current against it partly recovers the
  inverter's Kt assumption, not the motor's physics.
  `corr(ideal lossless DC current, measured pack current) = 0.9983`, the two
  channels are near redundant. Fitting Kt from them is close to fitting a
  constant to itself.
- Separate observation worth chasing: measured pack-to-shaft efficiency in this
  log runs p50 **0.775**, p90 0.889. The model with `eta_inverter = 0.95` produces
  roughly 0.90 typical. Some of the gap is low-load points and 10 Hz channel skew
  between the BMS and the inverter, but not obviously all of it. MEASURED, one log,
  not yet reconciled.

Settling this needs a torque source independent of the inverter: a dyno, or shaft
torque backed out of vehicle acceleration on a run that is NOT traction limited.
Until then the constant-Kt bias stays documented and unfixed, which is the honest
answer.

- **`Kt_droop` must be MEASURED/fit, not a plausible constant.** A hardcoded "droops
  ~12%" is exactly the fabricated-number thing this repo refuses (section 7). Fit it
  from the current-vs-torque log, or leave it as the documented bias the audit already
  carries. Rewrite the function from the existing one; keep the current signature and
  keep `eta_inverter`.

---

## 7. Style rules for this repo

Carried from the previous handoff, still in force:

- Owner's voice: casual, direct, dry. **No AI polish**, no "leverage/utilize/robust".
- **No em dashes.** Owner asked for them gone.
- Say "physics model", never "our model".
- **No proper nouns as method names.** Describe what the method does. `af/dteff`,
  `Andrew`, `freeman803` were all purged; don't reintroduce them.
- Every constant keeps provenance + an honesty tag: MEASURED / DATASHEET /
  GUESSESTIMATE. Unknown values print UNKNOWN or fail loudly — **never a plausible guess.**
- `params_cfr26.m` is the single source of truth. Don't put numbers in scripts.
- **Never push without the owner's explicit go-ahead.** Never add yourself as a
  contributor or co-author.

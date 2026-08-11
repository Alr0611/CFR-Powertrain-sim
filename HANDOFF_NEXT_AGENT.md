# HANDOFF — verify_math clean, redline bug fixed, and the radius is falsified

Written 2026-08-11, second session. Read this before running anything. Nothing is pushed.

The short version: the tyre fit had a real bug and it's fixed, the redline bug was real
and it's fixed, and the 0-75 m gap turned out not to be a gap in the force path at all.
It's the wheel radius, and the log rules the current value out on energy grounds.

---

## 0. Hard rules, inherited and non-negotiable

- **Never fabricate a number.** Unknown prints UNKNOWN or fails loudly. Every constant
  carries provenance + MEASURED / DATASHEET / DERIVED / GUESSESTIMATE.
- **Do not tune a number to make a result match.** If the sim disagrees with the car,
  report it.
- **Do not widen a `verify_math` check so your own change passes.** Two checks were
  restated this session and both carry a written justification in place. Read it before
  touching them.
- `params_cfr26.m` is the single source of truth. No numbers in scripts.
- **Never push without the owner's go-ahead.** Author is `Alr0611`. Pushes happen
  locally through the owner's git GUI, no collaborators.
- No em dashes. Casual, direct, dry. Keep comments short, not essays.
- **DO NOT TOUCH THE FIRMWARE. AT ALL.** Separate repo, embedded team owns it. Read the
  PID code as reference for what the TC does and nothing else. The owner also said not to
  lean on firmware code or constants as truth, derive instead where you can.

---

## 1. What changed this session

| file | change |
|---|---|
| `params_cfr26.m` | tyre coefficients refitted with PDX2 constrained; stale fit comments removed |
| `lib/motor_peak_torque.m` | **redline bug fixed here**, torque now goes to 0 above redline |
| `lib/accel_tc_core.m` | dropped the `min(rpm, p.redline)` clamp |
| `accel_model.m` | same clamp dropped in `recovery_40_80` |
| `lib/top_speed.m` | guard so float overshoot at redline doesn't return zero force |
| `verify_math.m` | sections 6 and 14 restated, now 50/50 |
| `sweep_accel_tc_sim.m` | NEW. TC sweep, ratio x gain, one page per torque map |
| `build_accel_tc_sweep_simulink.m` | NEW. Builds `accel_tc_sweep_sim.slx` |
| `lib/accel_tc_sweep_sample.m` | NEW. Config-keyed cache so sweeps can't go stale |
| `tools/*.py` | 6 new analysis tools, listed in HOW_TO_USE.md |
| `HOW_TO_USE.md` | updated for the new models and tools |

`accel_sim.slx`, `build_accel_simulink.m` and `accel_tc_sim.slx` are untouched on purpose.

---

## 2. verify_math is 50/50

Was 45/48. Count went to 50 because two restated checks each became two narrower ones.

**`mu decreases with load` — fixed properly, not by relaxing anything.**
The old free fit returned PDX2 = +0.00248. That was a fit artifact. Three tools show it:

- `tools/mu_vs_load_nonparametric.py` reads peak mu off raw samples, finds it falling 5%
  from 600 to 1200 N.
- `tools/mu_load_model_vs_data.py` TEST 2 is the clean one. mu at MATCHED SLIP, mean of
  the samples in each (slip, Fz) cell. Falls with load in every single slip band, -3.4%
  to -7.3%. No peak-finding, no model, no fit.
- `tools/pdx2_identifiability.py` shows why the fit missed it. Pin PDX2 anywhere from 0 to
  -0.20 and refit the other 13, RMS moves 3.7 N out of 85. PKX2 swings 6.3 to 25.4 across
  that grid. The slip-stiffness terms eat the load sensitivity and PDX2 parks wherever.

`tools/refit_mf_pdx2_constrained.py` solves for the PDX2 that reproduces the measured
peak-mu slope, refitting everything else. **PDX2 = -0.08617**, costs +0.9% RMS. Bonus: the
fitted peak moved to SL 0.16-0.20, which is inside the measured range. The old fit peaked
at 0.21-0.35, outside the data.

**`nominal mu in 1.3-1.4` and `top-speed rpm under redline` — both restated.** The first
was a band drawn around a superseded derived value; the second hardcoded 112 kph in a
script and only ever asserted that one speed was reachable. Both replaced with real
falsifiable claims. Justification is written at each site.

**LMUX = 0.65 is still the biggest unmeasured assumption in the tyre model.** Nothing this
session measured it. It's now guarded by a range check so nobody quietly moves it to
shift an accel time, but a guard is not a measurement.

---

## 3. The redline bug was real, and fixing it produced a real optimum

The bug: `interp1(..., min(rpm, p.redline), ...)` clamps the LOOKUP, not the RESULT, so
past redline the motor kept making redline torque forever.

**Three call sites had it, not one.** `lib/accel_tc_core.m`, `accel_model.m`
(`recovery_40_80`), and `lib/accel_075m.m`, which feeds the gear study's trade-off sweep.
Fixed centrally in `lib/motor_peak_torque.m` so all three are covered.

Proof it was real: at 5.20:1 the sim trapped 106.2 kph against a 96.1 kph redline limit.
Post-fix every ratio respects its limit.

Ratio sweep now has a genuine optimum where it used to fall monotonically:

```
 ratio   t75    trap   redline_kph
  4.61  4.988   102.1     108.4
  5.20  4.770    95.6      96.1
  5.80  4.713    85.8      86.2   <- best on the grid
  6.40  4.764    77.8      78.1
```

`lib/accel_075m.m` puts its optimum at 5.20 instead. The two disagree because 075m has no
123 Nm driver cap. **Treat both optima as provisional until the radius is settled**, since
the radius moves the redline speed and therefore where the optimum sits.

---

## 4. The 0-75 m gap: it isn't the force path, it's the radius

Worked in the order the last handoff asked for. Gearing first, then the force path.

**Gearing is fine.** `G = motor_rpm / rear_wheel_rpm` measured straight off the log, no
radius involved: **4.6133** against 4.6154 nominal. -0.04%. Not the fault.

**The torque envelope is fine.** Delivered torque at full throttle is 122-124 Nm flat from
1500 to 4500 rpm, against the 123 Nm the sim assumes. The motor delivers about 1% over
request, not 22%.

**eta cannot explain it.** At r = 0.221, even eta = 0.94 leaves +0.216 s of gap. There is
no defensible eta that closes it. The last handoff's "eta is the biggest lever" is dead.

**The radius-free check.** `tools/rpm_vs_time_check.py` compares sim motor rpm against
logged motor rpm versus time since launch. Neither side needs a radius. The base sim runs
**14.0% below** the logged rpm through the whole run. So the deficit is real.

**The falsification.** `tools/radius_from_energy_balance.py`. Motor energy is
`integral of T*omega dt`, which contains no radius. Car energy is dKE + drag + rolling,
which scales as roughly r^2. The ratio is the required drivetrain efficiency:

```
  r (m)   implied eta
 0.2000       0.875     ~16 inch effective rolling
 0.2032       0.903     firmware TIRE_RADIUS_M
 0.2210       1.070     params p.r_wheel        <-- NOT PHYSICAL
 0.2286       1.146     18 inch OD / 2          <-- NOT PHYSICAL
```

At 0.221 the road absorbed 144.1 kJ while the motor produced 137.7 kJ. That can't happen.
All four runs agree independently. At eta = 0.794 the log implies **r = 0.1905 m**.

Three things point the same way: this energy solve (0.19-0.20), the firmware's own
vehicleSpeed scaling (0.1998 recovered from undriven front wheels), and the firmware
constant 0.2032. All near a 16 inch, none near 0.221.

**`p.r_wheel` was deliberately NOT changed.** Changing it would be tuning a number to
close a gap, which is the one thing this repo doesn't do. 0.221 is a genuine measurement,
of the Hoosier 18.0x6.0-10 RE channel. The question is whether that's our tyre. The owner
says "pretty sure the 18.0x6.0-10" but off a parts list, not a tape measure.

**This is the one thing to resolve next and it gates a lot.** Tape an unloaded rear tyre.

- 18 inch OD confirmed: r 0.221 stands, the measured tyre fit stands, and there is a real
  unexplained 14% force deficit that eta and torque have both been ruled out of.
- 16 inch OD: r ~0.195-0.203, everything reconciles, firmware was right, **but** Round 9
  has no drive/brake runs for the 16 so the whole longitudinal tyre model reverts to
  estimate.

---

## 5. Dynamic Kt, per torque bin

`tools/kt_per_torque_bin.py`. Not a droop constant, that question stays closed.

Pack-to-shaft efficiency per torque bin, energy ratios, no regression:

```
   T bin      n    Pmech/Pelec
   5-20     333       0.760
  20-40     321       0.735
  40-60     109       0.751
  60-80      60       0.785
 100-115     48       0.854
 115-130    238       0.878
```

That's a clean rise with torque and it's the trustworthy part of the file.

**The useful negative result:** `torqueFeedback` cannot be under-reading by the ~14% the
accel gap needs. If it were, true Pmech/Pelec at high torque would be 0.878 x 1.14 = 1.00.
So the Kt route does not explain the accel gap, which is what pushed the investigation
onto the radius.

**Known weakness, don't quote the regression half.** The per-bin slope estimator still
returns implied eta above 1.0 in the top bin even after a quasi-steady filter. Efficiency
varies with speed inside a bin, so the slope isn't cleanly 1/eta. The energy ratios above
are fine, the `k_inv` column is not. Fixing it needs either synchronised logging or phase
current, neither of which this log has.

---

## 6. Carried forward

- **Tyre size.** Blocking. See section 4.
- **Pressure is settled at 71 kPa / 10.3 psi**, owner confirmed. No refit needed.
- **High-slip tail still not measured.** Sweep reaches |SL| <= 0.186, launch runs 5-7.
  Everything past 0.19 is extrapolated shape. Still the honest hole in the tyre model.
- **Live TC gains still UNKNOWN.** Log pins full throttle at 123.0 Nm, matching no
  compile-time map, so NVM was written. Read back the five gain getters over CAN.
- **TC still worth 0.000 s in the sim** at every ratio, peak slip only 1.3-1.7, while the
  real car spun to 7.58. Unresolved. Likely the extrapolated high-slip tail plus a dirty
  hot surface. Do not invent a mu_scale for it. Log-derived effective mu is in
  `tools/log_force_path_audit.py` STEP 5, but note it depends on the radius too.
- **Regenerate everything downstream of `r_wheel`** once the radius is settled:
  `gear_ratio_optimization.m`, `accel_model.m`, top speed, tractive effort,
  `accel_fatigue.m`, `fatigue_spectrum.m`.

---

## 7. Mistakes made this session

1. Wrote enormous comment blocks in the source files. The owner asked for short and human,
   not a story per constant. Trimmed, but check anything I missed.
2. First pass at logged acceleration used `np.gradient` on quantised 10 Hz wheel speed and
   got a_max of 1.10 g, which made the gap look like 50%. Differentiation noise. The
   energy budget gives ~10-14% and that's the number to trust. **Integrate, don't
   differentiate, on this log.**
3. First per-torque-bin Kt run had no steadiness filter and returned efficiency above 1.0.
   The filter helped but did not fully fix it, see section 5.

Pattern, same as last session: verify before asserting, prefer measurement over inference,
and prefer integrals over derivatives on a coarse log.

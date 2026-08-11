# The drivetrain sim, explained

For someone who knows the car but not the MATLAB. What the code calculates, where every
number comes from, and which ones you're not allowed to quote yet.

Full equations are in `EQUATIONS.md`. Every constant lives in `params_cfr26.m`.

---

## 1. The trust labels

Every constant in `params_cfr26.m` has a tag saying where it came from. This is the most
important thing in the repo. When someone asks "is that number real", the tag answers it.

| Tag | Means | Example |
|---|---|---|
| **MEASURED** | We physically measured it on our car. Trust it. | Car mass 294 kg on scales. Wheel radius 0.200 m by roll-out. |
| **DATASHEET** | The manufacturer says so. Usually best case, on a bench, on a good day. | Motor peak torque 150 Nm, redline 6000 rpm. |
| **DERIVED** | Calculated from real data, but not *our* data, or not directly. | The whole tyre grip model. Real test data, wrong tyre. |
| **GUESSESTIMATE** | Someone made it up with a straight face. | Wheel inertia shape factor, CV joint loss. |

The rule that keeps this honest: numbers live in `params_cfr26.m` and nowhere else. If you
find a constant typed into a script, that's a bug. It will drift out of sync with the real
one and nobody will notice for six months.

---

## 2. The force path

Everything the sim does is one chain. Energy leaves the battery, each stage takes a cut,
whatever survives pushes the car.

```
battery -> inverter+motor -> spur+chain+diff -> halfshafts -> tyre -> ground
             ~0.86              0.83            0.956        grip limit
```

The mechanical stages multiply out to `p.eta_drivetrain = 0.794`:

```
0.98 (spur) x 0.95 (bearings) x 0.97 (chain) x 0.92 (diff) x 0.956 (halfshafts) = 0.794
```

Only the first bit, pack to shaft, is measured on our car. The four mechanical stages are
assumptions from the DT memo and none of them has ever been on a dyno. So the headline
"79% efficient" is one measurement wearing four guesses as a hat.

---

## 3. Motor: how much twist you get

Two limits, you always get the smaller one.

```
if rpm > redline:  T = 0                        // overspeed cut
else:              T = min(150 Nm, Power(rpm)/omega)
```

Below ~3300 rpm the flat 150 Nm cap binds, so the motor makes everything it's got. Above
that, power runs out first and torque falls off as `Power/speed`. That's why revving out
past the sweet spot hurts.

**The 123 Nm thing.** The car never actually asks for 150. The log shows full throttle
pinned at exactly **123.0 Nm** and the motor delivering 122-124. So `p.T_driver_max = 123`.
That number matches none of the compile-time firmware maps (100/130/150), which is how we
know someone wrote it to NVM at some point and didn't write it down.

### Efficiency

```
I_rms    = T / Kt                 // Kt = 0.83 Nm per amp
P_copper = 3 * I_rms^2 * R_phase  // heat in the windings
P_core   = a*rpm + b*rpm^2        // magnets dragging through iron
eta      = P_mech / (P_mech + P_copper + P_core)
```

Copper loss goes as current squared so it hurts at high torque. Core loss goes with speed
so it hurts at high rpm. There's a sweet spot in between and the gear ratio decides whether
you live in it.

> **Known bias.** `Kt` is treated as constant. On a real motor it droops as the iron
> saturates, so a given torque actually costs more current than we assume. That means we
> underestimate copper loss, worst at high torque. We tried to measure the droop off the
> telemetry and couldn't: the torque signal is itself derived from current, so you end up
> asking the data to confirm itself.

---

## 4. Gears

```
G = (30/15) * (30/13) = 4.6154    // spur x chain

wheel_torque = motor_torque * G * eta
wheel_speed  = motor_speed  / G
```

That's the entire gearbox. Multiply torque, divide speed.

**This one is confirmed.** We measured `G` off the log as motor rpm over rear wheel rpm,
which involves no tyre radius at all, and got **4.6133** against the tooth count 4.6154.
0.04% out. The gearing math is not a suspect in anything, which was worth establishing
because it let us go looking elsewhere.

---

## 5. Wheel radius: three numbers, not one

This is the part everyone gets wrong. We got it wrong for three sessions.

| Radius | Ours | What it is | Used for |
|---|---|---|---|
| Unloaded | 0.203 m | Jack it up, tape centre to tread | Basically nothing |
| **Loaded** (`r_load`) | **0.1901 m** | Ground to wheel centre, tyre squashed | The moment arm |
| **Effective rolling** (`r_wheel`) | **0.2000 m** | Distance travelled per radian | Speed and slip |

Order is always `loaded < effective < unloaded`.

The reason effective sits above loaded is genuinely counterintuitive, so here's the
explanation you can give the firmware guys: a loaded tyre rolls *further* per revolution
than its squashed radius suggests. The tread band is basically inextensible, it doesn't
stretch or shrink, so it walks over its own flat spot. Flattening the contact patch doesn't
delete circumference.

**Why one number for both is wrong.** Force is `torque / r_load`. Speed is
`omega * r_wheel`. Using the rolling radius for the force arm understates wheel force by
**5.2%** and cost about 0.10 s over 75 m. Both are now measured on our tyre and the sim
uses each for its own job.

### Measuring it, two minutes

Chalk a mark on the tyre, mark the ground under it, push the car straight through a whole
number of revolutions, mark the ground again, measure.

```
r_eff = distance / (2*pi*revolutions)
```

Driver in the seat, because load is the entire point.

Also worth passing on: **this is not a constant.** It shrinks with tread wear, with lower
pressure, and with more load. There's no single correct value forever, so re-measure on a
new set.

---

## 6. Tyre grip: the weakest link

A tyre doesn't have one grip number. It makes force depending on how much it's slipping.

```
slip = (wheel_speed * r - car_speed) / car_speed
```

Zero slip is free rolling, no force. Force climbs steeply with a bit of slip, peaks around
10-20%, then falls off. Past the peak you're spinning up and getting *less* grip, which is
the entire reason traction control exists.

The curve shape comes from the Pacejka "Magic Formula". Worth knowing that it's a curve
fit, not physics from first principles. It's called magic because it works, not because
anyone derived it.

> **Read this before quoting any grip number.**
>
> Our coefficients are fitted to real tyre test data from a **Hoosier 18.0x6.0-10**. The
> car runs a **Hoosier 16x7.5-10**. The test programme never ran a drive/brake test on
> ours, so there is no forward-grip data for our tyre and there never was.
>
> The donor casing is 1.5 in narrower and 2 in bigger in diameter. Both tyres *do* have
> cornering data though, so we could measure how far off the transfer is: ours grips about
> **4% less** sideways. So the model is mildly optimistic. That's an anchor, not a fix.

### The tail is a guess

Test data goes out to 19% slip. A standing start hits 500-700% slip. Everything past 19%
is the curve fit extrapolating into territory nobody measured, and that's exactly the
region that decides whether a spinning tyre recovers. So if anyone asks how confident we
are about wheelspin behaviour: we aren't.

### One thing we did get right

Grip falls as you push a tyre down harder. Sounds backwards, is real, well known.

Our fit originally said grip was *flat* with load, which is wrong. The reason is worth
understanding because it'll happen again: the fit has 14 knobs and several of them can
imitate each other. The load-sensitivity knob could be set anywhere from 0 to -0.20 and the
fit quality barely moved, so the optimiser just parked it wherever and went home.

The fix was to stop asking the fit and read the answer off the raw data instead. Bin the
measurements by load, compare grip at the *same* slip, look at it. Falls 3-7% from 600 N to
1200 N in every single slip band. No model, no fitting, no room to argue. Then we forced
the coefficient to match that.

General lesson: if a fit gives you a weird answer, check whether that parameter is even
identifiable before you believe it.

---

## 7. The two accel models

There are two, they disagree, and that's on purpose.

| | `accel_model.m` | `accel_model_tc.m` |
|---|---|---|
| Wheel speed | Not modelled, point mass | Its own state, so slip is real |
| Grip | An instantaneous force cap | Tyre makes force from slip, nothing clamped |
| Traction control | None | Mirrors the firmware |
| Torque ceiling | 150 Nm datasheet | 123 Nm, what the car asks for |
| Integrates over | Motor speed | Time, at 2 kHz |
| **0-75 m at 4.61:1** | **4.48 s** | **4.70 s** |

Real car did **4.64 s**. It lands between them, which is a good sign. The optimistic one is
optimistic, the conservative one is conservative, and reality is in the middle where it
belongs. Most of the 0.22 s between them is just the torque ceiling, 150 vs 123.

> **Known bug, left in on purpose.** `accel_model.m` has a units error in its traction cap:
> it divides by drivetrain efficiency twice, so the grip limit is ~26% too high and never
> actually binds. It's left alone so no published number silently moves.
>
> Practical upshot: any claim from that model like "grip doesn't affect our accel" is an
> artifact of the bug, not a result.

---

## 8. Traction control

The firmware watches rear axle slip, compares it to a 10% target, and cuts torque in
proportion to the error.

```
error     = measured_slip - 0.10
reduction = clamp(kp * error, 0, max_cut)
torque    = driver_torque * (1 - reduction)
```

> **It's called a PID. It's a P.**
>
> The function the TC calls only ever writes the P and I terms, never D, so the D gain does
> nothing at all. And both shipped maps set the integral limit to zero, which disables the
> I term twice over for good measure. So the whole controller is one multiply.
>
> Worth knowing before someone spends a weekend tuning D and reports that it made no
> difference.

There's also a speed gate: below 0.5 m/s TC is off entirely, because slip divides by car
speed and that blows up at a standstill.

### Why TC does nothing in our sim, and why that's correct

Peak torque cut across every gain we swept: zero. Looked like a bug. It isn't.

We derived the grip we actually had that day from the logged launches (hot dirty parking
lot, so about 0.85x the clean test data). At that grip:

| Torque ceiling | TC does |
|---|---|
| 123 Nm (what the car runs) | nothing, 0% cut |
| 130 Nm | almost nothing, 5% |
| 150 Nm | saturates its clamp, 75% |

At 123 Nm on that surface the car is **torque limited, not traction limited**. There is
nothing for TC to cut. Raise the ceiling to 150 and TC immediately becomes essential.

So the honest statement: TC is insurance that isn't currently being called on. If anyone
enables the 150 Nm map it stops being optional.

### The 7.58 slip number that scared everyone

Old notes said the car spun to 7.58 slip on every launch while the sim only hit 1.4, and
treated that as a serious model failure. It wasn't.

Slip divides by car speed, so at the instant of launch it explodes toward infinity.
Depending on which 10 Hz sample happened to land closest to standstill, the "peak" reads
anywhere from 3 to 36. Every run spends exactly 0.3 s above slip 1.0, at walking pace,
where it costs almost no time and where TC is switched off anyway.

Real wheelspin, but brief and cheap. Not the crisis it looked like.

---

## 9. What we found this round

### The wheel radius was wrong by 11%

The sim thought the car had 18 in tyres. It has 16 in tyres.

The old value, 0.221 m, was a genuine measurement. Of a tyre we don't run. That's how it
survived so long: it had a MEASURED tag and a paper trail, it was just measuring the wrong
object. Good lesson, a number being measured doesn't help if it's measured on the wrong
thing.

Three independent checks on the real value:

| Method | Result |
|---|---|
| Roll-out on the car (2 revs, 99 in) | 0.2001 |
| Our tyre's own test data | 0.1988 |
| Energy balance off the accel logs | 0.1975 |

Nothing shared between those three and they agree inside 1.3%. Fixing it took the accel
model from 14% slower than the real car to about 1%.

### A gearing bug that flattered short ratios

Above redline the code held torque at its redline value instead of cutting it, so the sim
let the car accelerate straight through the limiter. Free horsepower, no notes.

It only bites at high gear ratios, which meant it was quietly handing extra torque to
exactly the ratios the gear study was evaluating. Proof it was real: at 5.20:1 the sim
trapped 106 kph when redline only allows 96. Fixed, and the ratio recommendation moved.

### The firmware was fine

The repo used to claim firmware's tyre radius constant was 8% under and needed raising with
the embedded team. That was measured against our own wrong number.

Against the correct 0.200 m, firmware's 0.2032 is 1.6% over, and that's explained by tread
wear since theirs is a fresh-tyre nominal and ours is worn down. **Nothing to raise. We had
it wrong, not them.**

---

## 10. Things not to quote yet

If someone asks for one of these, give them the caveat with it.

| Number | Status | Why |
|---|---|---|
| Absolute grip / peak mu | DERIVED | Fitted to a different tyre, ~4% optimistic |
| Anything about wheelspin recovery | GUESS | Slip past 19% is extrapolated, from the wrong tyre |
| Belt-to-road factor `LMUX` | GUESS | It's 0.65 with nothing behind it, and it sits directly on grip |
| The four mechanical efficiencies | GUESS | Memo assumptions, none dyno'd or coastdown tested |
| CV joint loss coefficient | GUESS | Back-fitted to the memo's own assumed points, so it's circular |
| Live TC gains | UNKNOWN | NVM was written, every gain in the repo is a compile-time default |
| TC gain sweep results | VOID | TC never engages on this data, so the sweep is flat and says nothing |

**Safe to quote:** car mass, gear ratio, both wheel radii, motor torque actually delivered,
pack-to-shaft efficiency, and the fact that grip falls with load. All measured on our car
or our tyre.

### What would fix the biggest gaps, best value first

1. **Read the live TC gains over CAN at key-on.** Cheap, and every TC number is guesswork
   until someone does.
2. **Longitudinal tyre test on the 16x7.5.** Expensive, but it's the root of the grip,
   launch and TC uncertainty all at once.
3. **Coastdown or back-to-back dyno on the mechanical stages.** Turns four guesses into
   measurements.
4. **Re-run the roll-out on fresh tyres.** Two minutes, and the radius drifts with wear.

---

## 11. Running it

Open MATLAB, run `START.m`, then type a script name.

| You want | Type |
|---|---|
| Are the numbers self-consistent | `verify_math` |
| How quick is the car | `accel_model` |
| Accel with traction control | `accel_model_tc` |
| Sweep TC gains and ratios per torque map | `sweep_accel_tc_sim` |
| Which gear ratio is best | `gear_ratio_optimization` |
| Where the drivetrain losses are | `drivetrain_efficiency` |

`verify_math` is the important one. It's 50 checks that the repo's own numbers still agree
with each other. Change a constant, run it, and if something goes red you broke an
assumption somewhere else. Should always be 50/50.

**If you see "Undefined function":** the `lib` folder isn't on the MATLAB path. Run
`START.m`, or `addpath('lib')` from the repo folder.

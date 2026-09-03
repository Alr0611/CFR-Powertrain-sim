# CFR27 final-drive sprocket study

Fixed 15:30 gearbox (2.000) x chain (driven/13). Driver stays 13T, only the driven changes.

Chain geometry per Mott Ch.7. Everything below is tagged for where it came from.


## 0. Provenance key

`from-SHEET` = read out of the CFR24 workbooks. `DATASHEET` = Mott table or motor data.
`OWNER` = told to me directly by the owner. `CALC` = I computed it from tagged inputs.
`UNKNOWN` = not in any sheet, not measured, not guessed.


## 1. Fixed inputs pulled from the CFR24 tool

| Input | Value | Source | Tag |
|---|---|---|---|
| Chain | 520 | `KHK Sheet1!B11`, `Euro Sheet1!B11` | from-SHEET |
| Chain pitch P | 0.625 in = 15.875 mm | `Sprocket Gearing and Forces!C9,C11` | from-SHEET |
| Chain roller field | 0.25 in | `KHK Sheet1!B13` | from-SHEET |
| Driver teeth N1 | 13 | `Sprocket...!M8`, `KHK!B15` | from-SHEET |
| Driven teeth N2 (current) | 30 | `Sprocket...!M10` | from-SHEET |
| Gearbox | 15:30 = 2.000 | `Gear Design!D15,D16,D17` | from-SHEET |
| Motor | Emrax 208, 150 Nm, 68 kW | owner | OWNER |
| Transient torque seen in enduro/accel | 160 to 170 Nm | owner | OWNER |
| Max motor speed | 6500 rpm | `Sprocket...!M21` | from-SHEET |
| **Chain centre distance C** | **UNKNOWN** | not in any sheet | **UNKNOWN** |
| **Packaging envelope / clearances** | **UNKNOWN** | not in any sheet | **UNKNOWN** |
| **Sprocket mass / thickness** | **UNKNOWN** | not in any sheet | **UNKNOWN** |

Two notes on the sheet itself, both worth knowing:

- `KHK Sheet1!B13` is labelled *Roller Diameter* but the formula is `RIGHT(520,2)/10/8`, which is the
  520 roller *inner width*, not the roller diameter. Mislabel in the sheet, does not affect this study.
- The sheets disagree on peak torque: `Gear Design!D4` and `KHK!B2` say 140 Nm, `Sprocket...!C7` says 150 Nm.
  The owner says 150 Nm with 160 to 170 Nm transients, so I used 150 nominal / 170 worst case.


## 2. Validation gate: do I match the sheet's 13/30?

The sheet's pitch diameter column `B28:C71` is literally `=$C$11/SIN(PI()/N)`, which is Mott's
`D = P/sin(180/N)`. Same equation, so this should be exact.

| Item | Sheet | My calc | Error |
|---|---|---|---|
| 13T pitch dia | 66.3349808182 mm | 66.3349808182 mm | 0 |
| 30T pitch dia | 151.8725092069 mm | 151.8725092069 mm | 0 |
| Total ratio | 4.615384615384615 | 4.615384615384615 | 0 |

**GATE: PASS.** Exact to machine precision. Safe to proceed. (CALC)


## 3. The nine configs, geometry

`D = P/sin(180/N)` (Mott). `OD = P*(0.6 + cot(180/N))` (Mott). All CALC off from-SHEET P.

| Driven N2 | Total ratio | Pitch dia D2 (mm) | Outside dia (mm) | dD vs 30T (mm) | Chain length shift at fixed C (pitches) | Axle move to keep same chain (mm) | Min C for 120 deg wrap (mm) |
|---|---|---|---|---|---|---|---|
| 26 | 4.0000 | 131.70 | 140.27 | -20.17 | -2.0 | +15.88 | 65.4 |
| 27 | 4.1538 | 136.74 | 145.34 | -15.13 | -1.5 | +11.91 | 70.4 |
| 28 | 4.3077 | 141.79 | 150.42 | -10.09 | -1.0 | +7.94 | 75.5 |
| 29 | 4.4615 | 146.83 | 155.49 | -5.04 | -0.5 | +3.97 | 80.5 |
| 30 (current) | 4.6154 | 151.87 | 160.57 | +0.00 | +0.0 | -0.00 | 85.5 |
| 31 | 4.7692 | 156.92 | 165.64 | +5.04 | +0.5 | -3.97 | 90.6 |
| 32 | 4.9231 | 161.96 | 170.71 | +10.09 | +1.0 | -7.94 | 95.6 |
| 33 | 5.0769 | 167.01 | 175.78 | +15.13 | +1.5 | -11.91 | 100.7 |
| 34 | 5.2308 | 172.05 | 180.84 | +20.18 | +2.0 | -15.88 | 105.7 |

### What the last three columns mean

**Chain length shift.** Mott's `L = 2C/P + (N1+N2)/2 + ((N2-N1)/2pi)^2 * P/C`. Change only N2 and the
`(N1+N2)/2` term moves by `dN2/2` pitches. So:

- **Even** driven counts (26, 28, 30, 32, 34) shift by a **whole** number of pitches. Chain length stays even. Fine.
- **Odd** driven counts (27, 29, 31, 33) land on a **half pitch**. Chain has to be an even pitch count, so
  these need an offset (half) link, or you pull C in ~2 mm to swallow it. Offset links are the weak point
  of a chain, so on a car that matters.

This is the one result here that needs no centre distance at all, and it is the one that actually bites.

**Min C for 120 deg wrap.** Wrap on the small sprocket is `theta = 180 - 2*asin((D2-D1)/(2C))`.
Setting theta >= 120 deg reduces to `C >= D2 - D1`, which is C-free. That column is the hard floor on
centre distance for each config. If the measured C is above 105.7 mm, every config in this table clears
120 deg wrap. If it is below, the big sprockets start losing engagement.

## 4. Strength and rating, Mott Ch.7

### 4.1 Chain tension

Driver is 13T in every config, so tension is set by motor torque and the 13T pitch radius and
**does not change across the sweep**. Torque at the sprocket = motor torque x 2.000 gearbox.

| Case | Motor T (Nm) | T at 13T (Nm) | Chain tension (kN) | Tag |
|---|---|---|---|---|
| Nominal peak (Emrax 208) | 150 | 300 | 9.05 | OWNER |
| Transient seen in enduro/accel | 170 | 340 | 10.25 | OWNER |
| CFR24 sheet value | 140 | 280 | 8.44 | from-SHEET |

The 150 Nm row reproduces `Sprocket Gearing and Forces!M16` = 9.045 kN exactly. (CALC, gate passed)

### 4.2 Tensile margin

Mott Table 7-12 gives no. 50 chain (5/8 in pitch, same pitch as 520) an average tensile strength of
6100 lb = **27.13 kN** (DATASHEET, Mott T7-12).

| Case | Tension (kN) | Margin vs 27.13 kN |
|---|---|---|
| 150 Nm nominal | 9.05 | 3.00x |
| 170 Nm transient | 10.25 | 2.65x |

Caveat worth saying out loud: 520 motorcycle chain is **not** ANSI no. 50. Same pitch, different plate and
pin spec, and real 520 chain is usually stronger than the ANSI number. Using Mott's no. 50 here is the
conservative substitute because I do not have the actual 520 chain datasheet. Get the real tensile number
off the chain the team is buying and this margin goes up, not down.

### 4.3 Rated power, and why it does not close

Mott's power rating tables are 7-14 (no. 40), 7-15 (no. 60), 7-16 (no. 80). **There is no no. 50 table in
Mott.** So there is no clean table lookup for a 5/8 in chain. Bracketing at 13 teeth, 3000 rpm on the small
sprocket (6000 rpm motor through the 2.000 gearbox):

| Chain | Pitch | 13T @ 3000 rpm rating | Tag |
|---|---|---|---|
| no. 40 | 0.500 in | 2.79 hp | DATASHEET, Mott T7-14 |
| no. 60 | 0.750 in | 3.85 hp | DATASHEET, Mott T7-15 |
| no. 50 | 0.625 in | ~3.3 hp (bracketed, NOT a table value) | CALC |

Design power, Mott service factor 1.3 (Table 7-17, electric motor + moderate shock):

`Pdes = 1.3 x 68 kW = 88.4 kW = 118.6 hp` (CALC on OWNER motor power)

So Mott's rating method says ~3.3 hp and the design power is ~119 hp. **The chain fails Mott's power
rating by roughly 36x.** That is not a mistake in the arithmetic, it is what the method says.

Why it still runs on the car, stated honestly rather than hand-waved:

- Mott's ratings are for **15 000 hours** of continuous industrial duty. An FSAE car sees tens of hours
  of run time in its life. The fatigue and galling modes the table is protecting against never get there.
- The tables are ANSI industrial chain. 520 is a motorcycle chain built for exactly this kind of short-life,
  high-tension, high-shock job. Every motorcycle on the road violates the same table.
- On a straight tensile basis the chain has ~2.7x on ultimate at the 170 Nm transient, which is the check
  that actually governs here.

**Call it what it is:** the chain is justified by tensile margin and short duty life, not by Mott's power
rating. If someone asks in design event, that is the answer. Do not claim the Mott rating passes.

### 4.4 The 13T driver

Mott flags small sprockets for chordal action, the speed ripple from the chain wrapping a polygon instead
of a circle. It gets rough below about 17 teeth. **13T is below that line and we are keeping it.** Known
inherited compromise, not a design choice we are defending. It costs some smoothness and some chain and
sprocket wear life. The reason to keep it is that changing the driver is the only way to get between-step
ratios and the owner ruled that out, plus the driver is packaged tight to the gearbox output.

Chordal speed variation at 13T is `1 - cos(180/13)` = 2.9% peak to peak. (CALC)

### 4.5 The fixed 15:30 gear pair, one-time check

Does not change across the sweep, so this is a sanity check not a per-config number. All from
`Final Geometry!1. Gear Design` (from-SHEET), Mott Ch.9 bending and contact:

| Item | Value | Tag |
|---|---|---|
| Module m | 2.5 mm | from-SHEET D8 |
| Face width F | 25 mm | from-SHEET D11 |
| Np / Ng | 15 / 30 | from-SHEET D15,D16 |
| Dp / Dg | 37.5 / 75 mm | from-SHEET D18,D19 |
| Gear centre distance | 56.25 mm | from-SHEET D20 |
| Wt (max off torque curve) | 4246 N | from-SHEET D27 |
| Bending stress, pinion | 354.0 MPa | from-SHEET D38 |
| Contact stress, pinion | 1609.7 MPa | from-SHEET D40 |
| Required Sat (bending, SF=1) | 381.6 MPa | from-SHEET I44 |
| Required Sac (contact, SF=1) | 1813.9 MPa | from-SHEET I45 |

**Bending is fine.** 381.6 MPa required sits under grade 2 carburised steel (Mott Table 9-4, ~448 MPa).

**Contact is not fine at SF = 1.** 1813.9 MPa required is above grade 2 carburised (~1550 MPa) and only
grade 3 (~1895 MPa) covers it, with almost nothing left over. This is a pre-existing finding in the CFR24
sheet, it is not caused by anything in this sprocket study, and it does not move when the driven sprocket
changes. Flagging it because it showed up while I was reading the sheet: **the 15:30 pair is contact-stress
marginal and somebody should own that separately.**

## 5. Combined table: mech + sim on one page

**Correction to the handoff.** Section 2D says the sprocket ratios "line up, they are already CSV rows."
They are not. `gear_ratio_results.csv` steps 0.1 and `accel_results.csv` steps 0.05. Of the nine configs
only **26T (4.0000) is an exact row in both**. 30T is 4.6154 and the CSV has 4.61, close but not the same
number. **34T (5.2308) is off the end of both sweeps entirely, max tested ratio is 5.20, so it has no sim
data at all.** Everything else is linear interpolation between the two bracketing rows, tagged below.

| Driven | Total ratio | 0-75 m (s) | Trap (kph) | Endurance final SOC (%) | Fits? | Chain change needed? | Sim provenance |
|---|---|---|---|---|---|---|---|
| 26T | 4.0000 | 4.683 | 104.3 | 6.47 | UNKNOWN | chain length only (whole pitches) | exact |
| 27T | 4.1538 | 4.617 | 105.2 | 6.36 | UNKNOWN | **half pitch: offset link or move C** | interpolated |
| 28T | 4.3077 | 4.554 | 105.0 | 6.25 | UNKNOWN | chain length only (whole pitches) | interpolated |
| 29T | 4.4615 | 4.507 | 101.4 | 6.12 | UNKNOWN | **half pitch: offset link or move C** | interpolated |
| **30T** | 4.6154 | 4.474 | 98.0 | 5.98 | yes (on the car) | none, same as now | interpolated |
| 31T | 4.7692 | 4.455 | 94.9 | 5.84 | UNKNOWN | **half pitch: offset link or move C** | interpolated |
| 32T | 4.9231 | 4.447 | 91.9 | 5.68 | UNKNOWN | chain length only (whole pitches) | interpolated |
| 33T | 5.0769 | 4.449 | 89.1 | 5.52 | UNKNOWN | **half pitch: offset link or move C** | interpolated |
| 34T | 5.2308 | **no data** | -- | **no data** | UNKNOWN | chain length only (whole pitches) | OUT OF SWEEP |

`SOC98` = endurance final state of charge starting from 98%, per `gear_ratio_optimization.m:204`.
Higher is better. `0-75 m` lower is better. Note `t0_100kph` is NaN above 4.5 in the CSV because the car
never reaches 100 kph, which is why 0-75 m is the accel column that matters.

### Why every Fits? cell says UNKNOWN

There is **no centre distance and no packaging envelope anywhere in the CFR24 workbooks.** I searched all
five files for centre distance, clearance, envelope, chassis, ground, upright. The only distances in there
are gear-to-bearing spans on the shaft sheets and the two differential mount offsets (39.5 mm and 187.5 mm,
`Sprocket...!H33,H34`), none of which is the sprocket centre distance.

Per the handoff honesty rules, a guess that decides feasibility is not allowed. Fit is exactly that kind of
number, so it stays UNKNOWN and this is the escalation.

**Two measurements unblock the whole right-hand side of this table:**

1. **Centre distance C**, 13T centre to 30T centre, on the car or off the CAD. Gives exact chain length,
   exact wrap angle, and exact tensioner travel for all nine.
2. **Radial clearance** from the 30T outer edge to the nearest hard thing (chassis rail, floor, upright),
   and ride height at the sprocket. The sprocket grows **5.04 mm in diameter per tooth, so 2.52 mm on the
   radius**. 34T is 20.2 mm bigger on diameter than 30T, so 10.1 mm more radius. If there is more than
   ~10.1 mm of clearance around the 30T today, all nine fit. If there is less, the top of the range dies.

Both are tape-measure or CAD jobs. Neither needs a rig.

### Added mass and inertia

Absolute mass is **UNKNOWN**, no thickness or material for the sprocket blank in any sheet. What is
computable is the scaling, since all nine are the same part in different sizes. Thin uniform disc proxy,
mass goes as D^2 and inertia as D^4 (CALC, geometry only, no guessed mass):

| Driven | Mass vs 30T | Inertia vs 30T |
|---|---|---|
| 26T | 0.752x | 0.566x |
| 27T | 0.811x | 0.657x |
| 28T | 0.872x | 0.760x |
| 29T | 0.935x | 0.874x |
| 30T | 1.000x | 1.000x |
| 31T | 1.068x | 1.140x |
| 32T | 1.137x | 1.293x |
| 33T | 1.209x | 1.462x |
| 34T | 1.283x | 1.647x |

34T carries **1.65x** the driven-sprocket inertia of 30T, 26T carries 0.57x. Real sprockets are lightened
so the true exponent is softer than 4. For scale, `params_cfr26.m:338` has the whole driveline at
`p.I_driveline = 5e-4 kg*m^2`, which is tiny next to `p.I_rotor = 0.0256`, and the driven sprocket is
referred to the wheel side where it matters least. **This term is not going to decide anything.** Worth
computing so nobody has to wonder, not worth optimising.

## 6. Verdict: what is actually buildable

Nothing here is dead on geometry, because geometry cannot kill anything until C and the clearance are
measured. What separates them right now is **chain parity** and **whether the sim covers them.**

### Tier 1, bolt-on. Even tooth count, whole-pitch chain change, sim data exists.

| Rank | Config | Ratio | 0-75 m | SOC98 | Why |
|---|---|---|---|---|---|
| 1 | **30T** | 4.6154 | 4.474 | 5.98 | On the car. Zero work, zero risk. The thing to beat. |
| 2 | **32T** | 4.9231 | 4.447 | 5.68 | Quickest 0-75 m of the whole set. Costs 0.30 pts of SOC. Even, so chain grows exactly 1 pitch. |
| 3 | **28T** | 4.3077 | 4.554 | 6.25 | The endurance direction. +0.27 SOC over 30T for +0.08 s. Even, chain shrinks 1 pitch. |
| 4 | **26T** | 4.0000 | 4.683 | 6.47 | Best SOC of all nine and the only config that is an EXACT row in both CSVs. But slowest 0-75 m by 0.24 s. |

### Tier 2, needs an offset link. Odd tooth count, half-pitch chain length.

| Config | Ratio | 0-75 m | SOC98 | Note |
|---|---|---|---|---|
| 27T | 4.1538 | 4.617 | 6.36 | half pitch, offset link or pull C in ~2 mm |
| 29T | 4.4615 | 4.507 | 6.12 | half pitch, offset link or pull C in ~2 mm |
| 31T | 4.7692 | 4.455 | 5.84 | half pitch, offset link or pull C in ~2 mm |
| 33T | 5.0769 | 4.449 | 5.52 | half pitch, offset link or pull C in ~2 mm |

None of these buys anything a neighbouring even count does not. 31T sits between 30T and 32T and is worse
than 32T on time and worse than 30T on charge. **Do not take an offset link for a ratio you can get with
an even sprocket.** Offset links are the weakest link in a chain, literally.

### Tier 3, do not use

| Config | Ratio | Why |
|---|---|---|
| **34T** | 5.2308 | **Off the end of both sweeps.** Max tested ratio is 5.20. No 0-75 m and no SOC number exists for it. It is also the worst case for packaging (10.1 mm more radius than 30T) and carries 1.65x the sprocket inertia. Geometrically buildable, but nobody has simulated it. If it is genuinely wanted, rerun the sweep to 5.25 first. |

### The actual recommendation

**Keep 30T unless someone decides endurance charge is the binding constraint, in which case 28T.**

Reasoning, and it is mostly that the spread is small:

- Across the entire buildable range, 26T to 33T, 0-75 m moves 0.236 s and final SOC moves 0.95 points.
- 0-75 m is **flat** at the top. 32T and 33T are within 0.002 s of each other. The accel curve bottoms out
  around 4.95 and turns back up, so gearing shorter past 32T buys nothing and keeps costing charge.
- Every step toward more ratio costs roughly 0.14 to 0.16 points of final SOC per tooth, steadily, no knee.
- So the honest read: **32T is the fastest thing you can bolt on and it costs 0.30 SOC. 28T is the
  cheapest on charge that is still quick and it costs 0.08 s.** 30T is between them and already fitted.
  Unless endurance is actually charge-limited, the 0.08 s is not worth the sprocket and the chain change.

- 26T is tempting because it is the only exactly-simulated config and it wins SOC outright, but it gives
  up 0.24 s in accel, which is a lot next to a 0.49 point SOC gain over 30T.

### What is still blocking a final answer

| # | Blocker | Who | Unblocks |
|---|---|---|---|
| 1 | Chain centre distance C, 13T to 30T | tape measure or CAD | exact chain length, wrap angle, tensioner travel, all 9 |
| 2 | Radial clearance around the 30T, and ride height at the sprocket | tape measure or CAD | the whole Fits? column |
| 3 | Real 520 chain tensile rating | chain datasheet | replaces the Mott no. 50 stand-in in 4.2 |
| 4 | Whether endurance is actually charge-limited | sim / race engineering | decides 28T vs 30T vs 32T |
| 5 | Sweep does not reach 5.2308 | rerun `gear_ratio_optimization.m` to 5.25 | only needed if 34T is wanted |

### Not from this study, but found while reading the sheet

The 15:30 gear pair is **contact-stress marginal** (needs Sac 1813.9 MPa at SF=1, grade 2 carburised gives
~1550). See section 4.5. Unrelated to the sprocket choice, does not move across the sweep, but somebody
should own it.

---

Method: chain geometry and ratings per Mott, *Machine Elements in Mechanical Design*, Ch.7 (Tables 7-12,
7-14, 7-15, 7-17). Gear check per Ch.9. Fixed inputs from `CFR24 Driveline Tool - Final Geometry.xlsx`
and `cfr24 dt/Sprocket Gearing and Forces.xlsx`. Sim data from `output/gear_ratio_results.csv` and
`output/accel_results.csv`. `params_cfr26.m` stays the source of truth for ratios and was not edited.

## 7. The splined interface, measured off the CAD

Source: `Downloads/CFR26 motor gearbox assembly.STEP` (SolidWorks 2026, AP203). I parsed the BREP
directly rather than eyeballing it, so these are read off the solid, tagged **MEASURED-CAD**.

### 7.1 The part is 13T, not 12T. The CAD name is wrong.

The component is named **`DT-P2120_JTF 1324 - 12T`**. Its geometry is not 12T:

| Evidence | Value | What it means |
|---|---|---|
| Max cylindrical radius | 36.9662 mm, so OD 73.9324 mm | Mott OD for **13T** at 15.875 pitch is 73.9324. Exact match. 12T would be 68.7713. |
| Coaxial tip faces at that radius | **13** | 13 tooth tips |
| Roller seat pockets | **13**, dia 10.2138 mm | 13 seats, and the seat matches a 520 roller (10.16 nominal) |
| Tooth flank planes | **26** = 13 x 2 | 13 teeth, two flanks each |

**Four independent features all say 13.** The `- 12T` in the filename is a naming error. Worth fixing in
the CAD before somebody orders a 12T off the strength of the filename, because 12T would be 5.00:1 total,
not 4.615, and that is a whole different car.

### 7.2 The spline

| Feature | Value | Tag |
|---|---|---|
| Spline form | 6 straight-sided lobes at 60 deg | MEASURED-CAD |
| Minor diameter | 21.000 mm | MEASURED-CAD |
| Major diameter | 25.000 mm | MEASURED-CAD |
| Slot / tooth width | 5.000 mm | MEASURED-CAD |
| Sprocket plate thickness | 5.850 mm | MEASURED-CAD |
| Retention holes | 2 x dia 6.000 mm on a 37.000 mm span | MEASURED-CAD |

The mating male spline is on **`DT-P2127`**, the gearbox output shaft. It carries the same 21.0 / 25.0
cylinders, so the pair is confirmed from both sides. (That is also the part the CFR24
`Fatigue Load Cases.xlsx` sheet is named after.)

### 7.3 Does the spline constrain the sweep? No.

**The driven sprocket does not touch this spline.** It mounts to the differential, which is not in this
STEP at all (no part in the assembly has a radius anywhere near the 80.3 mm a 30T needs). So sweeping the
driven from 26T to 34T **never changes the shaft, the spline, or the driver**. All nine configs reuse the
existing splined 13T exactly as it sits.

That is the answer to the question: **yes, the spline stays the same across every config in this study.**

### 7.4 If you ever do change the driver

The spline is not what limits you. The bore only needs the sprocket root to clear the 25.0 mm major
diameter with wall left over. Root dia = pitch dia - roller dia:

| Driver N | Pitch dia (mm) | Root dia (mm) | Wall over spline (mm) | Total ratio with 30T |
|---|---|---|---|---|
| 10T | 51.37 | 41.21 | 8.11 | 6.000 |
| 11T | 56.35 | 46.19 | 10.59 | 5.455 |
| 12T | 61.34 | 51.18 | 13.09 | 5.000 |
| 13T **(current)** | 66.33 | 56.17 | 15.59 | 4.615 |
| 14T | 71.34 | 61.18 | 18.09 | 4.286 |
| 15T | 76.35 | 66.19 | 20.60 | 4.000 |
| 16T | 81.37 | 71.21 | 23.11 | 3.750 |

Even a 10T has 8.1 mm of wall over the spline, so **the bore is nowhere near the limit**. What actually
limits a small driver is Mott's chordal action (section 4.4), plus chain and sprocket wear life, and those
get worse fast below 13T. Going the other way, you are right that a bigger driver is trash for a different
reason: it kills the reduction. 15T with the 30T gives 4.000, which you can already get from a 26T driven
without touching the splined shaft or the tensioner setup.

**So the driver stays 13T, and not just because it was inherited. There is no version of moving it that
wins.** Small is limited by chordal action, big is limited by losing ratio you then have to buy back on
the driven anyway.

One practical note: any replacement driver has to have this exact 6-lobe 21.0 / 25.0 / 5.0 bore. That is a
bought-part constraint, not something you can machine into an arbitrary blank without a broach. Check the
bore spec against the numbers above before ordering, do not trust a part number alone, since the part
number on this one already has the wrong tooth count attached to it.

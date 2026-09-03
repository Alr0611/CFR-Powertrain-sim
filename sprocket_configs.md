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

## 8. Centre distance measured, and the diff sprocket from CAD

### 8.1 Centre distance

**C = 152.08 mm**, MEASURED-CAD (SolidWorks Measure, 13T centre to diff sprocket centre). This unblocks
everything in section 5 that said NEED C. Worth confirming once on the car, but it is a real number now,
not a guess.

### 8.2 The diff sprocket, measured off `cfr_sprocket.STEP`

| Feature | Value | Tag |
|---|---|---|
| Teeth | **30** | MEASURED-CAD |
| Outside diameter | 160.5656 mm | MEASURED-CAD |
| Pitch diameter | 151.873 mm | CALC, matches CAD OD exactly |
| Tooth plate thickness | 4.744 mm | MEASURED-CAD |
| Central bore | 45.600 mm | MEASURED-CAD |
| Hub thickness at bore | 8.712 mm | MEASURED-CAD |
| Bolt pattern | **6 x dia 6.310 mm on 92.690 mm BCD**, 60 deg spacing | MEASURED-CAD |
| Overall Z extent | 10.000 mm | MEASURED-CAD |

The CAD OD of 160.5656 is an exact match to Mott's OD for 30 teeth, so the tooth count is confirmed
independently of the filename. Same check that caught the 12T/13T error on the driver.

**This one is made in house**, not a bought JT part. That matters: a new driven sprocket keeps the same
45.60 bore and 92.69 BCD, so **the diff mounting is reusable across every tooth count in the sweep.**
Even the smallest (26T) has a root diameter of 121.54 mm against a bolt-hole outer edge at 99.0 mm, which
leaves 11.3 mm of web. No config in this study forces a new diff interface.

So both ends are now settled: the driver reuses its spline (section 7), the driven reuses its bolt
pattern. **Nothing in the 26T to 34T sweep requires a new shaft, hub, or mounting.**

### 8.3 Chain and wrap at the real centre distance

Mott `L = 2C/P + (N1+N2)/2 + ((N2-N1)/2pi)^2 * P/C` at C = 152.08:

| Driven | Ratio | Wrap on 13T (deg) | Chain (pitches) | Round to even | C for that even count (mm) | Axle move vs 152.08 |
|---|---|---|---|---|---|---|
| 26T | 4.0000 | 155.2 | 39.11 | 40 | 159.33 | +7.25 |
| 27T | 4.1538 | 153.2 | 39.68 | 40 | 154.71 | +2.63 |
| 28T | 4.3077 | 151.3 | 40.25 | 40 | 149.99 | -2.09 |
| 29T | 4.4615 | 149.3 | 40.84 | 40 | 145.18 | -6.90 |
| 30T **(current)** | 4.6154 | 147.3 | 41.42 | 42 | 156.84 | +4.76 |
| 31T | 4.7692 | 145.3 | 42.02 | 42 | 151.94 | -0.14 |
| 32T | 4.9231 | 143.4 | 42.61 | 42 | 146.94 | -5.14 |
| 33T | 5.0769 | 141.3 | 43.22 | 44 | 158.64 | +6.56 |
| 34T | 5.2308 | 139.3 | 43.83 | 44 | 153.55 | +1.47 |

**Wrap passes everywhere.** Worst case is 34T at 139.3 deg, still well clear of the 120 deg flag. The
120 deg limit would need C below 105.7 mm and we are at 152.08, so wrap is simply not a constraint on this
car. That column can stop being a worry.

**Chain length is the real work.** At the measured C the current 30T wants 41.42 pitches and the nearest
even count is 42, which corresponds to C = 156.84. That is 4.76 mm more than measured, so the current
build is taking up about 4.8 mm of slack somewhere, on the tensioner or in the diff mount adjustment.
That is normal and it is also the budget you have to play with. Read the last column as **how far the
diff has to move from where it sits today** to land on a clean even chain.

Cheapest changes from here, by how little the axle has to move:

- **31T: -0.14 mm.** Essentially a drop-in on a 42-pitch chain. Odd count so it wants an offset link.
- **34T: +1.47 mm** on a 44-pitch chain, but it is off the end of the sim sweep, so no data.
- **28T: -2.09 mm** on a 40-pitch chain. Even, no offset link. This is the clean one.
- **27T: +2.63 mm** on 40 pitches, odd.
- **30T: +4.76 mm** on 42, which is where it sits now.

### 8.4 Envelope numbers for the chassis lead

What the chassis lead actually needs is the driven sprocket outside diameter, since that is the thing that
has to clear structure. Growth is **+5.044 mm on diameter per tooth, so +2.522 mm on radius**.

| Driven | Ratio | Pitch dia (mm) | OD (mm) | OD radius (mm) | Root dia (mm) |
|---|---|---|---|---|---|
| 26T | 4.0000 | 131.70 | 140.27 | 70.13 | 121.54 |
| 27T | 4.1538 | 136.74 | 145.34 | 72.67 | 126.58 |
| 28T | 4.3077 **<- likely band** | 141.79 | 150.42 | 75.21 | 131.63 |
| 29T | 4.4615 **<- likely band** | 146.83 | 155.49 | 77.75 | 136.67 |
| 30T **(current)** | 4.6154 **<- likely band** | 151.87 | 160.57 | 80.28 | 141.71 |
| 31T | 4.7692 **<- likely band** | 156.92 | 165.64 | 82.82 | 146.76 |
| 32T | 4.9231 | 161.96 | 170.71 | 85.35 | 151.80 |
| 33T | 5.0769 | 167.01 | 175.78 | 87.89 | 156.85 |
| 34T | 5.2308 | 172.05 | 180.84 | 90.42 | 161.89 |

**Give the chassis lead this:**

| Case | Driven teeth | OD range (mm) | OD radius range (mm) |
|---|---|---|---|
| Likely, ratio 4.2 to 4.8 | 28T to 31T | 150.4 to 165.6 | 75.2 to 82.8 |
| Full sweep, 4.00 to 5.20 | 26T to 34T | 140.3 to 180.8 | 70.1 to 90.4 |
| Current build | 30T | 160.6 | 80.3 |

The honest ask to hand over: **design the envelope to 34T, OD 180.84 mm, radius 90.42 mm.** That is
+10.14 mm on radius over what is fitted today and it covers the entire sweep with margin. If the chassis
cannot give that, the next sensible line is 31T at radius 82.82 mm, which is +2.54 mm over today and
covers the whole 4.2 to 4.8 band you actually expect to land in.

**One thing still missing.** These are sprocket outside diameters. The chain sits on the pitch circle and
its outer link plates stand proud of the sprocket, so the true swept envelope is a few mm bigger than the
OD. Getting that exactly needs the **520 chain plate height, which is UNKNOWN** (not in any sheet, and the
chain is not in the STEP files I have). Tell the chassis lead the OD numbers are the sprocket only and to
carry a clearance allowance on top, or get the plate height off the chain datasheet and it becomes exact.

## 9. The chain, measured off `chain.STEP`

This closes the last envelope unknown. All MEASURED-CAD off part `DT-P2131_6261K244`.

| Feature | Measured | Note |
|---|---|---|
| Pitch | **15.8750 mm** | roller centres at Z = +/-7.938, so 15.875 apart. Confirms the sheet exactly. |
| Roller diameter | **10.1600 mm** | textbook 520. Confirms the chain number from the hardware, not just the sheet. |
| Plate height | **14.5034 mm** | plate end arcs are R7.2517 centred on the pin axis |
| Plate half height | **7.2517 mm** | this is the number that matters, see below |
| Outer plate span | 13.589 mm | plate outer faces. Pin heads or a master link may add, check before trusting it laterally. |

### 9.1 The envelope number the chassis lead actually needs

The pin centres sit **on the pitch circle**, and the plate stands 7.2517 mm proud of them. So:

```
chain envelope radius = driven pitch radius + 7.2517 mm
```
That runs about **2.9 mm outside the sprocket OD** across the whole sweep, because the sprocket tooth tip
sits slightly inside where the chain plate reaches. So quoting sprocket OD alone under-calls the envelope
by ~3 mm per side. Not huge, but it is the difference between a clearance check passing and fouling.

| Driven | Ratio | Pitch dia (mm) | Sprocket OD (mm) | OD radius (mm) | **Chain envelope radius (mm)** |
|---|---|---|---|---|---|
| 26T | 4.0000 | 131.70 | 140.27 | 70.13 | **73.10** |
| 27T | 4.1538 | 136.74 | 145.34 | 72.67 | **75.62** |
| 28T | 4.3077 <- likely | 141.79 | 150.42 | 75.21 | **78.14** |
| 29T | 4.4615 <- likely | 146.83 | 155.49 | 77.75 | **80.67** |
| 30T **(current)** | 4.6154 <- likely | 151.87 | 160.57 | 80.28 | **83.19** |
| 31T | 4.7692 <- likely | 156.92 | 165.64 | 82.82 | **85.71** |
| 32T | 4.9231 | 161.96 | 170.71 | 85.35 | **88.23** |
| 33T | 5.0769 | 167.01 | 175.78 | 87.89 | **90.76** |
| 34T | 5.2308 | 172.05 | 180.84 | 90.42 | **93.28** |

**Hand the chassis lead this:**

| Case | Driven | Chain envelope radius (mm) | Envelope diameter (mm) |
|---|---|---|---|
| Likely, ratio 4.2 to 4.8 | 28T to 31T | 78.1 to 85.7 | 156.3 to 171.4 |
| Full sweep, 4.00 to 5.20 | 26T to 34T | 73.1 to 93.3 | 146.2 to 186.6 |
| Current build | 30T | 83.2 | 166.4 |

**The ask: design to 93.3 mm radius (186.6 mm diameter)** and the whole 4.00 to 5.20 sweep fits with the
chain accounted for. That is **+10.1 mm on radius over what is fitted today**. If that is too much, the
fallback is 31T at 85.7 mm radius, +2.5 mm over today, which still covers all of 4.2 to 4.8.

Growth is **+2.522 mm of envelope radius per tooth**, so the chassis lead can price any target themselves.

### 9.2 What is left

Only one thing now: **how much radius is actually available** around the diff sprocket before you hit
structure. That is a chassis answer, not a drivetrain one. Put it in the orange cell on the Sprocket Calc
tab and the Fit check column resolves for all nine configs plus anything you type into the playground.

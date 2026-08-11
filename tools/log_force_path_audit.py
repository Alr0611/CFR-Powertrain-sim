#!/usr/bin/env python3
"""Audit the sim's force path against today_test.csv, outside in.

The sim takes 4.988 s over 75 m and the car did better than that. Working the chain:

  STEP 1  gear ratio, measured with NO radius involved (motor rpm vs wheel rpm). If G
          checks out, gearing isn't the fault and the radius question separates cleanly.
  STEP 2  what radius the log's own vehicleSpeed is built on.
  STEP 3  0-75 m rebuilt from undriven front wheels, so it doesn't inherit that radius.
  STEP 4  torque actually delivered vs what the sim assumes.
  STEP 5  effective mu on the day, derived from logged acceleration. Not picked.

Sign conventions, checked against the data rather than firmware headers:
  torqueFeedback  negative when motoring
  packCurrent     negative on discharge
  torqueRequest   positive, carries 200.0 as a sentinel, filtered out below
"""
import numpy as np
import pandas as pd

CSV = r"C:\Users\Aboud\Downloads\today_test.csv"
# Standing-start accel runs. Times from the previous session's segmentation; each is
# re-verified below by checking it actually starts near rest and ends near 27 m/s.
RUN_STARTS = (15554, 15741, 15914, 16151)
G_NOMINAL = (30.0 / 15.0) * (30.0 / 13.0)      # 15/30 spur x 30/13 chain = 4.6154
R_FIRMWARE = 0.2032                             # firmware TIRE_RADIUS_M, for comparison only


def load():
    d = pd.read_csv(CSV)
    d["Treq"] = d["VCFRONT_torqueRequest"].where(d["VCFRONT_torqueRequest"] < 199.0)
    d["Tfb"] = -d["PM100DX_torqueFeedback"]      # flip so motoring is POSITIVE
    d["Idis"] = -d["BMSB_packCurrent"]           # flip so discharge is POSITIVE
    d["wRear"] = 0.5 * (d["VCREAR_wheelSpeedRL"] + d["VCREAR_wheelSpeedRR"])
    d["wFront"] = 0.5 * (d["VCFRONT_wheelSpeedFL"] + d["VCFRONT_wheelSpeedFR"])
    return d


def step1_gear_ratio(d):
    print("\n=== STEP 1: gear ratio, measured WITHOUT the wheel radius ===")
    print("G = motor_rpm / rear_wheel_rpm. No radius anywhere in this, so it isolates the")
    print("gearing from the tyre-size question entirely.")
    m = (d["PM100DX_motorSpeed"] > 500) & (d["wRear"] > 100)
    mr, wr = d.loc[m, "PM100DX_motorSpeed"].to_numpy(), d.loc[m, "wRear"].to_numpy()
    ratio = mr / wr
    # Fit through the origin: a gear ratio has no offset. Least squares on motor = G*wheel.
    G_fit = float(np.sum(mr * wr) / np.sum(wr * wr))
    print(f"  n = {m.sum()} samples above 500 motor rpm")
    print(f"  per-sample ratio: median {np.median(ratio):.4f}  "
          f"p10 {np.percentile(ratio,10):.4f}  p90 {np.percentile(ratio,90):.4f}")
    print(f"  through-origin least squares: G = {G_fit:.4f}")
    print(f"  nominal 15/30 spur x 30/13 chain = {G_NOMINAL:.4f}")
    err = 100 * (G_fit - G_NOMINAL) / G_NOMINAL
    print(f"  -> error {err:+.2f}%  {'PASS, gearing is not the fault' if abs(err) < 2 else 'MISMATCH, investigate'}")
    print(f"  (p.gear_current is 4.61, which is {100*(4.61-G_NOMINAL)/G_NOMINAL:+.2f}% off the")
    print("   exact tooth-count ratio -- a rounding of 4.6154, not an error)")
    return G_fit


def step2_radius(d):
    print("\n=== STEP 2: what radius does the LOG's own vehicleSpeed use? ===")
    print("Front wheels are UNDRIVEN, so under acceleration they roll cleanly. If")
    print("vehicleSpeed = wFront * 2pi/60 * r, the implied r falls straight out.")
    m = (d["VCFRONT_vehicleSpeed"] > 3) & (d["wFront"] > 150)
    v = d.loc[m, "VCFRONT_vehicleSpeed"].to_numpy()
    w = d.loc[m, "wFront"].to_numpy() * 2 * np.pi / 60
    r_imp = float(np.sum(v * w) / np.sum(w * w))
    print(f"  n = {m.sum()}")
    print(f"  implied radius = {r_imp:.4f} m   (firmware TIRE_RADIUS_M = {R_FIRMWARE:.4f})")
    print(f"  -> {'confirms' if abs(r_imp-R_FIRMWARE) < 0.005 else 'does NOT match'} "
          "the firmware constant")
    print("  NOTE this is what the firmware BELIEVES, not what the tyre IS. It only tells")
    print("  us the scale factor sitting on every logged speed and distance.")
    return r_imp


def step3_t75(d, r_imp):
    print("\n=== STEP 3: 0-75 m rebuilt from UNDRIVEN FRONT WHEELS ===")
    print("vehicleSpeed inherits the firmware radius. Front wheel rpm does not -- it is a")
    print("raw sensor count. So distance is computed at several candidate radii and the")
    print("answer is reported as a FUNCTION of radius, with no radius assumed.")
    print("\n  Front wheels still under-read slightly (they carry rolling resistance and")
    print("  their own small slip), so this is a mild UNDER-estimate of true distance,")
    print("  i.e. a mild OVER-estimate of t75. Directional, not corrected for.")
    for r in (0.2032, 0.210, 0.2210, 0.2286):
        print(f"\n  --- assuming r_wheel = {r:.4f} m ---")
        ts = []
        for t0 in RUN_STARTS:
            seg = d[(d["t_s"] >= t0 - 5) & (d["t_s"] <= t0 + 25)]
            t = seg["t_s"].to_numpy()
            v = seg["wFront"].to_numpy() * 2 * np.pi / 60 * r
            if v.max() < 20:
                continue
            # launch = last sample at rest before the run
            moving = np.where(v > 0.5)[0]
            if len(moving) == 0:
                continue
            i0 = moving[0]
            x = np.concatenate([[0], np.cumsum(np.diff(t[i0:]) * v[i0:-1])])
            k = np.where(x >= 75)[0]
            if len(k):
                # linear interpolation onto exactly 75 m
                j = k[0]
                frac = (75 - x[j - 1]) / (x[j] - x[j - 1]) if j else 0
                t75 = t[i0 + j - 1] + frac * (t[i0 + j] - t[i0 + j - 1]) - t[i0]
                ts.append(t75)
                print(f"    run @ t={t0}: 0-75 m = {t75:.3f} s  (trap {v[i0+j]*3.6:.1f} kph)")
        if ts:
            print(f"    mean {np.mean(ts):.3f} s  spread {min(ts):.3f}-{max(ts):.3f}")
    print("\n  The 10 Hz log quantises each time to +/-0.05 s at best; treat the third")
    print("  decimal as noise.")


def step4_torque(d):
    print("\n=== STEP 4: motor torque envelope ACTUALLY DELIVERED ===")
    print("The sim caps driver torque at p.T_driver_max = 123.0 Nm because that is what")
    print("the VC REQUESTS. But the request is not what the shaft makes.")
    wot = (d["VCFRONT_acceleratorPosition"] > 95) & (d["PM100DX_motorSpeed"] > 200)
    print(f"\n  full throttle, n = {wot.sum()}")
    print(f"  requested  (VCFRONT_torqueRequest): median {d.loc[wot,'Treq'].median():.1f} "
          f"p95 {d.loc[wot,'Treq'].quantile(.95):.1f} max {d.loc[wot,'Treq'].max():.1f} Nm")
    print(f"  delivered  (torqueFeedback):        median {d.loc[wot,'Tfb'].median():.1f} "
          f"p95 {d.loc[wot,'Tfb'].quantile(.95):.1f} max {d.loc[wot,'Tfb'].max():.1f} Nm")
    print("\n  delivered torque vs motor rpm, full throttle only:")
    print(f"  {'rpm bin':>14} {'n':>6} {'median':>8} {'p95':>8} {'max':>8}")
    edges = [200, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500, 6100]
    for lo, hi in zip(edges[:-1], edges[1:]):
        m = wot & (d["PM100DX_motorSpeed"] >= lo) & (d["PM100DX_motorSpeed"] < hi)
        if m.sum() < 5:
            continue
        s = d.loc[m, "Tfb"]
        print(f"  {lo:5d}-{hi:<8d} {int(m.sum()):>6d} {s.median():8.1f} "
              f"{s.quantile(.95):8.1f} {s.max():8.1f}")
    print("\n  Compare against the sim's assumed envelope: flat 150 Nm to ~3300 rpm then")
    print("  power-limited, with the driver request capped at 123 Nm on top.")


def step5_mu(d, r_imp):
    print("\n=== STEP 5: effective mu on the day, DERIVED from logged acceleration ===")
    print("mu_eff = m*a / Fz_rear, with Fz_rear including load transfer at that same a.")
    print("This is the ONLY honest route to a mu for a hot, dirty parking lot. It is")
    print("derived from the car's own acceleration, not picked to match anything.")
    m_car, g, rear_static, h_cg, L_wb = 294.0, 9.81, 0.483, 0.3134, 1.543
    Crr, rho, CdA, ClA, rear_aero = 0.015, 1.225, 0.933, 1.499, 0.564
    for t0 in RUN_STARTS:
        seg = d[(d["t_s"] >= t0 - 5) & (d["t_s"] <= t0 + 25)].copy()
        t = seg["t_s"].to_numpy()
        v = seg["wFront"].to_numpy() * 2 * np.pi / 60 * r_imp
        if v.max() < 20:
            continue
        a = np.gradient(v, t)
        # Only the launch phase, and only while genuinely accelerating hard.
        k = (v > 1.0) & (v < 12.0) & (a > 0)
        if k.sum() < 5:
            continue
        aa, vv = a[k], v[k]
        Fdown = 0.5 * rho * ClA * vv**2
        Fz_rear = m_car * g * rear_static + m_car * aa * h_cg / L_wb + Fdown * rear_aero
        Fx = m_car * aa + 0.5 * rho * CdA * vv**2 + Crr * (m_car * g + Fdown)
        mu = Fx / Fz_rear
        print(f"  run @ t={t0}: a_max {aa.max():.2f} m/s2 ({aa.max()/g:.2f} g) | "
              f"mu_eff p90 {np.percentile(mu,90):.3f}  max {mu.max():.3f}")
    print("\n  Read this as a LOWER BOUND on available mu: the car was traction limited")
    print("  only in the instants it was actually spinning. Where TC was cutting torque,")
    print("  the car was TORQUE limited and this number understates grip.")


if __name__ == "__main__":
    d = load()
    print(f"loaded {len(d)} rows, {d['t_s'].iloc[-1]/3600:.2f} h")
    step1_gear_ratio(d)
    r_imp = step2_radius(d)
    step3_t75(d, r_imp)
    step4_torque(d)
    step5_mu(d, r_imp)

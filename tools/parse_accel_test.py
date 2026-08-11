#!/usr/bin/env python3
"""
parse_accel_test.py  --  test-day telemetry -> launch + traction-control analysis.

    python parse_accel_test.py today_test.csv [--dump-launch N]

WHAT CHANGED (and why)
  1. LAUNCH DETECTOR. The old gate wanted "speed climbs from a dead stop through
     90 kph" and found nothing in a mixed autocross session, because almost no
     run in a session like that is a clean full-length pull. It also gated on
     tq_out > 20, which never fires: in this log MOTORING TORQUE IS NEGATIVE.
     New detector: hard-accel segments where |motor rpm| > 2000 AND |torque| > 50
     AND speed is rising. No requirement to start from a stop or reach 90 kph.
  2. SLIP DEFINITION now matches the firmware exactly:
         slip = (v_rear_axle - v_vehicle) / v_vehicle
     with v_rear_axle = rear_axle_rpm -> m/s through TIRE_RADIUS_M, per
     app_vehicleSpeed_getAxleSlip(AXLE_REAR). The old rear/front - 1 is a
     different quantity and is NOT what the controller sees.
  3. TARGET is 0.10 (TC_TARGET_SLIP in torque.c), not 0.15.
  4. Slip is gated on vehicle speed like the firmware gates it, so the
     divide-by-zero garbage at the launch instant is excluded instead of
     showing up as a "36x slip outlier".

READ THIS BEFORE TRUSTING THE PID NUMBERS
  The firmware TC loop runs at 100 Hz (torque_periodic_100Hz). This log is
  10 Hz. That is a 10x undersample: Nyquist is 5 Hz, so any controller
  oscillation above 5 Hz is invisible or aliased. Settling time, steady-state
  error and gross overshoot survive at 10 Hz. Ringing frequency does not.
"""

import sys
import numpy as np
import pandas as pd

# ---- firmware constants (components/vc/front/, read-only reference) ----
TC_TARGET_SLIP  = 0.10     # TC_TARGET_SLIP, torque.c
TIRE_RADIUS_M   = 0.2032   # TIRE_RADIUS_M, vd.h
GEAR_RATIO      = 4.6154   # 15/30 spur x 30/13 chain
TC_SPEED_GATE   = 0.5      # m/s. TC_VEHICLESPEED_THRESHOLD_MPS = VEHICLE_STOPPED_THRESHOLD
# Compile-time gain maps, torque.h. THESE ARE DEFAULTS, NOT WHAT THE CAR RAN.
# tc_getActivePid() returns &tcPid_data, which is a LIB_NVM_MEMORY_REGION. The live
# gains come out of NVM; the header only seeds NVM when it is blank. This log shows a
# hard 123.0 Nm full-throttle ceiling, matching none of the three maps, so NVM had
# been written and the real kp / clamp are UNKNOWN. Read them back over CAN
# (thousandthKp/Ki/Kd, percentMaxTcLimit, percentILim getters) before trusting r_P.
TC_130_KP, TC_130_KI, TC_130_KD = 0.591, 0.0, 0.070   # <-- TC_SET_DEFAULT_PID
TC_130_MAXLIM, TC_130_ILIM      = 0.70, 0.0
TC_150_KP, TC_150_KI, TC_150_KD = 0.470, 0.0, 0.110
TC_150_MAXLIM, TC_150_ILIM      = 0.75, 0.0
TC_100_KP, TC_100_KI, TC_100_KD = 0.591, 0.0, 0.070
TC_100_MAXLIM, TC_100_ILIM      = 0.70, 0.0

# Which map r_P is scored against. The 130 Nm map is the compile-time default, so it
# is the least-wrong guess, but it is still a guess.
ASSUMED_KP, ASSUMED_MAXLIM = TC_130_KP, TC_130_MAXLIM
ASSUMED_MAP = "130Nm map (compile-time DEFAULT, ASSUMED, not confirmed)"

# VCFRONT_torqueRequest carries 200.0 as a sentinel. It is above every map max and
# sits at the 99th percentile, so max()/high percentiles return it and mean nothing.
TQ_REQ_SENTINEL = 200.0

# Driver demand ceiling, needed to recover the TC cut (see y_dem below). MEASURED
# from this log: at full throttle the request pins to exactly 123.0 Nm (p50 = p95
# over 707 apps>95 samples). Matches no compile-time map, which is the evidence that
# NVM was written. If you re-run on a different log, re-check this number.
TORQUE_MAX_NM = 123.0

# ---- detector thresholds ----
RPM_GATE   = 2000.0
TQ_GATE    = 50.0
MIN_LEN_S  = 0.8


def load(path):
    d = pd.read_csv(path)
    t = d["t_s"].to_numpy(float)
    g = {}
    g["rpm"]  = np.abs(d["PM100DX_motorSpeed"].to_numpy(float))
    # SIGN: motoring torque is logged NEGATIVE here and the request POSITIVE
    # (corr(req, fb) = -0.99). Take magnitudes so both are "torque produced".
    g["tqo"]  = np.abs(d["PM100DX_torqueFeedback"].to_numpy(float))
    g["tqr"]  = np.abs(d["VCFRONT_torqueRequest"].to_numpy(float))
    # 200.0 is a sentinel, not a request. Above every map max. Drop it or every
    # max/percentile on this channel reports 200 and means nothing.
    g["tqr"][g["tqr"] >= TQ_REQ_SENTINEL] = np.nan
    g["apps"] = d["VCFRONT_acceleratorPosition"].to_numpy(float)
    g["rear"] = np.nanmean(np.vstack([d["VCREAR_wheelSpeedRL"], d["VCREAR_wheelSpeedRR"]]), 0)
    g["front"] = np.nanmean(np.vstack([d["VCFRONT_wheelSpeedFL"], d["VCFRONT_wheelSpeedFR"]]), 0)
    g["veh"]  = d["VCFRONT_vehicleSpeed"].to_numpy(float)     # m/s (peak 27 = 98 kph)
    g["odo"]  = d["VCFRONT_odometer"].to_numpy(float)         # km
    return t, g


def firmware_slip(rear_rpm, veh_ms):
    """slip = (v_rear_axle - v_veh)/v_veh, exactly as app_vehicleSpeed_getAxleSlip.
    Gated on the same vehicle-speed threshold the firmware uses, so the
    standing-start divide-by-zero is excluded rather than reported."""
    v_rear = rear_rpm * (2 * np.pi / 60.0) * TIRE_RADIUS_M
    with np.errstate(divide="ignore", invalid="ignore"):
        s = (v_rear - veh_ms) / veh_ms
    return np.where(veh_ms > TC_SPEED_GATE, s, np.nan)


def find_accel_segments(t, rpm, tqo, veh):
    """Hard-accel segments: rpm and torque both up, speed rising through them.
    Deliberately NOT requiring a standing start or a 90 kph terminal speed --
    in a mixed session almost nothing satisfies that."""
    hot = (rpm > RPM_GATE) & (tqo > TQ_GATE)
    segs, i, n = [], 0, len(t)
    while i < n:
        if not hot[i]:
            i += 1
            continue
        j = i
        while j + 1 < n and hot[j + 1] and (t[j + 1] - t[j]) < 1.0:
            j += 1
        # walk the start backwards to where this pull actually began (near-zero speed
        # or the torque first coming on), so the launch transient is inside the window
        s = i
        while s > 0 and (t[i] - t[s]) < 3.0 and veh[s] > 0.3 and tqo[s] > 5:
            s -= 1
        # extend the end to the speed peak
        e = j
        while e + 1 < n and (t[e + 1] - t[j]) < 3.0 and veh[e + 1] >= veh[e] - 0.5:
            e += 1
        if (t[e] - t[s]) >= MIN_LEN_S and np.nanmax(veh[s:e + 1]) > np.nanmin(veh[s:e + 1]) + 3:
            segs.append((s, e))
            i = e + 1
        else:
            i = j + 1
    # merge overlapping / touching windows (the backward walk can create duplicates)
    merged = []
    for s0, e0 in sorted(segs):
        if merged and s0 <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], e0))
        else:
            merged.append((s0, e0))
    return merged


def settle_metrics(ts, sl, target=TC_TARGET_SLIP, band=0.02):
    """Step-response style metrics on the slip trace, treating `target` as setpoint."""
    ok = np.isfinite(sl)
    if ok.sum() < 4:
        return {}
    ts, sl = ts[ok], sl[ok]
    peak = np.nanmax(sl)
    overshoot = peak - target
    # first time it comes down into the band and stays for >=0.3 s
    settle = np.nan
    inb = np.abs(sl - target) <= band
    for a in range(len(ts)):
        if inb[a]:
            held = ts[(ts >= ts[a]) & (ts <= ts[a] + 0.3)]
            idx = np.searchsorted(ts, held)
            idx = idx[idx < len(inb)]
            if len(idx) and inb[idx].all():
                settle = ts[a] - ts[0]
                break
    tail = sl[ts >= ts[-1] - 0.6]
    sse = (np.nanmean(tail) - target) if len(tail) else np.nan
    # zero-crossings of the error = oscillation proxy (10 Hz: only <5 Hz visible)
    err = sl - target
    zc = int(np.sum(np.diff(np.sign(err[np.isfinite(err)])) != 0))
    return dict(peak=peak, overshoot=overshoot, settle=settle, sse=sse, zc=zc,
                frac_above=float(np.mean(sl > target)), n=len(sl),
                dur=ts[-1] - ts[0])


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: python parse_accel_test.py <csv> [--dump-launch N]")
    path = sys.argv[1]
    dump = None
    if "--dump-launch" in sys.argv:
        dump = int(sys.argv[sys.argv.index("--dump-launch") + 1])

    t, g = load(path)
    veh, rear, front = g["veh"], g["rear"], g["front"]
    slip = firmware_slip(rear, veh)

    print(f"\n=== SESSION ===  {len(t)} samples, {(t[-1]-t[0])/3600:.2f} h, "
          f"median {1/np.median(np.diff(t)):.0f} Hz")
    moving = veh > 2
    print(f"moving {moving.mean()*100:.1f}% of samples | peak speed {np.nanmax(veh):.1f} m/s "
          f"({np.nanmax(veh)*3.6:.0f} kph) | peak |torque| {np.nanmax(g['tqo']):.0f} Nm")
    print(f"slip (firmware defn, gated v>{TC_SPEED_GATE} m/s): "
          f"median {np.nanmedian(slip[moving]):+.3f}  p95 {np.nanpercentile(slip[moving],95):+.3f}  "
          f"max {np.nanmax(slip[moving]):+.2f}")

    segs = find_accel_segments(t, g["rpm"], g["tqo"], np.nan_to_num(veh))
    print(f"\n=== {len(segs)} HARD-ACCEL SEGMENT(S)  (|rpm|>{RPM_GATE:.0f} & "
          f"|tq|>{TQ_GATE:.0f}, speed rising) ===")
    if not segs:
        print("none found -- loosen RPM_GATE / TQ_GATE")
        return

    rows = []
    for n, (i, j) in enumerate(segs, 1):
        sl = slice(i, j + 1)
        ts, sv = t[sl] - t[i], slip[sl]
        v0, v1 = veh[i], np.nanmax(veh[sl])
        standing = v0 < 2.0
        m = settle_metrics(ts, sv)
        req, out = g["tqr"][sl], g["tqo"][sl]
        both = np.isfinite(req) & np.isfinite(out)
        cut = np.maximum(req - out, 0)
        cut_mean = np.nanmean(cut[both]) if both.any() else np.nan
        cut_max = np.nanmax(cut[both]) if both.any() else np.nan
        cut_frac = float(np.mean(cut[both] > 5)) if both.any() else np.nan
        # Reduction fraction y. THIS IS THE ONE THAT MATTERS, and the old version of
        # this script got it wrong.
        #
        # WRONG:  y = 1 - torqueFeedback / torqueRequest
        #   VCFRONT_torqueRequest is ALREADY POST-TC (the VC applies the reduction
        #   before the request leaves), so that ratio is not the TC cut at all. It is
        #   the gap between what was asked for and what the motor managed, which above
        #   ~5500 rpm is the power-limited envelope, not traction control.
        # RIGHT:  y = 1 - torqueRequest_postTC / driver_demand
        #   with driver_demand = apps/100 * torque_max.
        dem = (g["apps"][sl] / 100.0) * TORQUE_MAX_NM
        with np.errstate(divide="ignore", invalid="ignore"):
            ydem = np.where(dem > 20, 1.0 - req / dem, np.nan)
        ydem = np.clip(ydem, 0.0, 1.0)
        y_max = np.nanmax(ydem) if np.isfinite(ydem).any() else np.nan
        # kept only to show how far off the old definition was
        with np.errstate(divide="ignore", invalid="ignore"):
            yold = np.where(req > 20, 1 - out / req, np.nan)
        y_old = np.nanmax(yold) if np.isfinite(yold).any() else np.nan
        # 0-75 m by integrating vehicle speed. NOT the odometer: that channel has
        # 0.1 km (= 100 m) resolution, so it cannot resolve a 75 m run at all.
        vv = np.nan_to_num(veh[sl])
        dist = np.concatenate([[0.0], np.cumsum(np.diff(ts) * vv[:-1])])
        k75 = np.where(dist >= 75)[0]
        t75 = ts[k75[0]] if len(k75) else np.nan
        # Is the observed reduction consistent with a PURE P controller?
        # firmware calls lib_pi_typeb_calc, which never writes d_term, and both
        # gain maps ship ki=0 / ilim=0 -> y should be clamp(kp*(slip-target),0,maxlim)
        # NOTE: scored against an ASSUMED map. The live gains are in NVM and this log
        # proves NVM was written (123.0 Nm ceiling matches no map). A poor r_P here is
        # therefore NOT evidence against pure-P, it may just be the wrong kp.
        y_pred = np.clip(ASSUMED_KP * (sv - TC_TARGET_SLIP), 0, ASSUMED_MAXLIM)
        okp = np.isfinite(y_pred) & np.isfinite(ydem)
        r_p = np.corrcoef(y_pred[okp], ydem[okp])[0, 1] if okp.sum() > 3 else np.nan
        rows.append((n, t[i], standing, v0, v1, m, cut_mean, cut_max, cut_frac,
                     y_max, y_old, t75, r_p))

    hdr = (f"{'#':>3} {'t_start':>9} {'type':>9} {'v0':>5} {'vpk':>5} {'0-75m':>6} "
           f"{'slip_pk':>8} {'over':>7} {'settle':>7} {'sse':>7} {'zc':>3} {'cut_avg':>8} "
           f"{'cut_max':>8} {'y_dem':>6} {'y_old':>6} {'r_P':>5}")
    print(hdr); print("-" * len(hdr))
    for (n, t0, st, v0, v1, m, cm, cx, cf, ym, yo, t75, rp) in rows:
        f = lambda x, p=2: ("  n/a" if (x is None or not np.isfinite(x)) else f"{x:.{p}f}")
        print(f"{n:3d} {t0:9.1f} {'STANDING' if st else 'rolling':>9} {v0:5.1f} {v1:5.1f} "
              f"{f(t75):>6} {f(m.get('peak')):>8} {f(m.get('overshoot')):>7} "
              f"{f(m.get('settle')):>7} {f(m.get('sse'),3):>7} {m.get('zc',0):3d} "
              f"{f(cm,1):>8} {f(cx,1):>8} {f(ym):>6} {f(yo):>6} {f(rp):>5}")

    print(f"\nslip_pk/over/sse are vs the {TC_TARGET_SLIP:.0%} firmware target. "
          f"settle = first entry into +/-2% held 0.3 s.")
    print(f"y_dem = peak TC cut, 1 - postTC_request / driver_demand, demand = apps/100 "
          f"* {TORQUE_MAX_NM:.0f} Nm. THIS is the controller output y.")
    print("y_old = the old, WRONG 1 - feedback/request. Request is already post-TC, so")
    print("        that column is mostly the motor envelope, not TC. Shown to compare.")
    print(f"r_P scored against {ASSUMED_MAP}, kp={ASSUMED_KP}, clamp={ASSUMED_MAXLIM}.")
    print("cut_* = requested minus delivered torque (Nm), same caveat as y_old.")
    print("zc = error zero-crossings; at 10 Hz only oscillation below 5 Hz is visible.")

    if dump:
        n, (i, j) = dump, segs[dump - 1]
        sl = slice(i, j + 1)
        print(f"\n=== LAUNCH {n} SAMPLE DUMP (t0={t[i]:.1f}s) ===")
        print(f"{'t_rel':>6} {'veh':>6} {'rear':>7} {'front':>7} {'v_rear':>7} "
              f"{'slip':>7} {'req':>6} {'out':>6} {'y':>5}")
        for k in range(i, j + 1):
            vr = g["rear"][k] * (2 * np.pi / 60) * TIRE_RADIUS_M
            y = (1 - g["tqo"][k] / g["tqr"][k]) if g["tqr"][k] > 20 else np.nan
            s = slip[k]
            print(f"{t[k]-t[i]:6.2f} {veh[k]:6.2f} {g['rear'][k]:7.1f} {g['front'][k]:7.1f} "
                  f"{vr:7.2f} {s if np.isfinite(s) else float('nan'):7.3f} "
                  f"{g['tqr'][k]:6.1f} {g['tqo'][k]:6.1f} {y if np.isfinite(y) else float('nan'):5.2f}")


if __name__ == "__main__":
    main()

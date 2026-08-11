#!/usr/bin/env python3
"""Can we fit an EMRAX 208 Kt droop from today_test.csv? Probe, not a deliverable.

Model under test (lib/emrax208_efficiency.m):
    Irms      = T / Kt                       <- Kt constant today (p.Nm_per_Arms)
    P_copper  = 3 * Irms^2 * R_phase
    P_core    = a*rpm + b*rpm^2
    eta_motor = P_mech / (P_mech + P_copper + P_core)
    eta_real  = eta_motor * eta_inverter

Droop candidate:  Kt(T) = Kt0 * (1 - alpha * T / T_ref)

The log gives DC pack current, not phase RMS. So we cannot see Irms directly.
What we CAN see is the total pack->shaft loss, and ask whether it grows with
torque faster than constant-Kt copper loss predicts.
"""
import numpy as np, pandas as pd

KT0, RPH, CA, CB, ETA_INV = 0.83, 0.012, 0.10833, 2.7778e-5, 0.95
T_REF = 150.0

d = pd.read_csv(r"C:\Users\Aboud\Downloads\today_test.csv")
t   = d["t_s"].to_numpy(float)
rpm = np.abs(d["PM100DX_motorSpeed"].to_numpy(float))
tq  = np.abs(d["PM100DX_torqueFeedback"].to_numpy(float))
ipk = d["BMSB_packCurrent"].to_numpy(float)
vpk = d["BMSB_packVoltage"].to_numpy(float)

# motoring = current leaving the pack (logged negative here, same as torque)
p_dc    = vpk * (-ipk)                       # W out of pack, >0 when motoring
p_shaft = tq * rpm * (2*np.pi/60.0)          # W at the shaft

# ---------------------------------------------------------------- gate
# Need real load and real speed or eta is dominated by noise / core loss.
m = (tq > 10) & (rpm > 500) & (p_dc > 500) & np.isfinite(p_dc)
print(f"samples total {len(t)}, pass gate {m.sum()}")

# steady-ish: torque and rpm not slewing hard (10 Hz, so this is coarse)
dtq  = np.abs(np.gradient(tq))
drpm = np.abs(np.gradient(rpm))
steady = m & (dtq < 8) & (drpm < 150)
print(f"of those, 'steady' (|dT|<8 Nm/sample, |drpm|<150) {steady.sum()}")

for name, sel in (("all-load", m), ("steady", steady)):
    T, N, PD, PS = tq[sel], rpm[sel], p_dc[sel], p_shaft[sel]
    eta = PS / PD
    print(f"\n=== {name}: n={sel.sum()} ===")
    print(f"  torque range   {T.min():.0f} .. {T.max():.0f} Nm   (p50 {np.median(T):.0f})")
    print(f"  rpm range      {N.min():.0f} .. {N.max():.0f}")
    print(f"  measured eta   p10 {np.percentile(eta,10):.3f}  p50 {np.median(eta):.3f}  p90 {np.percentile(eta,90):.3f}")
    # how many samples actually sit up where droop would show?
    for thr in (60, 80, 100, 120):
        print(f"    T > {thr:3d} Nm : {np.sum(T>thr):5d} samples")

# ------------------------------------------------- circularity check
# If the inverter derives torqueFeedback from measured current and its own Kt,
# then T vs I_pack is the inverter's model, not the motor's physics.
sel = steady
T, N, I = tq[sel], rpm[sel], -ipk[sel]
# DC current at fixed speed should scale ~ T*omega/V; strip the speed term
omega = N * (2*np.pi/60.0)
pred_i = T * omega / vpk[sel]                # ideal lossless DC current
r = np.corrcoef(pred_i, I)[0, 1]
print(f"\ncorr(ideal DC current, measured pack current) = {r:.4f}  (n={sel.sum()})")

# ------------------------------------------------- the actual fit
# loss = P_dc - P_shaft.  Model: copper(alpha) + core + inverter haircut.
loss_meas = p_dc[sel] - p_shaft[sel]

def loss_model(alpha):
    kt = KT0 * (1.0 - alpha * T / T_REF)
    kt = np.maximum(kt, 0.05)
    irms = T / kt
    return 3*irms**2*RPH + CA*N + CB*N**2

for alpha in (0.0, 0.05, 0.10, 0.15, 0.20, 0.30):
    resid = loss_meas - loss_model(alpha)
    print(f"  alpha={alpha:4.2f}  Kt(150Nm)={KT0*(1-alpha):.3f}  "
          f"resid mean {resid.mean():8.0f} W   rms {np.sqrt((resid**2).mean()):8.0f} W")

print(f"\n  measured loss: mean {loss_meas.mean():.0f} W, p50 {np.median(loss_meas):.0f} W, "
      f"p95 {np.percentile(loss_meas,95):.0f} W")
print(f"  modelled copper at alpha=0, T=p95: "
      f"{3*(np.percentile(T,95)/KT0)**2*RPH:.0f} W")

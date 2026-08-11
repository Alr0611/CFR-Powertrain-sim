#!/usr/bin/env python3
"""Kt across the torque range, per bin. Not a single droop constant.

The droop question is closed: kt_droop_probe.py showed one scalar is unidentifiable from
this log and the check is near circular anyway, since torqueFeedback is the inverter's own
current-derived estimate. This is a different question.

torqueFeedback isn't a torque sensor. The inverter computes T = Kt_inverter * I_rms with
whatever Kt it was configured with. If the real machine constant differs then true torque
is k * T_feedback, and k shouldn't be constant because saturation drops Kt as current
rises. Estimating k per torque bin is the ask.

Power balance:  V*I_dc = T_true*w + 3*R*I_rms^2 + core(w) + P_inv
The terms have different shapes (signal in T*w, copper in T^2, core in w and w^2), so
inside a bin where T is nearly fixed and w sweeps wide, they separate by slope in w.

*** READ THIS BEFORE QUOTING ANYTHING. *** The energy ratios (Pmech/Pelec per bin) are
solid. The k_inv regression column is NOT: it still returns implied efficiency above 1.0
in the top bin even with the steadiness filter on, because efficiency varies with speed
inside a bin so the slope isn't cleanly 1/eta. Fixing it needs synchronised logging or
phase current, neither of which this log has.

Other limits: P_inv isn't measured, it sits in the intercept. R_phase is cold datasheet.
Only the RATIO k is estimable, not absolute Kt, since Kt_inverter is unknown.
"""
import numpy as np
import pandas as pd

CSV = r"C:\Users\Aboud\Downloads\today_test.csv"
R_PHASE = 0.012          # ohm, DATASHEET, cold
KT_DATASHEET = 0.83      # Nm/Arms, DATASHEET. Used only to turn T into an assumed I_rms.
CORE_A, CORE_B = 0.10833, 2.7778e-5      # core loss = a*rpm + b*rpm^2, from params_cfr26


def load():
    d = pd.read_csv(CSV)
    d["Tfb"] = -d["PM100DX_torqueFeedback"]       # motoring positive
    d["Idis"] = -d["BMSB_packCurrent"]            # discharge positive
    d["rpm"] = d["PM100DX_motorSpeed"]
    d["w"] = d["rpm"] * 2 * np.pi / 60
    d["Pelec"] = d["BMSB_packVoltage"] * d["Idis"]
    d["Pmech"] = d["Tfb"] * d["w"]
    d["Irms"] = d["Tfb"] / KT_DATASHEET
    d["core"] = CORE_A * d["rpm"] + CORE_B * d["rpm"] ** 2
    d["copper"] = 3 * R_PHASE * d["Irms"] ** 2
    return d


def motoring(d, steady=True):
    """Motoring only, real load, real speed. Regen and coast carry no information here.

    STEADINESS FILTER, and it is not optional. The log is 10 Hz and the channels are NOT
    time-synchronised. During a hard launch torque and current swing by tens of percent
    inside one sample interval, so T_feedback and I_pack in the same row describe slightly
    different instants. That misalignment does not average out -- it correlates with the
    transient and biases the power balance. Without this filter the top torque bin returns
    an implied efficiency ABOVE 1.0, which is a physical impossibility and the clearest
    possible sign the unfiltered estimate is not trustworthy.

    Run with steady=False to reproduce that broken behaviour and see the difference.
    """
    m = d[(d["Tfb"] > 5) & (d["rpm"] > 500) & (d["Idis"] > 5)
          & d["BMSB_packVoltage"].notna()].copy()
    if not steady:
        return m
    dt = d["t_s"].diff().median()
    m["dT"] = d["Tfb"].diff().abs() / dt
    m["dw"] = d["rpm"].diff().abs() / dt
    # Thresholds: torque moving under 60 Nm/s and speed under 1500 rpm/s. At 10 Hz that
    # is under 6 Nm and 150 rpm of drift within one sample, i.e. a few percent.
    return m[(m["dT"] < 60) & (m["dw"] < 1500)]


def estimate_k(g, r_phase=R_PHASE):
    """Per-bin least squares for k in  Pelec - copper - core = k*(T*w) + const."""
    y = g["Pelec"] - 3 * r_phase * g["Irms"] ** 2 - g["core"]
    x = g["Pmech"]
    A = np.column_stack([x, np.ones(len(x))])
    sol, *_ = np.linalg.lstsq(A, y, rcond=None)
    k_inv, c = sol            # y = k_inv*Pmech + c, where k_inv = 1/eta_residual
    # y is electrical power net of the modelled losses. If the torque estimate were exact
    # and the loss model complete, y would equal Pmech and k_inv would be 1.0.
    # k_inv > 1 means MORE electrical power went in than T_feedback*w accounts for:
    # either unmodelled loss, or T_feedback UNDER-reads.
    return k_inv, c


if __name__ == "__main__":
    d = load()
    m = motoring(d)
    print(f"{len(m)} QUASI-STEADY motoring samples "
          f"(of {len(motoring(d, steady=False))} motoring total)\n")

    print("=== per-torque-bin power balance ===")
    print("k_inv = slope of (electrical power - modelled losses) against T_feedback*w.")
    print("k_inv = 1.00 would mean the torque estimate and the loss model close exactly.")
    print("k_inv > 1 means unaccounted electrical input: unmodelled loss, or T under-read.\n")
    print(f"{'T bin (Nm)':>12} {'n':>6} {'rpm span':>12} {'k_inv':>8} {'implied eta':>12} "
          f"{'Pmech kW':>9} {'copper W':>9} {'core W':>8}")
    edges = [5, 20, 40, 60, 80, 100, 115, 130]
    rows = []
    for lo, hi in zip(edges[:-1], edges[1:]):
        g = m[(m["Tfb"] >= lo) & (m["Tfb"] < hi)]
        if len(g) < 40:
            print(f"{lo:5d}-{hi:<6d} {len(g):>6d}   too few samples")
            continue
        k_inv, c = estimate_k(g)
        print(f"{lo:5d}-{hi:<6d} {len(g):>6d} {g['rpm'].min():5.0f}-{g['rpm'].max():<6.0f} "
              f"{k_inv:8.3f} {1/k_inv:12.3f} {g['Pmech'].mean()/1000:9.2f} "
              f"{g['copper'].mean():9.0f} {g['core'].mean():8.0f}")
        rows.append((0.5 * (lo + hi), k_inv, len(g)))

    print("\n=== direct efficiency check, no regression ===")
    print("energy-weighted Pmech / Pelec per torque bin. If this is implausibly LOW at high")
    print("torque, either there is a big unmodelled loss or T_feedback under-reads there.\n")
    print(f"{'T bin (Nm)':>12} {'n':>6} {'Pmech/Pelec':>13} {'loss kW':>9} "
          f"{'modelled loss kW':>18} {'unexplained kW':>16}")
    for lo, hi in zip(edges[:-1], edges[1:]):
        g = m[(m["Tfb"] >= lo) & (m["Tfb"] < hi)]
        if len(g) < 40:
            continue
        eta = g["Pmech"].sum() / g["Pelec"].sum()
        loss = (g["Pelec"] - g["Pmech"]).mean()
        modelled = (g["copper"] + g["core"]).mean()
        print(f"{lo:5d}-{hi:<6d} {len(g):>6d} {eta:13.3f} {loss/1000:9.2f} "
              f"{modelled/1000:18.2f} {(loss-modelled)/1000:16.2f}")

    print("\n=== sensitivity to R_phase (DATASHEET 0.012, cold; hot copper is higher) ===")
    print(f"{'R_phase':>9}" + "".join(f"{f'{lo}-{hi} Nm':>12}"
                                      for lo, hi in zip(edges[:-1], edges[1:])))
    for r in (0.012, 0.015, 0.018, 0.022):
        row = f"{r:9.3f}"
        for lo, hi in zip(edges[:-1], edges[1:]):
            g = m[(m["Tfb"] >= lo) & (m["Tfb"] < hi)]
            row += f"{estimate_k(g, r)[0]:12.3f}" if len(g) >= 40 else f"{'-':>12}"
        print(row)

    print("\n=== is k_inv actually TRENDING with torque, or is it flat? ===")
    if len(rows) >= 3:
        c = np.array([r[0] for r in rows])
        k = np.array([r[1] for r in rows])
        n = np.array([r[2] for r in rows])
        sl, ic = np.polyfit(c, k, 1, w=np.sqrt(n))
        print(f"  weighted linear trend: k_inv = {ic:.4f} {sl:+.6f} * T")
        print(f"  over 20 -> 125 Nm that is {ic+sl*20:.3f} -> {ic+sl*125:.3f} "
              f"({100*((ic+sl*125)/(ic+sl*20)-1):+.1f}%)")
        print("  A RISING k_inv with torque is the saturation signature (Kt falling as")
        print("  current rises). A FLAT one means this log cannot resolve saturation and")
        print("  the honest answer is a single ratio with the stated error bar.")

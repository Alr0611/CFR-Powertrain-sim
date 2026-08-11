#!/usr/bin/env python3
"""Solve for the rolling radius that makes the logged accel runs energetically possible.

Three things in the chain are measured and not in dispute: gear ratio 4.6133 (no radius
involved), delivered torque 122-124 Nm, and motor speed straight off the inverter. That
leaves ONE free scale factor between what the motor did and how far the car went, which
is the rolling radius. So solve for it instead of assuming it.

Per run:
  motor energy  = integral of T*w dt            <- contains no radius
  car energy    = dKE(r) + drag(r) + rolling(r) <- scales as roughly r^2
and the ratio IS the required drivetrain efficiency. Compare against 0.794.

Well conditioned because a 10% radius error is a ~20% energy error. Sharp test.

Why it matters: p.r_wheel = 0.221 is a real measurement, but of the Hoosier 18.0x6.0-10.
It's only our radius if that's our tyre, which has never been confirmed with a tape.

Nothing is tuned here. eta stays at its independently derived 0.794 and the answer comes
out as a radius, with the full radius-vs-eta trade printed so both can be judged.
"""
import numpy as np
import pandas as pd

CSV = r"C:\Users\Aboud\Downloads\today_test.csv"
RUN_STARTS = (15554, 15741, 15914, 16151)

M_CAR, G_ACC = 294.0, 9.81
CDA, CLA, RHO, CRR = 0.933, 1.499, 1.225, 0.015
I_ROTOR, I_DRIVELINE, M_WHEEL, KFACTOR = 0.0256, 5e-4, 5.6, 0.60
G_RATIO = 4.6154
ETA_NOMINAL = 0.794


def runs():
    d = pd.read_csv(CSV)
    d["Tfb"] = -d["PM100DX_torqueFeedback"]
    out = []
    for t0 in RUN_STARTS:
        seg = d[(d["t_s"] >= t0 - 5) & (d["t_s"] <= t0 + 25)]
        rpm = seg["PM100DX_motorSpeed"].to_numpy()
        if rpm.max() < 4000:
            continue
        i0 = int(np.argmax(rpm > 100))
        while i0 > 0 and rpm[i0 - 1] > 20:
            i0 -= 1
        out.append(dict(t0=t0,
                        t=seg["t_s"].to_numpy()[i0:] - seg["t_s"].to_numpy()[i0],
                        rpm=rpm[i0:],
                        T=seg["Tfb"].to_numpy()[i0:],
                        wf=seg["VCFRONT_wheelSpeedFL"].to_numpy()[i0:]))
    return out


def energy_ratio(r, run, t_lo=1.0, t_hi=4.0, detail=False, src="front"):
    """needed / delivered over the window. Equals eta_drivetrain at the correct radius.

    src="front" uses the UNDRIVEN FRONT wheels for vehicle speed. Use this one.
    src="motor" uses motor speed / G. Kept only to show what the error looks like.

    Why it matters, this was got wrong once already: the rears are still slipping through
    this whole window, 3-6% against the fronts at 1-4 s and 12-22% at 1.0 s. Deriving
    vehicle speed from motor speed therefore OVERSTATES v by ~4-5%, and since KE goes as
    v^2 that overstates the energy the car absorbed by ~9%. That inflated the implied eta
    at r = 0.221 from 0.99 to 1.07 and made it look like a conservation-of-energy
    violation when it is really just an implausibly high efficiency.

    Front wheels under-read slightly (rolling resistance, their own small slip), so the
    truth sits a hair above the front number. Not corrected for, it is well under the
    effect being measured.
    """
    t, rpm, T, wf = run["t"], run["rpm"], run["T"], run["wf"]
    m = (t >= t_lo) & (t <= t_hi)
    if m.sum() < 8:
        return np.nan
    t_, rpm_, T_, wf_ = t[m], rpm[m], T[m], wf[m]
    w = rpm_ * 2 * np.pi / 60
    if src == "front":
        v = wf_ * 2 * np.pi / 60 * r
    else:
        v = w / G_RATIO * r

    I_wheel = KFACTOR**2 * M_WHEEL * r**2
    # effective translating mass: car + 4 wheels + rotor/driveline reflected through G
    m_eff = M_CAR + (4 * I_wheel + (I_ROTOR + I_DRIVELINE) * G_RATIO**2) / r**2

    dKE = 0.5 * m_eff * (v[-1] ** 2 - v[0] ** 2)
    Fdown = 0.5 * RHO * CLA * v**2
    Fdrag = 0.5 * RHO * CDA * v**2
    Froll = CRR * (M_CAR * G_ACC + Fdown)
    road_work = np.trapezoid((Fdrag + Froll) * v, t_)
    needed = dKE + road_work

    delivered = np.trapezoid(T_ * w, t_)     # motor mechanical energy, radius-free
    if detail:
        return dict(dKE=dKE, road=road_work, needed=needed, delivered=delivered,
                    v0=v[0], v1=v[-1], m_eff=m_eff, ratio=needed / delivered)
    return needed / delivered


if __name__ == "__main__":
    R = runs()
    print(f"{len(R)} standing starts\n")
    print("=== needed/delivered energy ratio vs assumed radius (1.0-4.0 s window) ===")
    print("This ratio IS the required drivetrain efficiency. Compare against 0.794.\n")
    print(f"{'r (m)':>8}" + "".join(f"{f'run{x[chr(39)+chr(39)] if False else x}':>10}"
                                    for x in [r['t0'] for r in R]) + f"{'mean':>9}   verdict")
    rr = np.arange(0.185, 0.2351, 0.005)
    means = []
    for r in rr:
        vals = [energy_ratio(r, run) for run in R]
        mu = float(np.nanmean(vals))
        means.append(mu)
        verdict = ""
        if mu > 1.0:
            verdict = "IMPOSSIBLE (eta > 1)"
        elif mu > 0.90:
            verdict = "implausible"
        elif abs(mu - ETA_NOMINAL) < 0.02:
            verdict = "<== matches eta 0.794"
        print(f"{r:8.4f}" + "".join(f"{v:10.3f}" for v in vals) + f"{mu:9.3f}   {verdict}")

    means = np.array(means)
    k = np.where(np.diff(np.sign(means - ETA_NOMINAL)))[0]
    if len(k):
        i = k[0]
        r_sol = np.interp(ETA_NOMINAL, means[i:i + 2], rr[i:i + 2])
        print(f"\n  -> at eta_drivetrain = {ETA_NOMINAL}, the log implies "
              f"r_wheel = {r_sol:.4f} m")
        print(f"     unloaded OD would be roughly {2*r_sol/0.0254/0.96:.1f} inch "
              "(effective rolling radius is ~4% under unloaded)")

    print("\n=== raw energies, so this is auditable instead of a black box ===")
    print("At r = 0.2210 (params) and r = 0.2000, per run, over 1.0-4.0 s:\n")
    for r in (0.2210, 0.2000):
        print(f"  --- r = {r:.4f} m ---")
        print(f"  {'run':>8} {'v 1.0s':>8} {'v 4.0s':>8} {'m_eff':>8} {'dKE kJ':>9} "
              f"{'road kJ':>9} {'needed kJ':>11} {'motor kJ':>10} {'ratio':>8}")
        for run in R:
            e = energy_ratio(r, run, detail=True)
            print(f"  {run['t0']:>8} {e['v0']:8.2f} {e['v1']:8.2f} {e['m_eff']:8.1f} "
                  f"{e['dKE']/1000:9.1f} {e['road']/1000:9.1f} {e['needed']/1000:11.1f} "
                  f"{e['delivered']/1000:10.1f} {e['ratio']:8.3f}")
    print("\n  'motor kJ' is the integral of T_feedback * omega. It contains NO radius.")
    print("  'needed kJ' is what the car absorbed, off the undriven front wheels.")
    print("  Ratio IS the required eta_drivetrain. Above 1.0 is impossible; above ~0.90")
    print("  is not impossible but is not credible for this drivetrain either.")

    print("\n=== the honest trade: every (radius, eta) pair consistent with the log ===")
    print("Both cannot be chosen freely. Pick the radius with a tape measure and eta")
    print("follows, or vice versa.\n")
    print(f"{'r (m)':>8} {'implied eta':>13}  comment")
    for r in (0.1950, 0.2000, 0.2032, 0.2100, 0.2210, 0.2286):
        mu = float(np.nanmean([energy_ratio(r, run) for run in R]))
        c = ""
        if r == 0.2032:
            c = "firmware TIRE_RADIUS_M; 16in OD / 2"
        elif r == 0.2210:
            c = "params p.r_wheel, TTC RE for 18.0x6.0-10"
        elif r == 0.2286:
            c = "18 inch OD / 2, unloaded"
        elif r == 0.2000:
            c = "~16 inch effective rolling"
        if mu > 1.0:
            flag = "  <-- NOT PHYSICAL"
        elif mu > 0.90:
            flag = "  <-- implausible for spur+chain+diff+12deg halfshafts"
        else:
            flag = ""
        print(f"{r:8.4f} {mu:13.3f}  {c}{flag}")

    print("\n=== same thing off MOTOR speed, to show the error that was made ===")
    print("Motor speed includes rear wheelspin, which is still 3-6% here. Don't use this.")
    print(f"{'r (m)':>8} {'front (right)':>15} {'motor (wrong)':>15}")
    for r in (0.2000, 0.2032, 0.2100, 0.2210, 0.2286):
        a = float(np.nanmean([energy_ratio(r, run) for run in R]))
        b = float(np.nanmean([energy_ratio(r, run, src="motor") for run in R]))
        print(f"{r:8.4f} {a:15.3f} {b:15.3f}")

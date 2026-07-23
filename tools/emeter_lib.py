#!/usr/bin/env python3
"""
EMETER_LIB -- shared loader + metrics for the competition energy-meter logs.

Everything that reads a TDMS file goes through here so the benchmark script and
the lap study cannot drift apart on sign conventions, units or lap detection.

WHAT THE E-METER GIVES US (see tools/emeter_unpack.py --channels-only)
    Voltage      V,  100 Hz   pack terminal voltage
    Current      A,  100 Hz   pack current (sign convention varies BY TEAM)
    Energy       Wh, 100 Hz   cumulative counter, CONTINUES ACROSS STINTS
    GLV          V,  100 Hz   low-voltage system battery
    Violation    bool         organiser power-limit flag
    TeamSignal1-4 int32       team-defined; ZERO in every 2025 endurance file
    Temperature1 degC, 1 Hz   optional, and unreliable (see TEMPERATURE below)

Three traps in this data, all handled here:

1. SIGN CONVENTION IS PER-TEAM. Some cars log discharge negative, some positive,
   and some have the Energy channel and V*I disagreeing with EACH OTHER. Never
   trust the raw sign. We normalise off each run's own net integral so that
   "consumption is positive, regen is negative" always holds.

2. THE ENERGY COUNTER DOES NOT RESET BETWEEN STINTS. For most cars the second
   endurance file STARTS at the first file's ending value. Summing the final
   values double-counts. Always use delta = E[-1] - E[0] per stint, then sum.
   (Some cars do reset; the delta form is correct either way.)

3. THERE IS NO SPEED, DISTANCE OR LAP CHANNEL. Laps are recovered by combining
   two independent estimates: the quasi-periodicity of the power trace
   (autocorrelation) and the event format (22 laps in two driver stints). Neither
   works alone -- autocorrelation cannot tell a lap from a half-lap, and the
   format alone gives no per-stint precision. See resolve_lap_times(). Lap counts
   are ESTIMATES and carry a per-stint agreement flag.

TEMPERATURE: Temperature1 is a single probe with no documented mounting point,
it is missing on 17 of 52 endurance files, and where present it produces obvious
garbage (one car reads 0 degC, another peaks at 3106 degC). It is NOT a motor,
inverter or pack-cell temperature. It is loaded and reported, but flagged, and
nothing load-bearing is built on it.
"""

import os
import re
import sys
from dataclasses import dataclass, field

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAWDIR = os.path.join(HERE, "emeter_work", "raw")
OUTDIR = os.path.join(HERE, "output")

NAME_RE = re.compile(r"^(\d+)_(.+?)_(\d{6}-\d{6})(.*)\.tdms$", re.IGNORECASE)

# ---------------------------------------------------------------------------
# ASSUMPTIONS -- every one of these is an input we did NOT measure. Change here.
# ---------------------------------------------------------------------------
LAP_KM = 1.0          # km per endurance lap. FSAE endurance is ~22 km over 22 laps.
                      # ASSUMPTION: used ONLY to convert Wh/lap -> Wh/km. Because it
                      # is a single constant applied to every car, it CANNOT change
                      # the ranking -- it only sets the absolute Wh/km scale.
ENDURANCE_LAPS = 22   # full endurance distance, for the 22-lap feasibility study

# Validity gates for "this is a real endurance run we can rank".
MIN_LAPS_RANKED = 8      # below this it is an out-lap or a DNF
MIN_ENERGY_WH = 300.0    # a car that moved for 20 min cannot have used ~0 Wh
MIN_MEAN_KW = 2.0        # ...nor averaged under 2 kW. Both catch a dead e-meter
                         # (car 243 logged 22.6 min and 1 Wh -- it recorded nothing,
                         # and without this gate it ranks first at 0.0 Wh/lap).

# Autocorrelation search window for the lap period (s). Deliberately wide -- the
# window is NOT where the answer comes from. Harmonics are broken by the event
# format (11 laps per driver stint); see resolve_lap_times().
LAP_MIN_S, LAP_MAX_S = 30.0, 140.0
LAP_CONSENSUS_TOL = 0.15   # ACF must land within +-15% of the format-implied lap time


def require_nptdms():
    try:
        from nptdms import TdmsFile  # noqa: F401
    except ImportError:
        import subprocess
        print("npTDMS not found -- installing...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet", "npTDMS"])
    from nptdms import TdmsFile
    return TdmsFile


@dataclass
class Stint:
    """One TDMS file = one continuous logging session."""
    car: int
    university: str
    stamp: str
    path: str
    t: np.ndarray            # s, from t=0
    P: np.ndarray            # W, SIGN-NORMALISED: consumption positive, regen negative
    V: np.ndarray            # V
    I: np.ndarray            # A, sign-normalised to match P
    E_delta_Wh: float        # |E[-1]-E[0]|, the organiser's own counter
    E_trapz_Wh: float        # our integral of P, for cross-validation
    temp: np.ndarray = field(default=None)   # degC @1 Hz, or None
    temp_ok: bool = False
    violation: bool = False
    dt: float = 0.01

    @property
    def duration_s(self):
        return len(self.P) * self.dt

    @property
    def counter_mismatch_pct(self):
        """Disagreement between the organiser's Wh counter and our own integral."""
        if self.E_delta_Wh <= 0:
            return np.nan
        return 100.0 * abs(self.E_trapz_Wh - self.E_delta_Wh) / self.E_delta_Wh


def parse_name(path):
    m = NAME_RE.match(os.path.basename(path))
    if not m:
        return None
    car, uni, stamp, tag = m.groups()
    return int(car), uni, stamp, tag.strip(" _"), "ENDUR-EV" in tag.upper()


def load_stint(path, TdmsFile=None):
    """Read one TDMS file into a sign-normalised Stint."""
    TdmsFile = TdmsFile or require_nptdms()
    meta = parse_name(path)
    if meta is None:
        return None
    car, uni, stamp, _, _ = meta

    tf = TdmsFile.read(path)
    d = tf["Data"]
    V = np.asarray(d["Voltage"][:], dtype=float)
    I = np.asarray(d["Current"][:], dtype=float)
    E = np.asarray(d["Energy"][:], dtype=float)
    dt = float(d["Voltage"].properties.get("wf_increment", 0.01))

    # -- TRAP 1: normalise sign off this run's OWN net integral, not the raw sign.
    P_raw = V * I
    net = np.trapezoid(P_raw, dx=dt)
    sign = -1.0 if net < 0 else 1.0
    P = P_raw * sign
    I = I * sign

    # -- TRAP 2: delta, never the final value (counter carries across stints).
    E_delta = abs(float(E[-1] - E[0]))
    E_trapz = abs(net) / 3600.0

    temp, temp_ok = None, False
    try:
        temp = np.asarray(tf["Temperature"]["Temperature1"][:], dtype=float)
        # Sanity gate: a real ambient/pack probe sits in a believable band and
        # actually varies. 0 degC rails and 3106 degC spikes are sensor faults.
        finite = temp[np.isfinite(temp)]
        temp_ok = (
            finite.size > 10
            and float(np.nanmin(finite)) > 5.0
            and float(np.nanmax(finite)) < 120.0
        )
    except (KeyError, TypeError):
        pass

    try:
        violation = bool(np.asarray(d["Violation"][:], dtype=float).max() > 0)
    except (KeyError, TypeError):
        violation = False

    return Stint(
        car=car, university=uni, stamp=stamp, path=path,
        t=np.arange(len(P)) * dt, P=P, V=V, I=I,
        E_delta_Wh=E_delta, E_trapz_Wh=E_trapz,
        temp=temp, temp_ok=temp_ok, violation=violation, dt=dt,
    )


def find_endurance(root=RAWDIR):
    """Group ENDUR-EV file paths by car number, chronologically."""
    by_car = {}
    for dirpath, _, files in os.walk(root):
        for f in files:
            if not f.lower().endswith(".tdms"):
                continue
            meta = parse_name(os.path.join(dirpath, f))
            if meta and meta[4]:
                by_car.setdefault(meta[0], []).append(os.path.join(dirpath, f))
    return {c: sorted(v) for c, v in sorted(by_car.items())}


# ---------------------------------------------------------------------------
# LAP RECOVERY
# ---------------------------------------------------------------------------
def lap_candidates(stint, decimate=10, n_keep=12):
    """
    Autocorrelation peaks of the power trace -- the candidate lap periods.

    There is no lap channel, so we use the fact that a driver repeats the same
    accelerate/brake sequence every lap: the autocorrelation of |P(t)| peaks at
    the lap period. Returns [(lag_s, acf_height), ...] sorted by height.

    This returns CANDIDATES, not an answer, because a single trace cannot
    distinguish the lap period from its harmonics: a course with two similar
    halves correlates at half the lap time, often MORE strongly than at the lap
    itself. (Toronto is the worked example -- peaks at 31.7 / 66.4 / 98.0 / 130.1 s,
    tallest at 31.7 s, but the real lap is 66.4 s.) Picking the tallest peak here
    would have given Toronto 50 laps and made it look twice as efficient as it was.
    Disambiguation happens in resolve_lap_times(), using the field.
    """
    P = np.abs(stint.P)
    k = max(1, int(decimate))
    n = (len(P) // k) * k
    if n < k * 100:
        return []
    P = P[:n].reshape(-1, k).mean(axis=1)
    fs = 1.0 / (stint.dt * k)

    x = P - P.mean()
    sd = x.std()
    if sd <= 0:
        return []
    x = x / sd
    ac = np.correlate(x, x, "full")[len(x) - 1:] / len(x)
    lags = np.arange(len(ac)) / fs

    band = (lags >= LAP_MIN_S) & (lags <= LAP_MAX_S)
    if not band.any():
        return []
    ac_b, lag_b = ac[band], lags[band]
    peaks = np.r_[False, (ac_b[1:-1] > ac_b[:-2]) & (ac_b[1:-1] > ac_b[2:]), False]
    if not peaks.any():
        i = int(np.argmax(ac_b))
        return [(float(lag_b[i]), float(ac_b[i]))]
    cand = sorted(zip(lag_b[peaks].tolist(), ac_b[peaks].tolist()), key=lambda c: -c[1])
    return cand[:n_keep]


def active_time(stint, idle_kw=0.5, min_stop_s=20.0):
    """
    Seconds the car was actually running, excluding SUSTAINED stops.

    Not the same as "samples above a power threshold". Within a normal lap the
    car drops under any idle threshold constantly -- every brake zone and every
    coast. Counting those as stopped would throw away a third of the run. A stop
    only counts if power stays low for at least `min_stop_s` continuously, which
    is a grid queue or a driver change, not a corner.

    This matters because lap count = active_time / lap_time. Charging phantom
    laps to a car that sat on the grid makes it look artificially efficient.
    """
    low = stint.P < idle_kw * 1000.0
    if not low.any():
        return stint.duration_s
    # run-length encode the low-power mask, keep only runs long enough to be stops
    d = np.diff(np.r_[0, low.view(np.int8), 0])
    starts, ends = np.flatnonzero(d == 1), np.flatnonzero(d == -1)
    need = int(min_stop_s / stint.dt)
    stopped = sum((e - s) for s, e in zip(starts, ends) if (e - s) >= need)
    return max(0.0, (len(stint.P) - stopped) * stint.dt)


def resolve_lap_times(stints_by_car):
    """
    Turn per-stint candidate peaks into lap times.

    Autocorrelation alone CANNOT do this. A power trace that repeats every lap
    also repeats at half and a third of a lap, and on this course the half-lap
    peak is frequently the taller one (Toronto: peaks at 31.7 / 66.4 / 98.0 /
    130.1 s -- a clean harmonic series whose tallest member is the WRONG one).
    Picking the tallest peak gave Toronto 50 laps and made a 20 kW car look like
    the second most efficient in the field. So we need one outside fact.

    The outside fact is the event format: FSAE endurance is 22 laps, split into
    two driver stints of 11. So for any full-length stint the lap time must be
    close to active_time / 11 -- an estimate that involves no signal processing
    at all. We use that as a PRIOR and let the autocorrelation supply the
    precision: each candidate lag (and its 2nd and 3rd harmonics) is scored by
    peak height weighted by agreement with the prior, and the best wins.

    The two methods are independent -- one is the rulebook plus a stopwatch, the
    other is signal processing on the power trace -- so their agreement is a real
    cross-check, and `agreed` records it per stint. Across the field they agree
    within 15% on 45 of 52 stints.

    Returns {path: (lap_s, acf_height, agreed_with_prior)}.
    """
    prior_frac = 0.25          # sigma of the prior, as a fraction of expected lap
    full_stint_s = 600.0       # below this a stint is not a full 11-lap driver run

    cands, actives = {}, {}
    for stints in stints_by_car.values():
        for s in stints:
            cands[s.path] = lap_candidates(s)
            actives[s.path] = active_time(s)

    # field fallback for stints too short for the 11-lap prior to apply
    rough = []
    for p, c in cands.items():
        if c and actives[p] >= full_stint_s:
            rough.append(actives[p] / (ENDURANCE_LAPS / 2))
    field_lap = float(np.median(rough)) if rough else 70.0

    out = {}
    for path, c in cands.items():
        if not c:
            out[path] = (np.nan, 0.0, False)
            continue
        act = actives[path]
        expect = act / (ENDURANCE_LAPS / 2) if act >= full_stint_s else field_lap

        best, best_score = None, -1.0
        for lag, h in c:
            for m in (1, 2, 3):                    # candidate, or it is a harmonic
                val = lag * m
                if not (LAP_MIN_S <= val <= LAP_MAX_S):
                    continue
                w = np.exp(-0.5 * ((val - expect) / (prior_frac * expect)) ** 2)
                score = max(h, 0.0) * w
                if score > best_score:
                    best, best_score = (val, h), score
        if best is None:
            lag, h = c[0]
            out[path] = (float(lag), float(h), False)
            continue
        lap, h = best
        out[path] = (float(lap), float(h), abs(lap - expect) / expect <= LAP_CONSENSUS_TOL)
    return out


def split_laps(stint, lap_s):
    """
    Cut a stint into per-lap slices of the recovered period.

    Honest about what this is: a FIXED-PERIOD segmentation, not a start/finish
    line. It cannot tell you a real lap TIME (the e-meter has no position
    reference). What it CAN do is chop the run into equal-length windows so that
    lap-to-lap ENERGY variation is measurable -- which is what the driver-
    consistency analysis needs. Windows are aligned to the start of the run.
    """
    if not np.isfinite(lap_s) or lap_s <= 0:
        return []
    n = int(stint.duration_s // lap_s)
    per = int(round(lap_s / stint.dt))
    return [slice(i * per, (i + 1) * per) for i in range(n)]


# ---------------------------------------------------------------------------
# PER-CAR METRICS
# ---------------------------------------------------------------------------
def car_metrics(car, stints, lapmap, lap_km=LAP_KM):
    """
    Roll every endurance stint for one car into a single comparable record.

    Energy is summed as per-stint DELTAS (trap 2). Peak power is reported both as
    the raw maximum and as the 99.9th percentile -- the raw max on a 100 Hz
    pack-side shunt catches switching spikes that are not really "power the car
    used", so the percentile is the number worth ranking on.

    `lapmap` comes from resolve_lap_times() over the WHOLE field, so lap counts
    here are already harmonic-disambiguated.
    """
    if not stints:
        return None

    E_Wh = sum(s.E_delta_Wh for s in stints)
    dur_s = sum(s.duration_s for s in stints)
    allP = np.concatenate([s.P for s in stints])
    dt = stints[0].dt

    # regen: negative half of the sign-normalised power trace
    regen_Wh = float(-np.trapezoid(np.minimum(allP, 0.0), dx=dt) / 3600.0)
    gross_Wh = float(np.trapezoid(np.maximum(allP, 0.0), dx=dt) / 3600.0)

    laps, lap_times, confs, agreed, act_s = 0.0, [], [], True, 0.0
    for s in stints:
        a = active_time(s)
        act_s += a
        lap_s, conf, ok = lapmap.get(s.path, (np.nan, 0.0, False))
        if np.isfinite(lap_s) and lap_s > 0:
            laps += a / lap_s          # active time only -- no phantom grid laps
            lap_times.append(lap_s)
            confs.append(conf)
            agreed = agreed and ok

    moving = allP > 500.0   # W; drop key-on idle so "average power" means driving
    rec = {
        "car": car,
        "university": stints[0].university,
        "n_stints": len(stints),
        "duration_min": dur_s / 60.0,
        "active_min": act_s / 60.0,
        "energy_Wh": E_Wh,
        "gross_Wh": gross_Wh,
        "regen_Wh": regen_Wh,
        "regen_pct": 100.0 * regen_Wh / gross_Wh if gross_Wh > 0 else 0.0,
        "P_mean_kW": float(allP[moving].mean() / 1e3) if moving.any() else np.nan,
        "P_peak_kW": float(allP.max() / 1e3),
        "P_p999_kW": float(np.percentile(allP, 99.9) / 1e3),
        "V_mean": float(np.concatenate([s.V for s in stints]).mean()),
        "laps_est": laps,
        "lap_s_est": float(np.mean(lap_times)) if lap_times else np.nan,
        "lap_conf": float(np.mean(confs)) if confs else 0.0,
        "lap_agrees_field": agreed,
        "counter_mismatch_pct": float(np.nanmax([s.counter_mismatch_pct for s in stints])),
        "violation": any(s.violation for s in stints),
        "temp_ok": any(s.temp_ok for s in stints),
        "stints": stints,
    }
    rec["Wh_per_lap"] = E_Wh / laps if laps >= 1 else np.nan
    rec["km_est"] = laps * lap_km
    rec["Wh_per_km"] = E_Wh / rec["km_est"] if rec["km_est"] > 0 else np.nan
    rec["ranked"] = bool(
        laps >= MIN_LAPS_RANKED
        and np.isfinite(rec["Wh_per_lap"])
        and E_Wh >= MIN_ENERGY_WH
        and np.isfinite(rec["P_mean_kW"])
        and rec["P_mean_kW"] >= MIN_MEAN_KW
    )
    return rec


def analyse_field(root=RAWDIR, lap_km=LAP_KM, verbose=True):
    """
    Full pipeline: find endurance runs -> load -> resolve laps across the whole
    field -> per-car metrics. Lap resolution is field-wide by design, so this is
    the entry point both the benchmark and the lap study use.
    """
    TdmsFile = require_nptdms()
    by_car = find_endurance(root)
    if not by_car:
        return []
    loaded = {}
    for car, paths in by_car.items():
        if verbose:
            print(f"  reading car {car} ({len(paths)} endurance stint(s))...", flush=True)
        stints = [s for s in (load_stint(p, TdmsFile) for p in paths) if s is not None]
        if stints:
            loaded[car] = stints

    lapmap = resolve_lap_times(loaded)
    if verbose:
        agree = sum(1 for v in lapmap.values() if v[2])
        med = np.median([v[0] for v in lapmap.values() if np.isfinite(v[0])])
        print(f"  field lap consensus: {med:.1f} s ({agree}/{len(lapmap)} stints agree)")

    recs = [car_metrics(c, s, lapmap, lap_km) for c, s in loaded.items()]
    return [r for r in recs if r]


def efficiency_factor(recs):
    """
    The competition's OWN efficiency metric, not just Wh/lap.

    Wh/lap on its own rewards driving slowly -- a car that crawls uses less energy
    per lap and would "win" a pure economy ranking while losing the event. FSAE
    scores efficiency as a product of pace AND energy, roughly

        EffFactor = (t_min / t_car) * (E_min / E_car)

    both terms <= 1, best car = 1.0. We have both ingredients: energy from the Wh
    counter, and lap time from the recovered power-trace period.

    CAVEAT: lap time here is ESTIMATED by autocorrelation, so this reproduces the
    SHAPE of the official metric, not the official score. Use it to see who was
    genuinely efficient versus merely slow -- not to predict points.
    """
    ok = [r for r in recs if r["ranked"] and np.isfinite(r["lap_s_est"])]
    if not ok:
        return
    t_min = min(r["lap_s_est"] for r in ok)
    e_min = min(r["Wh_per_lap"] for r in ok)
    for r in recs:
        if r in ok:
            r["eff_factor"] = (t_min / r["lap_s_est"]) * (e_min / r["Wh_per_lap"])
        else:
            r["eff_factor"] = np.nan


# ---------------------------------------------------------------------------
# 2026 competition context (supplied by the team, Michigan 2026 official results)
# NOTE: the e-meter data in hand is 2025. Same teams, one year of development
# apart -- see the caveat printed by emeter_benchmark.py.
# ---------------------------------------------------------------------------
RESULTS_2026 = {
    "oregon-state-univ": (1, 1, 895.5),
    "rochester-institute-of-technology": (2, 8, 856.7),
    "univ-of-pittsburgh---pittsburgh": (3, 6, 807.2),
    "carnegie-mellon-univ": (4, 46, 756.9),
    "univ-of-connecticut": (5, 103, 756.8),
    "univ-of-wisconsin---madison": (6, 38, 743.9),
    "california-polytechnic-state-univ-slo": (7, 62, 717.5),
    "kookmin-univ": (8, 30, 696.0),
    "cornell-univ": (9, 19, 681.3),
    "univ-of-michigan---ann-arbor": (10, 65, 671.3),
    "texas-a&m-univ": (12, 98, 609.7),
    "univ-of-washington": (14, 5, 562.4),
    "auburn-univ": (16, 111, 527.8),
    "concordia-university": (19, 43, 475.1),
    "massachusetts-inst-of-tech": (20, 9, 462.0),
}

CONCORDIA_2025_CAR = 246   # from the 2025 filenames: 246_concordia-university_*
CONCORDIA_2026_CAR = 43    # 2026 competition number, per the team


def pretty_uni(u):
    """Filename slug -> something printable (slugs carry --- separators and mojibake)."""
    for bad in ("�", "é", "\xe9"):
        u = u.replace(bad, "e")
    u = u.replace("---", "|").replace("--", "|").replace("-", " ").replace("|", " - ")
    return " ".join(u.split()).title()

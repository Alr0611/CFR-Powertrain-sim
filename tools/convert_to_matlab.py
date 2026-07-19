#!/usr/bin/env python3
r"""
Turns a telemetry CSV into MATLAB-ready data. The third link in the chain:
    export_influx_chunked.py  ->  CSV  ->  THIS  ->  .mat (and/or a wide CSV)

It eats BOTH shapes of CSV that exist in this project's life:
    WIDE  -- what export_influx_chunked.py writes (t_s + one column per channel).
             Already MATLAB-friendly; this just converts to .mat and fills gaps.
    LONG  -- what the Influx web UI's raw export gives you (_time/_field/_value
             rows, with '#' comment lines on top). This is the shape the old
             version of this script half-handled. It gets pivoted, de-duplicated,
             sorted, and gap-filled properly.

WHY THE GAP-FILL MATTERS
    Different channels report at different instants. Pivot them onto one time
    axis and most cells are holes. Every hole is filled with the channel's
    previous value (zero-order hold -- same thing parse_influx.m does), because
    "the sensor hasn't said anything new" means "the value hasn't changed",
    not "the value is unknown". Samples before a channel's first report stay
    NaN. Don't want any filling? --fill none.

USAGE
    python convert_to_matlab.py                     guided: finds CSVs next to you, asks
    python convert_to_matlab.py my_export.csv       -> telemetry_data.mat beside it
    python convert_to_matlab.py my_export.csv --csv-out wide.csv   also write a wide CSV
                                                    (repo data/ style, readtable-ready)
    python convert_to_matlab.py --help              all the knobs

IN MATLAB
    load('telemetry_data.mat')      % every channel by its real name, plus t_s and dt
    plot(t_s, PM100DX_motorSpeed)

SETUP: none. First run auto-installs what it needs (pandas; scipy for .mat),
same deal as the export tool.
"""

import argparse
import os
import sys


def ensure_deps(need_scipy):
    """First run installs what's missing so nobody has to think about pip."""
    missing = []
    try:
        import pandas  # noqa: F401
    except ImportError:
        missing.append("pandas")
    if need_scipy:
        try:
            import scipy  # noqa: F401
        except ImportError:
            missing.append("scipy")
    if not missing:
        return
    import subprocess
    print(f"One-time setup: installing {' + '.join(missing)}...")
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install"] + missing)
    except Exception as e:
        sys.exit(
            "\nCouldn't auto-install (no internet, or pip is locked down?).\n"
            "Run this once yourself, then start the tool again:\n"
            f"    pip install {' '.join(missing)}\n"
            f"  (the error was: {e})\n"
        )
    print("Done. Continuing...\n")


def sniff_format(path):
    """WIDE (t_s + channels) or LONG (_time/_field/_value)? Look at the header."""
    with open(path, "r", encoding="utf-8-sig", errors="replace") as f:
        header = ""
        for line in f:
            if line.strip() and not line.startswith("#"):   # Influx UI puts '#' comments on top
                header = line.lower()
                break
    cols = [c.strip().strip('"') for c in header.split(",")]
    if any(c in cols for c in ("_field", "field")) and any(c in cols for c in ("_value", "value")):
        return "long"
    if cols and cols[0] in ("t_s", "time", "_time") and len(cols) > 1:
        return "wide"
    # No recognizable time column at all -> say so instead of guessing wrong.
    sys.exit(
        f"\nCan't tell what kind of CSV this is: {path}\n"
        f"First header line was: {header.strip()}\n"
        "Expected either t_s + channel columns (export tool) or\n"
        "_time/_field/_value rows (Influx UI raw export).\n"
    )


def pick_col(df, *names):
    """First column present from names (Influx sometimes drops the underscore)."""
    for n in names:
        if n in df.columns:
            return n
    return None


def load_long(path):
    """Influx UI raw export -> wide DataFrame indexed 0..n with a t_s column."""
    import pandas as pd
    df = pd.read_csv(path, comment="#", low_memory=False)
    t_col = pick_col(df, "_time", "time")
    f_col = pick_col(df, "_field", "field")
    v_col = pick_col(df, "_value", "value")
    if not (t_col and f_col and v_col):
        sys.exit(f"\nLong-format CSV but couldn't find time/field/value columns in: {list(df.columns)}\n")

    df = df[[t_col, f_col, v_col]].copy()
    df.columns = ["time", "field", "value"]
    df["time"] = pd.to_datetime(df["time"], utc=True, errors="coerce")
    df["value"] = pd.to_numeric(df["value"], errors="coerce")
    bad = df["time"].isna() | df["field"].isna()
    if bad.any():
        print(f"  (dropped {bad.sum()} rows with unreadable time/field)")
    df = df[~bad]
    if df.empty:
        sys.exit("\nNothing readable in that file after cleaning. Is it the right CSV?\n")

    # pivot_table, not pivot: real exports HAVE duplicate (time, field) pairs
    # (chunk overlaps, re-pulls). pivot() crashes on those; mean() shrugs.
    wide = df.pivot_table(index="time", columns="field", values="value", aggfunc="mean")
    wide = wide.sort_index()
    t0 = wide.index[0]
    out = wide.reset_index(drop=True)
    out.insert(0, "t_s", (wide.index - t0).total_seconds())
    print(f"  {len(df)} rows -> {len(out)} time points x {len(out.columns)-1} channels "
          f"(started {t0.isoformat()})")
    return out


def load_wide(path):
    """Export-tool CSV: already t_s + channels. Just read and coerce numeric."""
    import pandas as pd
    df = pd.read_csv(path, comment="#", low_memory=False)
    t_col = df.columns[0]
    if t_col != "t_s":                      # tolerate a raw _time first column
        if df[t_col].dtype == object:
            t = pd.to_datetime(df[t_col], utc=True, errors="coerce")
            df[t_col] = (t - t.iloc[0]).dt.total_seconds()
        df = df.rename(columns={t_col: "t_s"})
    for c in df.columns:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df = df.sort_values("t_s").reset_index(drop=True)
    print(f"  {len(df)} rows x {len(df.columns)-1} channels")
    return df


def matlab_name(name):
    """A valid MATLAB variable name (same idea as matlab.lang.makeValidName)."""
    import re
    clean = re.sub(r"\W", "_", str(name))
    if not clean or not (clean[0].isalpha()):
        clean = "x" + clean
    return clean[:63]                       # MATLAB's namelengthmax


def convert(path, mat_out, csv_out, fill):
    fmt = sniff_format(path)
    print(f"Reading {path} ({fmt} format)...")
    df = load_long(path) if fmt == "long" else load_wide(path)

    chans = [c for c in df.columns if c != "t_s"]
    empty = [c for c in chans if df[c].notna().sum() == 0]
    if empty:
        print(f"  heads up: {len(empty)} channel(s) have NO data in this window: "
              + ", ".join(empty[:6]) + ("..." if len(empty) > 6 else ""))

    if fill == "zoh":
        df[chans] = df[chans].ffill()       # zero-order hold, like parse_influx.m

    # dt: the gap in front of each sample. First one gets the typical gap, so
    # sum(dt) ~ session length and nothing multiplies by zero.
    import numpy as np
    t = df["t_s"].to_numpy(dtype=float)
    dt = np.diff(t, prepend=t[0])
    if len(t) > 1:
        dt[0] = np.median(np.diff(t))

    if csv_out:
        df.to_csv(csv_out, index=False, float_format="%.6g")
        print(f"Wrote {csv_out}  (wide CSV, repo data/ style)")
        print(f"  In MATLAB:  W = readtable('{os.path.basename(csv_out)}');")

    if mat_out:
        import scipy.io as sio
        mat = {"t_s": t, "dt": dt}
        renamed = []
        for c in chans:
            key = matlab_name(c)
            if key != c:
                renamed.append(f"{c} -> {key}")
            mat[key] = df[c].to_numpy(dtype=float)
        sio.savemat(mat_out, mat)
        dur = (t[-1] - t[0]) / 60 if len(t) > 1 else 0
        print(f"Wrote {mat_out}  ({len(chans)} channels + t_s + dt, {dur:.1f} min of data)")
        if renamed:
            print("  some channel names weren't valid MATLAB names, so:")
            for r in renamed:
                print(f"    {r}")
        print(f"  In MATLAB:  load('{os.path.basename(mat_out)}')")


def guided():
    """No arguments: find CSVs sitting next to the user and ask which one."""
    csvs = sorted((f for f in os.listdir(".") if f.lower().endswith(".csv")),
                  key=os.path.getmtime, reverse=True)
    if not csvs:
        sys.exit(
            "\nNo CSV files in this folder. Run me from wherever your telemetry\n"
            "export landed, or pass the file directly:\n"
            "    python convert_to_matlab.py path\\to\\export.csv\n"
        )
    print("\n=====  TELEMETRY CSV -> MATLAB  =====")
    print("CSVs here (newest first):")
    for i, f in enumerate(csvs[:9], 1):
        print(f"   {i}) {f}")
    try:
        raw = input(f"\nWhich one? [1]: ").strip()
    except (EOFError, KeyboardInterrupt):
        sys.exit("\nCancelled.")
    idx = int(raw) - 1 if raw.isdigit() and 1 <= int(raw) <= len(csvs[:9]) else 0
    src = csvs[idx]
    mat_out = os.path.splitext(src)[0] + ".mat"
    ensure_deps(need_scipy=True)
    convert(src, mat_out, csv_out=None, fill="zoh")


def main():
    ap = argparse.ArgumentParser(
        description="Convert a telemetry CSV (export tool wide format OR Influx UI "
                    "long format) into a .mat and/or a clean wide CSV. "
                    "Run with no arguments for the guided version.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("csv", help="input CSV (from export_influx_chunked.py or the Influx UI)")
    ap.add_argument("--out", default=None,
                    help=".mat filename (default: input name with .mat; 'none' to skip)")
    ap.add_argument("--csv-out", default=None,
                    help="also write a cleaned wide CSV here (readtable-ready)")
    ap.add_argument("--fill", choices=["zoh", "none"], default="zoh",
                    help="gap fill: zoh = carry each channel's last value forward "
                         "(what the sim wants); none = leave holes as NaN")
    args = ap.parse_args()

    if not os.path.exists(args.csv):
        sys.exit(f"\nNo such file: {args.csv}\n")
    mat_out = args.out
    if mat_out is None:
        mat_out = os.path.splitext(args.csv)[0] + ".mat"
    elif mat_out.lower() == "none":
        mat_out = None
    if mat_out is None and not args.csv_out:
        sys.exit("\n--out none and no --csv-out: nothing to write, nothing to do.\n")

    ensure_deps(need_scipy=mat_out is not None)
    convert(args.csv, mat_out, args.csv_out, args.fill)


if __name__ == "__main__":
    if len(sys.argv) == 1:
        guided()
    else:
        main()

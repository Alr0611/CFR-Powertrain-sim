#!/usr/bin/env python3
"""
EMETER_UNPACK -- unpack the FSAE competition energy-meter archive, then tell us
what the e-meter actually logs.

WHERE THE DATA COMES FROM
    https://results.fsaeonline.com/MyResults.aspx?carnum=<carnum>
    -> "E-Meter Data" -> download the TDMS zip.
    No scraping is needed or wanted: download the archive once and point this
    script at it. The 2025 archive is the whole field in a single outer zip.

The organisers ship one outer zip containing one inner zip per car
(car_201.zip ... car_301.zip), each holding that team's TDMS logs for every
session they ran. File names carry the metadata:

    <carnum>_<university>_<yymmdd-hhmmss>[_ ENDUR-EV].tdms

Everything lands in a GITIGNORED working directory -- this is ~113 MB of other
teams' data and it does not belong in the repo.

Run this FIRST. The `--channels` dump at the end is the point: it prints the real
channel list off a real file, so nobody builds a metric on a channel that the
e-meter does not record. (Spoiler, and the reason this matters: the e-meter is a
PACK-SIDE energy counter. It logs volts, amps, cumulative watt-hours and one
optional temperature. It does NOT log speed, distance, lap markers, motor rpm,
torque or any inverter channel.)

    python tools/emeter_unpack.py                      # unpack + channel dump
    python tools/emeter_unpack.py --zip <path>         # non-default source zip
    python tools/emeter_unpack.py --channels-only      # just re-print the dump
"""

import argparse
import io
import os
import re
import sys
import zipfile
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_ZIP = os.path.join(os.path.expanduser("~"), "Downloads", "2025_E_Meter.zip")
WORKDIR = os.path.join(HERE, "emeter_work")
RAWDIR = os.path.join(WORKDIR, "raw")

# <carnum>_<university>_<timestamp>, with an optional trailing session tag.
NAME_RE = re.compile(r"^(\d+)_(.+?)_(\d{6}-\d{6})(.*)\.tdms$", re.IGNORECASE)


def require_nptdms():
    """npTDMS is the one dependency; install it rather than failing on import."""
    try:
        from nptdms import TdmsFile  # noqa: F401
    except ImportError:
        print("npTDMS not found -- installing it now...")
        import subprocess

        subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet", "npTDMS"])
    from nptdms import TdmsFile

    return TdmsFile


def parse_name(path):
    """Pull (car, university, timestamp, is_endurance) out of a TDMS filename."""
    m = NAME_RE.match(os.path.basename(path))
    if not m:
        return None
    car, uni, stamp, tag = m.groups()
    return {
        "car": int(car),
        "university": uni,
        "stamp": stamp,
        "tag": tag.strip(" _"),
        "endurance": "ENDUR-EV" in tag.upper(),
        "path": path,
    }


def unpack(src_zip, dest=RAWDIR):
    """Outer zip -> inner per-car zips -> TDMS files, one directory per car."""
    if not os.path.isfile(src_zip):
        sys.exit(f"source zip not found: {src_zip}\n(pass --zip <path> to point at it)")
    os.makedirs(dest, exist_ok=True)
    n_cars = n_files = 0
    with zipfile.ZipFile(src_zip) as outer:
        for entry in outer.namelist():
            if not entry.lower().endswith(".zip"):
                continue
            car = os.path.splitext(os.path.basename(entry))[0]
            cardir = os.path.join(dest, car)
            os.makedirs(cardir, exist_ok=True)
            with outer.open(entry) as fh:
                blob = fh.read()
            with zipfile.ZipFile(io.BytesIO(blob)) as inner:
                inner.extractall(cardir)
                n_files += len(inner.namelist())
            n_cars += 1
    print(f"unpacked {n_cars} car archives / {n_files} files -> {dest}")
    return dest


def inventory(root=RAWDIR):
    """Walk the unpacked tree and index every TDMS file we can parse a name from."""
    recs = []
    for dirpath, _, files in os.walk(root):
        for f in files:
            if f.lower().endswith(".tdms"):
                r = parse_name(os.path.join(dirpath, f))
                if r:
                    recs.append(r)
    return recs


def report_inventory(recs):
    by_car = defaultdict(list)
    for r in recs:
        by_car[r["car"]].append(r)
    endur = [r for r in recs if r["endurance"]]
    print(f"\n{len(recs)} TDMS files / {len(by_car)} cars / {len(endur)} ENDUR-EV runs\n")
    print(f"{'car':>5}  {'university':<42} {'files':>5} {'ENDUR-EV':>9}")
    print("-" * 66)
    for car in sorted(by_car):
        rs = by_car[car]
        uni = rs[0]["university"]
        ne = sum(1 for r in rs if r["endurance"])
        mark = "" if ne else "   <- no endurance run"
        print(f"{car:>5}  {uni:<42} {len(rs):>5} {ne:>9}{mark}")


def dump_channels(recs, TdmsFile):
    """
    Print the channel list off one real file, plus a schema consistency check
    across every endurance file. This is the step that decides what can honestly
    be computed downstream.
    """
    endur = sorted([r for r in recs if r["endurance"]], key=lambda r: -os.path.getsize(r["path"]))
    if not endur:
        print("\nno ENDUR-EV files found -- cannot dump channels")
        return
    sample = endur[0]
    print("\n" + "=" * 74)
    print("CHANNEL DUMP -- what the e-meter actually logs")
    print("=" * 74)
    print(f"sample file: {os.path.basename(sample['path'])}\n")

    t = TdmsFile.read_metadata(sample["path"])
    print("file properties:")
    for k, v in t.properties.items():
        print(f"    {k:<20} = {v}")
    for g in t.groups():
        print(f"\ngroup '{g.name}':")
        for c in g.channels():
            inc = c.properties.get("wf_increment", None)
            rate = f"{1/inc:g} Hz" if inc else "?"
            print(f"    {c.name:<16} n={len(c):<8} {str(c.dtype):<10} @ {rate}")

    # Schema consistency: a metric is only safe if every car records the channel.
    schemas = Counter()
    for r in endur:
        m = TdmsFile.read_metadata(r["path"])
        schemas[tuple(sorted(f"{g.name}/{c.name}" for g in m.groups() for c in g.channels()))] += 1
    print(f"\nschema consistency across all {len(endur)} ENDUR-EV files:")
    for schema, n in schemas.most_common():
        print(f"    {n:>3} files: {', '.join(s.split('/')[-1] for s in schema)}")

    print(
        "\nWHAT THIS MEANS (read before building anything on top):\n"
        "  present : Voltage, Current, Energy (cumulative Wh), GLV, Violation,\n"
        "            TeamSignal1-4 (team-defined), Temperature1 (optional, 1 Hz)\n"
        "  ABSENT  : speed, distance, lap markers, motor rpm, torque, motor temp,\n"
        "            inverter temp, any PM100DX channel\n"
        "  => the e-meter is a PACK-SIDE energy counter. Energy, power and Wh/km\n"
        "     economy are directly measurable. Drivetrain EFFICIENCY (mech out /\n"
        "     elec in) is NOT -- there is no mechanical-output channel to divide by.\n"
        "  => distance is not logged either, so Wh/km needs the rules lap length and\n"
        "     laps have to be recovered from the power trace (see emeter_lib.py).\n"
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zip", default=DEFAULT_ZIP, help="source archive (default: ~/Downloads/2025_E_Meter.zip)")
    ap.add_argument("--channels-only", action="store_true", help="skip unpacking, just re-print the channel dump")
    args = ap.parse_args()

    TdmsFile = require_nptdms()
    if not args.channels_only:
        unpack(args.zip)
    elif not os.path.isdir(RAWDIR):
        sys.exit(f"nothing unpacked yet at {RAWDIR} -- run without --channels-only first")

    recs = inventory()
    report_inventory(recs)
    dump_channels(recs, TdmsFile)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Pulls telemetry from Influx into a MATLAB-ready CSV (one column per channel,
t_s starts at 0). readtable() it and go.

SETUP (once)
    1. pip install influxdb-client tzdata
    2. Make yourself an API token in the Influx web UI (Load Data > API Tokens)
       and paste it into a file called influx_token.txt next to this script.

RUN
    python export_influx_chunked.py --start "2026-06-20 11:30" --stop "2026-06-20 13:00" --out my_run.csv

    Times are MONTREAL time -- type them straight off your phone, no UTC math.
    (Want UTC anyway? Stick a Z on the end: 2026-06-20T15:30:00Z.)
    Not sure of your window? Ballpark it wide -- quiet time returns nothing.

EDIT
    Different channels: edit DEFAULT_FIELDS below, or pass --fields.
    Everything else: --help
"""

import argparse
import csv
import os
import sys
import time
from datetime import datetime, timedelta, timezone


def montreal():
    """Montreal time (America/Toronto -- same zone), because that's where we live.
    Falls back to this computer's clock if the tz database is missing, which is
    the same thing unless your laptop thinks it's somewhere weird."""
    try:
        from zoneinfo import ZoneInfo
        return ZoneInfo("America/Toronto")
    except Exception:
        return None


def to_utc_z(s):
    """Turn a time string into the UTC Z-format Influx wants.

    Plain time ("2026-06-20 11:30")  -> treated as MONTREAL time and converted.
    Ends in Z or +hh:mm              -> used as-is.
    So you type the time off your phone and it just works.
    """
    try:
        dt = datetime.fromisoformat(s.strip().replace("Z", "+00:00"))
    except ValueError:
        sys.exit(
            f'\nCould not read the time "{s}".\n'
            'Use "2026-06-20 11:30" (Montreal time) or 2026-06-20T15:30:00Z (UTC).\n'
        )
    if dt.tzinfo is None:
        tz = montreal()
        dt = dt.replace(tzinfo=tz) if tz else dt.astimezone()
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")

# The default channel set: everything the gear-ratio / efficiency work needs.
# Pack V/I + SOC, motor speed/torque, all four wheel speeds (ratio-invariant
# ground truth), vehicle speed, odometer. Override with --fields.
DEFAULT_FIELDS = [
    "BMSB_packVoltage",
    "BMSB_packCurrent",
    "BMSB_packSOC",
    "PM100DX_motorSpeed",
    "PM100DX_torqueFeedback",
    "VCFRONT_wheelSpeedFL",
    "VCFRONT_wheelSpeedFR",
    "VCREAR_wheelSpeedRL",
    "VCREAR_wheelSpeedRR",
    "VCFRONT_vehicleSpeed",
    "VCFRONT_odometer",
]

HERE = os.path.dirname(os.path.abspath(__file__))
TOKEN_FILE = os.path.join(HERE, "influx_token.txt")

MAX_RETRIES = 4      # per-window retries before giving up on that window
RETRY_BACKOFF = 3    # seconds, grows each retry


def get_token(cli_token):
    """Token, in order of preference: --token, INFLUX_TOKEN env var, token file."""
    if cli_token:
        return cli_token
    if os.environ.get("INFLUX_TOKEN"):
        return os.environ["INFLUX_TOKEN"]
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE) as f:
            tok = f.read().strip()
        if tok:
            return tok
    sys.exit(
        "\nNo Influx token found. Make yourself one in the Influx web UI\n"
        "(Load Data > API Tokens), then either:\n"
        "  1. Save it as one line in:  " + TOKEN_FILE + "\n"
        "  2. Set the INFLUX_TOKEN environment variable\n"
        "  3. Pass --token <token>\n"
    )


def time_chunks(start_iso, stop_iso, minutes):
    start = datetime.fromisoformat(start_iso.replace("Z", "+00:00"))
    stop = datetime.fromisoformat(stop_iso.replace("Z", "+00:00"))
    if stop <= start:
        sys.exit("--stop must be after --start (both like 2026-06-20T15:30:00Z)")
    step = timedelta(minutes=minutes)
    cur = start
    while cur < stop:
        nxt = min(cur + step, stop)
        yield (cur.isoformat().replace("+00:00", "Z"),
               nxt.isoformat().replace("+00:00", "Z"))
        cur = nxt


def main():
    ap = argparse.ArgumentParser(
        description="Export car telemetry from InfluxDB to a wide MATLAB-ready CSV.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("--start", required=True,
                    help='range start, Montreal time, e.g. "2026-06-20 11:30" (add Z for UTC)')
    ap.add_argument("--stop", required=True,
                    help='range stop, same deal, e.g. "2026-06-20 13:00"')
    ap.add_argument("--out", default="telemetry_export.csv", help="output CSV filename")
    ap.add_argument("--fields", nargs="+", default=DEFAULT_FIELDS,
                    help="channel names to pull (space separated)")
    ap.add_argument("--rate", default="100ms", help="aggregation window (mean)")
    ap.add_argument("--chunk-minutes", type=int, default=5,
                    help="query window size; smaller = slower but safer")
    ap.add_argument("--url", default="http://192.168.100.115:8086",
                    help="InfluxDB URL (the car's DAQ box)")
    ap.add_argument("--org", default="90e50b9a4b0adcd6", help="InfluxDB org id")
    ap.add_argument("--bucket", default="CarTelemetry", help="InfluxDB bucket")
    ap.add_argument("--token", default=None, help="InfluxDB token (or use influx_token.txt)")
    args = ap.parse_args()

    # Check the cheap stuff (times) before demanding a token or a library.
    start_utc = to_utc_z(args.start)
    stop_utc = to_utc_z(args.stop)

    try:
        from influxdb_client import InfluxDBClient
    except ImportError:
        sys.exit("\ninfluxdb-client isn't installed. Run:  pip install influxdb-client tzdata\n")

    token = get_token(args.token)

    field_filter = " or ".join(f'r._field == "{f}"' for f in args.fields)
    flux_template = (
        'from(bucket: "{bucket}")\n'
        "  |> range(start: {start}, stop: {stop})\n"
        "  |> filter(fn: (r) => {field_filter})\n"
        "  |> aggregateWindow(every: {agg}, fn: mean, createEmpty: false)\n"
        '  |> keep(columns: ["_time", "_field", "_value", "_measurement"])\n'
    )

    # Long client timeout so a data-heavy (but healthy) window doesn't get cut off.
    client = InfluxDBClient(url=args.url, token=token, org=args.org, timeout=180_000)
    query_api = client.query_api()

    chunks = list(time_chunks(start_utc, stop_utc, args.chunk_minutes))
    print(f"\nPulling {len(args.fields)} channels")
    print(f"  you asked for:  {args.start} -> {args.stop}  (Montreal time unless you wrote Z)")
    print(f"  querying UTC:   {start_utc} -> {stop_utc}")
    print(f"  ({len(chunks)} windows of {args.chunk_minutes} min at {args.rate} sampling)\n")

    # Accumulate wide: {timestamp -> {field: value}}. A 90-min session fits in RAM fine.
    data = {}
    failed_windows = []

    for i, (w_start, w_stop) in enumerate(chunks, 1):
        flux = flux_template.format(bucket=args.bucket, start=w_start, stop=w_stop,
                                    field_filter=field_filter, agg=args.rate)
        print(f"[{i}/{len(chunks)}] {w_start} -> {w_stop} ...", end=" ", flush=True)

        tables = None
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                tables = query_api.query(flux, org=args.org)
                break
            except Exception as e:
                if attempt == MAX_RETRIES:
                    print(f"FAILED after {MAX_RETRIES} tries ({type(e).__name__}) -- skipping")
                    failed_windows.append((w_start, w_stop))
                else:
                    wait = RETRY_BACKOFF * attempt
                    print(f"\n    retry {attempt}/{MAX_RETRIES - 1} in {wait}s ({type(e).__name__})",
                          end=" ", flush=True)
                    time.sleep(wait)
        if tables is None:
            continue

        n = 0
        for table in tables:
            for record in table.records:
                data.setdefault(record.get_time(), {})[record.get_field()] = record.get_value()
                n += 1
        print(f"{n} points")

    client.close()

    if not data:
        sys.exit(
            "\nNo data came back at all. Usual suspects:\n"
            "  - wrong time range (check the 'querying UTC' line above looks sane)\n"
            "  - the car wasn't logging in that window\n"
            "  - wrong bucket / channel names (typo in --fields?)\n"
        )

    # Write wide: t_s + one column per field. Missing samples become empty
    # cells, which MATLAB's readtable turns into NaN -- exactly what we want.
    times = sorted(data.keys())
    t0 = times[0]
    with open(args.out, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["t_s"] + args.fields)
        for dt in times:
            row = [f"{(dt - t0).total_seconds():.3f}"]
            row += [data[dt].get(field, "") for field in args.fields]
            writer.writerow(row)

    dur = (times[-1] - t0).total_seconds()
    print(f"\nDone. {len(times)} rows x {len(args.fields)} channels "
          f"({dur / 60:.1f} min of data) -> {args.out}")
    print(f"In MATLAB:  W = readtable('{args.out}');   % t_s starts at 0")

    if failed_windows:
        print(f"\nHEADS UP: {len(failed_windows)} window(s) failed even after retries:")
        for a, b in failed_windows:
            print(f"    {a} -> {b}")
        print("That data is MISSING from the CSV. Re-run -- it's usually just network flake.")


if __name__ == "__main__":
    main()

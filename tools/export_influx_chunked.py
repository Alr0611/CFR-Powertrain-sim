#!/usr/bin/env python3
"""
Pulls telemetry from Influx into a MATLAB-ready CSV (one column per channel,
t_s starts at 0). readtable() it and go.

EASY MODE (just double-click / run with no arguments)
    python export_influx_chunked.py
    It walks you through it: paste your token once, type the time range off
    your phone, pick your channels, done.

SETUP (once)
    1. pip install influxdb-client tzdata
    2. Make yourself an API token in the Influx web UI (Load Data > API Tokens).
       Easy mode will offer to save it so you only paste it once.

SCRIPT MODE (for power users / automation)
    python export_influx_chunked.py --start "2026-06-20 11:30" --stop "2026-06-20 13:00" --out my_run.csv
    Times are MONTREAL time -- type them straight off your phone, no UTC math.
    (Want UTC anyway? Stick a Z on the end: 2026-06-20T15:30:00Z.)
    See all knobs with --help.

CHANNELS
    Easy mode groups all ~400 channels into subsystems (battery, motor, cooling,
    suspension, GPS...) so you just pick the group(s) you want. The full list
    lives in influx_channels.txt next to this script -- regenerate it from a new
    influx_fields.csv export if the car gains channels.
"""

import argparse
import csv
import os
import re
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
# ground truth), vehicle speed, odometer.
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
CHANNEL_FILE = os.path.join(HERE, "influx_channels.txt")


def load_channels():
    """Every channel from influx_channels.txt (one per line). If that file is
    missing, fall back to the sim essentials so the tool still runs."""
    try:
        with open(CHANNEL_FILE) as f:
            chans = [ln.strip() for ln in f if ln.strip() and not ln.startswith("#")]
        if chans:
            return chans
    except FileNotFoundError:
        pass
    return list(DEFAULT_FIELDS)


# Sort every channel into a subsystem by what the signal IS, not which ECU it's
# on (VCFRONT alone carries GPS, brakes, suspension, wheels...). First match wins,
# so order matters -- specific things (brakes, suspension) before the ECU catch-alls.
GROUP_ORDER = [
    "Battery & HV",
    "Motor & inverter",
    "Cooling & temps",
    "Wheels & speed",
    "Suspension",
    "Brakes",
    "Steering",
    "Driver inputs",
    "GPS & position",
    "Config, status & faults",
    "Other",
]


def classify(f):
    sig = f.split("_", 1)[1].lower() if "_" in f else f.lower()   # drop the ECU prefix
    if re.search(r"gps|latitude|longitude", sig) or sig in (
            "lat", "lon", "alt", "course", "heading", "day", "hour", "minute", "month", "year"):
        return "GPS & position"
    if "shockpot" in sig or "damper" in sig or "suspension" in sig:
        return "Suspension"
    if "brake" in sig:
        return "Brakes"
    if "steer" in sig:
        return "Steering"
    if re.search(r"wheelspeed|axlespeed|vehiclespeed|odometer", sig) or sig == "speed":
        return "Wheels & speed"
    if re.search(r"apps|accelerator|pedal|torquerequest|launch|bppc", sig) or sig in ("gear", "gearchangerejected"):
        return "Driver inputs"
    if re.search(r"coolant|fan|pump|radiator|thermal", sig) or ("temp" in sig and "cell" not in sig):
        return "Cooling & temps"
    if f.startswith("PM100DX"):
        return "Motor & inverter"
    if f.startswith("BMSB") or f.startswith("VCPDU") or re.search(r"contactor|cell|pack|soc|hvil|imd|isolation|precharge", sig):
        return "Battery & HV"
    if re.search(r"fault|status|state|error|crc|nvm|warn|calibrat|mem|reset|count|eeprom|checksum|param", sig):
        return "Config, status & faults"
    return "Other"


def grouped_channels():
    """{group name -> [channels]}, in GROUP_ORDER, empty groups dropped."""
    groups = {name: [] for name in GROUP_ORDER}
    for ch in load_channels():
        groups[classify(ch)].append(ch)
    return {name: groups[name] for name in GROUP_ORDER if groups[name]}

MAX_RETRIES = 4      # per-window retries before giving up on that window
RETRY_BACKOFF = 3    # seconds, grows each retry


def find_saved_token():
    """A token from the env var or the token file, or None. No prompting."""
    if os.environ.get("INFLUX_TOKEN"):
        return os.environ["INFLUX_TOKEN"]
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE) as f:
            tok = f.read().strip()
        if tok:
            return tok
    return None


def save_token(tok):
    with open(TOKEN_FILE, "w") as f:
        f.write(tok.strip() + "\n")


def get_token(cli_token):
    """For script mode: --token, then env var, then file. Exit with help if none."""
    if cli_token:
        return cli_token
    tok = find_saved_token()
    if tok:
        return tok
    sys.exit(
        "\nNo Influx token found. Make yourself one in the Influx web UI\n"
        "(Load Data > API Tokens), then either:\n"
        "  1. Save it as one line in:  " + TOKEN_FILE + "\n"
        "  2. Set the INFLUX_TOKEN environment variable\n"
        "  3. Pass --token <token>\n"
        "  ...or just run with no arguments for the guided version.\n"
    )


def time_chunks(start_iso, stop_iso, minutes):
    start = datetime.fromisoformat(start_iso.replace("Z", "+00:00"))
    stop = datetime.fromisoformat(stop_iso.replace("Z", "+00:00"))
    if stop <= start:
        sys.exit("Stop time must be after start time.")
    step = timedelta(minutes=minutes)
    cur = start
    while cur < stop:
        nxt = min(cur + step, stop)
        yield (cur.isoformat().replace("+00:00", "Z"),
               nxt.isoformat().replace("+00:00", "Z"))
        cur = nxt


def _api_hint(e, n_fields):
    """Turn an Influx ApiException into a message that actually says what's wrong."""
    status = getattr(e, "status", None)
    body = (getattr(e, "body", "") or getattr(e, "reason", "") or "")[:400]
    msg = f"\nInflux rejected the request (HTTP {status}).\n"
    if status == 401:
        msg += ("  -> Your API token is wrong or expired.\n"
                "     Make a fresh one in the Influx web UI (Load Data > API Tokens),\n"
                "     delete tools/influx_token.txt, and run again to re-enter it.\n")
    elif status in (403,):
        msg += "  -> Token is valid but not allowed to read this bucket. Make one with read access.\n"
    elif status == 404:
        msg += "  -> Bucket or org not found. Check they match the Influx UI (--bucket / --org).\n"
    elif status in (400, 422):
        msg += (f"  -> Influx couldn't run the query. You asked for {n_fields} channels at once;\n"
                "     that big a filter can trip it up. Try fewer groups, or a channel name\n"
                "     might be misspelled.\n")
    elif status and status >= 500:
        msg += "  -> Influx server error. Might be transient -- try again in a minute.\n"
    if body:
        msg += f"  Influx said: {body}\n"
    return msg


def run_export(start_utc, stop_utc, fields, out, token,
               rate="100ms", chunk_minutes=5,
               url="http://192.168.100.115:8086", org="90e50b9a4b0adcd6",
               bucket="CarTelemetry", echo_start=None, echo_stop=None):
    """The actual pull. Both easy mode and script mode funnel through here."""
    try:
        from influxdb_client import InfluxDBClient
        from influxdb_client.rest import ApiException
    except ImportError:
        sys.exit("\ninfluxdb-client isn't installed. Run:  pip install influxdb-client tzdata\n")

    # Filter with contains(set: [...]) -- ONE predicate over a list -- instead of
    # chaining N `or` clauses. With 200+ channels the giant OR filter can blow past
    # Influx's query-complexity limit and get rejected; a set never does.
    field_set = "[" + ", ".join(f'"{f}"' for f in fields) + "]"
    flux_template = (
        'from(bucket: "{bucket}")\n'
        "  |> range(start: {start}, stop: {stop})\n"
        "  |> filter(fn: (r) => contains(value: r._field, set: {field_set}))\n"
        "  |> aggregateWindow(every: {agg}, fn: mean, createEmpty: false)\n"
        '  |> keep(columns: ["_time", "_field", "_value", "_measurement"])\n'
    )

    # Long client timeout so a data-heavy (but healthy) window doesn't get cut off.
    client = InfluxDBClient(url=url, token=token, org=org, timeout=180_000)
    query_api = client.query_api()

    chunks = list(time_chunks(start_utc, stop_utc, chunk_minutes))
    print(f"\nPulling {len(fields)} channels")
    if echo_start:
        print(f"  you asked for:  {echo_start} -> {echo_stop}  (Montreal time unless you wrote Z)")
    print(f"  querying UTC:   {start_utc} -> {stop_utc}")
    print(f"  ({len(chunks)} windows of {chunk_minutes} min at {rate} sampling)\n")

    # Accumulate wide: {timestamp -> {field: value}}. A 90-min session fits in RAM fine.
    data = {}
    failed_windows = []

    for i, (w_start, w_stop) in enumerate(chunks, 1):
        flux = flux_template.format(bucket=bucket, start=w_start, stop=w_stop,
                                    field_set=field_set, agg=rate)
        print(f"[{i}/{len(chunks)}] {w_start} -> {w_stop} ...", end=" ", flush=True)

        tables = None
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                tables = query_api.query(flux, org=org)
                break
            except ApiException as e:
                # HTTP error from Influx. A 4xx (bad token, bad query) is deterministic --
                # retrying just wastes 18s per window. Bail immediately with the real reason.
                status = getattr(e, "status", 0) or 0
                if 400 <= status < 500:
                    print("FAILED")
                    client.close()
                    sys.exit(_api_hint(e, len(fields)))
                if attempt == MAX_RETRIES:
                    print(f"FAILED (HTTP {status}) -- skipping")
                    failed_windows.append((w_start, w_stop))
                else:
                    wait = RETRY_BACKOFF * attempt
                    print(f"\n    retry {attempt}/{MAX_RETRIES - 1} in {wait}s (HTTP {status})",
                          end=" ", flush=True)
                    time.sleep(wait)
            except Exception as e:
                # Network / timeout / anything else -- these CAN be transient, so retry,
                # but show the actual error instead of just its class name.
                if attempt == MAX_RETRIES:
                    print(f"FAILED after {MAX_RETRIES} tries -- {type(e).__name__}: {e}")
                    failed_windows.append((w_start, w_stop))
                else:
                    wait = RETRY_BACKOFF * attempt
                    print(f"\n    retry {attempt}/{MAX_RETRIES - 1} in {wait}s ({type(e).__name__}: {e})",
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
        if failed_windows and len(failed_windows) == len(chunks):
            # Nothing came back because every query ERRORED, not because the range was empty.
            sys.exit(
                "\nEvery window errored -- see the messages above. This is a connection/query\n"
                "problem, NOT an empty time range. Common causes:\n"
                "  - the DAQ box isn't reachable from here (are you on the car's network / VPN?)\n"
                "  - token expired -> delete tools/influx_token.txt and re-run\n"
                "  - too many channels at once -> try fewer groups\n"
            )
        sys.exit(
            "\nNo data in that window (the queries ran fine, they just found nothing):\n"
            "  - check the 'querying UTC' line above looks like the right time\n"
            "  - the car may not have been logging then\n"
            "  - a channel name might be misspelled\n"
        )

    # Write wide: t_s + one column per field. Missing samples become empty
    # cells, which MATLAB's readtable turns into NaN -- exactly what we want.
    times = sorted(data.keys())
    t0 = times[0]
    with open(out, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["t_s"] + fields)
        for dt in times:
            row = [f"{(dt - t0).total_seconds():.3f}"]
            row += [data[dt].get(field, "") for field in fields]
            writer.writerow(row)

    dur = (times[-1] - t0).total_seconds()
    print(f"\nDone. {len(times)} rows x {len(fields)} channels "
          f"({dur / 60:.1f} min of data) -> {out}")
    print(f"In MATLAB:  W = readtable('{out}');   % t_s starts at 0")

    if failed_windows:
        print(f"\nHEADS UP: {len(failed_windows)} window(s) failed even after retries:")
        for a, b in failed_windows:
            print(f"    {a} -> {b}")
        print("That data is MISSING from the CSV. Re-run -- it's usually just network flake.")


# ------------------------------------------------------------------ easy mode

def ask(prompt, default=None):
    """input() with a shown default. Empty answer -> the default."""
    tag = f" [{default}]" if default not in (None, "") else ""
    try:
        ans = input(f"{prompt}{tag}: ").strip()
    except (EOFError, KeyboardInterrupt):
        sys.exit("\nCancelled.")
    return ans if ans else (default if default is not None else "")


def _dedup(seq):
    """Drop duplicates but keep first-seen order (groups can overlap in theory)."""
    seen = set()
    out = []
    for x in seq:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out


def pick_from_group(chans, name):
    """Drill into one group and pick individual channels."""
    print(f"\n{name} -- {len(chans)} channels:")
    for i, c in enumerate(chans, 1):
        print(f"   {i:2d}) {c}")
    raw = ask("Pick numbers (Enter = all of them)", "").strip()
    if not raw:
        return list(chans)
    parts = [p for p in raw.replace(",", " ").split() if p]
    if all(p.isdigit() for p in parts):
        return [chans[int(p) - 1] for p in parts if 1 <= int(p) <= len(chans)] or list(chans)
    return parts


def pick_channels():
    """Group-based menu -> list of channel names."""
    groups = grouped_channels()
    names = list(groups)
    total = sum(len(v) for v in groups.values())

    print("\nPick channels by SUBSYSTEM:")
    for i, name in enumerate(names, 1):
        print(f"   {i:2d}) {name:<24} {len(groups[name]):3d}")
    print()
    print(f"  Enter    -> just the sim essentials ({len(DEFAULT_FIELDS)} channels)")
    print("  1,3      -> those groups, combined")
    print(f"  all      -> everything ({total} channels)")
    print("  list 2   -> see and pick individual channels inside group 2")
    raw = ask("\nYour pick", "").strip()

    if not raw:
        return list(DEFAULT_FIELDS)
    low = raw.lower()
    if low == "all":
        return [c for v in groups.values() for c in v]
    if low.startswith("list"):
        rest = raw[4:].strip()
        if rest.isdigit() and 1 <= int(rest) <= len(names):
            return pick_from_group(groups[names[int(rest) - 1]], names[int(rest) - 1])
        print('  (which group? e.g. "list 2")')
        return pick_channels()

    parts = [p for p in raw.replace(",", " ").split() if p]
    if parts and all(p.isdigit() for p in parts):
        chosen = []
        for p in parts:
            idx = int(p)
            if 1 <= idx <= len(names):
                chosen += groups[names[idx - 1]]
            else:
                print(f"  (ignoring {p} -- out of range)")
        return _dedup(chosen) or list(DEFAULT_FIELDS)
    return parts   # treated as channel names typed directly


def interactive():
    print("\n=====  CFR TELEMETRY EXPORT  =====")
    print("Answer the prompts. Enter = the default in [brackets].\n")

    # --- token ---
    token = find_saved_token()
    if token:
        print("Using your saved API token.")
    else:
        print("First run needs your Influx API token (Influx web UI > Load Data > API Tokens).")
        token = ask("Paste your token").strip()
        if not token:
            sys.exit("Need a token to talk to Influx. Grab one and try again.")
        # Save it automatically so future runs never ask again.
        save_token(token)
        print("Saved -- you won't have to type it again. (Stored in influx_token.txt,")
        print("which is gitignored, so it stays off GitHub.)")

    # --- time range ---
    print('\nTime range in MONTREAL time, like "2026-06-20 11:30" (24-hour clock).')
    start = ask("Start")
    stop = ask("Stop")
    if not start or not stop:
        sys.exit("Need both a start and a stop time.")
    start_utc, stop_utc = to_utc_z(start), to_utc_z(stop)

    # --- channels ---
    fields = pick_channels()

    # --- output name ---
    out = ask("\nSave to filename", "telemetry_export.csv")
    if not out.lower().endswith(".csv"):
        out += ".csv"

    # --- confirm ---
    print("\n----------------------------------")
    print(f"  {start}  ->  {stop}   (Montreal)")
    print(f"  {len(fields)} channels: {', '.join(fields)}")
    print(f"  -> {out}")
    print("----------------------------------")
    if not ask("Go?", "Y").lower().startswith("y"):
        sys.exit("Okay, nothing pulled.")

    run_export(start_utc, stop_utc, fields, out, token,
               echo_start=start, echo_stop=stop)


# ------------------------------------------------------------------ script mode

def main():
    ap = argparse.ArgumentParser(
        description="Export car telemetry from InfluxDB to a wide MATLAB-ready CSV. "
                    "Run with no arguments for the guided version.",
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

    start_utc = to_utc_z(args.start)     # cheap checks before demanding a token
    stop_utc = to_utc_z(args.stop)
    token = get_token(args.token)

    run_export(start_utc, stop_utc, args.fields, args.out, token,
               rate=args.rate, chunk_minutes=args.chunk_minutes,
               url=args.url, org=args.org, bucket=args.bucket,
               echo_start=args.start, echo_stop=args.stop)


if __name__ == "__main__":
    if len(sys.argv) == 1:
        interactive()      # no arguments -> friendly guided mode
    else:
        main()             # any flags -> classic script mode

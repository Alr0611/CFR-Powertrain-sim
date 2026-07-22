#!/usr/bin/env python3
r"""Export car telemetry from InfluxDB to a wide, MATLAB-ready CSV (t_s starts at 0,
one column per channel). readtable() it and go.

Just run it -- no arguments -- for the guided version:
    python export_influx_chunked.py
It walks you through token (pasted once, then saved), time range, and channels.

Times are MONTREAL time -- type them off your phone, e.g. "2026-06-20 11:30".
Add a Z for UTC instead. Leading zeros optional ("2026-7-11 11:20" is fine).

Script mode for automation:
    python export_influx_chunked.py --start "2026-06-20 11:30" --stop "2026-06-20 13:00" --out run.csv
    (--help for all knobs)

Keep influx_channels.txt next to this script -- it's the ~400-channel list the
picker groups by subsystem. Without it you still get the sim essentials.
"""

import argparse
import csv
import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
TOKEN_FILE = os.path.join(HERE, "influx_token.txt")
CHANNEL_FILE = os.path.join(HERE, "influx_channels.txt")

# Defaults: the car's DAQ box + the channels the gear-ratio / efficiency work needs.
URL, ORG, BUCKET = "http://192.168.100.115:8086", "90e50b9a4b0adcd6", "CarTelemetry"
DEFAULT_FIELDS = [
    "BMSB_packVoltage", "BMSB_packCurrent", "BMSB_packSOC",
    "PM100DX_motorSpeed", "PM100DX_torqueFeedback",
    "VCFRONT_wheelSpeedFL", "VCFRONT_wheelSpeedFR",
    "VCREAR_wheelSpeedRL", "VCREAR_wheelSpeedRR",
    "VCFRONT_vehicleSpeed", "VCFRONT_odometer",
]


def ensure_deps():
    """First run installs influxdb-client; no-op after."""
    try:
        import influxdb_client  # noqa: F401
        return
    except ImportError:
        pass
    import subprocess
    print("One-time setup: installing 'influxdb-client'...")
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "influxdb-client", "tzdata"])
        import influxdb_client  # noqa: F401
    except Exception as e:
        sys.exit(f"\nCouldn't install it. Run this yourself, then retry:\n"
                 f"    {sys.executable} -m pip install influxdb-client tzdata\n  (error: {e})\n")
    print("Done.\n")


# ----------------------------------------------------------------- time parsing
def to_utc_z(s):
    """A date/time string -> the UTC 'Z' format Influx wants. Plain times are
    read as Montreal; anything ending in Z or +hh:mm is used as-is."""
    s = s.strip()
    dt = None
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))   # strict ISO (needs zero-padding)
    except ValueError:
        for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M",
                    "%Y-%m-%dT%H:%M:%S", "%Y/%m/%d %H:%M", "%Y-%m-%d", "%Y/%m/%d"):
            try:
                dt = datetime.strptime(s, fmt); break     # forgiving fallbacks
            except ValueError:
                continue
    if dt is None:
        sys.exit(f'\nCould not read the time "{s}". Try "2026-07-11 11:20" (Montreal) '
                 'or 2026-07-11T15:20:00Z (UTC).\n')
    if dt.tzinfo is None:
        try:
            from zoneinfo import ZoneInfo
            dt = dt.replace(tzinfo=ZoneInfo("America/Toronto"))   # Montreal
        except Exception:
            dt = dt.astimezone()                                 # fall back to this PC's clock
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def time_chunks(start_iso, stop_iso, minutes):
    start = datetime.fromisoformat(start_iso.replace("Z", "+00:00"))
    stop = datetime.fromisoformat(stop_iso.replace("Z", "+00:00"))
    if stop <= start:
        sys.exit("Stop time must be after start time.")
    cur = start
    while cur < stop:
        nxt = min(cur + timedelta(minutes=minutes), stop)
        yield cur.isoformat().replace("+00:00", "Z"), nxt.isoformat().replace("+00:00", "Z")
        cur = nxt


# ------------------------------------------------------------ channels / tokens
def load_channels():
    """Every channel from influx_channels.txt, or the sim essentials if it's missing."""
    try:
        with open(CHANNEL_FILE) as f:
            chans = [ln.strip() for ln in f if ln.strip() and not ln.startswith("#")]
        return chans or list(DEFAULT_FIELDS)
    except FileNotFoundError:
        return list(DEFAULT_FIELDS)


# Sort each channel into a subsystem by what the SIGNAL is (not which ECU it's on --
# VCFRONT alone carries GPS, brakes, suspension...). First match wins, so specific
# things come before the ECU catch-alls.
GROUP_ORDER = ["Battery & HV", "Motor & inverter", "Cooling & temps", "Wheels & speed",
               "Suspension", "Brakes", "Steering", "Driver inputs", "GPS & position",
               "Config, status & faults", "Other"]


def classify(f):
    sig = f.split("_", 1)[1].lower() if "_" in f else f.lower()
    if re.search(r"gps|latitude|longitude", sig) or sig in (
            "lat", "lon", "alt", "course", "heading", "day", "hour", "minute", "month", "year"):
        return "GPS & position"
    if re.search(r"shockpot|damper|suspension", sig):
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
    if f.startswith(("BMSB", "VCPDU")) or re.search(r"contactor|cell|pack|soc|hvil|imd|isolation|precharge", sig):
        return "Battery & HV"
    if re.search(r"fault|status|state|error|crc|nvm|warn|calibrat|mem|reset|count|eeprom|checksum|param", sig):
        return "Config, status & faults"
    return "Other"


def grouped_channels():
    """{group -> [channels]}, in GROUP_ORDER, empty groups dropped."""
    groups = {name: [] for name in GROUP_ORDER}
    for ch in load_channels():
        groups[classify(ch)].append(ch)
    return {name: chans for name, chans in groups.items() if chans}


def find_saved_token():
    """Token from the env var or the saved file, or None."""
    if os.environ.get("INFLUX_TOKEN"):
        return os.environ["INFLUX_TOKEN"]
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE) as f:
            return f.read().strip() or None
    return None


# ------------------------------------------------------------------- the export
def run_export(start_utc, stop_utc, fields, out, token,
               rate="100ms", chunk_minutes=5, echo=None):
    """The actual pull. Both guided and script mode funnel through here."""
    try:
        from influxdb_client import InfluxDBClient
        from influxdb_client.rest import ApiException
    except ImportError:
        sys.exit("\ninfluxdb-client isn't installed. Run:  pip install influxdb-client tzdata\n")

    # Filter with a pushed-down OR of field equalities: `r._field == "a" or ... == "b"`.
    # Flux optimizes THIS at the storage layer, so it's fast. contains(value:.., set:[..])
    # looks tidier but is NOT pushed down -- the box reads the whole bucket into memory and
    # filters there, which times out even for ~25 channels. The catch: one giant OR over all
    # ~400 channels is rejected as too complex (HTTP 400), so we split the channels into
    # batches of BATCH and query each batch per window, merging the results.
    BATCH = 40
    batches = [fields[k:k+BATCH] for k in range(0, len(fields), BATCH)]
    flux_t = ('from(bucket: "{b}")\n'
              "  |> range(start: {s}, stop: {e})\n"
              "  |> filter(fn: (r) => {filt})\n"
              "  |> aggregateWindow(every: {a}, fn: mean, createEmpty: false)\n"
              '  |> keep(columns: ["_time", "_field", "_value"])\n')

    client = InfluxDBClient(url=URL, token=token, org=ORG, timeout=180_000)
    q = client.query_api()
    chunks = list(time_chunks(start_utc, stop_utc, chunk_minutes))
    print(f"\nPulling {len(fields)} channels")
    if echo:
        print(f"  you asked for: {echo[0]} -> {echo[1]} (Montreal unless you wrote Z)")
    print(f"  querying UTC:  {start_utc} -> {stop_utc}")
    nb = f", {len(batches)} channel-batches each" if len(batches) > 1 else ""
    print(f"  ({len(chunks)} windows of {chunk_minutes} min at {rate}{nb})\n")

    data, failed = {}, []          # data: {timestamp -> {field: value}}, fits in RAM for a session
    for i, (ws, we) in enumerate(chunks, 1):
        print(f"[{i}/{len(chunks)}] {ws} -> {we} ...", end=" ", flush=True)
        n, window_failed = 0, False
        for batch in batches:
            filt = " or ".join(f'r._field == "{f}"' for f in batch)
            flux = flux_t.format(b=BUCKET, s=ws, e=we, filt=filt, a=rate)
            tables = query_with_retry(q, flux, client, len(fields))
            if tables is None:
                window_failed = True; continue
            for table in tables:
                for rec in table.records:
                    data.setdefault(rec.get_time(), {})[rec.get_field()] = rec.get_value()
                    n += 1
        if window_failed:
            failed.append((ws, we))
        print(f"{n} points")
    client.close()

    if not data:
        if failed and len(failed) == len(chunks):
            sys.exit("\nEvery window errored (see above) -- a connection/query problem, not an empty\n"
                     "range. On the car's network? Token fresh? Too many channels at once?\n")
        sys.exit("\nNo data in that window (queries ran fine, found nothing). Check the 'querying UTC'\n"
                 "line, that the car was logging then, and the channel names.\n")

    times = sorted(data)
    t0 = times[0]
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["t_s"] + fields)
        for dt in times:
            w.writerow([f"{(dt - t0).total_seconds():.3f}"] + [data[dt].get(fld, "") for fld in fields])

    print(f"\nDone. {len(times)} rows x {len(fields)} channels "
          f"({(times[-1]-t0).total_seconds()/60:.1f} min) -> {out}")
    print(f"In MATLAB:  W = readtable('{out}');   % t_s starts at 0")
    if failed:
        print(f"\nHEADS UP: {len(failed)} window(s) failed even after retries -- that data is MISSING.")
        print("Re-run; it's usually network flake.")


def query_with_retry(q, flux, client, n_fields, max_tries=4):
    """Query one window. 4xx (bad token/query) is deterministic -> bail with the real
    reason. Network/5xx is transient -> back off and retry. None means give up on it."""
    from influxdb_client.rest import ApiException
    for attempt in range(1, max_tries + 1):
        try:
            return q.query(flux, org=ORG)
        except ApiException as e:
            status = getattr(e, "status", 0) or 0
            if 400 <= status < 500:
                print("FAILED"); client.close(); sys.exit(api_hint(e, n_fields))
            err = f"HTTP {status}"
        except Exception as e:
            err = f"{type(e).__name__}: {e}"
        if attempt == max_tries:
            print(f"FAILED ({err}) -- skipping"); return None
        wait = 3 * attempt
        print(f"\n    retry {attempt}/{max_tries-1} in {wait}s ({err})", end=" ", flush=True)
        time.sleep(wait)


def api_hint(e, n_fields):
    """Turn an Influx HTTP error into a message that says what's actually wrong."""
    status = getattr(e, "status", None)
    body = (getattr(e, "body", "") or getattr(e, "reason", "") or "")[:300]
    hints = {
        401: "Your API token is wrong or expired. Make a fresh one (Load Data > API Tokens),\n"
             "     delete tools/influx_token.txt, and run again.",
        403: "Token is valid but can't read this bucket. Make one with read access.",
        404: "Bucket or org not found -- check they match the Influx UI.",
        400: f"Influx couldn't run the query. {n_fields} channels at once can trip it -- try fewer\n"
             "     groups, or a channel name may be misspelled.",
    }
    hint = hints.get(status, hints.get(400) if status == 422 else
                     "Influx server error, maybe transient -- try again in a minute.")
    msg = f"\nInflux rejected the request (HTTP {status}).\n  -> {hint}\n"
    return msg + (f"  Influx said: {body}\n" if body else "")


# --------------------------------------------------------------------- guided mode
def ask(prompt, default=None):
    tag = f" [{default}]" if default not in (None, "") else ""
    try:
        ans = input(f"{prompt}{tag}: ").strip()
    except (EOFError, KeyboardInterrupt):
        sys.exit("\nCancelled.")
    return ans or (default or "")


def pick_channels():
    """Subsystem menu -> list of channel names."""
    groups = grouped_channels()
    names = list(groups)
    total = sum(len(v) for v in groups.values())
    print("\nPick channels by SUBSYSTEM:")
    for i, name in enumerate(names, 1):
        print(f"   {i:2d}) {name:<24} {len(groups[name]):3d}")
    print(f"\n  Enter -> sim essentials ({len(DEFAULT_FIELDS)}) | 1,3 -> those groups | "
          f"all -> everything ({total}) | list 2 -> pick inside group 2")
    raw = ask("\nYour pick", "").strip()

    if not raw:
        return list(DEFAULT_FIELDS)
    low = raw.lower()
    if low == "all":
        return [c for v in groups.values() for c in v]
    if low.startswith("list"):
        rest = raw[4:].strip()
        if rest.isdigit() and 1 <= int(rest) <= len(names):
            name = names[int(rest) - 1]
            chans = groups[name]
            print(f"\n{name} -- {len(chans)} channels:")
            for i, c in enumerate(chans, 1):
                print(f"   {i:2d}) {c}")
            nums = ask("Pick numbers (Enter = all)", "").replace(",", " ").split()
            return [chans[int(p) - 1] for p in nums if p.isdigit() and 1 <= int(p) <= len(chans)] or list(chans)
        print('  (which group? e.g. "list 2")'); return pick_channels()

    parts = raw.replace(",", " ").split()
    if all(p.isdigit() for p in parts):
        chosen = [c for p in parts if 1 <= int(p) <= len(names) for c in groups[names[int(p) - 1]]]
        return list(dict.fromkeys(chosen)) or list(DEFAULT_FIELDS)   # de-dup, keep order
    return parts     # treated as channel names typed directly


def interactive():
    print("\n=====  CFR TELEMETRY EXPORT  =====")
    print("Answer the prompts. Enter = the default in [brackets].\n")
    token = find_saved_token()
    if token:
        print("Using your saved API token.")
    else:
        print("First run needs your Influx API token (web UI > Load Data > API Tokens).")
        token = ask("Paste your token")
        if not token:
            sys.exit("Need a token to talk to Influx.")
        with open(TOKEN_FILE, "w") as f:
            f.write(token + "\n")
        print("Saved -- won't ask again. (influx_token.txt is gitignored.)")

    print('\nTime range in MONTREAL time, like "2026-06-20 11:30" (24-hour clock).')
    start, stop = ask("Start"), ask("Stop")
    if not start or not stop:
        sys.exit("Need both a start and a stop time.")
    fields = pick_channels()
    out = ask("\nSave to filename", "telemetry_export.csv")
    if not out.lower().endswith(".csv"):
        out += ".csv"

    print(f"\n----------------------------------\n  {start}  ->  {stop}   (Montreal)")
    print(f"  {len(fields)} channels -> {out}\n----------------------------------")
    if not ask("Go?", "Y").lower().startswith("y"):
        sys.exit("Okay, nothing pulled.")
    run_export(to_utc_z(start), to_utc_z(stop), fields, out, token, echo=(start, stop))


# ---------------------------------------------------------------------- script mode
def main():
    ap = argparse.ArgumentParser(
        description="Export car telemetry from InfluxDB to a wide MATLAB-ready CSV. "
                    "Run with no arguments for the guided version.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    ap.add_argument("--start", required=True, help='range start, Montreal time (add Z for UTC)')
    ap.add_argument("--stop", required=True, help='range stop, same deal')
    ap.add_argument("--out", default="telemetry_export.csv", help="output CSV filename")
    ap.add_argument("--fields", nargs="+", default=DEFAULT_FIELDS, help="channel names to pull")
    ap.add_argument("--rate", default="100ms", help="aggregation window (mean)")
    ap.add_argument("--chunk-minutes", type=int, default=5, help="query window size")
    ap.add_argument("--token", default=None, help="InfluxDB token (or use influx_token.txt)")
    args = ap.parse_args()

    start_utc, stop_utc = to_utc_z(args.start), to_utc_z(args.stop)   # cheap checks before token
    token = args.token or find_saved_token()
    if not token:
        sys.exit("\nNo Influx token. Make one (Load Data > API Tokens), then save it in\n"
                 f"  {TOKEN_FILE}\nset INFLUX_TOKEN, pass --token, or run with no args for guided mode.\n")
    run_export(start_utc, stop_utc, args.fields, args.out, token,
               rate=args.rate, chunk_minutes=args.chunk_minutes, echo=(args.start, args.stop))


if __name__ == "__main__":
    ensure_deps()
    interactive() if len(sys.argv) == 1 else main()

#!/usr/bin/env python3
"""
export_influx_chunked.py

Pulls a time range from InfluxDB in small windows (avoids the ~100MB
truncation) and writes a WIDE, MATLAB-ready CSV: one row per 100ms sample,
a t_s time column (starts at 0), and one column per channel named exactly
as the field. Read straight into MATLAB with readtable() -- no pivoting.

SETUP:
    pip install influxdb-client --break-system-packages

FILL IN BELOW: url, token, org, bucket, field list, time range.
"""

from influxdb_client import InfluxDBClient
import csv

# ---- CONNECTION SETTINGS (fill these in) ----
INFLUX_URL = "http://192.168.100.115:8086"
INFLUX_TOKEN = "NkMs9TYxYwMrpiCE6-HrfrBJPys9herBcDxDuVnskVwgOqCojHPu2lrplb3V3D83KXiHpvpidqU69QOcpm1jqQ=="
INFLUX_ORG = "90e50b9a4b0adcd6"
BUCKET = "CarTelemetry" 

# ---- QUERY SETTINGS ----
# COMP endurance re-pull, June 20 2026, ~15:35-16:55 UTC session (found
# earlier). This time WITH wheel-speed sensors so the gear-ratio efficiency
# sweep can run on comp (real race pace) instead of the July 11 test day.
START_TIME = "2026-06-20T15:30:00Z"
STOP_TIME  = "2026-06-20T17:00:00Z"
CHUNK_MINUTES = 5
AGG_WINDOW = "100ms"

# Endurance fields for the gear-ratio EFFICIENCY sweep on comp data:
# pack V/I, motor rpm/torque, all four wheel-speed sensors (ratio-invariant
# ground truth), speed + odometer. (SOC stays on July 11 -- comp DNF'd.)
FIELDS = [
    "BMSB_packVoltage",
    "BMSB_packCurrent",
    "BMSB_packSOC",
    "PM100DX_motorSpeed",
    "PM100DX_torqueFeedback",
    "VCFRONT_wheelSpeedFL",     # 4 wheel-speed sensors = wheel_rpm ground truth
    "VCFRONT_wheelSpeedFR",
    "VCREAR_wheelSpeedRL",
    "VCREAR_wheelSpeedRR",
    "VCFRONT_vehicleSpeed",
    "VCFRONT_odometer",
]

OUTPUT_CSV = "comp_june20_data.csv"

# ---- BUILD FIELD FILTER ----
field_filter = " or ".join(f'r._field == "{f}"' for f in FIELDS)

FLUX_TEMPLATE = '''
from(bucket: "{bucket}")
  |> range(start: {start}, stop: {stop})
  |> filter(fn: (r) => {field_filter})
  |> aggregateWindow(every: {agg}, fn: mean, createEmpty: false)
  |> keep(columns: ["_time", "_field", "_value", "_measurement"])
'''

def time_chunks(start_iso, stop_iso, minutes):
    from datetime import datetime, timedelta, timezone
    start = datetime.fromisoformat(start_iso.replace("Z", "+00:00"))
    stop = datetime.fromisoformat(stop_iso.replace("Z", "+00:00"))
    step = timedelta(minutes=minutes)
    cur = start
    while cur < stop:
        nxt = min(cur + step, stop)
        yield cur.isoformat().replace("+00:00", "Z"), nxt.isoformat().replace("+00:00", "Z")
        cur = nxt

MAX_RETRIES = 4          # per-chunk retries on timeout before giving up on that chunk
RETRY_BACKOFF = 3        # seconds, grows each retry

def main():
    import time as _time
    # Longer client timeout so a normal (data-heavy) chunk doesn't get cut off.
    client = InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG, timeout=180_000)
    query_api = client.query_api()

    # Accumulate WIDE: {timestamp -> {field: value}}, so the output is one row
    # per 100ms with a column per channel -- a drop-in for the MATLAB scripts,
    # no pivoting needed. A ~90-min window fits comfortably in RAM.
    data = {}
    n_points = 0
    failed_windows = []

    for chunk_start, chunk_stop in time_chunks(START_TIME, STOP_TIME, CHUNK_MINUTES):
        flux = FLUX_TEMPLATE.format(
            bucket=BUCKET, start=chunk_start, stop=chunk_stop,
            field_filter=field_filter, agg=AGG_WINDOW,
        )
        print(f"Querying {chunk_start} -> {chunk_stop} ...")

        tables = None
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                tables = query_api.query(flux, org=INFLUX_ORG)
                break
            except Exception as e:
                if attempt == MAX_RETRIES:
                    print(f"  !! FAILED after {MAX_RETRIES} tries ({type(e).__name__}); skipping this window")
                    failed_windows.append((chunk_start, chunk_stop))
                else:
                    wait = RETRY_BACKOFF * attempt
                    print(f"  .. timeout/err ({type(e).__name__}), retry {attempt}/{MAX_RETRIES-1} in {wait}s")
                    _time.sleep(wait)
        if tables is None:
            continue

        rows_this_chunk = 0
        for table in tables:
            for record in table.records:
                data.setdefault(record.get_time(), {})[record.get_field()] = record.get_value()
                rows_this_chunk += 1
        n_points += rows_this_chunk
        print(f"  -> {rows_this_chunk} points ({len(data)} unique timestamps so far)")

    client.close()

    # ---- write WIDE, MATLAB-ready: t_s + one column per field ----
    if not data:
        print("\nNo data in this window. Check the time range / that the car was logging.")
        return
    times = sorted(data.keys())
    t0 = times[0]
    with open(OUTPUT_CSV, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["t_s"] + FIELDS)              # header = MATLAB variable names
        for dt in times:
            row = [f"{(dt - t0).total_seconds():.3f}"]
            for field in FIELDS:
                row.append(data[dt].get(field, ""))    # missing -> empty -> NaN in MATLAB
            writer.writerow(row)
    print(f"\nDone. {len(times)} rows x {len(FIELDS)} fields (wide, MATLAB-ready) -> {OUTPUT_CSV}")
    print(f"In MATLAB:  W = readtable('{OUTPUT_CSV}');  % t_s starts at 0")

    if failed_windows:
        print(f"\n{len(failed_windows)} window(s) failed after retries (usually transient network):")
        for a, b in failed_windows:
            print(f"   {a} -> {b}")
        print("Re-run the script -- a fresh pass usually clears transient timeouts.")

if __name__ == "__main__":
    main()

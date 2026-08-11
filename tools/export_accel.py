#!/usr/bin/env python3
"""
export_accel.py  --  one-click accel/TC-test export. Grabs ONLY the launch
channels (not everything), uses your already-saved token.

HOW TO USE:
  1. Edit START and STOP below to your test window (Montreal time, 24-hour).
  2. Run it:   python export_accel.py
  3. Then parse:  python parse_accel_test.py today_test.csv   (in Downloads)

Must be on the car's DAQ network (the box is 192.168.100.115).
"""

import export_influx_chunked as ex   # reuse the tested exporter's guts

# ============ EDIT THESE TWO (Montreal time, 24-hour clock) ============
START = "2026-08-09 10:30"    # full day -- empty hours just return nothing
STOP  = "2026-08-09 17:00"
# ======================================================================

OUT = r"C:\Users\Aboud\Downloads\today_test.csv"

# only the channels the accel parser + DT analysis need
FIELDS = [
    "PM100DX_motorSpeed",          # motor rpm
    "PM100DX_torqueFeedback",      # torque delivered
    "VCFRONT_torqueRequest",       # torque asked for (TC cutting?)
    "VCFRONT_acceleratorPosition", # driver pedal
    "VCREAR_wheelSpeedRL",         # driven (rear) wheels -> slip
    "VCREAR_wheelSpeedRR",
    "VCFRONT_wheelSpeedFL",        # front (undriven) = true ground speed
    "VCFRONT_wheelSpeedFR",
    "VCFRONT_vehicleSpeed",        # speed -> accel times
    "VCFRONT_odometer",            # distance -> 0-75 m
    "BMSB_packVoltage",            # launch power / energy
    "BMSB_packCurrent",
    "PM100DX_motorTemp",           # thermal over repeated launches
]

if __name__ == "__main__":
    ex.ensure_deps()
    token = ex.find_saved_token()   # reads tools/influx_token.txt / INFLUX_TOKEN env
    if not token:
        raise SystemExit(
            "No saved token. Put it as one line in tools/influx_token.txt, or run "
            "export_influx_chunked.py once and paste it when asked.")
    ex.run_export(ex.to_utc_z(START), ex.to_utc_z(STOP), FIELDS, OUT, token,
                  echo=(START, STOP))
    print("\nNext:  cd C:\\Users\\Aboud\\Downloads  &&  python parse_accel_test.py today_test.csv")

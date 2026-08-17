"""Tail space_monitor.log and print an alert when a snap-back occurs:
a space change A -> B followed within a few seconds by B -> A.
"""

import datetime
import json
import subprocess
import sys

LOG = "/Users/drmaciver/Projects/windows-debugging/space_monitor.log"
WINDOW = datetime.timedelta(seconds=6)

proc = subprocess.Popen(["tail", "-n", "0", "-F", LOG], stdout=subprocess.PIPE, text=True)

history = []  # (timestamp, space) of space_changed events
for line in proc.stdout:
    try:
        rec = json.loads(line)
    except json.JSONDecodeError:
        continue
    if rec["event"] != "space_changed":
        continue
    ts = datetime.datetime.fromisoformat(rec["ts"])
    space = rec["space"]
    history.append((ts, space))
    history = [h for h in history if ts - h[0] <= WINDOW]
    # snap-back: current space equals a space seen recently, with a different
    # space in between
    spaces = [s for _, s in history]
    if len(spaces) >= 3 and spaces[-1] == spaces[-3] and spaces[-2] != spaces[-1]:
        print(
            f"SNAPBACK at {rec['ts']}: pulled back to space {space} "
            f"(sequence {spaces[-3:]}), frontmost={rec['frontmost']}",
            flush=True,
        )

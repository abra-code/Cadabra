#!/usr/bin/env python3
# Tests/helpers/fake_sandbox_discover.py - stands in for replay's sandbox-discover.py in the
# Record a Pack tests. It takes the same arguments, records them, and writes the JSON events the
# real tool writes to standard error, from a scenario file instead of from running anything.
#
#   FAKE_DISCOVER_SCENARIO  a JSON file: {"events": [event, ...], "exit": status}
#   FAKE_DISCOVER_ARGV      a file this run's arguments are written to, one per line
#   FAKE_DISCOVER_RUNS      optional: a file that gets one line for each run
#
# The command "hang" (as the last argument, after /bin/sh -c) makes it wait to be ended, for the
# Stop test; it writes a first pass event before waiting.

import json
import os
import sys
import time

argv = sys.argv[1:]
with open(os.environ["FAKE_DISCOVER_ARGV"], "w", encoding="utf-8") as fh:
    fh.write("\n".join(argv) + "\n")

if os.environ.get("FAKE_DISCOVER_RUNS"):
    with open(os.environ["FAKE_DISCOVER_RUNS"], "a", encoding="utf-8") as fh:
        fh.write("run\n")

if argv and argv[-1] == "hang":
    sys.stderr.write(json.dumps({"event": "pass", "pass": 1, "exit": 1, "read_only": [], "read_write": []}) + "\n")
    sys.stderr.flush()
    while True:
        time.sleep(1)

with open(os.environ["FAKE_DISCOVER_SCENARIO"], "rb") as fh:
    scenario = json.load(fh)
for event in scenario["events"]:
    sys.stderr.write(json.dumps(event) + "\n")
    sys.stderr.flush()
sys.exit(scenario.get("exit", 0))

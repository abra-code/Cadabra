#!/usr/bin/env python3
"""Refresh Tests/fixtures/agentvm/ from a real agent-vm.

The library tests read agent-vm's answers from these fixtures, through fake_agent_vm.sh. When
agent-vm changes its --json output, run this against the new build and rerun the suite: a field
the library reads that disappeared shows up as a failing drift check in
45-agentvm-library.test.sh or 47-agentvm-boxes.test.sh, instead of as a broken window.

Usage:
    refresh_agentvm_fixtures.py AGENT_VM STOPPED_BOX [RUNNING_BOX]
    refresh_agentvm_fixtures.py --lifecycle AGENT_VM IMAGE
    refresh_agentvm_fixtures.py --import FILE NAME

AGENT_VM is the agent-vm to ask, for example ~/Development/agent-vm/.build/signed/release/agent-vm.

The first form writes version.json, doctor.json, image-list.json, box-list.json, packs.json and
box-status-stopped.json, and execlog.json and netlog.json from STOPPED_BOX's logs (so pick a
box that has run a program and tried the network). RUNNING_BOX, when given, must be running
with a project shared and a program running in it, so the fixture carries every field; it
writes box-status-running.json. For example:
    agent-vm exec --box B --project ~/Development/scratch --read-only -- /bin/sleep 30 &
Nothing here starts or stops a virtual machine. Note that `box list` deletes disposable boxes
that have stopped, as it always does.

--lifecycle creates a disposable box from IMAGE, starts it, stops it and deletes it, writing
box-create.json, box-start.json and the progress events of the start and the stop
(box-start.events, box-stop.events). It STARTS A VIRTUAL MACHINE: macOS runs at most two at
once, so do it when no other work needs a slot.

--import sanitizes a capture made by hand (a JSON document, or JSON lines for a .events file)
and writes it as the fixture NAME. update-guest.events and box-status-unresponsive.json are
made this way (see the README).

Needs the Claude Code sandbox off (agent-vm reads its store and talks to supervisors over their
control sockets). The user's home folder is replaced with /Users/you in every string, so the
fixtures carry no account name. JSON documents are re-serialized with sorted keys and two-space
indentation, event lines with sorted keys, one per line; agent-vm's own output escapes "/" as
"\\/", which JSON readers treat the same.
"""
import json
import os
import subprocess
import sys

FIXTURES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "fixtures", "agentvm")
HOME = os.path.expanduser("~")
LIFECYCLE_BOX = "cadabra-fixture-box"


def sanitize(value):
    if isinstance(value, dict):
        return {key: sanitize(item) for key, item in value.items()}
    if isinstance(value, list):
        return [sanitize(item) for item in value]
    if isinstance(value, str) and HOME and HOME != "/":
        return value.replace(HOME, "/Users/you")
    return value


def write_json(name, data):
    with open(os.path.join(FIXTURES, name), "w", encoding="utf-8") as out:
        json.dump(sanitize(data), out, indent=2, sort_keys=True)
        out.write("\n")
    print(f"wrote {name}")


def write_events(name, text):
    """JSON event lines, sanitized; a line that is not JSON (an error) is kept as it is."""
    lines = []
    for line in text.splitlines():
        try:
            lines.append(json.dumps(sanitize(json.loads(line)), sort_keys=True))
        except ValueError:
            lines.append(line.replace(HOME, "/Users/you") if HOME and HOME != "/" else line)
    with open(os.path.join(FIXTURES, name), "w", encoding="utf-8") as out:
        out.write("\n".join(lines) + "\n")
    print(f"wrote {name}")


def run(agent_vm, args):
    result = subprocess.run([agent_vm] + args + ["--json"], capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(f"{' '.join(args)} failed ({result.returncode}): {result.stderr.strip()}\n")
        return None
    return result


def capture(agent_vm, args, name, check=None):
    result = run(agent_vm, args)
    if result is None:
        return False
    data = json.loads(result.stdout)
    problem = check(data) if check else None
    if problem:
        sys.stderr.write(f"{name} not written: {problem}\n")
        return False
    write_json(name, data)
    return True


def stopped(data):
    return None if data.get("state") == "stopped" else f"the box is {data.get('state')}, not stopped"


def running_with_exec(data):
    if data.get("state") != "running":
        return f"the box is {data.get('state')}, not running"
    if not data.get("project") or not data.get("activeExecs"):
        return "no project is shared or no program runs in the box (see the usage)"
    return None


def not_empty(data):
    return None if data else "the log is empty (see the usage)"


def queries(agent_vm, stopped_box, running_box):
    os.makedirs(FIXTURES, exist_ok=True)
    ok = capture(agent_vm, ["version"], "version.json")
    ok = capture(agent_vm, ["doctor"], "doctor.json") and ok
    ok = capture(agent_vm, ["image", "list"], "image-list.json") and ok
    ok = capture(agent_vm, ["box", "list"], "box-list.json") and ok
    ok = capture(agent_vm, ["box", "packs"], "packs.json") and ok
    ok = capture(agent_vm, ["box", "status", stopped_box], "box-status-stopped.json", stopped) and ok
    ok = capture(agent_vm, ["box", "execlog", stopped_box, "--last", "5"], "execlog.json",
                 not_empty) and ok
    ok = capture(agent_vm, ["box", "netlog", stopped_box, "--last", "5"], "netlog.json",
                 not_empty) and ok
    if running_box:
        ok = capture(agent_vm, ["box", "status", running_box], "box-status-running.json",
                     running_with_exec) and ok
    return ok


def lifecycle(agent_vm, image):
    os.makedirs(FIXTURES, exist_ok=True)
    created = run(agent_vm, ["box", "create", LIFECYCLE_BOX, "--image", image, "--memory-gb", "4",
                             "--allow", "pack:npm", "--allow", "example.com", "--disposable"])
    if created is None:
        return False
    write_json("box-create.json", json.loads(created.stdout))
    ok = True
    started = run(agent_vm, ["box", "start", LIFECYCLE_BOX])
    if started is not None:
        write_json("box-start.json", json.loads(started.stdout))
        write_events("box-start.events", started.stderr)
        stopped_run = run(agent_vm, ["box", "stop", LIFECYCLE_BOX])
        if stopped_run is not None:
            write_events("box-stop.events", stopped_run.stderr)
        else:
            ok = False
    else:
        ok = False
    if run(agent_vm, ["box", "delete", LIFECYCLE_BOX]) is None:
        sys.stderr.write(f"delete the box {LIFECYCLE_BOX} by hand once it has stopped\n")
        ok = False
    return ok


def import_capture(path, name):
    os.makedirs(FIXTURES, exist_ok=True)
    with open(path, encoding="utf-8") as source:
        text = source.read()
    if name.endswith(".events"):
        write_events(name, text)
    else:
        write_json(name, json.loads(text))
    return True


def main(argv):
    if len(argv) == 4 and argv[1] == "--lifecycle":
        return 0 if lifecycle(argv[2], argv[3]) else 1
    if len(argv) == 4 and argv[1] == "--import":
        return 0 if import_capture(argv[2], argv[3]) else 1
    if len(argv) in (3, 4) and not argv[1].startswith("--"):
        return 0 if queries(argv[1], argv[2], argv[3] if len(argv) == 4 else None) else 1
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

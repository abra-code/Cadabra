#!/usr/bin/env python3
"""Refresh Tests/fixtures/agentvm/ from a real agent-vm.

The library tests read agent-vm's answers from these fixtures, through fake_agent_vm.sh. When
agent-vm changes its --json output, run this against the new build and rerun the suite: a field
the library reads that disappeared shows up as a failing drift check in
45-agentvm-library.test.sh, instead of as a broken window.

Usage:
    refresh_agentvm_fixtures.py AGENT_VM STOPPED_BOX [RUNNING_BOX]

AGENT_VM is the agent-vm to ask, for example ~/Development/agent-vm/.build/signed/release/agent-vm.
STOPPED_BOX is any stopped box. RUNNING_BOX, when given, must be running with a project shared
and a program running in it, so the fixture carries every field; for example:
    agent-vm exec --box B --project ~/Development/scratch --read-only -- /bin/sleep 30 &

Needs the Claude Code sandbox off (agent-vm reads its store and talks to supervisors over their
control sockets). Writes version.json, doctor.json, box-status-stopped.json and, with a running
box, box-status-ready.json. box-status-unresponsive.json is made by hand (see the README), since
a wedged supervisor cannot be produced on request.

The user's home folder is replaced with /Users/you in every string, so the fixtures carry no
account name. Output is re-serialized with sorted keys and two-space indentation; agent-vm's own
output escapes "/" as "\\/", which JSON readers treat the same.
"""
import json
import os
import subprocess
import sys

FIXTURES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "fixtures", "agentvm")
HOME = os.path.expanduser("~")


def sanitize(value):
    if isinstance(value, dict):
        return {key: sanitize(item) for key, item in value.items()}
    if isinstance(value, list):
        return [sanitize(item) for item in value]
    if isinstance(value, str) and HOME and HOME != "/":
        return value.replace(HOME, "/Users/you")
    return value


def capture(agent_vm, args, name, check=None):
    result = subprocess.run([agent_vm] + args + ["--json"], capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(f"{' '.join(args)} failed ({result.returncode}): {result.stderr.strip()}\n")
        return False
    data = sanitize(json.loads(result.stdout))
    problem = check(data) if check else None
    if problem:
        sys.stderr.write(f"{name} not written: {problem}\n")
        return False
    with open(os.path.join(FIXTURES, name), "w", encoding="utf-8") as out:
        json.dump(data, out, indent=2, sort_keys=True)
        out.write("\n")
    print(f"wrote {name}")
    return True


def stopped(data):
    return None if data.get("state") == "stopped" else f"the box is {data.get('state')}, not stopped"


def ready_with_exec(data):
    if data.get("state") != "ready":
        return f"the box is {data.get('state')}, not ready"
    if not data.get("project") or not data.get("activeExecs"):
        return "no project is shared or no program runs in the box (see the usage)"
    return None


def main(argv):
    if len(argv) not in (3, 4):
        sys.stderr.write(__doc__)
        return 2
    agent_vm = argv[1]
    os.makedirs(FIXTURES, exist_ok=True)
    ok = capture(agent_vm, ["version"], "version.json")
    ok = capture(agent_vm, ["doctor"], "doctor.json") and ok
    ok = capture(agent_vm, ["box", "status", argv[2]], "box-status-stopped.json", stopped) and ok
    if len(argv) == 4:
        ok = capture(agent_vm, ["box", "status", argv[3]], "box-status-ready.json",
                     ready_with_exec) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

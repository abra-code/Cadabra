#!/usr/bin/env python3
"""Turn agent-vm's --json output into tab-separated rows for the shell library.

aichat.agentvm.library.sh runs agent-vm and pipes its JSON here; nothing else in Cadabra reads
agent-vm's output. agent-vm's human text is for people and changes freely, while its --json
output is a contract (agent-vm's Private/cadabra-integration-work-items.md), so the shell never
parses the text and this file never guesses at it.

THE SAME INVARIANT AS acp_catalog.py: every emitted field is non-empty and contains no tab,
carriage return or newline. Tab is IFS whitespace, so an empty field would collapse into its
neighbor under `IFS=<tab> read` and shift every later field left. Absent values are "-";
control characters inside a value become "?" (a path that holds one is shown mangled rather
than splitting a row). Booleans are "true" or "false"; lists are comma-joined.

Usage (the JSON on stdin):
    agentvm_json.py version   <- agent-vm version --json
    agentvm_json.py status    <- agent-vm box status <box> --json
    agentvm_json.py doctor    <- agent-vm doctor --json

"version" emits one row:
    version, path, guestVersion, guestFeatures, guestDigest, guestError
"status" emits one row:
    state, pid, supervisorVersion, supervisorPath, startedAt, project, projectReadOnly,
    activeExecs, guestVersion, guestFeatures, image, statusError
"doctor" emits one row per check:
    name, status, detail

Input that is not JSON, or JSON of the wrong shape, is reported on stderr and exits 1 with
nothing on stdout, so a caller never reads a plausible-looking partial row.
"""
import json
import sys

ABSENT = "-"


def field(value):
    """One TSV field: never empty, never a tab or line break."""
    if value is None:
        return ABSENT
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(int(value)) if float(value).is_integer() else str(value)
    if isinstance(value, list):
        text = ",".join(str(item) for item in value)
    else:
        text = str(value)
    text = "".join("?" if ch in "\t\r\n" or ord(ch) < 32 else ch for ch in text)
    return text if text else ABSENT


def row(values):
    return "\t".join(field(v) for v in values)


def need_object(data, what):
    if not isinstance(data, dict):
        raise ValueError(f"expected a JSON object from {what}")
    return data


def version_rows(data):
    data = need_object(data, "agent-vm version --json")
    daemon = data.get("guestDaemon")
    daemon = daemon if isinstance(daemon, dict) else {}
    yield row([data.get("version"), data.get("path"),
               daemon.get("version"), daemon.get("features"), daemon.get("digest"),
               daemon.get("error")])


def status_rows(data):
    data = need_object(data, "agent-vm box status --json")
    record = data.get("box")
    record = record if isinstance(record, dict) else {}
    yield row([data.get("state"), data.get("pid"),
               data.get("supervisorVersion"), data.get("supervisorPath"), data.get("startedAt"),
               data.get("project"), data.get("projectReadOnly"), data.get("activeExecs"),
               data.get("guestVersion"), data.get("guestFeatures"),
               record.get("image"), data.get("statusError")])


def doctor_rows(data):
    data = need_object(data, "agent-vm doctor --json")
    checks = data.get("checks")
    if not isinstance(checks, list):
        raise ValueError("agent-vm doctor --json has no checks list")
    for check in checks:
        if isinstance(check, dict):
            yield row([check.get("name"), check.get("status"), check.get("detail")])


COMMANDS = {"version": version_rows, "status": status_rows, "doctor": doctor_rows}


def main(argv):
    if len(argv) != 2 or argv[1] not in COMMANDS:
        sys.stderr.write("usage: agentvm_json.py version|status|doctor < agent-vm-output.json\n")
        return 2
    try:
        data = json.load(sys.stdin)
        lines = list(COMMANDS[argv[1]](data))
    except (ValueError, UnicodeDecodeError) as error:
        sys.stderr.write(f"agentvm_json.py {argv[1]}: {error}\n")
        return 1
    for line in lines:
        sys.stdout.write(line + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

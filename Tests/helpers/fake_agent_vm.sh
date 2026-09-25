#!/bin/sh
# Tests/helpers/fake_agent_vm.sh - agent-vm, answered from files.
#
# aichat.agentvm.library.sh runs agent-vm through agentvm_bin, and CADABRA_AGENT_VM points that
# here. The real agent-vm needs macOS 27, a store of multi-GB images and virtual machines, and
# answers differently on every Mac; this answers the same way every time, from JSON captured from
# a real agent-vm (Tests/fixtures/agentvm/, see the README there), and it can fail on request.
#
# -- The state directory ($FAKE_AGENTVM_DIR) -------------------------------------
#   log        APPENDED to, one line per invocation: the arguments, space-joined.
#   home       REWRITTEN each invocation: AGENT_VM_HOME as the fake saw it, or "(unset)".
#   exit       when present, every invocation prints the file "stderr" (if any) to stderr and
#              exits with this status, before looking at its arguments.
#   version    what --version prints (default 0.1.8).
#   <key>.json the answer to one query, overriding the fixture:
#              version.json  <- version --json
#              doctor.json   <- doctor --json
#              box-<name>.json <- box status <name> --json; with no such file the box does not
#              exist, and the fake answers the way agent-vm does for a missing box.
#
# -- What it implements ---------------------------------------------------------
#   --version,  version --json,  doctor --json,  box status <name> --json
# Anything else fails with status 64, so a test that reaches an unimplemented command finds out.

state="${FAKE_AGENTVM_DIR:?fake_agent_vm: FAKE_AGENTVM_DIR is not set}"
fixtures="${FAKE_AGENTVM_FIXTURES:-$(/usr/bin/dirname "$0")/../fixtures/agentvm}"
[ -d "$state" ] || /bin/mkdir -p "$state"

printf '%s\n' "$*" >> "$state/log"
if [ -n "${AGENT_VM_HOME+set}" ]; then
    printf '%s\n' "$AGENT_VM_HOME" > "$state/home"
else
    printf '(unset)\n' > "$state/home"
fi

if [ -f "$state/exit" ]; then
    [ -f "$state/stderr" ] && /bin/cat "$state/stderr" >&2
    exit "$(/bin/cat "$state/exit")"
fi

# answer <key> - the state directory's <key>.json, else the fixture of that name.
answer() {
    if [ -f "$state/$1.json" ]; then
        /bin/cat "$state/$1.json"
    else
        /bin/cat "$fixtures/$1.json"
    fi
}

case "$*" in
    "--version")
        if [ -f "$state/version" ]; then
            /bin/cat "$state/version"
        else
            printf '0.1.8\n'
        fi ;;
    "version --json")
        answer version ;;
    "doctor --json")
        answer doctor ;;
    "box status "*" --json")
        box="$3"
        if [ ! -f "$state/box-$box.json" ]; then
            printf 'Error: no box %s; `agent-vm box list` shows the existing ones\n' "$box" >&2
            exit 1
        fi
        /bin/cat "$state/box-$box.json" ;;
    *)
        printf 'Error: fake_agent_vm does not implement: %s\n' "$*" >&2
        exit 64 ;;
esac

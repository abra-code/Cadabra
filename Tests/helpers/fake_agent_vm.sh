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
#   fail-<a>-<b>  when present, the command "<a> <b>" (fail-box-delete, fail-image-setup)
#              prints "Error: " and the file's text to stderr and exits 1.
#   version    what --version prints (default 0.2.1).
#   delay      seconds between the progress events of a long command (default 0).
#   <key>.json the answer to one query, overriding the fixture of that name:
#              version, doctor, image-list, box-list, packs, execlog, netlog, box-create,
#              secret-list, image-info, box-info.
#   exec-error when present, `exec` prints "Error: " and the file's text and exits 1 (agent-vm's
#              refusal of a share, say); otherwise exec runs nothing and exits 0.
#   box-<name>.json  <- box status <name> --json. With no such file the box does not exist, and
#              the commands that name a box answer the way agent-vm does for a missing box.
#
# -- What it implements ---------------------------------------------------------
#   --version, version --json, doctor --json, image list --json, box list --json,
#   box packs --json, box status|execlog|netlog <name> ... --json,
#   box create <name> --image <image> ... --json (creates box-<name>.json),
#   box delete <name> --json (removes it), image delete <name> --json, box view <name> ... --json,
#   image info <name> --json and box info <name> --json (the box must exist),
#   box shell <name>, secret list --json, exec --box <name> ... -- <argv> (runs nothing),
#   and the long ones, which print progress events on stderr like agent-vm
#   and exit 130 (SIGINT) or 143 (SIGTERM) when stopped:
#   box start <name> [--owner-pid N] --json, box stop <name> --json,
#   image update-guest <name> --json, image setup <name> --json, image create <name> ... --json.
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
if [ -f "$state/fail-$1-$2" ]; then
    printf 'Error: %s\n' "$(/bin/cat "$state/fail-$1-$2")" >&2
    exit 1
fi

# answer <key> - the state directory's <key>.json, else the fixture of that name.
answer() {
    if [ -f "$state/$1.json" ]; then
        /bin/cat "$state/$1.json"
    else
        /bin/cat "$fixtures/$1.json"
    fi
}

# need_box <name> - agent-vm's answer for a box that does not exist.
need_box() {
    [ -f "$state/box-$1.json" ] && return 0
    printf 'Error: no box %s; `agent-vm box list` shows the existing ones\n' "$1" >&2
    exit 1
}

# progress <events file> <name> - the events on stderr, "delay" seconds apart, stoppable.
# The sleep runs in the background and is waited for, so a signal is handled at once rather
# than after the sleep.
progress() {
    trap 'printf "Error: %s was canceled\n" "$2" >&2; exit 130' INT
    trap 'printf "Error: %s was canceled\n" "$2" >&2; exit 143' TERM
    delay=0
    [ -f "$state/delay" ] && delay="$(/bin/cat "$state/delay")"
    while IFS= read -r line; do
        printf '%s\n' "$line" >&2
        if [ "$delay" != "0" ]; then
            /bin/sleep "$delay" &
            wait $!
        fi
    done < "$1"
}

case "$1 $2" in
    "--version ")
        if [ -f "$state/version" ]; then
            /bin/cat "$state/version"
        else
            printf '0.2.1\n'
        fi ;;
    "version --json")
        answer version ;;
    "doctor --json")
        answer doctor ;;
    "image list")
        answer image-list ;;
    "box list")
        answer box-list ;;
    "box packs")
        answer packs ;;
    "secret list")
        answer secret-list ;;
    "image info")
        answer image-info ;;
    "box info")
        need_box "$3"
        answer box-info ;;
    "exec --box")
        need_box "$3"
        if [ -f "$state/exec-error" ]; then
            printf 'Error: %s\n' "$(/bin/cat "$state/exec-error")" >&2
            exit 1
        fi ;;
    "box status")
        need_box "$3"
        /bin/cat "$state/box-$3.json" ;;
    "box execlog")
        need_box "$3"
        answer execlog ;;
    "box netlog")
        need_box "$3"
        answer netlog ;;
    "box create")
        if [ -f "$state/box-$3.json" ]; then
            printf 'Error: a box named %s already exists\n' "$3" >&2
            exit 1
        fi
        /bin/cp "$fixtures/box-status-stopped.json" "$state/box-$3.json"
        answer box-create ;;
    "box delete")
        need_box "$3"
        /bin/rm -f "$state/box-$3.json" ;;
    "image delete")
        ;;
    "box view")
        need_box "$3" ;;
    "box shell")
        need_box "$3"
        printf 'fake shell in %s\n' "$3" ;;
    "box start")
        need_box "$3"
        progress "$fixtures/box-start.events" "starting $3"
        answer box-start ;;
    "box stop")
        need_box "$3"
        progress "$fixtures/box-stop.events" "stopping $3" ;;
    "image update-guest")
        progress "$fixtures/update-guest.events" "the guest update of $3" ;;
    "image setup")
        progress "$fixtures/update-guest.events" "the setup of $3" ;;
    "image create")
        progress "$fixtures/image-create.events" "the build of $3" ;;
    *)
        printf 'Error: fake_agent_vm does not implement: %s\n' "$*" >&2
        exit 64 ;;
esac

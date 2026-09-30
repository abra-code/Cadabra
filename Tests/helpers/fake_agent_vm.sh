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
#              prints "Error: " and the file's text to stderr and exits 1, or with the status in
#              fail-<a>-<b>-status when that is present (75 for agent-vm's "no free VM slot").
#   version    what --version prints (default: AGENTVM_MIN_VERSION from the library, the oldest
#              version Cadabra accepts, so raising it needs no change here), and then also the
#              version in version --json's answer, unless version.json overrides that.
#   delay      seconds between the progress events of a long command (default 0).
#   <key>.json the answer to one query, overriding the fixture of that name:
#              version, doctor, image-list, box-list, packs, execlog, netlog, box-create,
#              secret-list, image-info, box-info.
#   exec-error when present, `exec` prints "Error: " and the file's text and exits 1 (agent-vm's
#              refusal of a share, say); otherwise exec runs nothing and exits 0, unless:
#   exec-run   when present, `exec` runs the program after "--" on this Mac, as the box would:
#              standard input and output pass through, each --env NAME=VALUE is set for it, and
#              its status is exec's. The box user's home is then the test's $HOME, so Cadabra's
#              tools copy lands in the scratch home and the MCP servers run from there.
#   box-<name>.json  <- box status <name> --json. With no such file the box does not exist, and
#              the commands that name a box answer the way agent-vm does for a missing box.
#   secrets    the Keychain, once `secret set` or `secret delete` has run: one "<name><TAB>
#              <readable>" line per secret, which `secret list --json` then answers from (before
#              that, from secret-list.json). `secret set` stores as readable.
#   secret-<name>  the value `secret set <name>` read from stdin, as it arrived.
#
# -- What it implements ---------------------------------------------------------
#   --version, version --json, doctor --json, image list --json, box list --json,
#   box packs --json, box status|execlog|netlog <name> ... --json,
#   box create <name> --image <image> ... --json (creates box-<name>.json),
#   box delete <name> --json (removes it), box recreate <name> --json (a stopped record again),
#   image delete <name> --json, box view <name> ... --json,
#   image info <name> --json and box info <name> --json (the box must exist),
#   box shell <name>, box network <name> ... --json (changes nothing), secret list --json, secret set <name> (value on stdin),
#   secret delete <name>, exec --box <name> ... -- <argv> (runs nothing),
#   and the long ones, which print progress events on stderr like agent-vm
#   and exit 130 (SIGINT) or 143 (SIGTERM) when stopped:
#   box start <name> [--owner-pid N] --json, box stop <name> --json,
#   image update-guest <name> --json, image setup <name> --json, image create <name> ... --json.
# Anything else fails with status 64, so a test that reaches an unimplemented command finds out.

state="${FAKE_AGENTVM_DIR:?fake_agent_vm: FAKE_AGENTVM_DIR is not set}"
fixtures="${FAKE_AGENTVM_FIXTURES:-$(/usr/bin/dirname "$0")/../fixtures/agentvm}"
agentvm_library="${OMC_APP_BUNDLE_PATH:-$(/usr/bin/dirname "$0")/../../Cadabra.app}/Contents/Resources/Scripts/aichat.agentvm.library.sh"
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
    if [ -f "$state/fail-$1-$2-status" ]; then
        exit "$(/bin/cat "$state/fail-$1-$2-status")"
    fi
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

# secrets_tsv  ->  the fake Keychain, one "<name><TAB><true|false>" line per secret.
secrets_tsv() {
    if [ -f "$state/secrets" ]; then
        /bin/cat "$state/secrets"
        return 0
    fi
    answer secret-list | /usr/bin/awk -F'"' '/"name"/ { name = $4 } /"readable"/ { print name "\t" ($0 ~ /true/ ? "true" : "false") }'
}

# secrets_json  ->  the fake Keychain as `secret list --json` prints it.
secrets_json() {
    secrets_tsv | /usr/bin/awk -F'\t' 'BEGIN { printf "[" } { printf "%s\n  {\n    \"name\" : \"%s\",\n    \"readable\" : %s\n  }", (NR > 1 ? "," : ""), $1, $2 } END { print "\n]" }'
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
            /usr/bin/sed -n 's/^AGENTVM_MIN_VERSION="\(.*\)"$/\1/p' "$agentvm_library"
        fi ;;
    "version --json")
        # The same version --version prints, when the "version" file sets it, as agent-vm would.
        if [ -f "$state/version" ] && [ ! -f "$state/version.json" ]; then
            /usr/bin/jq --arg v "$(/bin/cat "$state/version")" '.version = $v' "$fixtures/version.json"
        else
            answer version
        fi ;;
    "doctor --json")
        answer doctor ;;
    "image list")
        answer image-list ;;
    "box list")
        answer box-list ;;
    "box packs")
        answer packs ;;
    "secret list")
        secrets_json ;;
    "secret set")
        /bin/cat > "$state/secret-$3"
        secrets_tsv | /usr/bin/awk -F'\t' -v name="$3" '$1 != name' > "$state/secrets.new"
        printf '%s\ttrue\n' "$3" >> "$state/secrets.new"
        /bin/mv -f "$state/secrets.new" "$state/secrets"
        printf 'Stored secret %s in the Keychain\n' "$3" ;;
    "secret delete")
        found="$(secrets_tsv | /usr/bin/awk -F'\t' -v name="$3" '$1 == name { print "yes" }')"
        if [ -z "$found" ]; then
            printf 'Error: no secret named %s in the Keychain\n' "$3" >&2
            exit 1
        fi
        secrets_tsv | /usr/bin/awk -F'\t' -v name="$3" '$1 != name' > "$state/secrets.new"
        /bin/mv -f "$state/secrets.new" "$state/secrets"
        /bin/rm -f "$state/secret-$3"
        printf 'Deleted secret %s\n' "$3" ;;
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
        fi
        if [ -f "$state/exec-run" ]; then
            shift 3
            while [ $# -gt 0 ] && [ "$1" != "--" ]; do
                if [ "$1" = "--env" ] && [ $# -gt 1 ]; then
                    export "$2"
                    shift
                fi
                shift
            done
            if [ $# -eq 0 ]; then
                printf 'Error: fake_agent_vm: exec without "--"\n' >&2
                exit 64
            fi
            shift
            exec "$@"
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
    "box recreate")
        need_box "$3"
        /bin/cp "$fixtures/box-status-stopped.json" "$state/box-$3.json"
        answer box-create ;;
    "image delete")
        ;;
    "box view")
        need_box "$3" ;;
    "box network")
        need_box "$3"
        printf '{"allow": [], "mode": "allowlist"}\n' ;;
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

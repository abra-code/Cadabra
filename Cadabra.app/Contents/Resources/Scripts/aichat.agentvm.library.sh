#!/bin/sh
# aichat.agentvm.library.sh
#
# The only file in Cadabra that runs agent-vm, the tool that makes and runs macOS virtual
# machines ("boxes") for agents and their tools. Everything that needs an image, a box or a
# running program in one goes through the functions here, so there is one place that knows
# which agent-vm binary is in use, how to read its answers, and how its failures reach the user.
#
# WHICH agent-vm. Three candidates, the first one set wins:
#   - CADABRA_AGENT_VM in the environment: the test seam, pointed at Tests/helpers/fake_agent_vm.sh
#     (the CADABRA_CURL pattern of aichat.library.sh);
#   - /developer/agent-vm in the settings file: a developer override, typically
#     ~/Development/agent-vm/.build/signed/release/agent-vm, so Cadabra can follow an agent-vm
#     working tree while the two change together;
#   - the installed ~/.local/bin/agent-vm. Cadabra carries no agent-vm of its own: AgentVM's
#     package installs it for the user, with agent-vm-guest, the network packs and the image
#     recipes in a folder of their own (~/.local/share/agent-vm/versions/<version>/), and the
#     link in ~/.local/bin points at the newest. Terminal (agent-vm, avm) and every other app
#     run the same one. Cadabra runs it through the link, so a program it started shows the
#     link's path in ps (the orphan sweep in aichat.server.library.sh relies on that), and a
#     version installed while a box runs takes over at the next start.
# /developer/agent-vm-home, when set, becomes AGENT_VM_HOME for every run: agent-vm's store root,
# which a project on another volume needs, and which a Finder-launched app cannot inherit from a
# shell. It applies to whichever binary runs, so switching binaries never switches stores.
#
# READING ITS ANSWERS. Only --json output is read, through agentvm_json.py, which turns it into
# tab-separated rows with no empty fields. agent-vm's human text changes freely; its JSON is a
# contract with this library. A failed call leaves agent-vm's own message (written for people,
# naming the fix) for agentvm_last_error, and alerts show it as it is.
#
# GATES. agent-vm is built for macOS 27 and would not even load on an older system, so
# agentvm_available checks the macOS version before anything runs the binary, then that the
# binary exists and is at least AGENTVM_MIN_VERSION.
[ -n "${__AICHAT_AGENTVM_LIB:-}" ] && return 0
__AICHAT_AGENTVM_LIB=1

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"

# Always the newest agent-vm version Cadabra is tested with: there is one development stream,
# so an older agent-vm (an installation from before a Cadabra update, or the developer override
# pointing at a stale build) is refused rather than guessed at.
# Raise it with every agent-vm version Cadabra moves to. The tests and the fake agent-vm read it
# from here, so the number lives only on this line.
AGENTVM_MIN_VERSION="0.4.3"
AGENTVM_MIN_MACOS="27"

# Where AgentVM's package puts the link to the newest agent-vm, and where to get the package.
agentvm_installed="$HOME/.local/bin/agent-vm"
agentvm_releases_page="https://github.com/abra-code/agent-vm/releases"
agentvm_python="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
agentvm_json_py="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/agentvm_json.py"
agentvm_job_py="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/agentvm_job.py"

# Where agentvm_json leaves agent-vm's stderr for agentvm_last_error. Named after the handler's
# pid: $$ is the handler's own pid inside every subshell of it too, so a call made in $( ) - the
# usual way to call it - still leaves the message where the caller can find it afterwards.
agentvm_err_file="${TMPDIR:-/tmp}/cadabra-agentvm.$$.stderr"

# agentvm_setting <name>  ->  /developer/<name> from the settings file, or nothing.
# Reads only: a missing file stays missing.
agentvm_setting() {
    [ -f "$cadabra_settings" ] || return 0
    "$plister" get string "$cadabra_settings" "/developer/$1" 2>/dev/null
}

# agentvm_origin  ->  test, developer or installed: where agentvm_bin's answer comes from.
# The Box Manager names it next to the version, so a forgotten override is visible.
agentvm_origin() {
    if [ -n "${CADABRA_AGENT_VM:-}" ]; then
        echo "test"
        return 0
    fi
    local _override="$(agentvm_setting agent-vm)"
    if [ -n "$_override" ]; then
        echo "developer"
        return 0
    fi
    echo "installed"
}

# agentvm_bin  ->  the agent-vm this library runs (see the header for the order).
agentvm_bin() {
    if [ -n "${CADABRA_AGENT_VM:-}" ]; then
        printf '%s\n' "$CADABRA_AGENT_VM"
        return 0
    fi
    local _override="$(agentvm_setting agent-vm)"
    if [ -n "$_override" ]; then
        printf '%s\n' "$_override"
        return 0
    fi
    printf '%s\n' "$agentvm_installed"
}

# agentvm_real_dir  ->  the folder agentvm_bin's links end in: the installed version's own
# folder, where agent-vm-guest, the packs and the recipes sit beside agent-vm. Nothing when
# the binary is not there.
agentvm_real_dir() {
    local _real
    _real="$(/usr/bin/readlink -f "$(agentvm_bin)" 2>/dev/null)"
    local _status=$?
    # A broken link prints the part it could resolve, with status 1.
    if [ "$_status" -ne 0 ] || [ -z "$_real" ]; then
        return 0
    fi
    /usr/bin/dirname "$_real"
}

# agentvm_run <args...>  ->  agent-vm's output and status, run with Cadabra's store setting.
agentvm_run() {
    local _bin="$(agentvm_bin)"
    local _home="$(agentvm_setting agent-vm-home)"
    if [ -n "$_home" ]; then
        AGENT_VM_HOME="$_home" "$_bin" "$@"
        return $?
    fi
    "$_bin" "$@"
}

# agentvm_json <args...>  ->  agent-vm's JSON on stdout, and agent-vm's status.
# --json goes last, after the caller's arguments; callers pass names that agentvm_valid_name
# accepted, so nothing after them can be read as an option or a program's argv.
# stderr is kept apart for agentvm_last_error and removed when the call succeeds.
agentvm_json() {
    /bin/rm -f "$agentvm_err_file"
    agentvm_run "$@" --json 2>"$agentvm_err_file"
    local _status=$?
    if [ "$_status" -eq 0 ]; then
        /bin/rm -f "$agentvm_err_file"
    fi
    return "$_status"
}

# agentvm_last_error [status]  ->  the message of the last failed call, for an alert.
# agent-vm writes "Error: <what failed and the fix>" to stderr, sometimes followed by more lines
# (a guest program's output, say). The message is everything from that line on, less the
# "Error: " prefix. Without such a line - a crash, a converter failure - it is every line that is
# not a progress event (a JSON line, from long commands). The message is forgotten once read.
agentvm_last_error() {
    local _message
    _message="$(/usr/bin/awk '
        found           { print; next }
        /^Error: /      { found = 1; sub(/^Error: /, ""); print; next }
        !/^\{/          { other = other $0 "\n" }
        END             { if (!found) printf "%s", other }' "$agentvm_err_file" 2>/dev/null)"
    /bin/rm -f "$agentvm_err_file"
    if [ -z "$_message" ]; then
        _message="agent-vm failed (status ${1:-unknown}) and gave no reason."
    fi
    printf '%s\n' "$_message"
}

# agentvm_rows <agentvm_json.py command> <agent-vm args...>  ->  TSV rows from agent-vm's JSON.
# A failure of either agent-vm or the conversion leaves its message for agentvm_last_error.
agentvm_rows() {
    local _command="$1"
    shift
    local _json
    _json="$(agentvm_json "$@")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        return "$_status"
    fi
    printf '%s\n' "$_json" | "$agentvm_python" "$agentvm_json_py" "$_command" 2>"$agentvm_err_file"
    _status=$?
    if [ "$_status" -eq 0 ]; then
        /bin/rm -f "$agentvm_err_file"
    fi
    return "$_status"
}

# agentvm_valid_name <name>  ->  0 when agent-vm accepts it as an image or box name.
# agent-vm's own rule (ImageStore.isValidName): lower-case letters, digits, ".", "_" and "-",
# starting with a letter or digit, at most 63 characters. Checked here as well because a name
# is an argv element: one that starts with "-" would be read as an option.
# The letters are spelled out, here and in the digit checks below, because a bracket RANGE
# follows the locale's collation order: in en_US.UTF-8, [a-z] also matches "B" through "Z".
agentvm_valid_name() {
    case "$1" in
        [abcdefghijklmnopqrstuvwxyz0123456789]*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *[!abcdefghijklmnopqrstuvwxyz0123456789._-]*) return 1 ;;
    esac
    [ "${#1}" -le 63 ]
}

# agentvm_valid_secret_name <name>  ->  0 when agent-vm accepts it as a secret name (SecretStore.isValidName):
# letters, digits and "_", not starting with a digit. The same rule as acp_agent_valid_secret_name,
# which the settings side checks without this library.
agentvm_valid_secret_name() {
    case "$1" in
        ''|[0123456789]*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]*) return 1 ;;
    esac
    return 0
}

# agentvm_version_at_least <have> <want>  ->  0 when have >= want, compared as dotted numbers.
# Anything that is not digits and dots is not at least anything.
agentvm_version_at_least() {
    case "$1" in ''|*[!0123456789.]*|.*|*.|*..*) return 1 ;; esac
    case "$2" in ''|*[!0123456789.]*|.*|*.|*..*) return 1 ;; esac
    local _have="$1." _want="$2."
    local _h _w
    while [ -n "$_have" ] || [ -n "$_want" ]; do
        _h="${_have%%.*}"
        _w="${_want%%.*}"
        _have="${_have#*.}"
        _want="${_want#*.}"
        [ -n "$_h" ] || _h=0
        [ -n "$_w" ] || _w=0
        if [ "$_h" -gt "$_w" ]; then
            return 0
        fi
        if [ "$_h" -lt "$_w" ]; then
            return 1
        fi
    done
    return 0
}

# agentvm_macos_reason <macOS version>  ->  why boxes are unavailable on it, or nothing.
agentvm_macos_reason() {
    local _major="${1%%.*}"
    case "$_major" in
        ''|*[!0123456789]*)
            printf 'Boxes need macOS %s or later, and this Mac did not report its macOS version.\n' "$AGENTVM_MIN_MACOS"
            return 0 ;;
    esac
    if [ "$_major" -lt "$AGENTVM_MIN_MACOS" ]; then
        printf 'Boxes need macOS %s or later. This Mac runs macOS %s.\n' "$AGENTVM_MIN_MACOS" "$1"
    fi
}

# agentvm_bin_reason <path> <origin>  ->  why that agent-vm cannot be run, or nothing.
# -f as well as -x, because -x is also true of a directory.
agentvm_bin_reason() {
    case "$2" in
        developer)
            case "$1" in
                /*) ;;
                *)  printf 'The developer setting /developer/agent-vm is "%s", which is not an absolute path. Fix it, or clear it to use the installed agent-vm.\n' "$1"
                    return 0 ;;
            esac
            if [ ! -f "$1" ] || [ ! -x "$1" ]; then
                printf 'The developer setting /developer/agent-vm points at %s, which is not an executable file. Build agent-vm there, or clear the setting to use the installed agent-vm.\n' "$1"
            fi ;;
        test)
            if [ ! -f "$1" ] || [ ! -x "$1" ]; then
                printf 'CADABRA_AGENT_VM is %s, which is not an executable file.\n' "$1"
            fi ;;
        *)
            if [ ! -f "$1" ] || [ ! -x "$1" ]; then
                printf 'AgentVM is not installed: there is no agent-vm at %s. Install AgentVM from %s.\n' "$1" "$agentvm_releases_page"
            fi ;;
    esac
}

# agentvm_version_reason <path> <origin> <output of --version> <its status>
#   ->  why that agent-vm is unusable, or nothing.
agentvm_version_reason() {
    # One line: the reason goes into an alert, and a crashing binary can print several.
    local _output="$(printf '%s' "$3" | /usr/bin/tr '\n' ' ')"
    local _fix="Install the newest AgentVM from $agentvm_releases_page."
    if [ "$2" = "developer" ]; then
        _fix="Rebuild it, or clear the developer setting /developer/agent-vm to use the installed agent-vm."
    fi
    if [ "$4" != "0" ]; then
        printf '%s did not report its version (status %s: %s). %s\n' "$1" "$4" "${_output:-no output}" "$_fix"
        return 0
    fi
    case "$3" in
        ''|*[!0123456789.]*)
            printf '%s did not report a version: "%s". %s\n' "$1" "$_output" "$_fix"
            return 0 ;;
    esac
    agentvm_version_at_least "$3" "$AGENTVM_MIN_VERSION"
    local _new_enough=$?
    if [ "$_new_enough" -ne 0 ]; then
        printf 'Cadabra needs agent-vm %s or later, and %s is %s. %s\n' "$AGENTVM_MIN_VERSION" "$1" "$3" "$_fix"
    fi
}

# agentvm_available  ->  0 when boxes can be used here; otherwise prints why, one line meant for
# an alert, and returns why: 1 when installing AgentVM would not help (an older macOS, a broken
# developer setting or test seam), agentvm_not_installed when the installed agent-vm is not
# there, agentvm_too_old when it is there but older than AGENTVM_MIN_VERSION or does not run.
# agentvm_install_job fixes the last two. Checked before any other call, and before a "where it
# runs" picker offers anything but This Mac.
agentvm_not_installed=2
agentvm_too_old=3
agentvm_available() {
    local _reason="$(agentvm_macos_reason "$(/usr/bin/sw_vers -productVersion 2>/dev/null)")"
    if [ -n "$_reason" ]; then
        printf '%s\n' "$_reason"
        return 1
    fi
    local _bin="$(agentvm_bin)"
    local _origin="$(agentvm_origin)"
    _reason="$(agentvm_bin_reason "$_bin" "$_origin")"
    if [ -n "$_reason" ]; then
        printf '%s\n' "$_reason"
        [ "$_origin" = "installed" ] && return "$agentvm_not_installed"
        return 1
    fi
    local _version
    _version="$(agentvm_run --version 2>&1)"
    local _status=$?
    _reason="$(agentvm_version_reason "$_bin" "$_origin" "$_version" "$_status")"
    if [ -n "$_reason" ]; then
        printf '%s\n' "$_reason"
        [ "$_origin" = "installed" ] && return "$agentvm_too_old"
        return 1
    fi
    return 0
}

# agentvm_version_info  ->  TSV: version, path, guestVersion, guestFeatures, guestDigest,
# guestError. The guest fields describe the agent-vm-guest next to agent-vm, which is what
# `image update-guest` would install; guestError says why it could not describe itself.
agentvm_version_info() {
    agentvm_rows version version
}

# agentvm_box_status <box>  ->  TSV: state, pid, supervisorVersion, supervisorPath, startedAt,
# project, projectReadOnly, activeExecs, guestVersion, guestFeatures, image, statusError,
# ownerPid, memoryGB.
#
# Never starts or stops anything (agent-vm 0.1.6's `box status`), so it is safe to poll, but a
# supervisor that does not answer can hold it up for about 7 seconds (agent-vm's BoxStatus.of:
# 2 s for the socket to appear, 5 s for the answer). state is stopped, starting, running,
# stopping or unresponsive: something holds the box's lock but no supervisor answers (pid is
# "-"), or a supervisor answered without a state (pid is its pid); statusError says which.
# pid identifies the supervisor, which owns the virtual machine; activeExecs counts the
# programs exec and box shell run in the box right now, from any client, Cadabra or not.
agentvm_box_status() {
    if ! agentvm_valid_name "$1"; then
        printf '"%s" is not a box name agent-vm accepts.\n' "$1" > "$agentvm_err_file"
        return 2
    fi
    agentvm_rows status box status "$1"
}

# agentvm_doctor  ->  TSV rows: name, status (ok, info, warning, failure), detail.
agentvm_doctor() {
    agentvm_rows doctor doctor
}

# -- Images, boxes and their logs --------------------------------------------------------
# Rows as agentvm_json.py documents them. Each fails like agentvm_rows: agent-vm's status, and
# its message waiting for agentvm_last_error.

# _agentvm_refuse <status> <message>  ->  leaves the message for agentvm_last_error, returns status.
# For arguments refused before agent-vm runs, so every failure is read the same way.
_agentvm_refuse() {
    printf 'Error: %s\n' "$2" > "$agentvm_err_file"
    return "$1"
}

# _agentvm_need_name <image|box> <name>  ->  0, or 2 with the reason left for agentvm_last_error.
_agentvm_need_name() {
    agentvm_valid_name "$2" && return 0
    _agentvm_refuse 2 "\"$2\" is not a $1 name agent-vm accepts: lower-case letters, digits, \".\", \"_\" and \"-\", starting with a letter or digit, at most 63 characters."
}

# _agentvm_need_count <what> <value>  ->  0 when value is a whole number from 1 to 999.
_agentvm_need_count() {
    case "$2" in
        [123456789]|[123456789][0123456789]|[123456789][0123456789][0123456789]) return 0 ;;
    esac
    _agentvm_refuse 2 "$1 must be a whole number, and \"$2\" is not one."
}

# agentvm_images  ->  one row per image: name, state, failure, macOS, basedOn, ownSize, needs,
# recipe, created, guestVersion, cpus, memoryGB, diskGB, path, needKinds. ownSize is "-":
# agent-vm's lists measure no disk, agentvm_image_sizes does.
agentvm_images() {
    agentvm_rows images image list
}

# agentvm_boxes  ->  one row per box: name, state, image, network, cpus, memoryGB, ownSize, pid,
# project, projectReadOnly, activeExecs, disposable, ownerPid, startedAt, supervisorVersion,
# path, netMode, rules. ownSize is "-" (agentvm_box_sizes measures it); state is "running"
# for a box that is up. Like `box status`, listing never starts or stops anything; it does
# delete disposable boxes that have stopped (agent-vm's `box gc`, run by `box list`).
agentvm_boxes() {
    agentvm_rows boxes box list
}

# agentvm_packs  ->  one row per network pack: name, hosts (comma-joined), problem ("-" unless
# agent-vm cannot use the pack).
agentvm_packs() {
    agentvm_rows packs box packs
}

# agentvm_execlog <box> [last]  ->  one row per program run in the box, oldest first: started,
# status, seconds, program, prompts, stoppedOnPrompt. The last <last> runs when given.
agentvm_execlog() {
    _agentvm_need_name box "$1" || return $?
    if [ -n "${2:-}" ]; then
        _agentvm_need_count "The number of runs" "$2" || return $?
        agentvm_rows execlog box execlog "$1" --last "$2"
        return $?
    fi
    agentvm_rows execlog box execlog "$1"
}

# agentvm_netlog <box> [last] [denied]  ->  one row per connection attempt, oldest first: time,
# decision, host, port, method, reason. "denied" as the third argument keeps only refusals.
agentvm_netlog() {
    _agentvm_need_name box "$1" || return $?
    local _box="$1" _last="${2:-}" _denied="${3:-}"
    if [ -n "$_last" ]; then
        _agentvm_need_count "The number of entries" "$_last" || return $?
    fi
    if [ -n "$_last" ] && [ "$_denied" = "denied" ]; then
        agentvm_rows netlog box netlog "$_box" --last "$_last" --denied
    elif [ -n "$_last" ]; then
        agentvm_rows netlog box netlog "$_box" --last "$_last"
    elif [ "$_denied" = "denied" ]; then
        agentvm_rows netlog box netlog "$_box" --denied
    else
        agentvm_rows netlog box netlog "$_box"
    fi
}

# agentvm_box_create <box> <image> <cpus> <memory GB> <network> <disposable> [allow rules...]
#   ->  0 once the box exists (a clone takes a second or two, so this is not a job).
# cpus and memory may be empty for the image's own; network is allowlist, off or open;
# disposable is yes or no. Each allow rule is one --allow: a host, "*.domain", "host:port" or
# "pack:<name>". A rule is an argv element after an option, so one starting with "-" is refused.
agentvm_box_create() {
    if [ $# -lt 6 ]; then
        _agentvm_refuse 2 "agentvm_box_create needs a box, an image, CPUs, memory, a network mode and yes or no for disposable."
        return 2
    fi
    _agentvm_need_name box "$1" || return $?
    _agentvm_need_name image "$2" || return $?
    local _box="$1" _image="$2" _cpus="$3" _memory="$4" _net="$5" _disposable="$6"
    shift 6
    case "$_net" in
        allowlist|off|open) ;;
        *) _agentvm_refuse 2 "The network mode must be allowlist, off or open, not \"$_net\"."
           return $? ;;
    esac
    # The rules are now the positional parameters. Each one is taken off the front and put
    # back at the end behind its --allow, once per rule, which leaves "--allow r1 --allow r2 ...".
    local _rules=$# _rule
    while [ "$_rules" -gt 0 ]; do
        _rule="$1"
        shift
        case "$_rule" in
            ''|-*|*' '*)
                _agentvm_refuse 2 "\"$_rule\" is not a network rule: a host, \"*.domain\", \"host:port\" or \"pack:<name>\"."
                return $? ;;
        esac
        set -- "$@" --allow "$_rule"
        _rules=$((_rules - 1))
    done
    set -- box create "$_box" --image "$_image" --net "$_net" "$@"
    if [ -n "$_cpus" ]; then
        _agentvm_need_count "The number of CPUs" "$_cpus" || return $?
        set -- "$@" --cpus "$_cpus"
    fi
    if [ -n "$_memory" ]; then
        _agentvm_need_count "The memory in GB" "$_memory" || return $?
        set -- "$@" --memory-gb "$_memory"
    fi
    case "$_disposable" in
        yes) set -- "$@" --disposable ;;
        no)  ;;
        *)   _agentvm_refuse 2 "disposable must be yes or no, not \"$_disposable\"."
             return $? ;;
    esac
    agentvm_json "$@" >/dev/null
}

# agentvm_box_allow <box> <rule>  ->  0 once the rule is among the box's network rules. A
# running box's proxy rereads its rules at once, so the next connection it covers gets through.
# The rule is an argv element after --allow, so one that is empty, starts with "-" or holds
# whitespace is refused.
agentvm_box_allow() {
    _agentvm_need_name box "$1" || return $?
    case "$2" in
        ''|-*|*' '*|*"$(printf '\t')"*)
            _agentvm_refuse 2 "\"$2\" is not a network rule: a host, \"*.domain\", \"host:port\" or \"pack:<name>\"."
            return $? ;;
    esac
    agentvm_json box network "$1" --allow "$2" >/dev/null
}

# agentvm_box_delete <box>  ->  0 once the box and its disk are gone. agent-vm refuses a
# running box, with a message saying to stop it first.
agentvm_box_delete() {
    _agentvm_need_name box "$1" || return $?
    agentvm_json box delete "$1" >/dev/null
}

# agentvm_box_recreate <box>  ->  0 once the stopped box is made again as a fresh clone of its
# image as the image is now (after a guest update, say), with the same CPUs, memory, network rules
# and disposable flag (agent-vm's `box recreate`). Everything written in the old box goes,
# logins included. agent-vm refuses a box that runs. A clone, so it takes a moment, not a job.
agentvm_box_recreate() {
    _agentvm_need_name box "$1" || return $?
    agentvm_json box recreate "$1" >/dev/null
}

# agentvm_image_delete <image>  ->  0 once it is gone. agent-vm refuses an image that boxes or
# other images are made from, naming them.
agentvm_image_delete() {
    _agentvm_need_name image "$1" || return $?
    agentvm_json image delete "$1" >/dev/null
}

# agentvm_box_view <box> [interactive]  ->  0 once the box's supervisor shows its screen in a
# window (or brings the window to the front). The box must be running. "interactive" lets keys
# and clicks reach the box.
agentvm_box_view() {
    _agentvm_need_name box "$1" || return $?
    if [ "${2:-}" = "interactive" ]; then
        agentvm_json box view "$1" --interactive >/dev/null
        return $?
    fi
    agentvm_json box view "$1" >/dev/null
}

# The status agent-vm exits with when a start finds no free virtual machine slot. The refusal is
# macOS's own (Virtualization's), so it is right even when two starts pass agentvm_vm_slot_free
# at the same moment.
agentvm_no_slot_status=75

# _agentvm_slots_full  ->  doctor's explanation (how many run, the limit) when no macOS virtual
# machine can start on this Mac, else nothing. macOS runs at most two macOS guests at once,
# counting every application's. Doctor's "running VMs" check says "warning" when the limit is
# reached, and "info" when it could not count, which is not a reason to refuse; nor is a doctor
# that fails: the start then fails with agent-vm's own reason.
_agentvm_slots_full() {
    local _rows
    _rows="$(agentvm_doctor)"
    local _status=$?
    /bin/rm -f "$agentvm_err_file"
    if [ "$_status" -ne 0 ]; then
        return 0
    fi
    printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' '$1 == "running VMs" && $2 == "warning" { print $3 }'
}

# _agentvm_refuse_no_slot <status> [explanation]  ->  one message for every "no free slot"
# refusal, Cadabra's own check's or agent-vm's, left for agentvm_last_error; returns status. It
# names the AgentVM boxes that hold a slot (running, or starting: in a race, the one that took
# it), since stopping one is what the user can do in Cadabra (agent-vm's own message points to
# `agent-vm box list` in Terminal). Without doctor's explanation it states the limit.
_agentvm_refuse_no_slot() {
    local _why="${2:-macOS runs at most two macOS virtual machines at once, and that many are running}"
    local _running="$(agentvm_boxes 2>/dev/null | /usr/bin/awk -F'\t' '$2 == "running" || $2 == "starting" { printf "%s%s", sep, $1; sep = ", " }')"
    local _fix="Stop a box in Tools > AgentVM, or a virtual machine in another application, then try again."
    if [ -n "$_running" ]; then
        _fix="AgentVM boxes running: $_running. Stop one in Tools > AgentVM, or a virtual machine in another application, then try again."
    fi
    _agentvm_refuse "$1" "No virtual machine slot is free: $_why. $_fix"
}

# agentvm_vm_slot_free  ->  0 when another macOS virtual machine can start on this Mac;
# otherwise 1, with the reason for agentvm_last_error. A first check, so a start that cannot
# succeed is refused before a disposable box is made or a job begins, not a minute into a boot.
agentvm_vm_slot_free() {
    local _full="$(_agentvm_slots_full)"
    if [ -n "$_full" ]; then
        _agentvm_refuse_no_slot 1 "$_full"
        return 1
    fi
    return 0
}

# -- Jobs: long agent-vm commands that outlive the window --------------------------------
# agentvm_job.py runs them detached, in the folder agentvm_jobs_dir names; see its header.
# A job's target ("box:<name>", "image:<name>", or "image:a,b" for a guest update of several)
# is what it works on. agentvm_job.py runs one job per target at a time, comparing whole
# targets, so a second start of a box is refused up front; agentvm_job_busy also sees an image
# inside a several-image target, and agent-vm's own lock on each image is the final guard.

# agentvm_jobs_dir  ->  where the jobs live.
agentvm_jobs_dir() {
    printf '%s\n' "$mcp_app_support/Jobs"
}

# agentvm_job_start <kind> <target> <title> <agent-vm args...>  ->  the new job's id.
# Runs the agent-vm agentvm_bin names, with --json last (progress events) and Cadabra's store
# setting, exactly as agentvm_json would. Status 3 when a job for the same target still runs.
agentvm_job_start() {
    local _kind="$1" _target="$2" _title="$3"
    shift 3
    local _bin="$(agentvm_bin)"
    local _home="$(agentvm_setting agent-vm-home)"
    local _jobs="$(agentvm_jobs_dir)"
    local _status
    /bin/rm -f "$agentvm_err_file"
    if [ -n "$_home" ]; then
        AGENT_VM_HOME="$_home" "$agentvm_python" "$agentvm_job_py" start "$_jobs" "$_kind" "$_target" "$_title" -- "$_bin" "$@" --json 2>"$agentvm_err_file"
        _status=$?
    else
        "$agentvm_python" "$agentvm_job_py" start "$_jobs" "$_kind" "$_target" "$_title" -- "$_bin" "$@" --json 2>"$agentvm_err_file"
        _status=$?
    fi
    _agentvm_job_result "$_status" start
}

# _agentvm_job_result <status> <command>  ->  status. The job store's refusals are plain
# sentences on stderr; they get the "Error: " prefix agentvm_last_error reads.
_agentvm_job_result() {
    if [ "$1" -eq 0 ]; then
        /bin/rm -f "$agentvm_err_file"
        return 0
    fi
    local _message="$(/bin/cat "$agentvm_err_file" 2>/dev/null)"
    _agentvm_refuse "$1" "${_message:-agentvm_job.py $2 failed (status $1)}"
}

# -- Installing AgentVM --------------------------------------------------------------------

# The newest AgentVM release on GitHub, and the Developer ID team its package must be signed by.
agentvm_releases_api="https://api.github.com/repos/abra-code/agent-vm/releases/latest"
agentvm_team_id="T9NM2ZLDTY"
agentvm_install_py="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/agentvm_install.py"
# The job's target: one install at a time, whichever window started it.
agentvm_install_target="agentvm:AgentVM"

# agentvm_install_job <install|update>  ->  the new job's id (kind agentvm-install). The job
# downloads the newest AgentVM release package from GitHub, refuses it unless it is notarized
# and signed by AgentVM's team, installs its agent-vm part for the user (no administrator
# password, no shell profile change), and checks that agentvm_installed reports the release's
# version (agentvm_install.py). The package always installs to agentvm_installed, so this is
# for the installed origin only. Status 3 while another install runs.
agentvm_install_job() {
    local _title="Install AgentVM"
    [ "$1" = "update" ] && _title="Update AgentVM"
    /bin/rm -f "$agentvm_err_file"
    "$agentvm_python" "$agentvm_job_py" start "$(agentvm_jobs_dir)" agentvm-install "$agentvm_install_target" "$_title" -- \
        "$agentvm_python" "$agentvm_install_py" install --api "$agentvm_releases_api" \
        --min "$AGENTVM_MIN_VERSION" --team "$agentvm_team_id" --link "$agentvm_installed" 2>"$agentvm_err_file"
    _agentvm_job_result $? start
}

# -- Is a newer release out? ---------------------------------------------------------------
#
# The Box Manager says when the newest release is newer than the installed agent-vm. GitHub is
# asked at most once a day (agentvm_newest_every), with a short limit on the request, and the
# answer is kept in agentvm_newest_file as "<when asked, epoch seconds> TAB <version>". A failed
# lookup renews the date and keeps the version found before (none when there was none), so a
# Mac without a network asks once a day, not at every look, and an update already known stays
# offered. Only the installed origin is compared: a developer build or a test double is not
# something the release would replace.
agentvm_newest_every=86400
agentvm_newest_max_time=5

# agentvm_newest_file  ->  where the last lookup is kept.
agentvm_newest_file() {
    printf '%s\n' "$mcp_app_support/agentvm-newest.tsv"
}

# agentvm_newest  ->  the newest release's version from the last lookup, or nothing.
agentvm_newest() {
    local _file="$(agentvm_newest_file)"
    [ -f "$_file" ] || return 0
    /usr/bin/awk -F'\t' 'NR == 1 && $2 ~ /^[0-9]+(\.[0-9]+)*$/ { print $2 }' "$_file"
}

# agentvm_newest_check  ->  asks GitHub for the newest release when the last lookup is older than
# agentvm_newest_every, or in the future (a clock set back), or missing. Never fails: the Box
# Manager only loses its notice.
agentvm_newest_check() {
    local _file="$(agentvm_newest_file)"
    local _now="$(/bin/date +%s)"
    local _last=""
    [ -f "$_file" ] && _last="$(/usr/bin/awk -F'\t' 'NR == 1 { print $1 }' "$_file")"
    # A leading zero too: $(( )) would read the rest as octal, and "08" ends the handler.
    case "$_last" in
        ''|0?*|*[!0123456789]*) _last=0 ;;
    esac
    if [ "$_last" -le "$_now" ] && [ $((_now - _last)) -lt "$agentvm_newest_every" ]; then
        return 0
    fi
    local _version
    _version="$("$agentvm_python" "$agentvm_install_py" newest --api "$agentvm_releases_api" \
        --max-time "$agentvm_newest_max_time" 2>/dev/null)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        _version="$(agentvm_newest)"
    fi
    /bin/mkdir -p "$mcp_app_support" 2>/dev/null
    # Braces, so that a redirection that fails is silenced too.
    { printf '%s\t%s\n' "$_now" "$_version" > "$_file.$$"; } 2>/dev/null
    _status=$?
    if [ "$_status" -eq 0 ]; then
        /bin/mv -f "$_file.$$" "$_file" 2>/dev/null
        _status=$?
    fi
    [ "$_status" -eq 0 ] || /bin/rm -f "$_file.$$"
    return 0
}

# agentvm_update_available <installed version>  ->  the newest release's version when it is
# newer than the installed one, after agentvm_newest_check; nothing otherwise, and nothing for
# a developer build or a test double.
agentvm_update_available() {
    [ -n "$1" ] || return 0
    [ "$(agentvm_origin)" = "installed" ] || return 0
    agentvm_newest_check
    local _newest="$(agentvm_newest)"
    [ -n "$1" ] && [ -n "$_newest" ] && [ "$_newest" != "$1" ] || return 0
    agentvm_version_at_least "$1" "$_newest"
    local _current=$?
    [ "$_current" -eq 0 ] || printf '%s\n' "$_newest"
    return 0
}

# agentvm_installing  ->  0 while an install job runs.
agentvm_installing() {
    local _title="$(agentvm_job_busy "$agentvm_install_target")"
    [ -n "$_title" ]
}

# agentvm_jobs  ->  one row per job, oldest first: id, kind, target, title, state, status,
# started, ended, step, fraction, message, notice, error (agentvm_job.py list). state is
# running, done, failed, canceled or lost.
agentvm_jobs() {
    "$agentvm_python" "$agentvm_job_py" list "$(agentvm_jobs_dir)" 2>"$agentvm_err_file"
    _agentvm_job_result $? list
}

# agentvm_job_busy <target>  ->  the title of the running job that holds target, or nothing.
# A several-image target ("image:a,b") holds each of its images.
agentvm_job_busy() {
    agentvm_jobs | /usr/bin/awk -F'\t' -v target="$1" '
        $5 != "running" { next }
        $3 == target { print $4; exit }
        {
            split($3, side, ":")
            n = split(substr($3, length(side[1]) + 2), name, ",")
            for (i = 1; i <= n; i++) if (side[1] ":" name[i] == target) { print $4; exit }
        }'
}

# _agentvm_job_call <command> <id>  ->  agentvm_job.py <command> for one job; its refusal is left
# for agentvm_last_error.
_agentvm_job_call() {
    "$agentvm_python" "$agentvm_job_py" "$1" "$(agentvm_jobs_dir)" "$2" 2>"$agentvm_err_file"
    _agentvm_job_result $? "$1"
}

# agentvm_job_error <id>  ->  the whole error of a failed job, as agent-vm wrote it.
agentvm_job_error() {
    _agentvm_job_call error "$1"
}

# agentvm_job_cancel <id>  ->  0 once the job was asked to stop. agent-vm stops at its next safe
# point, so the job still shows as running for a moment; it ends as canceled.
agentvm_job_cancel() {
    _agentvm_job_call cancel "$1"
}

# agentvm_job_forget <id>  ->  0 once a finished job is removed from the list.
agentvm_job_forget() {
    _agentvm_job_call forget "$1"
}

# _agentvm_owner_pid  ->  the application's pid for --owner-pid, or nothing when OMC did not
# give one: a box Cadabra started stops when Cadabra goes away, however it goes (a crash, a
# force quit).
_agentvm_owner_pid() {
    case "${OMC_APP_PROCESS_ID:-}" in
        ''|*[!0123456789]*) ;;
        *) printf '%s\n' "$OMC_APP_PROCESS_ID" ;;
    esac
}

# agentvm_box_start_job <box>  ->  the job id. The box stops by itself when Cadabra exits (its
# owner lease), because a running box holds one of the two macOS virtual machine slots.
agentvm_box_start_job() {
    _agentvm_need_name box "$1" || return $?
    agentvm_vm_slot_free || return $?
    local _owner="$(_agentvm_owner_pid)"
    if [ -n "$_owner" ]; then
        agentvm_job_start box-start "box:$1" "Start $1" box start "$1" --owner-pid "$_owner"
        return $?
    fi
    agentvm_job_start box-start "box:$1" "Start $1" box start "$1"
}

# agentvm_box_stop_job <box>  ->  the job id. A clean shutdown of the guest takes a few seconds.
agentvm_box_stop_job() {
    _agentvm_need_name box "$1" || return $?
    agentvm_job_start box-stop "box:$1" "Stop $1" box stop "$1"
}

# agentvm_box_start <box>  ->  0 once the box is ready, after waiting for it (10-16 s from
# stopped). For a chat window's start, which shows its own progress and cannot go on without the
# box; the Box Manager starts boxes as jobs. A box that already runs is left as it is; one that
# is starting (a Box Manager job, say) is waited for, and one that is stopping is waited for and
# then started (agent-vm 0.2.15). None of them is slot-checked: each still holds its virtual
# machine slot and would count against itself.
agentvm_box_start() {
    _agentvm_need_name box "$1" || return $?
    local _row
    _row="$(agentvm_box_status "$1")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        return "$_status"
    fi
    local _state="$(printf '%s\n' "$_row" | /usr/bin/cut -f1)"
    case "$_state" in
        running)  return 0 ;;
        starting|stopping) ;;
        *)        agentvm_vm_slot_free || return $? ;;
    esac
    local _owner="$(_agentvm_owner_pid)"
    local _started
    if [ -n "$_owner" ]; then
        agentvm_json box start "$1" --owner-pid "$_owner" >/dev/null
        _started=$?
    else
        agentvm_json box start "$1" >/dev/null
        _started=$?
    fi
    # Two windows can pass the check above at the same moment; agent-vm's refusal of the second
    # then reads like the check's.
    if [ "$_started" -eq "$agentvm_no_slot_status" ]; then
        _agentvm_refuse_no_slot "$_started" "$(_agentvm_slots_full)"
    fi
    return "$_started"
}

# agentvm_box_warmup <box> <project> <yes|no read-only>  ->  0 once a program has run in the box
# with the project shared, at the same path. It checks what only agent-vm can (its share rules,
# a box already serving another project) and mounts the share, so the agent's own start does not
# wait for it. A refusal is agent-vm's message, naming the rule, for agentvm_last_error.
agentvm_box_warmup() {
    _agentvm_need_name box "$1" || return $?
    case "$2" in
        /*) ;;
        *) _agentvm_refuse 2 "The project must be an absolute path, not \"$2\"."
           return $? ;;
    esac
    case "$3" in
        yes) set -- "$1" "$2" --read-only ;;
        no)  set -- "$1" "$2" ;;
        *)   _agentvm_refuse 2 "read-only must be yes or no, not \"$3\"."
             return $? ;;
    esac
    local _box="$1" _project="$2"
    shift 2
    /bin/rm -f "$agentvm_err_file"
    agentvm_run exec --box "$_box" --project "$_project" "$@" -- /usr/bin/true </dev/null 2>"$agentvm_err_file"
    local _status=$?
    if [ "$_status" -eq 0 ]; then
        /bin/rm -f "$agentvm_err_file"
    fi
    return "$_status"
}

# agentvm_image_sizes <image> / agentvm_box_sizes <box>  ->  one row: ownSize, totalSize,
# addedOverBase, addedSize (agentvm_json.py sizes). agent-vm measures space only in
# `image info` and `box info` (about 0.1 s per disk, 0.3 s more for an image's growth over its
# base), so the lists stay quick; the Box Manager asks for one row when it is selected.
agentvm_image_sizes() {
    _agentvm_need_name image "$1" || return $?
    agentvm_rows sizes image info "$1"
}

agentvm_box_sizes() {
    _agentvm_need_name box "$1" || return $?
    agentvm_rows sizes box info "$1"
}

# agentvm_secrets  ->  one row per Keychain secret agent-vm keeps: name, readable (names only;
# agent-vm never prints a value).
agentvm_secrets() {
    agentvm_rows secrets secret list
}

# agentvm_secret_set <name>  ->  0 once agent-vm stored its stdin as the secret <name> in the
# login Keychain. The value comes only from stdin, never from an argument, so it is not in any
# process's argv; callers pipe it from the shell's builtin printf. agent-vm drops one final line
# end. Replacing a secret another agent-vm stored may make macOS ask first, and this waits for
# the answer.
agentvm_secret_set() {
    agentvm_valid_secret_name "$1" || { _agentvm_refuse 2 "\"$1\" is not a secret name."; return 2; }
    /bin/rm -f "$agentvm_err_file"
    agentvm_run secret set "$1" >/dev/null 2>"$agentvm_err_file"
    local _status=$?
    if [ "$_status" -eq 0 ]; then
        /bin/rm -f "$agentvm_err_file"
    fi
    return "$_status"
}

# agentvm_secret_delete <name>  ->  0 once the secret is gone from the Keychain.
agentvm_secret_delete() {
    agentvm_valid_secret_name "$1" || { _agentvm_refuse 2 "\"$1\" is not a secret name."; return 2; }
    /bin/rm -f "$agentvm_err_file"
    agentvm_run secret delete "$1" </dev/null >/dev/null 2>"$agentvm_err_file"
    local _status=$?
    if [ "$_status" -eq 0 ]; then
        /bin/rm -f "$agentvm_err_file"
    fi
    return "$_status"
}

# agentvm_image_update_guest_job <image>...  ->  the job id. Boots each image in turn to install
# the guest daemon next to agent-vm into it, so it needs a free virtual machine slot. Several
# images are one job, one agent-vm run: they update one after another, where separate jobs
# would compete for the two slots. The target names them all ("image:dev,dev-node"), and
# agentvm_job.py's one-job-per-target rule compares whole targets, so each image is also
# guarded by agent-vm's own lock on it.
agentvm_image_update_guest_job() {
    if [ $# -eq 0 ]; then
        _agentvm_refuse 2 "agentvm_image_update_guest_job needs at least one image."
        return 2
    fi
    local _image _names=""
    for _image in "$@"; do
        _agentvm_need_name image "$_image" || return $?
        _names="${_names:+$_names,}$_image"
    done
    agentvm_vm_slot_free || return $?
    if [ $# -eq 1 ]; then
        agentvm_job_start update-guest "image:$1" "Update the guest in $1" image update-guest "$1"
        return $?
    fi
    agentvm_job_start update-guest "image:$_names" "Update the guest in $# images" image update-guest "$@"
}

# agentvm_image_setup_job <image>  ->  the job id. Opens the image in a window where the user
# grants Full Disk Access by hand; the job ends when they are done.
agentvm_image_setup_job() {
    _agentvm_need_name image "$1" || return $?
    agentvm_vm_slot_free || return $?
    agentvm_job_start image-setup "image:$1" "Set up Full Disk Access in $1" image setup "$1"
}

# -- Building an image -------------------------------------------------------------------

# agentvm_recipes_dir  ->  the folder of agent-vm's image recipes, or nothing. AgentVM's package
# puts Recipes/ beside the real agent-vm (agentvm_real_dir). A developer build
# (/developer/agent-vm) in an agent-vm working tree has none beside it, since agent-vm's build
# script copies only the programs and their JSON files to .build/signed/release; for that
# origin the working tree's own Recipes/ is used: the nearest folder above the build that holds
# Package.swift and Recipes/.
agentvm_recipes_dir() {
    local _dir="$(agentvm_real_dir)"
    [ -n "$_dir" ] || return 0
    if [ -d "$_dir/Recipes" ]; then
        printf '%s\n' "$_dir/Recipes"
        return 0
    fi
    local _origin="$(agentvm_origin)"
    [ "$_origin" = "developer" ] || return 0
    local _up="$_dir"
    local _step
    for _step in 1 2 3 4; do
        _up="$(/usr/bin/dirname "$_up")"
        if [ -f "$_up/Package.swift" ] && [ -d "$_up/Recipes" ]; then
            printf '%s\n' "$_up/Recipes"
            return 0
        fi
    done
}

# agentvm_recipes  ->  one row per recipe that came with agent-vm (agentvm_recipes_dir): folder
# name, path of its recipe.json, description. Sorted by folder name (byte order, on the name
# alone: the glob's own order puts "xcode-platforms/" before "xcode/"); a folder whose recipe
# cannot be read is left out, and so is everything when there is no recipes folder.
agentvm_recipes() {
    local _dir="$(agentvm_recipes_dir)"
    [ -n "$_dir" ] || return 0
    local _recipe _row
    for _recipe in "$_dir"/*/recipe.json; do
        [ -f "$_recipe" ] || continue
        _row="$("$agentvm_python" "$agentvm_json_py" recipe "$_recipe" 2>/dev/null | /usr/bin/head -1)"
        [ -n "$_row" ] || continue
        printf '%s\t%s\t%s\n' "$(/usr/bin/basename "$(/usr/bin/dirname "$_recipe")")" "$_recipe" \
            "$(printf '%s\n' "$_row" | /usr/bin/cut -f5)"
    done | LC_ALL=C /usr/bin/sort -t "$(printf '\t')" -k1,1
}

# agentvm_recipe_info <recipe.json>  ->  the recipe's rows (agentvm_json.py recipe): the recipe
# itself, then its inputs and parameters. Fails, with the reason for agentvm_last_error, when
# the path is not absolute or the file is not a recipe.
agentvm_recipe_info() {
    case "$1" in
        /*) ;;
        *) _agentvm_refuse 2 "The recipe must be given as a full path, not \"$1\"."
           return 2 ;;
    esac
    "$agentvm_python" "$agentvm_json_py" recipe "$1" 2>"$agentvm_err_file"
    local _status=$?
    if [ "$_status" -eq 0 ]; then
        /bin/rm -f "$agentvm_err_file"
    fi
    return "$_status"
}

# _agentvm_recipe_name <name>  ->  0 when it is a name agent-vm accepts for a recipe input or
# parameter: lower-case letters, digits and "_", starting with a letter, at most 32 characters.
_agentvm_recipe_name() {
    case "$1" in
        [abcdefghijklmnopqrstuvwxyz]*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *[!abcdefghijklmnopqrstuvwxyz0123456789_]*) return 1 ;;
    esac
    [ "${#1}" -le 32 ]
}

# agentvm_image_create_job <image> <ipsw|from> <source> <recipe.json or ""> <cpus> <memory GB>
#                          <disk GB> [set:NAME=VALUE | input:NAME=PATH ...]  ->  the job id.
# source is the restore image's full path (ipsw) or the image to start from (from). cpus,
# memory and disk may be empty for agent-vm's defaults (or the base image's). Each set: becomes
# a --set for one of the recipe's parameters, each input: an --input with a file on this Mac;
# agent-vm itself refuses a name the recipe does not declare and a missing required one.
# Installing from a restore image takes minutes, a recipe on an existing image as long as its
# steps; either way it boots a virtual machine, so it needs a free slot.
agentvm_image_create_job() {
    if [ $# -lt 7 ]; then
        _agentvm_refuse 2 "agentvm_image_create_job needs an image, a source kind and source, a recipe, CPUs, memory and disk."
        return 2
    fi
    _agentvm_need_name image "$1" || return $?
    local _image="$1" _kind="$2" _source="$3" _recipe="$4" _cpus="$5" _memory="$6" _disk="$7"
    shift 7
    # The extras are validated and turned into options in place, as in agentvm_box_create:
    # each is taken off the front and put back at the end as its option and value.
    local _extras=$# _extra _name _value
    while [ "$_extras" -gt 0 ]; do
        _extra="$1"
        shift
        case "$_extra" in
            set:*=*)   _name="${_extra#set:}"; _value="${_name#*=}"; _name="${_name%%=*}" ;;
            input:*=*) _name="${_extra#input:}"; _value="${_name#*=}"; _name="${_name%%=*}" ;;
            *) _agentvm_refuse 2 "\"$_extra\" is neither a recipe parameter (set:NAME=VALUE) nor an input (input:NAME=PATH)."
               return 2 ;;
        esac
        if ! _agentvm_recipe_name "$_name"; then
            _agentvm_refuse 2 "\"$_name\" is not a recipe input or parameter name: lower-case letters, digits and \"_\", starting with a letter."
            return 2
        fi
        case "$_extra" in
            set:*) set -- "$@" --set "$_name=$_value" ;;
            input:*)
                case "$_value" in
                    /*) ;;
                    *) _agentvm_refuse 2 "The file for the recipe input $_name must be a full path, not \"$_value\"."
                       return 2 ;;
                esac
                if [ ! -f "$_value" ]; then
                    _agentvm_refuse 2 "The file for the recipe input $_name, $_value, does not exist."
                    return 2
                fi
                set -- "$@" --input "$_name=$_value" ;;
        esac
        _extras=$((_extras - 1))
    done
    case "$_kind" in
        ipsw)
            case "$_source" in
                /*.ipsw) ;;
                *) _agentvm_refuse 2 "The macOS restore file must be the full path of an .ipsw file, not \"$_source\"."
                   return 2 ;;
            esac
            if [ ! -f "$_source" ]; then
                _agentvm_refuse 2 "The macOS restore file $_source does not exist."
                return 2
            fi
            set -- --ipsw "$_source" "$@" ;;
        from)
            _agentvm_need_name image "$_source" || return $?
            set -- --from "$_source" "$@" ;;
        *)  _agentvm_refuse 2 "The source must be ipsw or from, not \"$_kind\"."
            return 2 ;;
    esac
    if [ -n "$_recipe" ]; then
        case "$_recipe" in
            /*) ;;
            *) _agentvm_refuse 2 "The recipe must be given as a full path, not \"$_recipe\"."
               return 2 ;;
        esac
        if [ ! -f "$_recipe" ]; then
            _agentvm_refuse 2 "The recipe $_recipe does not exist."
            return 2
        fi
        set -- "$@" --recipe "$_recipe"
    fi
    if [ -n "$_cpus" ]; then
        _agentvm_need_count "The number of CPUs" "$_cpus" || return $?
        set -- "$@" --cpus "$_cpus"
    fi
    if [ -n "$_memory" ]; then
        _agentvm_need_count "The memory in GB" "$_memory" || return $?
        set -- "$@" --memory-gb "$_memory"
    fi
    if [ -n "$_disk" ]; then
        _agentvm_need_count "The disk size in GB" "$_disk" || return $?
        set -- "$@" --disk-gb "$_disk"
    fi
    agentvm_vm_slot_free || return $?
    agentvm_job_start image-create "image:$_image" "Build image $_image" image create "$_image" "$@"
}

# -- A shell in a box, in Terminal -------------------------------------------------------

# _agentvm_quote <text>  ->  text as one single-quoted shell word.
_agentvm_quote() {
    printf "'%s'\n" "$(printf '%s' "$1" | /usr/bin/sed "s/'/'\\\\''/g")"
}

# agentvm_box_shell_file <box>  ->  the path of a .command file that opens a shell in the box.
# Terminal runs a .command file when it opens one, which is how a window-less handler hands
# the user an interactive terminal. The file names the agent-vm and store in use now; it is
# rewritten each time, so a changed setting takes effect on the next Shell.
agentvm_box_shell_file() {
    _agentvm_need_name box "$1" || return $?
    local _dir="$mcp_app_support/Shells"
    local _file="$_dir/$1.command"
    local _home="$(agentvm_setting agent-vm-home)"
    /bin/mkdir -p "$_dir"
    if [ $? -ne 0 ]; then
        _agentvm_refuse 1 "Could not create $_dir."
        return 1
    fi
    {
        printf '#!/bin/sh\n'
        printf '# Written by Cadabra'"'"'s AgentVM window: a shell in the box %s. Safe to delete.\n' "$1"
        if [ -n "$_home" ]; then
            printf 'AGENT_VM_HOME=%s\nexport AGENT_VM_HOME\n' "$(_agentvm_quote "$_home")"
        fi
        printf 'exec %s box shell %s\n' "$(_agentvm_quote "$(agentvm_bin)")" "$1"
    } > "$_file" || { _agentvm_refuse 1 "Could not write $_file."; return 1; }
    /bin/chmod 700 "$_file"
    printf '%s\n' "$_file"
}

# agentvm_box_shell <box>  ->  0 once Terminal was asked to open a shell in the box.
# CADABRA_OPEN is the test seam for /usr/bin/open.
agentvm_box_shell() {
    local _file
    _file="$(agentvm_box_shell_file "$1")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        return "$_status"
    fi
    "${CADABRA_OPEN:-/usr/bin/open}" -a Terminal "$_file" 2>"$agentvm_err_file"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        _agentvm_refuse "$_status" "Terminal could not open $_file."
        return "$_status"
    fi
    /bin/rm -f "$agentvm_err_file"
    return 0
}

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
#   - the installed ~/.local/bin/agent-vm. Cadabra carries no agent-vm of its own and does not
#     install one: the AgentVM app does, for the user, with agent-vm-guest, the network packs
#     and the image recipes in a folder of their own (~/.local/share/agent-vm/versions/<version>/),
#     and the link in ~/.local/bin points at the newest. Terminal (agent-vm, avm) and every
#     other app run the same one. Cadabra runs it through the link, so a program it started
#     shows the link's path in ps (the orphan sweep in aichat.server.library.sh relies on that),
#     and a version installed while a box runs takes over at the next start.
# /developer/agent-vm-home, when set, becomes AGENT_VM_HOME for every run: agent-vm's store root,
# which a project on another volume needs, and which a Finder-launched app cannot inherit from a
# shell. It applies to whichever binary runs, so switching binaries never switches stores.
#
# WHAT CADABRA DOES WITH IT. It runs agents and tools in boxes, makes and deletes the disposable
# box of a conversation, starts and stops boxes, and takes project snapshots. It does not
# install or update agent-vm, build or change images, or make, change or delete kept boxes:
# those belong to the AgentVM app (agentvm_app_show opens it).
#
# READING ITS ANSWERS. Only --json output is read, turned into tab-separated rows with no empty
# fields: by agentvm_json.py, and by jq for `status` (the AgentVM Boxes window polls it, and jq
# starts faster than Python). agent-vm's human text changes freely; its JSON is a contract with
# this library. A failed call leaves agent-vm's own message (written for people, naming the fix)
# for agentvm_last_error, and alerts show it as it is.
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
AGENTVM_MIN_VERSION="0.6.14"
AGENTVM_MIN_MACOS="27"

# Where the AgentVM app puts the link to the newest agent-vm, and where to get the app.
agentvm_installed="$HOME/.local/bin/agent-vm"
agentvm_app_page="https://github.com/abra-code/AgentVMApp/releases"
agentvm_python="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
agentvm_json_py="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/agentvm_json.py"

# Where agentvm_json leaves agent-vm's stderr for agentvm_last_error. Named after the handler's
# pid: $$ is the handler's own pid inside every subshell of it too, so a call made in $( ) - the
# usual way to call it - still leaves the message where the caller can find it afterwards.
# In Cadabra's own folder, not $TMPDIR (see cadabra_run_file): the name is predictable, and the
# file is written and read back without a look at what is there.
agentvm_err_file="$(cadabra_run_file "agentvm.$$.stderr")"

# agentvm_setting <name>  ->  /developer/<name> from the settings file, or nothing.
# Reads only: a missing file stays missing.
agentvm_setting() {
    [ -f "$cadabra_settings" ] || return 0
    "$plister" get string "$cadabra_settings" "/developer/$1" 2>/dev/null
}

# agentvm_origin  ->  test, developer or installed: where agentvm_bin's answer comes from.
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
                printf 'AgentVM is not set up on this Mac: there is no agent-vm at %s. The AgentVM app installs it.\n' "$1"
            fi ;;
    esac
}

# agentvm_version_reason <path> <origin> <output of --version> <its status>
#   ->  why that agent-vm is unusable, or nothing.
agentvm_version_reason() {
    # One line: the reason goes into an alert, and a crashing binary can print several.
    local _output="$(printf '%s' "$3" | /usr/bin/tr '\n' ' ')"
    local _fix="The AgentVM app updates it."
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
# an alert, and returns why: 1 when installing agent-vm would not help (an older macOS, a broken
# developer setting or test seam), agentvm_not_installed when the installed agent-vm is not
# there, agentvm_too_old when it is there but older than AGENTVM_MIN_VERSION or does not run.
# The AgentVM app fixes the last two. Checked before any other call, and before a "where it
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
# agent-vm's lists measure no disk.
agentvm_images() {
    agentvm_rows images image list
}

# agentvm_boxes  ->  one row per box: name, state, image, network, cpus, memoryGB, ownSize, pid,
# project, projectReadOnly, activeExecs, disposable, ownerPid, startedAt, supervisorVersion,
# path, netMode, rules. ownSize is "-" (the list measures no disk); state is "running"
# for a box that is up. Like `box status`, listing never starts or stops anything; it does
# delete disposable boxes that have stopped (agent-vm's `box gc`, run by `box list`).
agentvm_boxes() {
    agentvm_rows boxes box list
}

# agentvm_running_boxes_bytes [except box]  ->  the memory of the boxes running now, in bytes (from
# agent-vm's whole GB), for the memory warnings; 0 when none run, when boxes cannot be used here,
# or when agent-vm cannot list them (the warning then counts models only, as it did before boxes).
# A box starting or not answering holds its memory too; one stopping is about to free it. <except>
# is left out: a window's own disposable box, which goes when the window starts another.
agentvm_running_boxes_bytes() {
    agentvm_available >/dev/null 2>&1
    local _available=$?
    if [ "$_available" -ne 0 ]; then
        echo 0
        return 0
    fi
    local _rows
    _rows="$(agentvm_boxes)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        agentvm_last_error "$_status" >/dev/null
        echo 0
        return 0
    fi
    printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' -v except="${1:-}" '
        $1 != except && ($2 == "running" || $2 == "starting" || $2 == "unresponsive") && $6 ~ /^[0-9]+$/ { gb += $6 }
        END { printf "%.0f\n", gb * 1073741824 }'
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
    local _fix="Stop a box in Tools > AgentVM Boxes, or a virtual machine in another application, then try again."
    if [ -n "$_running" ]; then
        _fix="AgentVM boxes running: $_running. Stop one in Tools > AgentVM Boxes, or a virtual machine in another application, then try again."
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

# -- Status: every box and what works on it, in one answer -------------------------------
# `agent-vm status --json` lists the boxes with their states, the jobs that run or ended in the
# last hour, and how many virtual machines run. It measures no disk and changes nothing (unlike
# `box list`, it deletes no stopped disposable box), and takes a few hundredths of a second, so
# the AgentVM Boxes window polls it. A box whose supervisor does not answer holds it up for about
# 7 seconds. The *_rows filters read that JSON on stdin with jq, so one answer serves them all.
# jq is part of macOS 15 and later, and nothing here runs before agentvm_available, which needs
# macOS 27.

# Rows with no empty cells ("-" stands for a missing value) and no tabs or line ends inside one.
agentvm_jq_defs='
def cell: if . == null or . == "" then "-" else tostring | gsub("[\t\n\r]"; " ") end;
def row: map(cell) | join("\t");'

# agentvm_status  ->  `agent-vm status --json` as it is, for the filters below.
agentvm_status() {
    agentvm_json status
}

# agentvm_status_box_rows  <  status JSON  ->  one row per box:
#   1 name   2 state (stopped, starting, running, stopping, unresponsive)   3 image
#   4 memoryGB   5 activeExecs (programs running in it now)   6 ownerPid (the process it stops
#   with)   7 disposable (true or false)   8 statusError
# The running fields (5, 6) are "-" for a stopped box.
agentvm_status_box_rows() {
    /usr/bin/jq -r "$agentvm_jq_defs"' .boxes[]
        | [.box.name, .state, .box.image,
           (if .box.memoryBytes == null then null else .box.memoryBytes / 1073741824 | floor end),
           .activeExecs, .ownerPid, (.box.disposable // false), .statusError]
        | row'
}

# agentvm_status_job_rows  <  status JSON  ->  one row per job, oldest first:
#   1 id   2 state (queued, running, done, failed, canceled, lost)
#   3 target, the first one ("box:<name>", "image:<name>" or "ipsw")
#   4 what it does, the command's first two words ("box start")   5 status (the exit status, once
#   it ended)   6 error (after it failed or was canceled)
agentvm_status_job_rows() {
    /usr/bin/jq -r "$agentvm_jq_defs"' (.jobs // [])[]
        | [.id, .state, (.targets // [])[0], ((.command // [])[0:2] | join(" ")), .status, .error]
        | row'
}

# agentvm_status_vm_row  <  status JSON  ->  one row: how many macOS virtual machines run on this
# Mac (any application's), and how many can run at once. The count is "-" when agent-vm could
# not list processes.
agentvm_status_vm_row() {
    /usr/bin/jq -r "$agentvm_jq_defs"' [.runningVMs.count, .runningVMs.limit] | row'
}

# -- Jobs: starting and stopping a box without waiting for it ----------------------------
# A start takes 10 to 30 seconds and a stop a few, longer than a handler may wait, so the window
# that only shows boxes runs them as agent-vm jobs: detached processes that outlive the handler
# and the window, with their records in agent-vm's store, where `status` shows them to Cadabra,
# to the AgentVM app and to Terminal alike.

# agentvm_valid_job_id <id>  ->  0 when it has the form of a job id (digits, the hex digits a to
# f and "-", starting with a digit, as in 20261001-094934-a1b2c3). Checked because an id comes
# back from agent-vm and is kept on a pasteboard.
agentvm_valid_job_id() {
    case "$1" in
        [0123456789]*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *[!0123456789abcdef-]*) return 1 ;;
    esac
    [ "${#1}" -le 40 ]
}

# _agentvm_job_start <agent-vm args...>  ->  the new job's id on stdout, and agent-vm's status.
# `job start` checks the command before the job starts, so a refusal comes back here; what the
# command itself finds (an unknown box, no free slot) fails the job in the background.
# --json belongs before the "--": after it, everything is the job's command.
_agentvm_job_start() {
    /bin/rm -f "$agentvm_err_file"
    local _json
    _json="$(agentvm_run job start --json -- "$@" 2>"$agentvm_err_file")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        return "$_status"
    fi
    /bin/rm -f "$agentvm_err_file"
    local _id="$(printf '%s\n' "$_json" | /usr/bin/jq -r '.id // empty' 2>/dev/null)"
    if ! agentvm_valid_job_id "$_id"; then
        _agentvm_refuse 1 "agent-vm started a job and did not say which."
        return $?
    fi
    printf '%s\n' "$_id"
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
        _agentvm_job_start box start "$1" --owner-pid "$_owner"
        return $?
    fi
    _agentvm_job_start box start "$1"
}

# agentvm_box_stop_job <box>  ->  the job id. A clean shutdown of the guest takes a few seconds.
agentvm_box_stop_job() {
    _agentvm_need_name box "$1" || return $?
    _agentvm_job_start box stop "$1"
}

# -- The AgentVM app ---------------------------------------------------------------------
# Cadabra uses boxes and shows which run; installing and updating agent-vm, building images,
# making, changing and deleting boxes belong to the AgentVM app, which Cadabra opens at the
# right place through the app's agentvm:// links. A link only shows; it changes nothing.

# agentvm_app_open [box name]  ->  0 once the AgentVM app was asked to open, with that box
# selected when one is given; otherwise the status of /usr/bin/open, which fails when no
# application on this Mac answers agentvm:// links (the app is not installed).
# CADABRA_OPEN is the test seam for /usr/bin/open.
agentvm_app_open() {
    local _link="agentvm://status"
    if [ -n "${1:-}" ]; then
        _agentvm_need_name box "$1" || return $?
        _link="agentvm://box/$1"
    fi
    "${CADABRA_OPEN:-/usr/bin/open}" "$_link" 2>"$agentvm_err_file"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        _agentvm_refuse "$_status" "The AgentVM app is not on this Mac. Get it from $agentvm_app_page."
        return "$_status"
    fi
    /bin/rm -f "$agentvm_err_file"
    return 0
}

# agentvm_app_show [box name]  ->  0 once the AgentVM app was asked to open. When it is not on
# this Mac, an alert says so and offers its download page; 1 then. For a button or an alert's
# answer that sends the user to the app.
agentvm_app_show() {
    agentvm_app_open "${1:-}"
    local _status=$?
    if [ "$_status" -eq 0 ]; then
        return 0
    fi
    agentvm_last_error "$_status" >/dev/null
    "$alert" --level caution --title "The AgentVM app is not on this Mac" --ok "Open the Download Page" --cancel "Cancel" \
        "The AgentVM app installs agent-vm and makes the images and boxes that Cadabra runs agents and tools in."
    if [ $? -eq 0 ]; then
        "${CADABRA_OPEN:-/usr/bin/open}" "$agentvm_app_page"
    fi
    return 1
}

# -- Starting a box and waiting for it, programs in it, and its secrets ------------------

# agentvm_box_start <box>  ->  0 once the box is ready, after waiting for it (10-16 s from
# stopped). For a chat window's start, which shows its own progress and cannot go on without the
# box; the AgentVM Boxes window starts boxes as jobs. A box that already runs is left as it is; one
# that is starting (a job, say) is waited for, and one that is stopping is waited for and
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

# agentvm_box_exec <box> <program> [args...]  ->  the program's own output and status, run in the
# running box with no project shared: for work in the box user's own folders, such as copying
# Cadabra's tools there. Standard input and output pass through; agent-vm's stderr (and the
# program's) is kept for agentvm_last_error. Status 125 is agent-vm's own failure (the box is
# not running, say), anything else the program's.
agentvm_box_exec() {
    _agentvm_need_name box "$1" || return $?
    local _box="$1"
    shift
    /bin/rm -f "$agentvm_err_file"
    agentvm_run exec --box "$_box" -- "$@" 2>"$agentvm_err_file"
    local _status=$?
    if [ "$_status" -eq 0 ]; then
        /bin/rm -f "$agentvm_err_file"
    fi
    return "$_status"
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
        printf '# Written by Cadabra: a shell in the box %s. Safe to delete.\n' "$1"
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

# -- Sessions: a project's snapshot, what changed since, undo --------------------------
# A session needs no virtual machine: agent-vm clones the project folder on this Mac (APFS
# copy-on-write) into its store, so the project must be on the store's volume. One session per
# project is active at a time. Rows as agentvm_json.py's "sessions" and "report-summary" document
# them; failures leave agent-vm's message for agentvm_last_error, as everywhere in this file.

# agentvm_valid_session_id <id>  ->  0 when <id> has the shape of agent-vm's session ids
# ("20260930-213838-ad78": digits, lower-case hex letters and "-", starting with a digit), so it
# can be passed as an argument and never read as an option.
agentvm_valid_session_id() {
    case "$1" in
        [0123456789]*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *[!0123456789abcdef-]*) return 1 ;;
    esac
    return 0
}

# _agentvm_need_session <id>  ->  0, or 2 with the reason left for agentvm_last_error.
_agentvm_need_session() {
    agentvm_valid_session_id "$1" && return 0
    _agentvm_refuse 2 "\"$1\" is not an AgentVM session id."
}

# agentvm_session_start <project>  ->  the new session's row. Refused by agent-vm when the project
# is the home folder or holds it, is on another volume, or already has an active session.
agentvm_session_start() {
    case "$1" in
        /*) ;;
        *) _agentvm_refuse 2 "The project must be an absolute path, not \"$1\"."
           return 2 ;;
    esac
    agentvm_rows sessions session start --project "$1"
}

# agentvm_sessions  ->  every session's row, oldest first.
agentvm_sessions() {
    agentvm_rows sessions session list
}

# agentvm_session_end <id>  ->  the session's row once it is ended: its snapshot is kept for undo,
# and its project may have a new session.
agentvm_session_end() {
    _agentvm_need_session "$1" || return $?
    agentvm_rows sessions session end "$1"
}

# agentvm_session_discard <id>  ->  the session's row once its snapshot is deleted; undo is no
# longer possible. agent-vm ends an active session first.
agentvm_session_discard() {
    _agentvm_need_session "$1" || return $?
    agentvm_rows sessions session discard "$1"
}

# agentvm_session_summary <id>  ->  one row: what the project changed since the snapshot. Walks
# the project folder (quick for unchanged files, which agent-vm tells by their status-change time),
# so it is for a refresh after a message, not for a poll.
agentvm_session_summary() {
    _agentvm_need_session "$1" || return $?
    agentvm_rows report-summary session report "$1"
}

# agentvm_session_changes <id>  ->  one row per change, flagged first (agentvm_json.py "changes").
agentvm_session_changes() {
    _agentvm_need_session "$1" || return $?
    agentvm_rows changes session report "$1"
}

# agentvm_session_undo <id> [path...]  ->  one row, what was put back (agentvm_json.py "undo").
# With paths (relative to the project, as the report names them), only those entries and what is
# under them; otherwise every change. Each path goes as --path=<path>, so one that starts with "-"
# is still a value. What the session left is moved into the session's folder, never deleted.
agentvm_session_undo() {
    _agentvm_need_session "$1" || return $?
    local _id="$1"
    shift
    local _path _count=0
    for _path in "$@"; do
        set -- "$@" "--path=$_path"
        _count=$((_count + 1))
    done
    shift "$_count"
    agentvm_rows undo session undo "$_id" "$@"
}

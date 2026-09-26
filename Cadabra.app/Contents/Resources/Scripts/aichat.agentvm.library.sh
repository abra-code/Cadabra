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
#     working tree without a redeploy while the two change together;
#   - the embedded Contents/Support/AgentVM/agent-vm, built by update-cadabra.sh. agent-vm-guest
#     sits next to it, because agent-vm installs the guest daemon into images from there.
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

# 0.2.0: `box status` and `version --json` (0.1.6), progress events under --json (0.1.8), a clean
# cancel (0.1.9), permission prompts in the exec log (0.1.10), disposable boxes with an owner
# lease (0.1.11) and secrets (0.2.0). The Box Manager relies on all of them.
AGENTVM_MIN_VERSION="0.2.0"
AGENTVM_MIN_MACOS="27"

agentvm_embedded="$OMC_APP_BUNDLE_PATH/Contents/Support/AgentVM/agent-vm"
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

# agentvm_origin  ->  test, developer or embedded: where agentvm_bin's answer comes from.
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
    echo "embedded"
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
    printf '%s\n' "$agentvm_embedded"
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
                *)  printf 'The developer setting /developer/agent-vm is "%s", which is not an absolute path. Fix it, or clear it to use the agent-vm inside Cadabra.\n' "$1"
                    return 0 ;;
            esac
            if [ ! -f "$1" ] || [ ! -x "$1" ]; then
                printf 'The developer setting /developer/agent-vm points at %s, which is not an executable file. Build agent-vm there, or clear the setting to use the agent-vm inside Cadabra.\n' "$1"
            fi ;;
        test)
            if [ ! -f "$1" ] || [ ! -x "$1" ]; then
                printf 'CADABRA_AGENT_VM is %s, which is not an executable file.\n' "$1"
            fi ;;
        *)
            if [ ! -f "$1" ] || [ ! -x "$1" ]; then
                printf 'This copy of Cadabra has no agent-vm (%s is missing). Reinstall Cadabra.\n' "$1"
            fi ;;
    esac
}

# agentvm_version_reason <path> <origin> <output of --version> <its status>
#   ->  why that agent-vm is unusable, or nothing.
agentvm_version_reason() {
    # One line: the reason goes into an alert, and a crashing binary can print several.
    local _output="$(printf '%s' "$3" | /usr/bin/tr '\n' ' ')"
    local _fix="Reinstall Cadabra."
    if [ "$2" = "developer" ]; then
        _fix="Rebuild it, or clear the developer setting /developer/agent-vm to use the agent-vm inside Cadabra."
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
# an alert, and returns 1. Checked before any other call, and before a "where it runs" picker
# offers anything but This Mac.
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
        return 1
    fi
    local _version
    _version="$(agentvm_run --version 2>&1)"
    local _status=$?
    _reason="$(agentvm_version_reason "$_bin" "$_origin" "$_version" "$_status")"
    if [ -n "$_reason" ]; then
        printf '%s\n' "$_reason"
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
# project, projectReadOnly, activeExecs, guestVersion, guestFeatures, image, statusError.
#
# Never starts or stops anything (agent-vm 0.1.6's `box status`), so it is safe to poll, but a
# supervisor that does not answer can hold it up for about 7 seconds (agent-vm's BoxStatus.of:
# 2 s for the socket to appear, 5 s for the answer). state is stopped, starting, ready,
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
# recipe, created, guestVersion, cpus, memoryGB, diskGB, path, needKinds.
agentvm_images() {
    agentvm_rows images image list
}

# agentvm_boxes  ->  one row per box: name, state, image, network, cpus, memoryGB, ownSize, pid,
# project, projectReadOnly, activeExecs, disposable, ownerPid, startedAt, supervisorVersion,
# path, netMode, rules. Like `box status`, listing never starts or stops anything; it does
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

# agentvm_box_delete <box>  ->  0 once the box and its disk are gone. agent-vm refuses a
# running box, with a message saying to stop it first.
agentvm_box_delete() {
    _agentvm_need_name box "$1" || return $?
    agentvm_json box delete "$1" >/dev/null
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

# agentvm_vm_slot_free  ->  0 when another macOS virtual machine can start on this Mac;
# otherwise 1, with doctor's explanation (how many run, the limit) for agentvm_last_error.
# macOS runs at most two macOS guests at once, counting every application's, and agent-vm
# would only find out a minute into a start. Doctor's "running VMs" check says "warning" when
# the limit is reached, and "info" when it could not count: that is not a reason to refuse.
agentvm_vm_slot_free() {
    local _rows
    _rows="$(agentvm_doctor)"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        # Doctor itself failed: let the start go ahead and fail with agent-vm's own reason.
        /bin/rm -f "$agentvm_err_file"
        return 0
    fi
    local _full="$(printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' '$1 == "running VMs" && $2 == "warning" { print $3 }')"
    if [ -n "$_full" ]; then
        _agentvm_refuse 1 "No virtual machine slot is free: $_full. Stop a box or another virtual machine first."
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
# box; the Box Manager starts boxes as jobs. A box that already runs is left as it is, and one
# that is starting (a Box Manager job, say) is waited for: neither is slot-checked, since each
# already holds its virtual machine slot and would count against itself.
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
        ready)    return 0 ;;
        starting) ;;
        *)        agentvm_vm_slot_free || return $? ;;
    esac
    local _owner="$(_agentvm_owner_pid)"
    if [ -n "$_owner" ]; then
        agentvm_json box start "$1" --owner-pid "$_owner" >/dev/null
        return $?
    fi
    agentvm_json box start "$1" >/dev/null
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

# agentvm_secrets  ->  one row per Keychain secret agent-vm keeps: name, readable (names only;
# agent-vm never prints a value).
agentvm_secrets() {
    agentvm_rows secrets secret list
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

# The recipes Cadabra ships (copies of agent-vm's, see Recipes/README.md), one folder each.
agentvm_recipes_dir="$OMC_APP_BUNDLE_PATH/Contents/Resources/Recipes"

# agentvm_recipes  ->  one row per shipped recipe: folder name, path of its recipe.json,
# description. Sorted by folder name (byte order, on the name alone: the glob's own order puts
# "xcode-platforms/" before "xcode/"); a folder whose recipe cannot be read is left out.
agentvm_recipes() {
    local _recipe _row
    for _recipe in "$agentvm_recipes_dir"/*/recipe.json; do
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
                *) _agentvm_refuse 2 "The restore image must be the full path of an .ipsw file, not \"$_source\"."
                   return 2 ;;
            esac
            if [ ! -f "$_source" ]; then
                _agentvm_refuse 2 "The restore image $_source does not exist."
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

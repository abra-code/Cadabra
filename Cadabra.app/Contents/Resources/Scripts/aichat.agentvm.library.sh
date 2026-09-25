#!/bin/sh
# aichat.agentvm.library.sh
#
# The only file in Cadabra that runs agent-vm, the tool that makes and runs macOS virtual
# machines ("boxes") for agents and their tools. Everything that needs an image, a box or a
# running program in one goes through the functions here, so there is one place that knows
# which agent-vm binary is in use, how to read its answers, and how its failures reach the user.
# The design is AIChatApp/Private/agent-vm-integration-plan.md (D1, D3).
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

# 0.1.6 added `box status` (no side effects) and `version --json`, which this library relies on.
AGENTVM_MIN_VERSION="0.1.6"
AGENTVM_MIN_MACOS="27"

agentvm_embedded="$OMC_APP_BUNDLE_PATH/Contents/Support/AgentVM/agent-vm"
agentvm_python="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
agentvm_json_py="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/agentvm_json.py"

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

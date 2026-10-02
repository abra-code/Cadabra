#!/bin/sh
# aichat.agent.keys.library.sh
# The Keys window (aichat.agent.keys.json), opened from Select ACP Agent for an agent set to run
# in an agent-vm box: the keys the catalog says the agent can use, whether AgentVM keeps each in
# the login Keychain, storing and removing them, which one the agent gets (acp_agent_secret), and
# a shell in a kept box for logging in there instead.
#
# VALUES. A key's value exists in two places only: the SecureField, whose value OMC exports to
# every handler of this window while it holds one (so Store clears the field at once, and this
# library takes it out of the environment), and the pipe from the shell's builtin printf into
# `agent-vm secret set`. It is never an argument,
# never echoed, never written to a file or a setting.
#
# CONTEXT. Select ACP Agent's Keys... handler leaves "<agent id><TAB><run-in>" in
# KEYS_REQUEST_KEY and opens this window; init moves it to a key of this window's own, since
# two Keys windows can be open. The run-in is the Runs in picker's value when Keys... was pressed,
# stored or not: it names the box a login would go into.

[ -n "${__AICHAT_AGENT_KEYS_LIB:-}" ] && return 0
__AICHAT_AGENT_KEYS_LIB=1

# The pasted value, taken out of the environment before any program runs: every process a
# handler starts inherits it otherwise, and `agent-vm box start` (Open a Shell) leaves a box
# supervisor running with that environment for as long as the box runs. Only Store reads it.
keys_pasted_value="${OMC_ACTIONUI_VIEW_702_VALUE-}"
unset OMC_ACTIONUI_VIEW_702_VALUE

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.acp.agents.library.sh"
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agentvm.library.sh"

KEYS_INTRO_ID=700
KEYS_TABLE_ID=701
KEYS_VALUE_ID=702
KEYS_STORE_ID=703
KEYS_REMOVE_ID=704
KEYS_USE_ID=705
# How to get the selected key (the catalog's hint), under the value field.
KEYS_HINT_ID=706
KEYS_LOGIN_TEXT_ID=710
KEYS_LOGIN_BUTTON_ID=711
KEYS_STATUS_ID=720

KEYS_REQUEST_KEY="cadabra_agent_keys_request"

keys_tab="$(printf '\t')"

# keys_context_key <uuid>  ->  the pasteboard key holding this window's "<agent id><TAB><run-in>".
keys_context_key() {
    printf 'cadabra_agent_keys_%s\n' "$1"
}

# keys_context <uuid>  ->  sets keys_agent and keys_run_in from the window's context; 1 when there
# is none (the window was not opened from Select ACP Agent, or it is closing).
keys_context() {
    local _context="$("$pasteboard" "$(keys_context_key "$1")" get)"
    keys_agent="$(printf '%s\n' "$_context" | /usr/bin/cut -f1)"
    keys_run_in="$(printf '%s\n' "$_context" | /usr/bin/cut -f2)"
    if [ -z "$keys_agent" ]; then
        return 1
    fi
    return 0
}

# keys_catalog_keys <agent id>  ->  "<variable><TAB><label><TAB><hint>" per key the agent can use;
# an absent label or hint is "-".
keys_catalog_keys() {
    "$acp_python" "$acp_catalog_py" box-keys "$1" 2>/dev/null
}

# keys_catalog_login <agent id>  ->  the catalog's hint for logging in inside a kept box, or nothing.
keys_catalog_login() {
    "$acp_python" "$acp_catalog_py" box-login "$1" 2>/dev/null
}

# keys_agent_label <agent id>  ->  the catalog's name for the agent, else the id.
keys_agent_label() {
    local _label="$(acp_agent_catalog | /usr/bin/awk -F'\t' -v id="$1" '$1 == id { print $2; exit }')"
    printf '%s\n' "${_label:-$1}"
}

# keys_agent_has_keys <agent id>  ->  0 when the Keys window has something to offer for the agent
# in a box: a key it can use, or a way to log in inside one.
keys_agent_has_keys() {
    local _keys="$(keys_catalog_keys "$1")"
    if [ -n "$_keys" ]; then
        return 0
    fi
    local _login="$(keys_catalog_login "$1")"
    [ -n "$_login" ]
}

# keys_label_of <agent id> <variable>  ->  the key's label, else the variable itself.
keys_label_of() {
    local _label="$(keys_catalog_keys "$1" | /usr/bin/awk -F'\t' -v name="$2" '$1 == name { print $2; exit }')"
    if [ -z "$_label" ] || [ "$_label" = "-" ]; then
        _label="$2"
    fi
    printf '%s\n' "$_label"
}

# keys_status <uuid> <text>  ->  the status line under the window.
keys_status() {
    "$dialog" "$1" "$KEYS_STATUS_ID" "$2"
}

# keys_json_string <text>  ->  the text as a JSON string, quotes included. Labels come from the
# catalog; a double quote becomes a single one and a backslash a slash, rather than being
# escaped, since no label needs either.
keys_json_string() {
    printf '%s\n' "$1" | /usr/bin/awk '{ gsub(/"/, "\047"); gsub(/\\/, "/"); gsub(/\t/, " "); s = s (NR > 1 ? " " : "") $0 } END { printf "\"%s\"", s }'
}

# keys_paint <uuid>  ->  the table, the choice and the intro, from the catalog, the Keychain as
# `agent-vm secret list` reports it (names only) and the stored choice. Leaves the Store and
# Remove buttons off: a row has to be selected again, since the rows were replaced.
keys_paint() {
    local _uuid="$1"
    keys_context "$_uuid" || return 1
    local _label="$(keys_agent_label "$keys_agent")"
    local _keys="$(keys_catalog_keys "$keys_agent")"
    local _kept
    _kept="$(agentvm_secrets)"
    local _kept_status=$?
    local _unknown=no
    if [ "$_kept_status" -ne 0 ]; then
        _unknown=yes
        keys_status "$_uuid" "Could not read which keys AgentVM keeps: $(agentvm_last_error "$_kept_status")"
    fi
    local _chosen="$(acp_agent_secret "$keys_agent")"

    local _rows="" _options="$(printf '[{"title":"No key","tag":"none"}')"
    local _name _key_label _hint _state _readable _found=no
    if [ "$_chosen" = "none" ]; then
        _found=yes
    fi
    while IFS="$keys_tab" read -r _name _key_label _hint; do
        [ -n "$_name" ] || continue
        if [ "$_key_label" = "-" ]; then
            _key_label="$_name"
        fi
        if [ "$_unknown" = "yes" ]; then
            _state="Unknown"
        else
            _readable="$(printf '%s\n' "$_kept" | /usr/bin/awk -F'\t' -v name="$_name" '$1 == name { print $2; exit }')"
            case "$_readable" in
                true) _state="Stored" ;;
                '')   _state="Not stored" ;;
                *)    _state="Stored; macOS asks first" ;;
            esac
        fi
        _rows="$_rows$_key_label$keys_tab$_name$keys_tab$_state
"
        _options="$_options,{\"title\":$(keys_json_string "$_key_label"),\"tag\":\"$_name\"}"
        if [ "$_name" = "$_chosen" ]; then
            _found=yes
        fi
    done <<EOF
$_keys
EOF
    # A stored choice the agent does not use (an older catalog) stays visible rather than
    # reading as "No key"; one that cannot be read is named as such. Chat init refuses both.
    if [ "$_found" = "no" ]; then
        if [ "$_chosen" != "damaged" ] && acp_agent_valid_secret_name "$_chosen"; then
            _options="$_options,{\"title\":\"$_chosen (not used by this agent)\",\"tag\":\"$_chosen\"}"
        else
            _options="$_options,{\"title\":\"Setting not readable\",\"tag\":\"damaged\"}"
            _chosen="damaged"
        fi
    fi
    _options="$_options]"

    "$dialog" "$_uuid" omc_window "Keys for $_label"
    if [ -n "$_keys" ]; then
        "$dialog" "$_uuid" "$KEYS_INTRO_ID" markdown "**$_label** can use one of these keys in an AgentVM box. AgentVM keeps them in your login Keychain by variable name, so agents that use the same variable share one key."
    else
        "$dialog" "$_uuid" "$KEYS_INTRO_ID" markdown "Cadabra knows no key **$_label** takes. It can still log in inside a kept AgentVM box."
    fi
    printf '%s' "$_rows" | "$dialog" "$_uuid" "$KEYS_TABLE_ID" omc_table_set_rows_from_stdin
    "$dialog" "$_uuid" "$KEYS_TABLE_ID" omc_deselect
    "$dialog" "$_uuid" "$KEYS_VALUE_ID" omc_disable
    "$dialog" "$_uuid" "$KEYS_HINT_ID" ""
    "$dialog" "$_uuid" "$KEYS_STORE_ID" omc_disable
    "$dialog" "$_uuid" "$KEYS_REMOVE_ID" omc_disable
    "$dialog" "$_uuid" "$KEYS_USE_ID" omc_set_property options "$_options"
    "$dialog" "$_uuid" "$KEYS_USE_ID" "$_chosen"
    if [ -n "$_keys" ]; then
        "$dialog" "$_uuid" "$KEYS_USE_ID" omc_enable
    else
        "$dialog" "$_uuid" "$KEYS_USE_ID" omc_disable
    fi
    return 0
}

# keys_paint_login <uuid>  ->  the login part: a shell in the kept box the agent runs in, or why
# there is none.
keys_paint_login() {
    local _uuid="$1"
    keys_context "$_uuid" || return 1
    local _hint="$(keys_catalog_login "$keys_agent")"
    local _text
    case "$keys_run_in" in
        box:?*)
            local _box="${keys_run_in#box:}"
            if agentvm_valid_name "$_box"; then
                _text="Opens Terminal with a shell in the kept AgentVM box $_box, starting the box first if it is stopped. A login made there stays in $_box for later sessions."
                if [ -n "$_hint" ]; then
                    _text="$_text In the shell: $_hint"
                fi
                "$dialog" "$_uuid" "$KEYS_LOGIN_TEXT_ID" "$_text"
                "$dialog" "$_uuid" "$KEYS_LOGIN_BUTTON_ID" omc_set_property title "Open a Shell in $_box"
                "$dialog" "$_uuid" "$KEYS_LOGIN_BUTTON_ID" omc_enable
                return 0
            fi ;;
        new:?*)
            _text="The agent runs in a new disposable AgentVM box for each conversation, and a login made in one is deleted with it. To log in, choose a kept box in Runs in, or make one in the AgentVM app." ;;
        *)
            _text="The agent runs on this Mac, where it uses its own login." ;;
    esac
    "$dialog" "$_uuid" "$KEYS_LOGIN_TEXT_ID" "$_text"
    "$dialog" "$_uuid" "$KEYS_LOGIN_BUTTON_ID" omc_disable
    return 0
}

# keys_hint_of <agent id> <variable>  ->  how to get the key, or nothing.
keys_hint_of() {
    keys_catalog_keys "$1" | /usr/bin/awk -F'\t' -v name="$2" '$1 == name && $3 != "-" { print $3; exit }'
}

# keys_is_agent_key <agent id> <variable>  ->  0 when the catalog lists the variable for the agent.
keys_is_agent_key() {
    local _found="$(keys_catalog_keys "$1" | /usr/bin/awk -F'\t' -v name="$2" '$1 == name { print "yes"; exit }')"
    [ -n "$_found" ]
}

# keys_trim <value>  ->  the value less leading and trailing blanks and line ends. A pasted key
# often carries a trailing space or line end, and a key with one does not work. Builtins only,
# so the value is never an argument of a process.
keys_trim() {
    local _value="$1"
    while :; do
        case "$_value" in
            [[:space:]]*) _value="${_value#?}" ;;
            *) break ;;
        esac
    done
    while :; do
        case "$_value" in
            *[[:space:]]) _value="${_value%?}" ;;
            *) break ;;
        esac
    done
    printf '%s' "$_value"
}

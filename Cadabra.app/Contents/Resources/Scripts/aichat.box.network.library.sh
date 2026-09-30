#!/bin/sh
# aichat.box.network.library.sh
# The AgentVM Box Network window (aichat.box.network.json), opened with Network... on a chat
# window's box line: the hosts programs in the window's AgentVM box tried to reach since the
# agent started, refused ones first, and "Allow in This Box", which adds a rule to the box's
# network at once (agent-vm box network --allow), so the agent's next try gets through.
#
# CONTEXT. The chat window's Network... handler leaves the chat window's id in
# BOXNET_REQUEST_KEY and opens this window; init moves it to a key of this window's own, since a
# Network window can be open for each chat window. The box and the moment the agent started are
# read from the chat window's box line stamp each time (boxsession_line_show), so a chat window
# that has closed, and so released its box, leaves this window with nothing to show.
#
# HOST NAMES COME FROM THE BOX. The network log records what programs in the box asked for, so a
# host is whatever they wrote. A rule is built only from a plain host name and a port, and the
# user confirms it before it is added.

[ -n "${__AICHAT_BOX_NETWORK_LIB:-}" ] && return 0
__AICHAT_BOX_NETWORK_LIB=1

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxsession.library.sh"

BOXNET_HEADER_ID=800
BOXNET_TABLE_ID=801
BOXNET_ALLOW_ID=802
BOXNET_REFRESH_ID=804
BOXNET_STATUS_ID=806
BOXNET_ALLOW_AGENT_ID=803
BOXNET_SAVED_TEXT_ID=807
BOXNET_SAVED_TABLE_ID=808
BOXNET_SAVED_REMOVE_ID=809
BOXNET_SAVED_ROW_ID=810

BOXNET_REQUEST_KEY="cadabra_box_network_request"

boxnet_tab="$(printf '\t')"

# boxnet_context_key <uuid>  ->  the pasteboard key holding this window's chat window id.
boxnet_context_key() {
    printf 'cadabra_box_network_%s\n' "$1"
}

# boxnet_context <uuid>  ->  sets boxnet_chat, boxnet_box, boxnet_since, boxnet_agent and
# boxnet_agent_label from the window's context and the chat window's box line stamp; 1 when there
# is none (the window was not opened from a chat window, or that window's box has been
# released). boxnet_agent_label is empty for an agent that cannot have hosts saved for it (a
# typed command, or an agent neither the catalog nor the saved agents name).
boxnet_context() {
    boxnet_chat="$("$pasteboard" "$(boxnet_context_key "$1")" get)"
    boxnet_box=""
    boxnet_since=""
    boxnet_agent=""
    boxnet_agent_label=""
    if [ -z "$boxnet_chat" ]; then
        return 1
    fi
    local _stamp="$(pb_get "aichatv2_boxline_$boxnet_chat")"
    if [ -z "$_stamp" ]; then
        return 1
    fi
    boxnet_box="${_stamp%%"$boxnet_tab"*}"
    local _rest="${_stamp#*"$boxnet_tab"}"
    boxnet_since="${_rest%%"$boxnet_tab"*}"
    boxnet_agent="$(pb_get "aichatv2_boxagent_$boxnet_chat")"
    if [ -n "$boxnet_agent" ] && [ "$boxnet_agent" != "custom" ]; then
        boxnet_agent_label="$(acp_agent_label_for "$boxnet_agent")"
    fi
    return 0
}

# The awk program behind boxnet_rule and boxnet_rows.
boxnet_awk="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.box.network.awk"

# boxnet_rule <host> <port> <method>  ->  the allow rule for one connection, or "-" when the host
# is not a plain host name (see aichat.box.network.awk).
boxnet_rule() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" | /usr/bin/awk -F'\t' -v mode=rule -f "$boxnet_awk"
}

# boxnet_rows <box> <since>  ->  one row per host, port and outcome since <since>, refused first,
# then failed, then reached, each kind with the most recent first:
#   host, port, outcome (a stop sign for refused, a warning sign for failed, a check mark for
#   reached), connections, why (the reason, or the rule that allowed it),
#   rule (for Allow; "-" when there is none), decision (allowed, denied or failed)
# agent-vm's status on failure, with its reason left for agentvm_last_error.
boxnet_rows() {
    local _rows
    _rows="$(agentvm_netlog "$1" "$boxsession_line_netlog_last")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        return "$_status"
    fi
    printf '%s\n' "$_rows" | /usr/bin/awk -F'\t' -v mode=rows -v since="$2" -f "$boxnet_awk" \
        | /usr/bin/sort -t "$boxnet_tab" -k1,1n -k2,2r | /usr/bin/cut -f3-
}

# boxnet_status <uuid> <text>  ->  the line under the buttons.
boxnet_status() {
    "$dialog" "$1" "$BOXNET_STATUS_ID" "$2"
}

# boxnet_paint <uuid>  ->  0. The header and the table from the box's network log; with no box
# to show, says why and leaves the table empty.
boxnet_paint() {
    local _uuid="$1"
    "$dialog" "$_uuid" "$BOXNET_ALLOW_ID" omc_disable
    "$dialog" "$_uuid" "$BOXNET_ALLOW_AGENT_ID" omc_disable
    boxnet_context "$_uuid"
    local _have=$?
    if [ "$_have" -ne 0 ]; then
        "$dialog" "$_uuid" "$BOXNET_HEADER_ID" "No AgentVM box to show. Open this window with Network... under the model button of a chat window whose agent runs in an AgentVM box."
        printf '' | "$dialog" "$_uuid" "$BOXNET_TABLE_ID" omc_table_set_rows_from_stdin
        "$dialog" "$_uuid" "$BOXNET_REFRESH_ID" omc_disable
        boxnet_paint_saved "$_uuid"
        return 0
    fi
    boxnet_paint_saved "$_uuid"
    local _started="$(TZ=UTC /bin/date -j -f '%Y-%m-%dT%H:%M:%SZ' "$boxnet_since" '+%s' 2>/dev/null)"
    local _when="$boxnet_since"
    if [ -n "$_started" ]; then
        _when="$(/bin/date -r "$_started" '+%H:%M')"
    fi
    "$dialog" "$_uuid" "$BOXNET_HEADER_ID" "Connections programs in AgentVM box $boxnet_box made since the agent started at $_when. A refused host can be allowed in this box: the rule takes effect at once, and the agent's next try gets through."
    local _rows
    _rows="$(boxnet_rows "$boxnet_box" "$boxnet_since")"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        printf '' | "$dialog" "$_uuid" "$BOXNET_TABLE_ID" omc_table_set_rows_from_stdin
        boxnet_status "$_uuid" "Could not read the network log: $(agentvm_last_error "$_status")"
        return 0
    fi
    printf '%s\n' "$_rows" | /usr/bin/awk 'NF > 0' | "$dialog" "$_uuid" "$BOXNET_TABLE_ID" omc_table_set_rows_from_stdin
    "$dialog" "$_uuid" "$BOXNET_REFRESH_ID" omc_enable
    if [ -z "$_rows" ]; then
        boxnet_status "$_uuid" "No connections yet. A connection is logged when it ends, so one still open shows up when it closes."
    else
        boxnet_status "$_uuid" ""
    fi
    return 0
}

# boxnet_paint_saved <uuid>  ->  0. "Allow for <agent>..." and the hosts saved for the agent,
# shown when boxnet_context found an agent that can have hosts saved for it, hidden otherwise.
# Call after boxnet_context.
boxnet_paint_saved() {
    local _uuid="$1"
    local _id
    "$dialog" "$_uuid" "$BOXNET_SAVED_REMOVE_ID" omc_disable
    if [ -z "$boxnet_agent_label" ]; then
        for _id in $BOXNET_ALLOW_AGENT_ID $BOXNET_SAVED_TEXT_ID $BOXNET_SAVED_ROW_ID; do
            "$dialog" "$_uuid" "$_id" omc_hide
        done
        return 0
    fi
    "$dialog" "$_uuid" "$BOXNET_ALLOW_AGENT_ID" omc_set_property title "Allow for $boxnet_agent_label..."
    local _rules="$(acp_agent_allowed "$boxnet_agent")"
    if [ -z "$_rules" ]; then
        "$dialog" "$_uuid" "$BOXNET_SAVED_TEXT_ID" "No hosts allowed for $boxnet_agent_label in every new disposable AgentVM box yet, besides those it comes with. Allow for $boxnet_agent_label... adds one."
    else
        "$dialog" "$_uuid" "$BOXNET_SAVED_TEXT_ID" "Allowed for $boxnet_agent_label in every new disposable AgentVM box, besides the hosts it comes with:"
    fi
    printf '%s\n' "$_rules" | /usr/bin/awk 'NF > 0' | "$dialog" "$_uuid" "$BOXNET_SAVED_TABLE_ID" omc_table_set_rows_from_stdin
    # Remove... is off now, so the selection goes too: setting the rows keeps a row that is
    # still there selected, and a click on a selected row fires nothing to turn Remove on.
    "$dialog" "$_uuid" "$BOXNET_SAVED_TABLE_ID" omc_deselect
    for _id in $BOXNET_ALLOW_AGENT_ID $BOXNET_SAVED_TEXT_ID $BOXNET_SAVED_ROW_ID; do
        "$dialog" "$_uuid" "$_id" omc_show
    done
    return 0
}

# boxnet_selected_rule <uuid> <host> <port> <shown rule> <decision>  ->  prints the rule to allow
# for the selected row, or returns 1: nothing for a row that is not a refusal, and a line under
# the buttons for a host no rule can be made for. The rule shown in the hidden column must be one
# boxnet_rule builds from the row's host and port, for a tunnel or for plain HTTP, which also
# checks that the host is a plain host name: the host name came from a program in the box.
boxnet_selected_rule() {
    if [ "$5" != "denied" ] || [ -z "$4" ] || [ "$4" = "-" ]; then
        return 1
    fi
    local _tunnel="$(boxnet_rule "$2" "$3" CONNECT)"
    local _http="$(boxnet_rule "$2" "$3" GET)"
    if [ "$4" != "$_tunnel" ] && [ "$4" != "$_http" ]; then
        boxnet_status "$1" "No rule can be made for this host here: it is not a plain host name, or it asked for a raw connection to port 80, which rules leave out."
        return 1
    fi
    printf '%s\n' "$4"
}

# boxnet_allow_in_box <uuid> <rule>  ->  0 once the rule is in the box's rules, printing the line
# for under the buttons that says what it changes (a box whose network is off keeps the rule
# for later but refuses everything until it is turned on, which agent-vm does only while the
# box is stopped); 1 with the reason shown under the buttons otherwise. The caller repaints
# the window before showing the printed line, since a repaint clears it.
boxnet_allow_in_box() {
    agentvm_box_allow "$boxnet_box" "$2"
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        boxnet_status "$1" "Could not allow $2: $(agentvm_last_error "$_status")"
        return 1
    fi
    local _boxes
    _boxes="$(agentvm_boxes)"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        agentvm_last_error "$_status" >/dev/null
        _boxes=""
    fi
    local _mode="$(printf '%s\n' "$_boxes" | /usr/bin/awk -F'\t' -v box="$boxnet_box" '$1 == box { print $17; exit }')"
    if [ "$_mode" = "off" ]; then
        printf '%s\n' "Allowed $2 in AgentVM box $boxnet_box, but the box's network is off, so nothing gets through until it is turned on in Tools > AgentVM while the box is stopped."
    else
        printf '%s\n' "Allowed $2 in AgentVM box $boxnet_box. The agent's next try gets through; earlier refusals stay listed."
    fi
    return 0
}

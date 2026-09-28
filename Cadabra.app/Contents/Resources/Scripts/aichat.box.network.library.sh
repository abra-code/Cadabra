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

BOXNET_REQUEST_KEY="cadabra_box_network_request"

boxnet_tab="$(printf '\t')"

# boxnet_context_key <uuid>  ->  the pasteboard key holding this window's chat window id.
boxnet_context_key() {
    printf 'cadabra_box_network_%s\n' "$1"
}

# boxnet_context <uuid>  ->  sets boxnet_chat, boxnet_box and boxnet_since from the window's
# context and the chat window's box line stamp; 1 when there is none (the window was not opened
# from a chat window, or that window's box has been released).
boxnet_context() {
    boxnet_chat="$("$pasteboard" "$(boxnet_context_key "$1")" get)"
    boxnet_box=""
    boxnet_since=""
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
    boxnet_context "$_uuid"
    local _have=$?
    if [ "$_have" -ne 0 ]; then
        "$dialog" "$_uuid" "$BOXNET_HEADER_ID" "No AgentVM box to show. Open this window with Network... under the model button of a chat window whose agent runs in an AgentVM box."
        printf '' | "$dialog" "$_uuid" "$BOXNET_TABLE_ID" omc_table_set_rows_from_stdin
        "$dialog" "$_uuid" "$BOXNET_REFRESH_ID" omc_disable
        return 0
    fi
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

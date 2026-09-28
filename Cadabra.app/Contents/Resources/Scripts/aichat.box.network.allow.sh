#!/bin/sh
# aichat.box.network.allow.sh
# Allow in This Box...: after a confirmation, the selected refused host's rule is added to the
# box's network rules (agent-vm box network --allow), effective at once. The rule in the hidden
# column is checked against the row's host and port before use, since the host name came from a
# program in the box.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.box.network.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
# The chat window may have released its box since the rows were shown: say so, not nothing.
boxnet_context "$window_uuid"
have_box=$?
if [ "$have_box" -ne 0 ]; then
    boxnet_paint "$window_uuid"
    exit 0
fi
host="$OMC_ACTIONUI_TABLE_801_COLUMN_1_VALUE"
port="$OMC_ACTIONUI_TABLE_801_COLUMN_2_VALUE"
shown_rule="$OMC_ACTIONUI_TABLE_801_COLUMN_6_VALUE"
decision="$OMC_ACTIONUI_TABLE_801_COLUMN_7_VALUE"
if [ "$decision" != "denied" ] || [ -z "$shown_rule" ] || [ "$shown_rule" = "-" ]; then
    exit 0
fi
# The rule must be one this library builds from the row's host and port, for a tunnel or for
# plain HTTP, which also checks that the host is a plain host name.
tunnel_rule="$(boxnet_rule "$host" "$port" CONNECT)"
http_rule="$(boxnet_rule "$host" "$port" GET)"
rule="$shown_rule"
if [ "$rule" = "-" ] || { [ "$rule" != "$tunnel_rule" ] && [ "$rule" != "$http_rule" ]; }; then
    boxnet_status "$window_uuid" "No rule can be made for this host here: it is not a plain host name, or it asked for a raw connection to port 80, which rules leave out."
    exit 0
fi
"$alert" --level caution --title "Allow $rule in AgentVM box $boxnet_box?" --ok "Allow" --cancel "Cancel" \
    "Programs in the box, the agent among them, can then connect to $rule. The rule stays with the box: a kept box keeps it for later sessions, and a disposable box is deleted with it."
answer=$?
if [ "$answer" -ne 0 ]; then
    exit 0
fi
agentvm_box_allow "$boxnet_box" "$rule"
status=$?
if [ "$status" -ne 0 ]; then
    boxnet_status "$window_uuid" "Could not allow $rule: $(agentvm_last_error "$status")"
    exit 0
fi
boxnet_paint "$window_uuid"
# A box whose network is off keeps the rule for later but refuses everything until it is turned
# on, which agent-vm does only while the box is stopped.
boxes="$(agentvm_boxes)"
status=$?
if [ "$status" -ne 0 ]; then
    agentvm_last_error "$status" >/dev/null
    boxes=""
fi
mode="$(printf '%s\n' "$boxes" | /usr/bin/awk -F'\t' -v box="$boxnet_box" '$1 == box { print $17; exit }')"
if [ "$mode" = "off" ]; then
    boxnet_status "$window_uuid" "Allowed $rule in AgentVM box $boxnet_box, but the box's network is off, so nothing gets through until it is turned on in Tools > AgentVM while the box is stopped."
else
    boxnet_status "$window_uuid" "Allowed $rule in AgentVM box $boxnet_box. The agent's next try gets through; earlier refusals stay listed."
fi

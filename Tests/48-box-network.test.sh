#!/bin/sh
# Tests/48-box-network.test.sh - the AgentVM Box Network window, opened with Network... on a chat
# window's box line: the connections programs in the box made since the agent started, refused
# ones first, one row per host, port and outcome; and Allow in This Box, which adds a rule to the
# box's network after a confirmation, built only from a plain host name. agent-vm is
# fake_agent_vm.sh.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

cad_import_ids aichat.box.network.library.sh ""

FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
CADABRA_AGENT_VM="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
export CADABRA_AGENT_VM FAKE_AGENTVM_DIR
unset AGENT_VM_HOME
TAB=$(printf '\t')
LIB=aichat.box.network.library.sh
SINCE="2026-09-27T10:00:00Z"

# fake_reset - the fake with a running kept box b1 and a network log: one refusal before the
# agent started, then api.anthropic.com reached twice, a refused host on 443 and on another port,
# a refused plain-HTTP request, a failed connection, and a refused request the proxy could not
# parse (host "?").
fake_reset() {
    /bin/rm -rf "$FAKE_AGENTVM_DIR"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR"
    /bin/cp "$FIXTURES/box-status-running.json" "$FAKE_AGENTVM_DIR/box-b1.json"
    /bin/cat > "$FAKE_AGENTVM_DIR/netlog.json" <<'JSONEOF'
[
  {"decision": "denied", "host": "old.example", "method": "CONNECT", "port": 443, "reason": "not in the allowlist", "time": "2026-09-27T09:00:00Z"},
  {"decision": "allowed", "host": "api.anthropic.com", "method": "CONNECT", "port": 443, "rule": "pack:anthropic", "time": "2026-09-27T10:01:00Z"},
  {"decision": "denied", "host": "registry.npmjs.org", "method": "CONNECT", "port": 443, "reason": "not in the allowlist", "time": "2026-09-27T10:02:00Z"},
  {"decision": "allowed", "host": "api.anthropic.com", "method": "CONNECT", "port": 443, "rule": "pack:anthropic", "time": "2026-09-27T10:03:00Z"},
  {"decision": "denied", "host": "Git.Example.org", "method": "CONNECT", "port": 8443, "reason": "not in the allowlist", "time": "2026-09-27T10:04:00Z"},
  {"decision": "denied", "host": "plain.example", "method": "GET", "port": 80, "reason": "not in the allowlist", "time": "2026-09-27T10:05:00Z"},
  {"decision": "failed", "host": "down.example", "method": "CONNECT", "port": 443, "reason": "connection refused", "time": "2026-09-27T10:06:00Z"},
  {"decision": "denied", "host": "?", "method": "?", "port": 0, "reason": "not an HTTP request", "time": "2026-09-27T10:07:00Z"}
]
JSONEOF
}
fake_log() { /bin/cat "$FAKE_AGENTVM_DIR/log" 2>/dev/null; }

# open_network <window name>  ->  a Network window opened from chat window "chat1", whose box line
# stamp names box b1 and the agent's start.
open_network() {
    cad_pb_set aichatv2_boxline_chat1 "b1${TAB}$SINCE${TAB}AgentVM box b1"
    omc_window_switch "$1"
    ui_reset
    cad_pb_set cadabra_box_network_request chat1
    omc_run aichat.box.network.init
}

# select_host <host>  ->  that host's row selected, as the table reports it to the handlers.
select_host() {
    sel_row=$(ui_rows "$BOXNET_TABLE_ID" | /usr/bin/awk -F'\t' -v host="$1" '$1 == host { print; exit }')
    sel_col=1
    while [ "$sel_col" -le 7 ]; do
        omc_table_cell "$BOXNET_TABLE_ID" "$sel_col" "$(printf '%s\n' "$sel_row" | /usr/bin/cut -f"$sel_col")"
        sel_col=$((sel_col + 1))
    done
    omc_run aichat.box.network.selection.changed
}

row() { ui_rows "$BOXNET_TABLE_ID" | /usr/bin/awk -F'\t' -v host="$1" '$1 == host { print; exit }'; }
rule_of() { cad_call_lib "$LIB" boxnet_rule "$@"; }
# saved_deselects  ->  how many times this window's saved-hosts table was deselected (the harness
# journal: uuid, target, arguments), since the last ui_reset.
saved_deselects() {
    /usr/bin/awk -F'\t' -v u="$OMC_ACTIONUI_WINDOW_UUID" -v t="$BOXNET_SAVED_TABLE_ID" '$1 == u && $2 == t && index($3, "omc_deselect") == 1 { n++ } END { print n + 0 }' "$OMCTEST_UI/journal.tsv"
}

# table_deselects  ->  the same for the connections table.
table_deselects() {
    /usr/bin/awk -F'\t' -v u="$OMC_ACTIONUI_WINDOW_UUID" -v t="$BOXNET_TABLE_ID" '$1 == u && $2 == t && index($3, "omc_deselect") == 1 { n++ } END { print n + 0 }' "$OMCTEST_UI/journal.tsv"
}

section "the ids this file drives are the ones the window declares"
check "header, table, allow, refresh, status" "800 801 802 804 806" \
    "$BOXNET_HEADER_ID $BOXNET_TABLE_ID $BOXNET_ALLOW_ID $BOXNET_REFRESH_ID $BOXNET_STATUS_ID"

section "a rule is made only from a plain host name"
check "a tunnel to 443: the host"          "registry.npmjs.org" "$(rule_of registry.npmjs.org 443 CONNECT)"
check "plain HTTP to 80: the host"         "plain.example" "$(rule_of plain.example 80 GET)"
check "another port: host:port"            "git.example.org:8443" "$(rule_of Git.Example.org 8443 CONNECT)"
check "  and a raw tunnel to 80 none, which agent-vm leaves out on purpose" "-" "$(rule_of a.example 80 CONNECT)"
check "an unparsed request: none"          "-" "$(rule_of '?' 0 '?')"
check "an IP address: none"                "-" "$(rule_of 10.0.0.1 443 CONNECT)"
check "a name starting with a dash: none"  "-" "$(rule_of -rf.example 443 CONNECT)"
check "a name with a space: none"          "-" "$(rule_of 'a b.example' 443 CONNECT)"
check "agent-vm's any-public-host rule: none" "-" "$(rule_of public 443 CONNECT)"
check "a port out of range: none"          "-" "$(rule_of a.example 70000 CONNECT)"
check "a trailing dot goes, as agent-vm drops it" "example.com" "$(rule_of example.com. 443 CONNECT)"
check "a label over 63 characters: none" "-" "$(rule_of "$(printf '%064d' 0 | /usr/bin/tr 0 a).example" 443 CONNECT)"

section "opened with no chat window, the window says where it comes from"
fake_reset
omc_window_switch lonely
ui_reset
omc_run aichat.box.network.init
check "it says to use Network..."          "1" "$(cad_has "$(ui_value "$BOXNET_HEADER_ID")" 'Open this window with Network...')"
check "  shows nothing"                    "0" "$(ui_row_count "$BOXNET_TABLE_ID")"
check "  and asks agent-vm nothing"        "" "$(fake_log)"

section "the box's connections since the agent started, refused first"
fake_reset
open_network net1
check "the request is taken"               "" "$(cad_pb_get cadabra_box_network_request)"
check "the header names the box"           "1" "$(cad_has "$(ui_value "$BOXNET_HEADER_ID")" 'AgentVM box b1 made since the agent started at')"
check "the log was read from its end"      "1" "$(cad_has "$(fake_log)" 'box netlog b1 --last 999')"
check "one row per host, port and outcome, refused first, most recent first" \
    "? plain.example Git.Example.org registry.npmjs.org down.example api.anthropic.com" \
    "$(ui_rows "$BOXNET_TABLE_ID" | /usr/bin/cut -f1 | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
check "nothing from before the agent started" "" "$(row old.example)"
check "a reached host, counted"            "api.anthropic.com${TAB}443${TAB}✅${TAB}2${TAB}pack:anthropic${TAB}api.anthropic.com${TAB}allowed" "$(row api.anthropic.com)"
check "a refused one, with its rule"       "registry.npmjs.org${TAB}443${TAB}🛑${TAB}1${TAB}not in the allowlist${TAB}registry.npmjs.org${TAB}denied" "$(row registry.npmjs.org)"
check "a failed one, with its reason"      "down.example${TAB}443${TAB}⚠️${TAB}1${TAB}connection refused${TAB}down.example${TAB}failed" "$(row down.example)"
check "Allow waits for a selection"        "0" "$(ui_enabled "$BOXNET_ALLOW_ID")"

section "Allow is offered for a refused host with a rule, and only then"
select_host registry.npmjs.org
check "a refused host"                     "1" "$(ui_enabled "$BOXNET_ALLOW_ID")"
select_host api.anthropic.com
check "a reached one: no"                  "0" "$(ui_enabled "$BOXNET_ALLOW_ID")"
select_host down.example
check "a failed one: no"                   "0" "$(ui_enabled "$BOXNET_ALLOW_ID")"
select_host '?'
check "an unparsed request: no"            "0" "$(ui_enabled "$BOXNET_ALLOW_ID")"
check "  saying why"                       "1" "$(cad_has "$(ui_value "$BOXNET_STATUS_ID")" 'not a plain host name')"

section "Allow in This Box adds the rule after a confirmation"
select_host registry.npmjs.org
alerts_reset
alert_answer 1
omc_run aichat.box.network.allow
check "it asks first"                      "1" "$(alerts_mention 'Allow registry.npmjs.org in AgentVM box b1?')"
check "  and a No changes nothing"         "" "$(fake_log | /usr/bin/grep '^box network')"
alert_answer 0
omc_run aichat.box.network.allow
check "a Yes adds the rule to the box"     "box network b1 --allow registry.npmjs.org --json" "$(fake_log | /usr/bin/grep '^box network')"
check "  and says so"                      "1" "$(cad_has "$(ui_value "$BOXNET_STATUS_ID")" 'Allowed registry.npmjs.org in AgentVM box b1')"
fake_reset
open_network net2
select_host Git.Example.org
alert_answer 0
omc_run aichat.box.network.allow
check "another port is allowed by host:port" "box network b1 --allow git.example.org:8443 --json" "$(fake_log | /usr/bin/grep '^box network')"
fake_reset
open_network net3
select_host plain.example
alert_answer 0
omc_run aichat.box.network.allow
check "plain HTTP to 80 by the host"       "box network b1 --allow plain.example --json" "$(fake_log | /usr/bin/grep '^box network')"

section "Allow refuses a rule that does not match its row, and one agent-vm refuses"
fake_reset
open_network net4
select_host registry.npmjs.org
omc_table_cell "$BOXNET_TABLE_ID" 6 "public"
alerts_reset
omc_run aichat.box.network.allow
check "a hidden rule other than the row's is refused" "0|" "$(alerts_count)|$(fake_log | /usr/bin/grep '^box network')"
omc_table_cell "$BOXNET_TABLE_ID" 6 "registry.npmjs.org"
printf 'the box is being deleted\n' > "$FAKE_AGENTVM_DIR/fail-box-network"
alert_answer 0
omc_run aichat.box.network.allow
check "agent-vm's refusal is shown"        "1" "$(cad_has "$(ui_value "$BOXNET_STATUS_ID")" 'Could not allow registry.npmjs.org: the box is being deleted')"
/bin/rm -f "$FAKE_AGENTVM_DIR/fail-box-network"
alert_answers_reset

section "a box whose network is off keeps the rule, and says nothing gets through yet"
fake_reset
/bin/cat > "$FAKE_AGENTVM_DIR/box-list.json" <<'JSONEOF'
[{"box": {"image": "dev", "name": "b1", "network": {"allow": [], "mode": "off"}}, "running": true, "state": "running"}]
JSONEOF
open_network netoff
select_host registry.npmjs.org
alert_answer 0
omc_run aichat.box.network.allow
check "the rule is added"                  "box network b1 --allow registry.npmjs.org --json" "$(fake_log | /usr/bin/grep '^box network')"
check "  and the status says the network is off" "1" "$(cad_has "$(ui_value "$BOXNET_STATUS_ID")" "the box's network is off")"

section "Allow for <agent>: shown for an agent that can have hosts saved for it"
fake_reset
cad_reset
cad_pb_set aichatv2_boxagent_chat1 claude-code-acp
open_network agent1
check "the button, named for the agent"    "Allow for Claude Code (ACP adapter)..." "$(ui_prop "$BOXNET_ALLOW_AGENT_ID" title)"
check "  shown"                            "1" "$(ui_visible "$BOXNET_ALLOW_AGENT_ID")"
check "  and off until a refused host is selected" "0" "$(ui_enabled "$BOXNET_ALLOW_AGENT_ID")"
check "the saved hosts: none yet"          "1" "$(cad_has "$(ui_value "$BOXNET_SAVED_TEXT_ID")" 'No hosts allowed for Claude Code (ACP adapter) in every new disposable AgentVM box yet')"
check "  their table shown, empty"         "1|0" "$(ui_visible "$BOXNET_SAVED_ROW_ID")|$(ui_row_count "$BOXNET_SAVED_TABLE_ID")"
select_host registry.npmjs.org
check "a refused host turns it on"         "1" "$(ui_enabled "$BOXNET_ALLOW_AGENT_ID")"
select_host api.anthropic.com
check "  a reached one off"                "0" "$(ui_enabled "$BOXNET_ALLOW_AGENT_ID")"

section "Allow for <agent> adds the rule to the box and saves it for new boxes"
select_host registry.npmjs.org
alerts_reset
alert_answer 1
omc_run aichat.box.network.allow.agent
check "it asks first"                      "1" "$(alerts_mention 'Allow registry.npmjs.org for Claude Code (ACP adapter)?')"
check "  a No changes nothing"             "|" "$(fake_log | /usr/bin/grep '^box network')|$(cad_call acp_agent_allowed claude-code-acp)"
alert_answer 0
omc_run aichat.box.network.allow.agent
check "a Yes adds it to this box"          "box network b1 --allow registry.npmjs.org --json" "$(fake_log | /usr/bin/grep '^box network')"
check "  and lets go of the row, so the other Allow is one click away" "1" "$(table_deselects)"
check "  and saves it for the agent"       "registry.npmjs.org" "$(cad_call acp_agent_allowed claude-code-acp)"
check "  listed below"                     "registry.npmjs.org" "$(ui_rows "$BOXNET_SAVED_TABLE_ID")"
check "  and says both"                    "1" "$(cad_has "$(ui_value "$BOXNET_STATUS_ID")" 'Allowed registry.npmjs.org in AgentVM box b1. The agent'"'"'s next try gets through; earlier refusals stay listed. Saved for Claude Code (ACP adapter): new boxes allow it too.')"
select_host Git.Example.org
alert_answer 0
omc_run aichat.box.network.allow.agent
check "a second host joins the list"       "registry.npmjs.org git.example.org:8443" "$(cad_call acp_agent_allowed claude-code-acp | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
select_host registry.npmjs.org
alert_answer 0
omc_run aichat.box.network.allow.agent
check "the same one again is saved once"   "2" "$(cad_call acp_agent_allowed claude-code-acp | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "Allow for <agent> keeps what it saved when agent-vm refuses the box's rule"
select_host plain.example
printf 'the box is being deleted\n' > "$FAKE_AGENTVM_DIR/fail-box-network"
alert_answer 0
omc_run aichat.box.network.allow.agent
/bin/rm -f "$FAKE_AGENTVM_DIR/fail-box-network"
check "agent-vm's refusal is shown"        "1" "$(cad_has "$(ui_value "$BOXNET_STATUS_ID")" 'Could not allow plain.example: the box is being deleted')"
check "  and the saved list has the host"  "1" "$(ui_rows "$BOXNET_SAVED_TABLE_ID" | /usr/bin/grep -c '^plain.example$')"
alert_answers_reset

section "Remove stops saving a host, after a confirmation"
omc_table_cell "$BOXNET_SAVED_TABLE_ID" 1 "git.example.org:8443"
omc_run aichat.box.network.saved.selection.changed
check "a selected host turns Remove on"    "1" "$(ui_enabled "$BOXNET_SAVED_REMOVE_ID")"
alerts_reset
alert_answer 1
omc_run aichat.box.network.saved.remove
check "it asks first"                      "1" "$(alerts_mention 'Stop allowing git.example.org:8443 for Claude Code (ACP adapter)?')"
check "  a No keeps it"                    "1" "$(cad_call acp_agent_allowed claude-code-acp | /usr/bin/grep -c '^git.example.org:8443$')"
alert_answer 0
deselected="$(saved_deselects)"
omc_run aichat.box.network.saved.remove
check "a Yes removes only that one"       "registry.npmjs.org plain.example" "$(cad_call acp_agent_allowed claude-code-acp | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
check "  from the table too"               "0" "$(ui_rows "$BOXNET_SAVED_TABLE_ID" | /usr/bin/grep -c '^git.example.org:8443$')"
check "  Remove is off again"              "0" "$(ui_enabled "$BOXNET_SAVED_REMOVE_ID")"
check "  the list lets go of its selection" "$((deselected + 1))" "$(saved_deselects)"
check "  and the box keeps its rule"       "" "$(fake_log | /usr/bin/grep -- '--disallow')"
alert_answers_reset

section "no Allow for <agent> for a typed command, or with no agent recorded"
cad_pb_set aichatv2_boxagent_chat1 custom
open_network agent2
check "a typed command: hidden"            "0|0|0" "$(ui_visible "$BOXNET_ALLOW_AGENT_ID")|$(ui_visible "$BOXNET_SAVED_TEXT_ID")|$(ui_visible "$BOXNET_SAVED_ROW_ID")"
cad_pb_set aichatv2_boxagent_chat1 ""
open_network agent3
check "no agent recorded: hidden"          "0" "$(ui_visible "$BOXNET_ALLOW_AGENT_ID")"
cad_pb_set aichatv2_boxagent_chat1 claude-code-acp
cad_pb_set aichatv2_boxline_chat1 ""
omc_window_switch agent4
ui_reset
cad_pb_set cadabra_box_network_request chat1
omc_run aichat.box.network.init
check "a released box: hidden too"         "0" "$(ui_visible "$BOXNET_ALLOW_AGENT_ID")"
cad_pb_set aichatv2_boxagent_chat1 ""
cad_reset

section "the saved rules: stored as one line, and only rules come back"
check "not for a typed command"            "2" "$(cad_call acp_agent_allow_add custom example.com >/dev/null; echo $?)"
check "not a rule starting with a dash"    "2" "$(cad_call acp_agent_allow_add opencode --net >/dev/null; echo $?)"
check "not a rule with a space"            "2" "$(cad_call acp_agent_allow_add opencode 'a b' >/dev/null; echo $?)"
check "a wildcard is kept as it is"        "0|*.example.com" "$(cad_call acp_agent_allow_add opencode '*.example.com' >/dev/null; echo $?)|$(cad_call acp_agent_allowed opencode)"
"$cad_plister" set string "a.example -rm pack:npm b.example" "$cad_settings" /agents/allow/opencode >/dev/null 2>&1
check "a hand-edited word that is no rule is left out" "a.example pack:npm b.example" "$(cad_call acp_agent_allowed opencode | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
cad_reset

section "a chat window that has released its box leaves nothing to show"
fake_reset
open_network net5
cad_pb_set aichatv2_boxline_chat1 ""
omc_run aichat.box.network.refresh
check "the table empties"                  "0" "$(ui_row_count "$BOXNET_TABLE_ID")"
check "  and the header says why"          "1" "$(cad_has "$(ui_value "$BOXNET_HEADER_ID")" 'No AgentVM box to show')"
cad_pb_set aichatv2_boxline_chat1 "b1${TAB}$SINCE${TAB}AgentVM box b1"
omc_run aichat.box.network.refresh
select_host registry.npmjs.org
cad_pb_set aichatv2_boxline_chat1 ""
alerts_reset
omc_run aichat.box.network.allow
check "  Allow on a row shown before then asks nothing and says why" "0|0|1" \
    "$(alerts_count)|$(ui_row_count "$BOXNET_TABLE_ID")|$(cad_has "$(ui_value "$BOXNET_HEADER_ID")" 'No AgentVM box to show')"

section "Refresh comes back when the chat window has a box again"
fake_reset
open_network netback
cad_pb_set aichatv2_boxline_chat1 ""
omc_run aichat.box.network.refresh
check "no box: Refresh is off"             "0" "$(ui_enabled "$BOXNET_REFRESH_ID")"
cad_pb_set aichatv2_boxline_chat1 "b1${TAB}$SINCE${TAB}AgentVM box b1"
omc_run aichat.box.network.refresh
check "a box again: Refresh is on, and the rows are back" "1|1" "$(ui_enabled "$BOXNET_REFRESH_ID")|$([ "$(ui_row_count "$BOXNET_TABLE_ID")" -gt 0 ] && echo 1)"

section "a log agent-vm cannot give is said so"
fake_reset
open_network net6
printf '1\n' > "$FAKE_AGENTVM_DIR/exit"
printf 'Error: no box b1\n' > "$FAKE_AGENTVM_DIR/stderr"
omc_run aichat.box.network.refresh
/bin/rm -f "$FAKE_AGENTVM_DIR/exit" "$FAKE_AGENTVM_DIR/stderr"
check "the status gives agent-vm's reason" "1" "$(cad_has "$(ui_value "$BOXNET_STATUS_ID")" 'Could not read the network log: no box b1')"

section "closing forgets the window's chat window"
omc_run aichat.box.network.close
check "the context is gone"                "" "$(cad_pb_get "cadabra_box_network_$OMC_ACTIONUI_WINDOW_UUID")"

section "the chat window's Network... opens the window for its box, and only with one"
cad_pb_set cadabra_box_network_request ""
cad_pb_set "aichatv2_boxline_$OMC_ACTIONUI_WINDOW_UUID" ""
chains_reset
omc_run aichat.chat.box.network
check "a window with no box line opens nothing" "0|" "$(chain_asked aichat.box.network)|$(cad_pb_get cadabra_box_network_request)"
cad_pb_set "aichatv2_boxline_$OMC_ACTIONUI_WINDOW_UUID" "b1${TAB}$SINCE${TAB}AgentVM box b1"
omc_run aichat.chat.box.network
check "one with a line hands its id over"  "1|$OMC_ACTIONUI_WINDOW_UUID" "$(chain_asked aichat.box.network)|$(cad_pb_get cadabra_box_network_request)"
cad_pb_set "aichatv2_boxline_$OMC_ACTIONUI_WINDOW_UUID" ""
cad_pb_set cadabra_box_network_request ""

omctest_end

#!/bin/sh
# Tests/42-agent-keys.test.sh - the Keys window, opened from Select ACP Agent for an agent set to
# run in a box: the keys the catalog lists with their Keychain state, storing a value (on stdin,
# trimmed, never logged), which key the agent gets, removing one, and the shell for logging in
# inside a kept box. agent-vm is fake_agent_vm.sh; its Keychain is a file in its state folder.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

cad_import_ids aichat.agent.keys.library.sh ""

FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
CADABRA_AGENT_VM="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
CADABRA_OPEN="$OMCTEST_WORK/fake_open.sh"
export CADABRA_AGENT_VM FAKE_AGENTVM_DIR CADABRA_OPEN
unset AGENT_VM_HOME
TAB=$(printf '\t')

/bin/cat > "$CADABRA_OPEN" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$OMCTEST_WORK/opened"
/usr/bin/env >> "$OMCTEST_WORK/opened-env"
EOF
/bin/chmod +x "$CADABRA_OPEN"

# fake_reset - the fake with a stopped kept box try1, a free VM slot, and the fixture Keychain:
# CLAUDE_CODE_OAUTH_TOKEN (stored by another agent-vm, so not readable without asking) and
# OPENAI_API_KEY.
fake_reset() {
    /bin/rm -rf "$FAKE_AGENTVM_DIR" "$OMCTEST_WORK/opened"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR"
    /bin/cp "$FIXTURES/box-status-stopped.json" "$FAKE_AGENTVM_DIR/box-try1.json"
    /usr/bin/sed 's/"warning"/"ok"/g' "$FIXTURES/doctor.json" > "$FAKE_AGENTVM_DIR/doctor.json"
}
fake_log() { /bin/cat "$FAKE_AGENTVM_DIR/log" 2>/dev/null; }

# open_keys <window name> <agent id> <run-in>  ->  a Keys window opened for the agent, as Select
# ACP Agent's Keys... opens it.
open_keys() {
    omc_window_switch "$1"
    ui_reset
    cad_pb_set cadabra_agent_keys_request "$2$TAB$3"
    omc_run aichat.agent.keys.init
}

# select_key <variable> <state>  ->  a row of the key table selected.
select_key() {
    omc_table_cell "$KEYS_TABLE_ID" 2 "$1"
    omc_table_cell "$KEYS_TABLE_ID" 3 "$2"
    omc_run aichat.agent.keys.selection.changed
}

# row <variable>  ->  the key table's row for the variable.
row() { ui_rows "$KEYS_TABLE_ID" | /usr/bin/awk -F'\t' -v name="$1" '$2 == name { print; exit }'; }

# options  ->  the agent gets picker's option tags, space-joined.
options() {
    ui_prop "$KEYS_USE_ID" options | "$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3" -c \
        'import json, sys; print(" ".join(o["tag"] for o in json.load(sys.stdin)))' 2>&1
}

section "the ids this file drives are the ones the window declares"
check "table, value, buttons, picker, login, status" "701 702 703 704 705 711 720" \
    "$KEYS_TABLE_ID $KEYS_VALUE_ID $KEYS_STORE_ID $KEYS_REMOVE_ID $KEYS_USE_ID $KEYS_LOGIN_BUTTON_ID $KEYS_STATUS_ID"

section "opened with no agent, the window says where it comes from and offers nothing"
cad_reset
fake_reset
omc_window_switch lonely
ui_reset
omc_run aichat.agent.keys.init
check "it says to use Select ACP Agent"  "1" "$(cad_has "$(ui_value "$KEYS_STATUS_ID")" 'Keys... in Select ACP Agent')"
check "  and asks agent-vm nothing"      "" "$(fake_log)"

section "the catalog's keys for the agent, with what the Keychain holds"
open_keys claude claude-code-acp new:dev-agents
check "the window is named for the agent" "Keys for Claude" "$(ui_title | /usr/bin/cut -c1-15)"
check "one row per key, in the catalog's order" "CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY" "$(ui_rows "$KEYS_TABLE_ID" | /usr/bin/cut -f2 | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
check "a key another agent-vm stored"    "Stored; macOS asks first" "$(row CLAUDE_CODE_OAUTH_TOKEN | /usr/bin/cut -f3)"
check "a key not stored"                 "Not stored" "$(row ANTHROPIC_API_KEY | /usr/bin/cut -f3)"
check "the key it does not use is not listed" "" "$(row OPENAI_API_KEY)"
check "the choices"                      "none CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY" "$(options)"
check "  with no key chosen"             "none" "$(ui_value "$KEYS_USE_ID")"
check "nothing to store before a row is selected" "0|0|0" "$(ui_enabled "$KEYS_VALUE_ID")|$(ui_enabled "$KEYS_STORE_ID")|$(ui_enabled "$KEYS_REMOVE_ID")"
check "a disposable box offers no login" "0" "$(ui_enabled "$KEYS_LOGIN_BUTTON_ID")"
check "  and says why"                   "1" "$(cad_has "$(ui_value "$KEYS_LOGIN_TEXT_ID")" 'deleted with it')"

section "a row selects what Store and Remove act on"
select_key CLAUDE_CODE_OAUTH_TOKEN "Stored; macOS asks first"
check "a stored key can be replaced and removed" "1|1|1" "$(ui_enabled "$KEYS_VALUE_ID")|$(ui_enabled "$KEYS_STORE_ID")|$(ui_enabled "$KEYS_REMOVE_ID")"
check "  and says how to get it"         "1" "$(cad_has "$(ui_value "$KEYS_HINT_ID")" 'claude setup-token')"
check "the table names it briefly"       "Claude subscription token" "$(row CLAUDE_CODE_OAUTH_TOKEN | /usr/bin/cut -f1)"
select_key ANTHROPIC_API_KEY "Not stored"
check "a missing key can only be stored" "1|1|0" "$(ui_enabled "$KEYS_VALUE_ID")|$(ui_enabled "$KEYS_STORE_ID")|$(ui_enabled "$KEYS_REMOVE_ID")"
check "  and a key with no hint clears the last one" "" "$(ui_value "$KEYS_HINT_ID")"
select_key OPENAI_API_KEY "Stored"
check "a key the agent does not use offers nothing" "0|0|0" "$(ui_enabled "$KEYS_VALUE_ID")|$(ui_enabled "$KEYS_STORE_ID")|$(ui_enabled "$KEYS_REMOVE_ID")"

section "Store puts the trimmed value in the Keychain, on stdin only, and gives the key to the agent"
omc_table_cell "$KEYS_TABLE_ID" 2 ANTHROPIC_API_KEY
omc_control "$KEYS_VALUE_ID" "  sk-ant-test-1234 "
omc_run aichat.agent.keys.store
check "agent-vm got the value, trimmed"  "sk-ant-test-1234" "$(/bin/cat "$FAKE_AGENTVM_DIR/secret-ANTHROPIC_API_KEY")"
check "  on stdin: its command line names the key only" "secret set ANTHROPIC_API_KEY" "$(fake_log | /usr/bin/grep '^secret set')"
check "  and the value is nowhere in the log" "0" "$(cad_has "$(fake_log)" 'sk-ant-test')"
check "the field is emptied"             "1" "$(ui_calls "${TAB}${KEYS_VALUE_ID}${TAB} *\$")"
check "the agent gets the key"           "ANTHROPIC_API_KEY" "$(cad_call acp_agent_secret claude-code-acp)"
check "  as the picker shows"            "ANTHROPIC_API_KEY" "$(ui_value "$KEYS_USE_ID")"
check "the row reads stored"             "Stored" "$(row ANTHROPIC_API_KEY | /usr/bin/cut -f3)"
check "the status says so"               "1" "$(cad_has "$(ui_value "$KEYS_STATUS_ID")" 'Stored Anthropic API key. Claude')"
check "no other agent got it"            "none" "$(cad_call acp_agent_secret opencode)"

section "Store refuses what it cannot store, and changes nothing"
omc_table_cell "$KEYS_TABLE_ID" 2 CLAUDE_CODE_OAUTH_TOKEN
omc_control "$KEYS_VALUE_ID" "   "
omc_run aichat.agent.keys.store
check "a blank value is refused"         "1" "$(cad_has "$(ui_value "$KEYS_STATUS_ID")" 'Paste the value of Claude subscription token')"
check "  and agent-vm is not asked"      "1" "$(fake_log | /usr/bin/grep -c '^secret set')"
omc_table_cell "$KEYS_TABLE_ID" 2 OPENAI_API_KEY
omc_control "$KEYS_VALUE_ID" "sk-other"
omc_run aichat.agent.keys.store
check "a key the agent does not use is refused" "1" "$(cad_has "$(ui_value "$KEYS_STATUS_ID")" 'Select a key first')"
check "  and the field is emptied anyway" "" "$(ui_value "$KEYS_VALUE_ID")"
printf 'the Keychain is locked\n' > "$FAKE_AGENTVM_DIR/fail-secret-set"
omc_table_cell "$KEYS_TABLE_ID" 2 CLAUDE_CODE_OAUTH_TOKEN
omc_control "$KEYS_VALUE_ID" "tok-1"
omc_run aichat.agent.keys.store
check "agent-vm's refusal is shown"      "1" "$(cad_has "$(ui_value "$KEYS_STATUS_ID")" 'Could not store Claude subscription token: the Keychain is locked')"
check "  and the agent keeps its key"    "ANTHROPIC_API_KEY" "$(cad_call acp_agent_secret claude-code-acp)"
/bin/rm -f "$FAKE_AGENTVM_DIR/fail-secret-set"

section "the picker chooses the agent's key, and stores it at once"
omc_control "$KEYS_USE_ID" none
omc_run aichat.agent.keys.use.changed
check "no key"                           "none" "$(cad_call acp_agent_secret claude-code-acp)"
check "  said"                           "1" "$(cad_has "$(ui_value "$KEYS_STATUS_ID")" 'gets no key')"
omc_control "$KEYS_USE_ID" CLAUDE_CODE_OAUTH_TOKEN
omc_run aichat.agent.keys.use.changed
check "the token"                        "CLAUDE_CODE_OAUTH_TOKEN" "$(cad_call acp_agent_secret claude-code-acp)"
omc_control "$KEYS_USE_ID" OPENAI_API_KEY
omc_run aichat.agent.keys.use.changed
check "a value that is no choice changes nothing" "CLAUDE_CODE_OAUTH_TOKEN" "$(cad_call acp_agent_secret claude-code-acp)"
omc_control "$KEYS_USE_ID" damaged
omc_run aichat.agent.keys.use.changed
check "  nor does the unreadable entry"  "CLAUDE_CODE_OAUTH_TOKEN" "$(cad_call acp_agent_secret claude-code-acp)"

section "Remove asks first, since every agent using the variable loses the key"
alerts_reset; alert_answers_reset
alert_answer 1
omc_table_cell "$KEYS_TABLE_ID" 2 CLAUDE_CODE_OAUTH_TOKEN
omc_run aichat.agent.keys.remove
check "it asked"                         "1" "$(alerts_mention 'Every agent that uses CLAUDE_CODE_OAUTH_TOKEN loses it')"
check "  and Cancel removed nothing"     "0" "$(fake_log | /usr/bin/grep -c '^secret delete')"
alert_answer 0
omc_run aichat.agent.keys.remove
check "Remove deletes it"                "secret delete CLAUDE_CODE_OAUTH_TOKEN" "$(fake_log | /usr/bin/grep '^secret delete')"
check "  the agent that had it gets none" "none" "$(cad_call acp_agent_secret claude-code-acp)"
check "  and the row reads not stored"   "Not stored" "$(row CLAUDE_CODE_OAUTH_TOKEN | /usr/bin/cut -f3)"
alert_answers_reset

section "a kept box offers a shell for logging in, started first"
cad_reset
fake_reset
open_keys codex codex-acp box:try1
/bin/rm -f "$OMCTEST_WORK/opened-env"
check "the button names the box"         "Open a Shell in try1|1" "$(ui_prop "$KEYS_LOGIN_BUTTON_ID" title)|$(ui_enabled "$KEYS_LOGIN_BUTTON_ID")"
check "  with the catalog's instructions" "1" "$(cad_has "$(ui_value "$KEYS_LOGIN_TEXT_ID")" 'codex-acp cli login --device-auth')"
omc_control "$KEYS_VALUE_ID" "sk-typed-not-stored"
omc_run aichat.agent.keys.login
check "the stopped box is started, owned by Cadabra" "1" "$(fake_log | /usr/bin/grep -c '^box start try1 --owner-pid')"
check "  then Terminal opens a shell in it" "1" "$(/usr/bin/grep -c '^-a Terminal ' "$OMCTEST_WORK/opened")"
check "  and the button is back"         "1" "$(ui_enabled "$KEYS_LOGIN_BUTTON_ID")"
check "a value left in the field is not in the environment of what it runs" "1|0" "$(/bin/test -s "$OMCTEST_WORK/opened-env" && echo 1)|$(/usr/bin/grep -c 'sk-typed-not-stored' "$OMCTEST_WORK/opened-env")"
omc_control "$KEYS_VALUE_ID" ""
open_keys codex2 codex-acp new:dev
omc_run aichat.agent.keys.login
check "a disposable box starts nothing"  "1" "$(fake_log | /usr/bin/grep -c '^box start')"
omc_run aichat.agent.keys.close
omc_control "$KEYS_USE_ID" CODEX_API_KEY
omc_run aichat.agent.keys.use.changed
check "a closed window's handlers act on nothing" "none" "$(cad_call acp_agent_secret codex-acp)"

section "the value field stores nothing by itself"
# ActionUI fires a SecureField's actionID on focus loss as well as on Return, so an actionID on
# the field would store whatever it holds when the user clicks anything else.
check "the field has no action" "0" "$("$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3" -c 'import json, sys
def walk(n):
    if isinstance(n, dict):
        if n.get("id") == int(sys.argv[2]):
            print(1 if any(k.endswith("ctionID") for k in n.get("properties", {})) else 0)
        for v in n.values():
            walk(v)
    elif isinstance(n, list):
        for v in n:
            walk(v)
walk(json.load(open(sys.argv[1])))' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj/aichat.agent.keys.json" "$KEYS_VALUE_ID")"

section "no undeclared view ids were written"
check "none" "" "$(ui_unknown_writes)"

omctest_end

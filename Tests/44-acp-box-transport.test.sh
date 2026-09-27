#!/bin/sh
# Tests/44-acp-box-transport.test.sh - an external ACP agent in an agent-vm box: the catalog's box
# objects (acp_catalog.py box <id>) and the transport that wraps the agent in `agent-vm exec`
# (acp_transport_json.py --box ...). No box is started: these are the argv and JSON the Chat
# element would be given.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

cad_py="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
SCRIPTS="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts"
AGENTVM="/Applications/Cadabra.app/Contents/Support/AgentVM/agent-vm"
PROJECT="/Users/someone/src/app"

catalog() { "$cad_py" "$SCRIPTS/acp_catalog.py" "$@" 2>&1; }

# transport <level> <agent id> <command> [more options] - the box transport's JSON, or the error.
transport() {
    t_level="$1"
    t_id="$2"
    t_command="$3"
    shift 3
    "$cad_py" "$SCRIPTS/acp_transport_json.py" /bin/echo external "$t_command" "$OMCTEST_WORK/no-such-mcp.json" "$OMCTEST_WORK" false \
        --box cadabra-test-1 --agent-vm "$AGENTVM" --project "$PROJECT" --agent-id "$t_id" --level "$t_level" "$@" 2>&1
}

# field <json> <python expression over t> - one value of a transport, printed by Python.
field() {
    printf '%s' "$1" | "$cad_py" -c 'import json, sys; t = json.load(sys.stdin)["transport"]; print('"$2"')' 2>&1
}

section "the catalog's box objects"
check "Claude runs its adapter"          '["claude-agent-acp"]' "$(catalog box claude-code-acp | "$cad_py" -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["argv"]))')"
check "opencode runs opencode acp"       '["opencode", "acp"]'  "$(catalog box opencode | "$cad_py" -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["argv"]))')"
check "Codex is allowed OpenAI's hosts"  '["pack:openai"]'      "$(catalog box codex-acp | "$cad_py" -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["allow"]))')"
check "an agent with no box object prints nothing" "" "$(catalog box cursor)"
check "  and an unknown id nothing either"         "" "$(catalog box no-such-agent)"
check "box-list gives an agent's rules"  "pack:anthropic" "$(catalog box-list claude-code-acp allow)"
check "  and its secrets, in order"      "CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY" "$(catalog box-list claude-code-acp secrets | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
check "  nothing for an agent with no box object" "" "$(catalog box-list cursor allow)"
check "box-keys gives each key's variable, label and hint" "CODEX_API_KEY|Codex API key|-" "$(catalog box-keys codex-acp | /usr/bin/head -1 | /usr/bin/tr '\t' '|')"
check "  a hint where the catalog has one" "1" "$(cad_has "$(catalog box-keys claude-code-acp | /usr/bin/head -1 | /usr/bin/cut -f3)" 'claude setup-token')"
check "  one line per key, in order"     "CODEX_API_KEY OPENAI_API_KEY" "$(catalog box-keys codex-acp | /usr/bin/cut -f1 | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
check "  nothing for an agent with no box object" "" "$(catalog box-keys cursor)"
check "box-login gives the login hint"   "Run opencode auth login and choose the provider." "$(catalog box-login opencode)"
check "  nothing for an agent with no box object" "" "$(catalog box-login cursor)"
check "the rows never carry box details" "0" "$(cad_has "$(catalog rows)" 'OPENCODE_CONFIG_CONTENT')"
check "  while the rows are still there" "1" "$(cad_has "$(catalog rows)" 'claude-code-acp')"

section "the agent is wrapped in agent-vm exec, in the project"
json="$(transport free claude-code-acp "claude-agent-acp" --secret CLAUDE_CODE_OAUTH_TOKEN)"
check "the command starts with agent-vm exec" "['$AGENTVM', 'exec', '--box', 'cadabra-test-1', '--project', '$PROJECT']" "$(field "$json" 't["command"][:6]')"
check "the agent comes after --"         "['--', 'claude-agent-acp']" "$(field "$json" 't["command"][-2:]')"
check "the secret is named, not valued"  "1" "$(cad_has "$json" '"--secret", "CLAUDE_CODE_OAUTH_TOKEN"')"
check "the catalog's env reaches the guest" "1" "$(cad_has "$json" '"--env", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"')"
check "cwd is the project"               "$PROJECT" "$(field "$json" 't["cwd"]')"
check "the startup timeout is 60 s"      "60" "$(field "$json" 't["startupTimeoutSeconds"]')"
check "no Mac PATH is sent"              "False" "$(field "$json" '"env" in t')"

section "the autonomy level"
check "Claude free is bypassPermissions" "{'mode': 'bypassPermissions'}" "$(field "$(transport free claude-code-acp x)" 't["sessionConfig"]')"
check "Claude ask is its default mode"   "{'mode': 'default'}"           "$(field "$(transport ask claude-code-acp x)" 't["sessionConfig"]')"
check "Claude plan is plan"              "{'mode': 'plan'}"              "$(field "$(transport plan claude-code-acp x)" 't["sessionConfig"]')"
check "Codex free is full access"        "{'mode': 'agent-full-access'}" "$(field "$(transport free codex-acp x)" 't["sessionConfig"]')"
json="$(transport plan codex-acp codex-acp)"
check "Codex plan is refused, with the reason" "1" "$(cad_has "$json" 'Share the project read-only instead')"
check "  and no transport is printed"    "0" "$(cad_has "$json" '"protocol"')"
json="$(transport ask opencode "opencode acp")"
check "opencode ask travels as its config" "1" "$(cad_has "$json" 'OPENCODE_CONFIG_CONTENT={\"permission\":{\"edit\":\"ask\"')"
check "  and the project's own config is ignored" "1" "$(cad_has "$json" '"--env", "OPENCODE_DISABLE_PROJECT_CONFIG=1"')"
check "  with no session mode"           "False" "$(field "$json" '"sessionConfig" in t')"
json="$(transport free opencode "opencode acp")"
check "opencode free allows"             "1" "$(cad_has "$json" '{\"permission\":{\"edit\":\"allow\"')"
check "  and keeps the project's config" "0" "$(cad_has "$json" 'OPENCODE_DISABLE_PROJECT_CONFIG')"

section "the command in the box"
json="$(transport free opencode "$HOME/.opencode/bin/opencode acp")"
check "a Mac path is replaced by the catalog's argv" "['--', 'opencode', 'acp']" "$(field "$json" 't["command"][-3:]')"
json="$(transport free "" "my-agent --acp" --env FOO=bar)"
check "an agent with no box object keeps its command" "['--', 'my-agent', '--acp']" "$(field "$json" 't["command"][-3:]')"
check "  and gets the caller's env"      "1" "$(cad_has "$json" '"--env", "FOO=bar"')"
json="$(transport free opencode "opencode acp" --env OPENCODE_CONFIG_CONTENT=mine)"
check "the caller's env wins over the level's" "1" "$(cad_has "$json" '"--env", "OPENCODE_CONFIG_CONTENT=mine"')"
check "  once"                           "0" "$(cad_has "$json" 'permission')"
json="$(transport free opencode "opencode acp" --read-only)"
check "a read-only share is passed on"   "1" "$(cad_has "$json" '"--project", "'"$PROJECT"'", "--read-only"')"

section "refusals print no transport"
json="$(transport ask "" "my-agent --acp")"
check "asking, for an agent with no recipe, is refused" "1" "$(cad_has "$json" 'does not know how to make this agent ask')"
check "  with no transport"              "0" "$(cad_has "$json" '"protocol"')"
check "  while working freely is fine"   "1" "$(cad_has "$(transport free "" "my-agent --acp")" '"protocol"')"
check "box-unavailable names Codex's plan level" "1" "$(cad_has "$(catalog box-unavailable codex-acp plan)" 'no plan-only mode')"
check "  and an agent with no recipe asking" "1" "$(cad_has "$(catalog box-unavailable custom:2 ask)" 'does not know how')"
check "  and nothing for a level that holds" "" "$(catalog box-unavailable claude-code-acp plan)"
json="$("$cad_py" "$SCRIPTS/acp_transport_json.py" /bin/echo external "opencode acp" "$OMCTEST_WORK/x.json" "$OMCTEST_WORK" false \
    --box b --agent-vm "$AGENTVM" --project relative/path --level free 2>&1)"
check "a relative project is refused"    "1" "$(cad_has "$json" 'must be an absolute path')"
check "  with no transport"              "0" "$(cad_has "$json" '"protocol"')"
json="$("$cad_py" "$SCRIPTS/acp_transport_json.py" /bin/echo mlx /models/m "$OMCTEST_WORK/x.json" "$OMCTEST_WORK" true \
    --box b --agent-vm "$AGENTVM" --project "$PROJECT" --level free 2>&1)"
check "mlx-agent is not boxed in this version" "1" "$(cad_has "$json" 'external only')"
check "  and is not silently run on this Mac"  "0" "$(cad_has "$json" '"protocol"')"
json="$(transport free opencode "opencode acp" --env NOVALUE)"
check "an --env without a value is refused" "1" "$(cad_has "$json" 'needs NAME=VALUE')"
json="$("$cad_py" "$SCRIPTS/acp_transport_json.py" /bin/echo external "opencode acp" "$OMCTEST_WORK/x.json" "$OMCTEST_WORK" false \
    --box b --agent-vm "$AGENTVM" --project "$PROJECT" --agent-id claude-code-acp 2>&1)"
check "a box with no level is refused"   "1" "$(cad_has "$json" '--level')"
check "  rather than the freest mode"    "0" "$(cad_has "$json" 'bypassPermissions')"
json="$(transport free opencode "opencode acp" --read)"
check "an abbreviated option is refused" "0" "$(cad_has "$json" '"--read-only"')"
check "  with no transport"              "0" "$(cad_has "$json" '"protocol"')"
json="$("$cad_py" "$SCRIPTS/acp_transport_json.py" /bin/echo external "opencode acp" "$OMCTEST_WORK/x.json" "$OMCTEST_WORK" false \
    --box "" --agent-vm "$AGENTVM" --project "$PROJECT" --level free 2>&1)"
check "an empty box name is refused"     "1" "$(cad_has "$json" 'needs a box name')"

section "the path without --box is unchanged"
json="$("$cad_py" "$SCRIPTS/acp_transport_json.py" /bin/echo external "opencode acp" "$OMCTEST_WORK/x.json" "$OMCTEST_WORK" false 2>&1)"
check "the command is the user's"        "['opencode', 'acp']" "$(field "$json" 't["command"]')"
check "  with the Mac PATH"              "True" "$(field "$json" '"PATH" in t["env"]')"
check "  and no box keys"                "0" "$(cad_has "$json" 'sessionConfig')"

omctest_end

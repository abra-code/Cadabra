#!/bin/sh
# Tests/47-allow-folder.test.sh - Allow a Folder... in a chat window: which folders are refused,
# the window's own list, the MCP config generated with it, the signal to the window's agent, and
# the handler behind the button.
#
# mlx-agent itself is not started here (it would need a model): a stand-in process carries its
# command line and records the signal. That the real agent restarts the changed servers on SIGHUP
# is mlx-agent's own test.
#
# Needs the sandbox off (ps). POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.allow.folder.library.sh
PY="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
AGENT="$OMC_APP_BUNDLE_PATH/Contents/Support/MLX/mlx-agent"
SUPPORT="$HOME/Library/Application Support/Cadabra"
SESSION="$SUPPORT/Sessions/w1"
CFG="$SESSION/mcp-config.json"
LIST="$SESSION/window-folders.json"
# The generator writes the profile's path without doubled slashes, which the scratch $HOME has.
SESSION_PLAIN="$(printf '%s\n' "$SESSION" | /usr/bin/sed 's|//*|/|g')"
TAB=$(printf '\t')

WORK="$(cd "$OMCTEST_WORK" && pwd -P)/allow-folder"
/bin/rm -rf "$WORK"
/bin/mkdir -p "$WORK/project" "$WORK/extra one" "$WORK/extra-two" "$WORK/target"
/bin/ln -s "$WORK/target" "$WORK/link"
HOME_REAL="$(cd "$HOME" && pwd -P)"
/bin/mkdir -p "$HOME/Documents/notes" "$HOME/.ssh" "$HOME/.config/tool" "$HOME/Library/Developer/Xcode" "$HOME/Library/Application Support/Other"
HUP_FILE="$WORK/hup"
export HUP_FILE

allow() { cad_call_lib "$LIB" "$@"; }
# generate [options...]  ->  the window's config generated as chat init does; messages dropped.
generate() {
    ( PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE
      cad_call_lib aichat.mcp.servers.library.sh generate_stdio_mcp_config "$CFG" "$@" >/dev/null 2>&1 )
}
# server_args <config> <name>  ->  that server's arguments, one per line; nothing when absent.
server_args() { /usr/bin/jq -r --arg n "$2" '.servers[] | select(.name == $n) | .args[]' "$1" 2>/dev/null; }
# profile_of <config>  ->  the path after replay's --sandbox-profile.
profile_of() { server_args "$1" local | /usr/bin/awk 'take { print; exit } $0 == "--sandbox-profile" { take = 1 }'; }
names() { /usr/bin/jq -r '[.servers[].name] | join(" ")' "$1" 2>/dev/null; }
# stand_in <config>  ->  starts a process with the bundled agent's command line for that config,
# which notes every SIGHUP in $HUP_FILE; its pid in STAND_IN.
stand_in() {
    /bin/bash -c 'exec -a "$1" /bin/sh -c "trap \"echo hup >> \\\"\$HUP_FILE\\\"\" HUP; while :; do /bin/sleep 0.1; done" acp --backend foundation --mcp-config "$2"' _ "$AGENT" "$1" &
    STAND_IN=$!
    /bin/sleep 0.3
}
stop_stand_in() {
    /bin/kill "$STAND_IN" 2>/dev/null
    wait "$STAND_IN" 2>/dev/null
}

cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1
cad_call mcp_prefs_set_string servers/local/project "$WORK/project"
cad_call mcp_prefs_set_bool allow-network false

section "folders that are never allowed from a chat window"
refusal() { allow allow_folder_refusal "$1"; }
check "a project folder is fine"               "" "$(refusal "$WORK/extra one")"
check "a folder of the home folder is fine"    "" "$(refusal "$HOME_REAL/Documents/notes")"
check "one tool's folder in Library is fine"   "" "$(refusal "$HOME_REAL/Library/Developer/Xcode")"
check "the home folder is refused"             "1" "$(cad_has "$(refusal "$HOME_REAL")" "home folder")"
check "  and the folder that contains it"      "1" "$(cad_has "$(refusal "$(/usr/bin/dirname "$HOME_REAL")")" "home folder")"
check "  and the root"                         "1" "$(cad_has "$(refusal "/")" "home folder")"
check "Library is refused"                     "1" "$(cad_has "$(refusal "$HOME_REAL/Library")" "every application")"
check "  and its Application Support"          "1" "$(cad_has "$(refusal "$HOME_REAL/Library/Application Support")" "every application")"
check "  another application's folder in it is not" "" "$(refusal "$HOME_REAL/Library/Application Support/Other")"
check "Cadabra's own folder is refused"        "1" "$(cad_has "$(refusal "$HOME_REAL/Library/Application Support/Cadabra")" "Cadabra's own")"
check "  and a folder inside it"               "1" "$(cad_has "$(refusal "$HOME_REAL/Library/Application Support/Cadabra/Sessions")" "Cadabra's own")"
check "a hidden folder of the home folder is refused" "1" "$(cad_has "$(refusal "$HOME_REAL/.ssh")" "Hidden folders")"
check "  and a folder inside one"              "1" "$(cad_has "$(refusal "$HOME_REAL/.config/tool")" "Hidden folders")"
check "nothing at all is refused"              "That is not a folder." "$(refusal "")"
check "the data volume, which holds the home folder under another name, is refused" "1" "$(cad_has "$(refusal "/System/Volumes/Data")" "home folder")"
check "  and the folders that contain it"      "1|1" "$(cad_has "$(refusal "/System/Volumes")" "home folder")|$(cad_has "$(refusal "/System")" "home folder")"

section "the folder is its real path"
check "a link gives its target"                "$WORK/target" "$(allow allow_folder_real "$WORK/link")"
check "a link to the home folder is the home folder" "$HOME_REAL" "$(/bin/ln -s "$HOME" "$WORK/home-link"; allow allow_folder_real "$WORK/home-link")"
check "a file is no folder"                    "" "$(: > "$WORK/file"; allow allow_folder_real "$WORK/file")"
check "a relative path is no folder"           "" "$(allow allow_folder_real "Documents")"
check "a missing folder is no folder"          "" "$(allow allow_folder_real "$WORK/nowhere")"
check "\"..\" and a doubled slash are resolved"  "$WORK/target" "$(allow allow_folder_real "$WORK/project/..//target/.")"
# A folder reached under another spelling of its name: where the file system ignores case, and
# through the data volume's own path. The refusals compare names, so the real one must come back.
if [ -d "$HOME/DOCUMENTS/NOTES" ]; then
    check "another case gives the name the folder has" "$HOME_REAL/Documents/notes" "$(allow allow_folder_real "$HOME/DOCUMENTS/NOTES")"
    check "  so Library in another case is still refused" "1" "$(cad_has "$(refusal "$(allow allow_folder_real "$HOME/LIBRARY")")" "every application")"
    check "  and Cadabra's own folder"         "1" "$(/bin/mkdir -p "$SUPPORT"; cad_has "$(refusal "$(allow allow_folder_real "$HOME/library/application support/cadabra")")" "Cadabra's own")"
fi
if [ -d "/System/Volumes/Data$HOME_REAL" ]; then
    check "the data volume's path to the home folder is the home folder" "$HOME_REAL" "$(allow allow_folder_real "/System/Volumes/Data$HOME_REAL")"
fi
NL="
"
/bin/mkdir -p "$WORK/line${NL}" "$WORK/line" "$WORK/two${NL}lines" "$WORK/a${TAB}tab"
check "a name ending in a line break is not taken for its neighbor" "" "$(allow allow_folder_real "$WORK/line${NL}")"
check "  nor is a name with a line break or a tab a folder here" "|" "$(allow allow_folder_real "$WORK/two${NL}lines")|$(allow allow_folder_real "$WORK/a${TAB}tab")"

section "the window's own list"
check "no list at first"                       "" "$(allow allow_folder_list w1)"
allow allow_folder_add w1 "$WORK/extra one" read-only
check "a folder is added"                      "0" "$?"
check "  read-only"                            "read-only${TAB}$WORK/extra one" "$(allow allow_folder_list w1)"
allow allow_folder_add w1 "$WORK/extra one" read-only
check "  adding it again changes nothing"      "read-only${TAB}$WORK/extra one" "$(allow allow_folder_list w1)"
allow allow_folder_add w1 "$WORK/extra-two" read-write
check "a second one, read-write, is listed first" "read-write${TAB}$WORK/extra-two
read-only${TAB}$WORK/extra one" "$(allow allow_folder_list w1)"
allow allow_folder_add w1 "$WORK/extra one" read-write
check "the first one again, now read-write: moved, not doubled" "read-write${TAB}$WORK/extra-two
read-write${TAB}$WORK/extra one" "$(allow allow_folder_list w1)"
allow allow_folder_undo w1
check "undo puts back the list before the last change" "read-write${TAB}$WORK/extra-two
read-only${TAB}$WORK/extra one" "$(allow allow_folder_list w1)"
check "another window has none"                "" "$(allow allow_folder_list w2)"
/bin/rm -f "$LIST" "$LIST.before"

section "the config generated with the window's list"
generate
build_status=$?
check "the plain config is generated"          "0" "$build_status"
check "  with the three servers that need no network" "local pdf time" "$(names "$CFG")"
BASE_PROFILE="$(profile_of "$CFG")"
check "  replay's profile has its usual name"  "$SESSION_PLAIN/mcp-replay-sandbox.json" "$BASE_PROFILE"
BASE_SUM="$(/usr/bin/shasum "$BASE_PROFILE" | /usr/bin/cut -d' ' -f1)"
allow allow_folder_add w1 "$WORK/extra one" read-only
allow allow_folder_add w1 "$WORK/extra-two" read-write
generate --window-folders "$LIST"
WIN_PROFILE="$(profile_of "$CFG")"
case "$WIN_PROFILE" in
    "$SESSION_PLAIN"/mcp-replay-sandbox-????????????.json) named=yes ;;
    *) named="no: $WIN_PROFILE" ;;
esac
check "with the list, the profile has a name of its own" "yes" "$named"
check "  so replay's command line differs"     "1" "$([ "$WIN_PROFILE" != "$BASE_PROFILE" ] && echo 1)"
check "  the read-only folder is in it"        "1" "$(/usr/bin/jq --arg p "$WORK/extra one" '[.read_only[] | select(. == $p)] | length' "$WIN_PROFILE")"
check "  and the read-write one"               "1" "$(/usr/bin/jq --arg p "$WORK/extra-two" '[.read_write[] | select(. == $p)] | length' "$WIN_PROFILE")"
check "  the read-only folder is not writable" "0" "$(/usr/bin/jq --arg p "$WORK/extra one" '[.read_write[] | select(. == $p)] | length' "$WIN_PROFILE")"
check "  the project stays replay's one --allow-write" "$WORK/project" "$(server_args "$CFG" local | /usr/bin/awk 'take { print; exit } $0 == "--allow-write" { take = 1 }')"
check "  the usual profile is left as it was"  "$BASE_SUM" "$(/usr/bin/shasum "$BASE_PROFILE" | /usr/bin/cut -d' ' -f1)"
check "the PDF server gets both folders as roots" "2" "$(server_args "$CFG" pdf | /usr/bin/grep -c -e "^$WORK/extra one\$" -e "^$WORK/extra-two\$")"
check "the same list gives the same profile name" "$WIN_PROFILE" "$(generate --window-folders "$LIST"; profile_of "$CFG")"
check "the settings were not changed"          "0" "$(cad_call mcp_prefs_get_string servers/local/project >/dev/null; /usr/bin/grep -c "extra-two" "$SUPPORT/settings.plist" 2>/dev/null)"

# A folder of the list that a tool has since replaced with a link to somewhere else.
/bin/mkdir -p "$WORK/swap" "$WORK/secret"
/usr/bin/jq -n --arg p "$WORK/swap" '{read_only: [], read_write: [$p]}' > "$WORK/swap.json"
swapped() { /usr/bin/jq '[((.read_only // [])[], (.read_write // [])[]) | select(endswith("/swap") or endswith("/secret"))] | length' "$(profile_of "$CFG")"; }
generate --window-folders "$WORK/swap.json"
check "a folder of the list is in the profile" "1" "$(swapped)"
/bin/rmdir "$WORK/swap"
/bin/ln -s "$WORK/secret" "$WORK/swap"
generate --window-folders "$WORK/swap.json"
check "  once it has become a link it is left out, and so is the link's target" "0" "$(swapped)"
check "  for the PDF server too"               "0" "$(server_args "$CFG" pdf | /usr/bin/grep -c -e '/swap$' -e '/secret$')"
check "  the servers are all still there"      "local pdf time" "$(names "$CFG")"

printf '{"read_only": ["%s"], "read_write": ["%s"]}\n' "$WORK/extra-two" "$WORK/extra-two" > "$WORK/both.json"
generate --window-folders "$WORK/both.json"
check "a folder in both lists of a damaged file is read-only" "1|0" "$(/usr/bin/jq --arg p "$WORK/extra-two" '[.read_only[] | select(. == $p)] | length' "$(profile_of "$CFG")")|$(/usr/bin/jq --arg p "$WORK/extra-two" '[(.read_write // [])[] | select(. == $p)] | length' "$(profile_of "$CFG")")"

printf 'not json\n' > "$WORK/bad.json"
generate --window-folders "$WORK/bad.json"
check "a list that cannot be read: no config, rather than one without the folders" "no" "$([ -f "$CFG" ] && echo yes || echo no)"
printf '{"read_only": ["relative/path"]}\n' > "$WORK/bad.json"
generate --window-folders "$WORK/bad.json"
check "  the same for a path that is not absolute" "no" "$([ -f "$CFG" ] && echo yes || echo no)"
generate --window-folders "$LIST" --box b1
check "  and it is not an option of a box" "no" "$([ -f "$CFG" ] && echo yes || echo no)"

section "when a folder can be allowed for a window"
applies() { allow allow_folder_applies "$1"; echo $?; }
check "no config: no"                          "1" "$(applies w1)"
generate --window-folders "$LIST"
check "a local model's tools on this Mac: yes" "0" "$(applies w1)"
cad_pb_set aichatv2_boxtools_w1 "b1${TAB}/p${TAB}no${TAB}/g${TAB}/c"
check "tools in an AgentVM box: no"            "1" "$(applies w1)"
cad_pb_set aichatv2_boxtools_w1 ""
cad_pb_set aichatv2_agent_w1 "opencode"
check "an external agent: no"                  "1" "$(applies w1)"
cad_pb_set aichatv2_agent_w1 ""
/usr/bin/jq '.servers |= map(select(.name == "time"))' "$CFG" > "$CFG.t" && /bin/mv "$CFG.t" "$CFG"
check "only the time server: no, it uses no folder" "1" "$(applies w1)"
check "the bundled mlx-agent reloads its servers" "0" "$(allow allow_folder_agent_reloads; echo $?)"

section "applying the list: the config is replaced and the window's agent is told"
/bin/rm -f "$LIST" "$LIST.before"
generate
allow allow_folder_add w1 "$WORK/extra one" read-only
BEFORE_SUM="$(/usr/bin/shasum "$CFG" | /usr/bin/cut -d' ' -f1)"
( PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE; allow allow_folder_apply w1 >/dev/null 2>&1 )
check "no agent running: refused (2)"          "2" "$?"
check "  the config is left as it was"         "$BEFORE_SUM" "$(/usr/bin/shasum "$CFG" | /usr/bin/cut -d' ' -f1)"
check "  and nothing is left beside it"        "no" "$([ -f "$SESSION/mcp-config.next.json" ] && echo yes || echo no)"

# An agent that ends between being found and being told: the old config goes back.
( PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE
  allow eval 'allow_folder_agent_pid() { printf "%s\n" 99999999; }; allow_folder_apply w1' >/dev/null 2>&1 )
check "an agent gone before the signal: refused (2)" "2" "$?"
check "  the config is put back as it was"     "$BEFORE_SUM" "$(/usr/bin/shasum "$CFG" | /usr/bin/cut -d' ' -f1)"
check "  and nothing is left beside it"        "no" "$([ -f "$SESSION/mcp-config.next.json" ] || [ -f "$SESSION/mcp-config.before.json" ] && echo yes || echo no)"

# Another window's agent, and a program that only has the config path among its arguments.
/bin/mkdir -p "$SUPPORT/Sessions/w2"
/bin/cp "$CFG" "$SUPPORT/Sessions/w2/mcp-config.json"
stand_in "$SUPPORT/Sessions/w2/mcp-config.json"
OTHER_AGENT="$STAND_IN"
/bin/sh -c 'trap "echo wrong >> \"$HUP_FILE\"" HUP; while :; do /bin/sleep 0.1; done' not-the-agent /mlx-agent --mcp-config "$CFG" &
IMPOSTOR=$!
/bin/sleep 0.3
check "another window's agent is not this window's" "" "$(allow allow_folder_agent_pid w1)"
stand_in "$CFG"
check "the window's agent is found by its config" "$STAND_IN" "$(allow allow_folder_agent_pid w1)"
/bin/rm -f "$HUP_FILE"
( PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE; allow allow_folder_apply w1 >/dev/null 2>&1 )
check "with the agent running it applies"      "0" "$?"
/bin/sleep 0.5
check "  the agent got one SIGHUP, and nobody else did" "hup" "$(/bin/cat "$HUP_FILE" 2>/dev/null)"
check "  the config now names the folder's profile" "1" "$(/usr/bin/jq --arg p "$WORK/extra one" '[.read_only[] | select(. == $p)] | length' "$(profile_of "$CFG")")"
check "  with the same servers"                "local pdf time" "$(names "$CFG")"
check "  and nothing is left beside it"        "no" "$([ -f "$SESSION/mcp-config.next.json" ] && echo yes || echo no)"

# A server of the running session that the new config would lose.
/usr/bin/jq '.servers += [{"name": "search", "command": "/usr/bin/true", "args": []}]' "$CFG" > "$CFG.t" && /bin/mv "$CFG.t" "$CFG"
BEFORE_SUM="$(/usr/bin/shasum "$CFG" | /usr/bin/cut -d' ' -f1)"
/bin/rm -f "$HUP_FILE"
( PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE; allow allow_folder_apply w1 >/dev/null 2>&1 )
check "a config that would lose a server is refused (1)" "1" "$?"
check "  the config is left as it was"         "$BEFORE_SUM" "$(/usr/bin/shasum "$CFG" | /usr/bin/cut -d' ' -f1)"
check "  and the agent is not told"            "" "$(/bin/cat "$HUP_FILE" 2>/dev/null)"

section "a model switch keeps the window's folders"
( PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE
  cad_call_lib aichat.mcp.servers.library.sh aichat_acp_transport_json "$AGENT" foundation "" w1 true >/dev/null 2>&1 )
check "the transport built again still has the folder" "1" "$(/usr/bin/jq --arg p "$WORK/extra one" '[.read_only[] | select(. == $p)] | length' "$(profile_of "$CFG")" 2>/dev/null)"
( PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE
  cad_call_lib aichat.mcp.servers.library.sh aichat_acp_transport_json "$AGENT" external "/usr/bin/true" w1 true >/dev/null 2>&1 )
check "an external agent's config does not get it" "$SESSION_PLAIN/mcp-replay-sandbox.json" "$(profile_of "$CFG")"

section "the button's handler"
omc_window_switch w1
OMC_ACTIONUI_WINDOW_UUID=w1
export OMC_ACTIONUI_WINDOW_UUID
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE
/bin/rm -f "$LIST" "$LIST.before" "$HUP_FILE"
generate
BEFORE_SUM="$(/usr/bin/shasum "$CFG" | /usr/bin/cut -d' ' -f1)"

allow allow_folder_button w1
check "the button goes into the model bar's slot" "1" "$(cad_journal 548 | /usr/bin/grep -c 'omc_insert_element {"type":"Button","id":549')"
check "  with its plain tooltip"               "1" "$(cad_has "$(ui_prop 549 help)" "one more folder")"
cad_pb_set aichatv2_agent_w1 "opencode"
allow allow_folder_button w1
check "an external agent's window: taken out, not put back" "2|1" "$(cad_journal 549 | /usr/bin/grep -c omc_remove_element)|$(cad_journal 548 | /usr/bin/grep -c omc_insert_element)"
cad_pb_set aichatv2_agent_w1 ""
allow allow_folder_button w1

alerts_reset
omc_dialog_answer choose_folder "$HOME/.ssh"
omc_run aichat.chat.allow.folder
check "a refused folder: an alert says why"    "1" "$(alerts_mention "Hidden folders")"
check "  and nothing is listed"                "" "$(allow allow_folder_list w1)"

alerts_reset
alert_answers_reset
alert_answer 1
omc_dialog_answer choose_folder "$WORK/extra-two/"
omc_run aichat.chat.allow.folder
check "the question names the folder"          "1" "$(alerts_mention "Allow $WORK/extra-two?")"
check "  Cancel: nothing is listed"            "" "$(allow allow_folder_list w1)"
check "  and the config is untouched"          "$BEFORE_SUM" "$(/usr/bin/shasum "$CFG" | /usr/bin/cut -d' ' -f1)"

alerts_reset
alert_answers_reset
alert_answer 2
omc_dialog_answer choose_folder "$WORK/link"
omc_run aichat.chat.allow.folder
check_status "Read and Write on a link"        0
check "  the link's target is listed, read-write" "read-write${TAB}$WORK/target" "$(allow allow_folder_list w1)"
/bin/sleep 0.5
check "  the agent was told"                   "hup" "$(/bin/cat "$HUP_FILE" 2>/dev/null)"
check "  the config has it"                    "1" "$(/usr/bin/jq --arg p "$WORK/target" '[.read_write[] | select(. == $p)] | length' "$(profile_of "$CFG")")"
check "  the button's tooltip lists it"        "1" "$(cad_has "$(ui_prop 549 help)" "$WORK/target (read-write)")"

stop_stand_in
alerts_reset
alert_answers_reset
alert_answer 0
omc_dialog_answer choose_folder "$WORK/extra one"
omc_run aichat.chat.allow.folder
check "Read Only with the agent gone: an alert" "1" "$(alerts_mention "model is not running")"
check "  and the list is as before"            "read-write${TAB}$WORK/target" "$(allow allow_folder_list w1)"

alerts_reset
unset OMC_ACTIONUI_WINDOW_UUID
omc_dialog_answer choose_folder "$WORK/extra one"
omc_run aichat.chat.allow.folder
check "run without a window (a link): nothing asked" "0" "$(alerts_count)"
check "  and nothing listed"                   "read-write${TAB}$WORK/target" "$(allow allow_folder_list w1)"

section "the offer after a refused tool call"
OMC_ACTIONUI_WINDOW_UUID=w1
export OMC_ACTIONUI_WINDOW_UUID
/bin/mkdir -p "$HOME/Downloads/sub"
OFFER_KEY=aichatv2_folder_offer_w1
DISMISSED="$SESSION/window-folders-dismissed.txt"
# tool_call <result text>  ->  the envelope of a finished tool call with that result.
tool_call() {
    /usr/bin/jq -c -n --arg text "$1" '{data: {toolCall: {contentText: $text, id: "c1", kind: "read", status: "failed", title: "read_file"}, type: "toolCall"}, id: "c1", sequence: 7, type: "toolCall"}'
}
refused() { allow allow_folder_refused_path "$(tool_call "$1")"; }
check "the Local server's refusal names the path" "$HOME/Downloads/a b.txt" \
    "$(refused "{\"error\": \"tool call failed: Transport error: Path not allowed: $HOME/Downloads/a b.txt is outside the allowed directories (use list_allowed_directories to see them)\"}")"
check "the PDF server's too"                   "/tmp/out.pdf" "$(refused "{\"error\": \"output outside allowed roots: /tmp/out.pdf\"}")"
check "a command's refused path"               "/Users/x/PROBE 2" "$(refused "--- write test ---
touch: /Users/x/PROBE 2: Operation not permitted
WROTE: no")"
check "  after a tool named by its path"       "/x/y" "$(refused "/bin/sh: /x/y: Operation not permitted")"
check "  a line that names no path: nothing"   "" "$(refused "Operation not permitted")"
check "a call refused nothing: nothing"        "" "$(refused "[FILE] notes.txt")"
check "an entry that is no tool call: nothing" "" "$(allow allow_folder_refused_path '{"type":"message","data":{"text":"Path not allowed: /x is outside the allowed directories"}}')"

hint() { allow allow_folder_hint "$1"; }
check "a folder is its own hint"               "$HOME_REAL/Downloads/sub" "$(hint "$HOME/Downloads/sub")"
check "a file's hint is its folder"            "$HOME_REAL/Downloads" "$(hint "$HOME/Downloads/missing.txt")"
check "a path that is not there yet: the nearest folder above" "$HOME_REAL/Downloads/sub" "$(hint "$HOME/Downloads/sub/new/deeper/file.txt")"
check "a path that is not absolute: nothing"   "" "$(hint "Downloads/file.txt")"

# offer <path>  ->  what the entry handler does in the background for a call refused that path.
offer() { allow allow_folder_offer w1 "$(tool_call "Path not allowed: $1 is outside the allowed directories (use list_allowed_directories to see them)")" >/dev/null 2>&1; }
offers() { cad_journal 562 | /usr/bin/grep -c 'omc_insert_element {"type":"HStack","id":563'; }
stand_in "$CFG"
/bin/rm -f "$DISMISSED"
cad_pb_set "$OFFER_KEY" ""
cad_journal_reset

offer "$HOME/Downloads/report.txt"
check "a refused file: its folder is offered"  "1" "$(offers)"
check "  the line shows it from the home folder" "~/Downloads" "$(ui_value 564)"
check "  with Allow a Folder... and Dismiss"   "1|1" "$(cad_journal 562 | /usr/bin/grep -c '"actionID":"aichat.chat.allow.folder.offered"')|$(cad_journal 562 | /usr/bin/grep -c '"actionID":"aichat.chat.allow.folder.dismiss"')"
check "  the chooser of the offer opens at the line's folder" "__ACTIONUI_VIEW_564_VALUE__" \
    "$(/usr/bin/jq -r '.COMMAND_LIST[] | select(.COMMAND_ID == "aichat.chat.allow.folder.choose") | .CHOOSE_FOLDER_DIALOG.DEFAULT_LOCATION | join(" ")' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Command.json")"
check "  and the window has a slot for the line" "1" "$(/usr/bin/jq '[.. | objects | select(.id? == 562)] | length' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj/aichat.chat.json")"
offer "$HOME/Downloads/other.txt"
check "the same folder again: one line"        "1" "$(offers)"
offer "$HOME/nothing-here.txt"
check "the home folder is never offered"       "1|$HOME_REAL/Downloads" "$(offers)|$(cad_pb_get "$OFFER_KEY")"
offer "/"
check "  nor the root"                         "1" "$(offers)"
offer "$HOME/.ssh/id_rsa"
check "  nor a hidden folder of the home folder" "1" "$(offers)"
offer "$WORK/target/sub/file"
check "a folder the window already has read-write is not offered" "1" "$(offers)"
offer "$WORK/extra-two/file"
check "another folder replaces the line"       "2|$WORK/extra-two" "$(offers)|$(cad_pb_get "$OFFER_KEY")"
check "  the old line taken out first"         "1" "$(cad_has "$(cad_journal 563)" "omc_remove_element")"

omc_run aichat.chat.allow.folder.dismiss
check "Dismiss takes the line away"            "" "$(cad_pb_get "$OFFER_KEY")"
offer "$WORK/extra-two/file"
check "  and that folder is not offered again" "2" "$(offers)"
offer "$HOME/Downloads/report.txt"
check "  another one still is"                 "3" "$(offers)"

/bin/mkdir "$SESSION/window-folders-offer.lock"
/bin/rm -f "$DISMISSED"
offer "$WORK/extra-two/file"
check "while another offer is being put up: left out" "3" "$(offers)"
/usr/bin/touch -t 202001010000 "$SESSION/window-folders-offer.lock"
offer "$WORK/extra-two/file"
check "  a lock left behind is taken over"     "4" "$(offers)"
check "  and released"                         "0" "$([ -d "$SESSION/window-folders-offer.lock" ] && echo 1 || echo 0)"

cad_pb_set aichatv2_agent_w1 "opencode"
offer "$HOME/Downloads/report.txt"
check "an external agent's window gets no offer" "4" "$(offers)"
allow allow_folder_button w1
check "  and loses the one it had"             "" "$(cad_pb_get "$OFFER_KEY")"
cad_pb_set aichatv2_agent_w1 ""
allow allow_folder_button w1

# The line's Allow a Folder...: its button hands over to the command with the chooser, which is
# the main handler with the folder chosen there.
chains_reset
omc_run aichat.chat.allow.folder.offered
check "the line's button hands over to the chooser's command" "1" "$(chain_asked aichat.chat.allow.folder.choose)"
check "  which has no chooser of its own"      "null" "$(/usr/bin/jq -r '.COMMAND_LIST[] | select(.COMMAND_ID == "aichat.chat.allow.folder.offered") | .CHOOSE_FOLDER_DIALOG' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Command.json")"
offer "$HOME/Downloads/report.txt"
check "offered again"                          "$HOME_REAL/Downloads" "$(cad_pb_get "$OFFER_KEY")"
/bin/rm -f "$HUP_FILE"
alerts_reset
alert_answers_reset
alert_answer 0
omc_dialog_answer choose_folder "$HOME/Downloads/sub"
omc_run aichat.chat.allow.folder.choose
check "a folder inside the offered one is allowed" "1" "$(allow allow_folder_list w1 | /usr/bin/grep -c -F "read-only${TAB}$HOME_REAL/Downloads/sub")"
check "  the offer stays: its folder is still refused" "$HOME_REAL/Downloads" "$(cad_pb_get "$OFFER_KEY")"
alerts_reset
alert_answers_reset
alert_answer 0
omc_dialog_answer choose_folder "$HOME/Downloads"
omc_run aichat.chat.allow.folder.choose
check "the offered folder is allowed"          "1" "$(allow allow_folder_list w1 | /usr/bin/grep -c -F -x "read-only${TAB}$HOME_REAL/Downloads")"
check "  and the offer goes"                   "" "$(cad_pb_get "$OFFER_KEY")"
/bin/sleep 0.5
check "  the agent was told each time"         "2" "$(/usr/bin/grep -c hup "$HUP_FILE" 2>/dev/null)"

# The refused path is a tool's text, so a folder's name is the model's to shape. Whatever it
# holds, it is only named: as one string of the line's JSON, as the line's value, and as one
# whole line of the dismissed list.
ODD="$WORK/odd \"q\" \$(touch $WORK/made) \`touch $WORK/made\` \\ * [x] 'a' ; & -n"
/bin/mkdir -p "$ODD/sub" "$WORK/odd-plain"
cad_journal_reset
offer "$ODD/sub/file.txt"
check "a folder with quotes and shell characters in its name is offered" "$ODD/sub" "$(cad_pb_get "$OFFER_KEY")"
check "  as one string of the line"            "$ODD/sub" "$(cad_journal 562 | /usr/bin/sed -n 's/^omc_insert_element //p' | /usr/bin/jq -r '.children[2].properties.help')"
check "  and nothing else of the line changed" "HStack|6|aichat.chat.allow.folder.offered|aichat.chat.allow.folder.dismiss" \
    "$(cad_journal 562 | /usr/bin/sed -n 's/^omc_insert_element //p' | /usr/bin/jq -r '[.type, (.children | length | tostring), .children[3].properties.actionID, .children[4].properties.actionID] | join("|")')"
check "  the line's value is the name as it is" "$ODD/sub" "$(ui_value 564)"
check "  nothing in the name was run"          "0" "$([ -e "$WORK/made" ] && echo 1 || echo 0)"
omc_run aichat.chat.allow.folder.dismiss
check "  dismissed, it is one line of the list" "1" "$(/usr/bin/grep -c -F -x -e "$ODD/sub" "$DISMISSED")"
offer "$ODD/sub/file.txt"
check "  and is not offered again"             "" "$(cad_pb_get "$OFFER_KEY")"
offer "$WORK/odd-plain/file.txt"
check "  a folder whose name only begins the same still is" "$WORK/odd-plain" "$(cad_pb_get "$OFFER_KEY")"
omc_run aichat.chat.allow.folder.dismiss
/bin/mkdir -p "$WORK/line
break"
offer "$WORK/line
break/file.txt"
check "a folder with a line break in its name is not offered" "" "$(cad_pb_get "$OFFER_KEY")"

# The entry handler makes the offer for a finished tool call, and for nothing else.
cad_journal_reset
/bin/rm -f "$DISMISSED"
omc_trigger 1 "" "$(tool_call "Path not allowed: $WORK/extra-two/x is outside the allowed directories (use list_allowed_directories to see them)")"
omc_run aichat.chat.entry
omc_wait_for "[ -n \"\$(\"$OMC_OMC_SUPPORT_PATH/pasteboard\" $OFFER_KEY get)\" ]" 10
check "the entry handler offers the folder of a refused call" "$WORK/extra-two" "$(cad_pb_get "$OFFER_KEY")"
stop_stand_in

/bin/kill "$OTHER_AGENT" "$IMPOSTOR" 2>/dev/null
wait "$OTHER_AGENT" "$IMPOSTOR" 2>/dev/null
/bin/rm -rf "$WORK"
omctest_end

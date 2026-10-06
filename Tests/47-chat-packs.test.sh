#!/bin/sh
# Tests/47-chat-packs.test.sh - Allow Packs... in a chat window: the button, the sheet of
# Agentic Session Tools opened over the chat window, and Use These Packs having the window's
# running tools follow (the config generated again, the signal to the window's agent).
#
# mlx-agent itself is not started here: a stand-in process carries its command line and records
# the signal, as in 47-allow-folder.test.sh.
#
# Needs the sandbox off (ps). POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.allow.folder.library.sh
AGENT="$OMC_APP_BUNDLE_PATH/Contents/Support/MLX/mlx-agent"
SUPPORT="$HOME/Library/Application Support/Cadabra"
SESSION="$SUPPORT/Sessions/w1"
CFG="$SESSION/mcp-config.json"
LIST="$SESSION/window-folders.json"
SESSION_PLAIN="$(printf '%s\n' "$SESSION" | /usr/bin/sed 's|//*|/|g')"
USER_PACKS="$SUPPORT/SandboxPacks"
RUN="$SUPPORT/Run"
PACKS_TABLE_ID="$(cad_lib_var mcp_packs_table_view aichat.mcp.servers.library.sh)"
RW_TABLE_ID="$(cad_lib_var mcp_rw_table_view aichat.mcp.servers.library.sh)"
BUTTON_ID="$(cad_lib_var allow_packs_button_id $LIB)"
RECORD_ID="$(cad_lib_var allow_packs_record_id $LIB)"
INTRO_ID="$(cad_lib_var allow_packs_intro_id $LIB)"
for id in "$PACKS_TABLE_ID" "$RW_TABLE_ID" "$BUTTON_ID" "$RECORD_ID" "$INTRO_ID"; do
    if [ -z "$id" ]; then
        printf '%s: a view id was not found in the libraries\n' "$0" >&2
        exit 1
    fi
done

WORK="$(cd "$OMCTEST_WORK" && pwd -P)/chat-packs"
/bin/rm -rf "$WORK" "$USER_PACKS"
/bin/mkdir -p "$WORK/project" "$WORK/tools" "$WORK/cache" "$USER_PACKS"
HUP_FILE="$WORK/hup"
export HUP_FILE
PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

allow() { cad_call_lib "$LIB" "$@"; }
generate() {
    cad_call_lib aichat.mcp.servers.library.sh generate_stdio_mcp_config "$CFG" "$@" >/dev/null 2>&1
}
server_args() { /usr/bin/jq -r --arg n "$2" '.servers[] | select(.name == $n) | .args[]' "$1" 2>/dev/null; }
profile_of() { server_args "$1" local | /usr/bin/awk 'take { print; exit } $0 == "--sandbox-profile" { take = 1 }'; }
# in_profile <read_only|read_write> <path>  ->  how often the window's profile lists the path.
in_profile() {
    /usr/bin/jq --arg k "$1" --arg p "$2" '[(.[$k] // [])[] | select(. == $p)] | length' "$(profile_of "$CFG")" 2>/dev/null
}
stand_in() {
    /bin/bash -c 'exec -a "$1" /bin/sh -c "trap \"echo hup >> \\\"\$HUP_FILE\\\"\" HUP; while :; do /bin/sleep 0.1; done" acp --backend foundation --mcp-config "$2"' _ "$AGENT" "$1" &
    STAND_IN=$!
    /bin/sleep 0.3
}
stop_stand_in() {
    /bin/kill "$STAND_IN" 2>/dev/null
    wait "$STAND_IN" 2>/dev/null
}
row_of() {
    ui_rows "$PACKS_TABLE_ID" | /usr/bin/awk -F'\t' -v id="$1" '$3 == id { print NR - 1 }'
}
click() {
    omc_trigger "$PACKS_TABLE_ID" "" "$(row_of "$1")"
    omc_run aichat.mcp.servers.packs.toggle
}
stored() {
    cad_call mcp_prefs_array_list servers/local/packs | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//'
}
sheet_files() {
    /bin/ls "$RUN" 2>/dev/null | /usr/bin/grep -c "^tools-packs\.w1\."
}
hups() {
    /bin/sleep 0.5
    /bin/cat "$HUP_FILE" 2>/dev/null | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//'
}
sum_of() { /usr/bin/shasum "$1" | /usr/bin/cut -d' ' -f1; }

cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1
cad_call mcp_prefs_set_string servers/local/project "$WORK/project"
cad_call mcp_prefs_set_bool allow-network false
printf '{"formatVersion": 1, "id": "work", "title": "Work tools", "read_only": ["%s"], "read_write": ["%s"]}\n' "$WORK/tools" "$WORK/cache" > "$USER_PACKS/work.json"

section "a window with a list of its own gets a profile named after its content"
/bin/mkdir -p "$SESSION"
generate
check "without a list: the usual name"  "$SESSION_PLAIN/mcp-replay-sandbox.json" "$(profile_of "$CFG")"
printf '{}\n' > "$LIST"
generate --window-folders "$LIST"
case "$(profile_of "$CFG")" in
    "$SESSION_PLAIN"/mcp-replay-sandbox-????????????.json) named=yes ;;
    *) named="no: $(profile_of "$CFG")" ;;
esac
check "with an empty list: a name of its own" "yes" "$named"
/bin/rm -f "$LIST"
generate

section "the button"
omc_window_switch w1
OMC_ACTIONUI_WINDOW_UUID=w1
export OMC_ACTIONUI_WINDOW_UUID
check "packs can be chosen for a window with the Local server" "0" "$(allow allow_packs_applies w1; echo $?)"
allow allow_folder_button w1
check "the button goes in beside Allow a Folder..." "1" "$(cad_journal 548 | /usr/bin/grep -c "omc_insert_element {\"type\":\"Button\",\"id\":$BUTTON_ID")"
check "  and runs the chat window's command" "1" "$(cad_journal 548 | /usr/bin/grep -c '"actionID":"aichat.chat.packs"')"
check "  named like its neighbor"       "1" "$(cad_journal 548 | /usr/bin/grep -c '"title":"Allow Packs..."')"
/bin/cp "$CFG" "$CFG.kept"
/usr/bin/jq '.servers |= map(select(.name != "local"))' "$CFG.kept" > "$CFG"
check "not for a window without the Local server" "1" "$(allow allow_packs_applies w1; echo $?)"
cad_journal_reset
allow allow_folder_button w1
check "  which gets Allow a Folder... alone" "1|0" "$(cad_journal 548 | /usr/bin/grep -c '"id":549')|$(cad_journal 548 | /usr/bin/grep -c "\"id\":$BUTTON_ID")"
alerts_reset
omc_run aichat.chat.packs
check "  and no sheet"                  "0" "$(cad_journal omc_window | /usr/bin/grep -c omc_present_modal)"
/bin/mv -f "$CFG.kept" "$CFG"
cad_pb_set aichatv2_agent_w1 "opencode"
check "not for an external agent's window" "1" "$(allow allow_packs_applies w1; echo $?)"
cad_pb_set aichatv2_agent_w1 ""

section "the sheet over the chat window"
cad_journal_reset
omc_run aichat.chat.packs
check_status "the handler ran" 0
check "the sheet is the one of Agentic Session Tools" "1" "$(cad_has "$(cad_journal omc_window)" 'omc_present_modal aichat.mcp.servers.packs')"
check "  with the packs listed"         "1" "$([ -n "$(row_of work)" ] && echo 1)"
check "  Record a Pack... is hidden"    "1" "$(cad_journal "$RECORD_ID" | /usr/bin/grep -c omc_hide)"
check "  and its text says what Use These Packs does here" "1" "$(cad_has "$(ui_value "$INTRO_ID")" "this conversation from your next message")"
check "the sheet is marked as a chat window's" "yes" "$([ -f "$RUN/tools-packs.w1.chat" ] && echo yes || echo no)"

section "Cancel changes nothing"
click work
omc_run aichat.mcp.servers.packs.cancel
check "nothing is stored"               "" "$(stored)"
check "the sheet's files go, the mark too" "0" "$(sheet_files)"

section "Use These Packs has the window's tools follow"
BEFORE_SUM="$(sum_of "$CFG")"
stand_in "$CFG"
/bin/rm -f "$HUP_FILE"
omc_run aichat.chat.packs
click work
cad_journal_reset
alerts_reset
omc_run aichat.mcp.servers.packs.use
check_status "the handler ran" 0
check "the pack is stored, as from the settings" "work" "$(stored)"
check "the sheet goes"                  "1" "$(cad_has "$(cad_journal omc_window)" 'omc_dismiss_modal')"
check "  and its files with it"         "0" "$(sheet_files)"
check "the agent was told once"         "hup" "$(hups)"
check "the window's profile has the pack's folder to read" "1" "$(in_profile read_only "$WORK/tools")"
check "  and the one to change"         "1" "$(in_profile read_write "$WORK/cache")"
case "$(profile_of "$CFG")" in
    "$SESSION_PLAIN"/mcp-replay-sandbox-????????????.json) named=yes ;;
    *) named="no: $(profile_of "$CFG")" ;;
esac
check "  under a name of its own, so the server is started again" "yes" "$named"
check "the window has a list of its own now, an empty one" "{}" "$(/bin/cat "$LIST" 2>/dev/null)"
check "nothing is said"                 "0" "$(alerts_count)"
check "the tables of the settings window are not written here" "0" "$(cad_writes "$RW_TABLE_ID")"

/bin/rm -f "$HUP_FILE"
WITH_SUM="$(sum_of "$CFG")"
omc_run aichat.chat.packs
omc_run aichat.mcp.servers.packs.use
check "the same packs again: the agent is left alone" "" "$(hups)"
check "  and the config as it was"      "$WITH_SUM" "$(sum_of "$CFG")"

section "packs changed in the settings since the window's tools started"
# Stored without telling any agent, as Use These Packs in Agentic Session Tools does.
cad_call mcp_prefs_set_packs ""
/bin/rm -f "$HUP_FILE"
omc_run aichat.chat.packs
check "the sheet shows the pack unticked" "square" "$(ui_rows "$PACKS_TABLE_ID" | /usr/bin/awk -F'\t' '$3 == "work" { print $1 }')"
omc_run aichat.mcp.servers.packs.use
check "Use These Packs with the ticks as stored still has the window follow" "hup" "$(hups)"
check "  the pack's folders are out of its profile" "0|0" "$(in_profile read_only "$WORK/tools")|$(in_profile read_write "$WORK/cache")"
/bin/rm -f "$HUP_FILE"
omc_run aichat.chat.packs
click work
omc_run aichat.mcp.servers.packs.use
check "ticked again: told again"        "hup|1" "$(hups)|$(in_profile read_only "$WORK/tools")"
WITH_SUM="$(sum_of "$CFG")"

section "when the tools cannot follow, the packs stay as they were"
stop_stand_in
omc_run aichat.chat.packs
click work
alerts_reset
omc_run aichat.mcp.servers.packs.use
check "an alert says so"                "1|1" "$(alerts_mention "The packs were not changed")|$(alerts_mention "model is not running")"
check "the stored packs are put back"   "work" "$(stored)"
check "the config is as it was"         "$WITH_SUM" "$(sum_of "$CFG")"
check "the sheet is gone all the same"  "0" "$(sheet_files)"

# A window that had no list: the empty one made for the attempt goes with it.
/bin/rm -f "$LIST"
omc_run aichat.chat.packs
click work
alerts_reset
omc_run aichat.mcp.servers.packs.use
check "a failed first change leaves the window without a list" "no" "$([ -f "$LIST" ] && echo yes || echo no)"
check "  and the packs as they were"    "work" "$(stored)"

section "unticking takes the folders away again"
printf '{}\n' > "$LIST"
stand_in "$CFG"
/bin/rm -f "$HUP_FILE"
omc_run aichat.chat.packs
click work
omc_run aichat.mcp.servers.packs.use
check "nothing is stored"               "" "$(stored)"
check "the agent was told"              "hup" "$(hups)"
check "the pack's folders are out of the profile" "0|0" "$(in_profile read_only "$WORK/tools")|$(in_profile read_write "$WORK/cache")"

section "the same sheet from the settings window tells no agent"
/bin/rm -f "$HUP_FILE"
omc_run aichat.mcp.servers.packs
check "it is not marked as a chat window's" "no" "$([ -f "$RUN/tools-packs.w1.chat" ] && echo yes || echo no)"
click work
omc_run aichat.mcp.servers.packs.use
check "the pack is stored"              "work" "$(stored)"
check "  and the agent is not told"     "" "$(hups)"
stop_stand_in

/bin/rm -rf "$WORK"
omctest_end

#!/bin/sh
# Tests/49-mcp-inspect-catalog.test.sh - the MCP Servers window is a catalog: every server
# Cadabra has, with its tools, whatever Agentic Session Tools turns on and wherever tools are
# set to run. It follows no conversation, so nothing in it may look like a running state.
#
# The generator starts the real servers on this Mac to list their tools; no box and no
# agent-vm is involved.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.mcp.inspect.library.sh
SERVER_TABLE_ID=200
COMMAND_FIELD_ID=210
STATUS_ID=212
NOTE_ID=214
TOOLS_TABLE_ID=300
WIN="inspect-window-1"
CFG="$OMCTEST_WORK/inspect/mcp-config.json"
PROJECT="$OMCTEST_WORK/project"
LAYOUT="$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj/aichat.mcp.inspect.json"
REPORT="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/mcp_tools_report.py"
PY="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
/bin/mkdir -p "$PROJECT"

lib() { cad_call_lib "$LIB" "$@"; }
run_in() { cad_call_lib aichat.mcp.servers.library.sh mcp_tools_set_run_in "$1" >/dev/null; }
box_set() { cad_call_lib aichat.mcp.servers.library.sh mcp_box_set_setting "$1" "$2"; }
prefs_reset() {
    cad_reset
    cad_call mcp_prefs_write_defaults >/dev/null 2>&1
    cad_call mcp_prefs_set_string servers/local/project "$PROJECT"
}
# generate [options]  ->  the generator's output; the config is in $CFG.
generate() {
    /bin/rm -f "$CFG"
    ( PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE
      cad_call_lib aichat.mcp.servers.library.sh generate_stdio_mcp_config "$CFG" "$@" 2>&1 )
}
names() { /usr/bin/jq -r '[.servers[].name] | join(" ")' "$CFG" 2>/dev/null; }
server_args() { /usr/bin/jq -r --arg n "$1" '.servers[] | select(.name == $n) | .args | join(" ")' "$CFG" 2>/dev/null; }
# has <text> <part>  ->  yes or no.
has() {
    case "$1" in
        *"$2"*) echo yes ;;
        *)      echo no ;;
    esac
}
# table_names  ->  the server names in the window's table, in order.
table_names() { ui_rows "$SERVER_TABLE_ID" "$WIN" | /usr/bin/cut -f1 | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//'; }
# table_marks  ->  what the mark column holds, one "|" per row around the marks.
table_marks() { ui_rows "$SERVER_TABLE_ID" "$WIN" | /usr/bin/cut -f2 | /usr/bin/tr '\n' '|'; }

# -----------------------------------------------------------------------------------------
section "the window says what it is"
note=$(/usr/bin/jq -r --argjson id "$NOTE_ID" '.. | objects | select(.id? == $id) | .properties.text' "$LAYOUT")
check "the line under the list: every server"         "yes" "$(has "$note" "All available MCP servers.")"
check "  and where the choice is made"                "yes" "$(has "$note" "Agentic Session Tools chooses which ones a conversation gets")"
check "  always shown"                                "null" "$(/usr/bin/jq -r --argjson id "$NOTE_ID" '.. | objects | select(.id? == $id) | .properties.hidden' "$LAYOUT")"

# -----------------------------------------------------------------------------------------
section "the generator with every server"
prefs_reset
generate --all-servers >/dev/null
check "the defaults: all four"                 "local pdf time search" "$(names)"
check "  PDF with its editing tools"           "yes" "$(has "$(server_args pdf)" "--writable")"
# Everything that chooses servers, turned the other way: none of it may change the catalog.
cad_call mcp_prefs_set_bool servers/local/enabled false >/dev/null 2>&1
cad_call mcp_prefs_set_bool servers/time/enabled false >/dev/null 2>&1
cad_call mcp_prefs_set_bool servers/pdf/writable false >/dev/null 2>&1
cad_call mcp_prefs_set_bool allow-network false >/dev/null 2>&1
run_in box:s3
box_set pdf false
box_set internet false
generate --all-servers >/dev/null
check "servers turned off, tools set to a box: still all four" "local pdf time search" "$(names)"
check "  PDF still with its editing tools"     "yes" "$(has "$(server_args pdf)" "--writable")"
run_in mac
generate >/dev/null
check "a conversation on this Mac gets its own choice" "pdf" "$(names)"
check "  without PDF editing"                  "no" "$(has "$(server_args pdf)" "--writable")"
# No folder for the PDF server on this Mac: a conversation gets none, the catalog still lists it.
prefs_reset
cad_call mcp_prefs_set_string servers/local/project "" >/dev/null 2>&1
"$cad_plister" set array "$cad_settings" /servers/local/allowed-read >/dev/null 2>&1
"$cad_plister" set array "$cad_settings" /servers/local/allowed-write >/dev/null 2>&1
cad_call mcp_prefs_set_bool servers/local/include-session-tmpdir false >/dev/null 2>&1
generate >/dev/null
check "no folders: a conversation has no PDF server" "local time search" "$(names)"
generate --all-servers >/dev/null
check "  the catalog still has it"             "local pdf time search" "$(names)"
out=$(generate --all-servers --window-folders /nowhere)
check "the option comes alone"                 "yes" "$(has "$out" "cannot be combined")"
check "  and no config is written"             "no" "$([ -f "$CFG" ] && echo yes || echo no)"

# -----------------------------------------------------------------------------------------
section "filling the window"
prefs_reset
run_in box:s3
box_set local false
cad_call mcp_prefs_set_bool servers/time/enabled false >/dev/null 2>&1
lib mcp_inspect_populate "$WIN" >/dev/null 2>&1
check "all four servers, whatever is turned on"   "local pdf time search" "$(table_names)"
check "  no mark on a server that answered"       "||||" "$(table_marks)"
check "  nothing is written to the line under the list" "" "$(ui_value "$NOTE_ID" "$WIN")"
lib mcp_inspect_show_server "$WIN" 0 >/dev/null 2>&1
check "a selection shows the server's command"    "yes" "$(has "$(ui_value "$COMMAND_FIELD_ID" "$WIN")" "/Contents/Support/replay --mcp-server")"
check "  and its tools"                           "yes" "$([ "$(ui_row_count "$TOOLS_TABLE_ID" "$WIN")" -gt 0 ] && echo yes || echo no)"
check "  with their count"                        "yes" "$(has "$(ui_value "$STATUS_ID" "$WIN")" "tool(s)")"

# -----------------------------------------------------------------------------------------
section "a server that did not answer has a warning sign, not a colored dot"
DUMP="$OMCTEST_WORK/dump.json"
printf '%s\n' '{"servers":[{"name":"good","status":"ok","tools":[]},{"name":"bad","status":"failed","error":"no such file"}]}' > "$DUMP"
rows=$("$PY" -B "$REPORT" servers "$DUMP")
WARNING=$(printf '\342\232\240\357\270\217')
check "answered: no mark"   "good||0"          "$(printf '%s\n' "$rows" | /usr/bin/sed -n 1p | /usr/bin/tr '\t' '|')"
check "failed: the sign"    "bad|$WARNING|1"   "$(printf '%s\n' "$rows" | /usr/bin/sed -n 2p | /usr/bin/tr '\t' '|')"
check "its reason"          "Server failed to start: no such file" "$("$PY" -B "$REPORT" summary "$DUMP" 1)"

check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end

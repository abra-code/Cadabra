#!/bin/sh
# Tests/49-mcp-inspect-box-note.test.sh - the MCP Servers window's note for tools set to run in
# an AgentVM box. The window starts and lists this Mac's servers whatever Where tools run says,
# so it has to say when a conversation would start other servers, somewhere else.
#
# No server is started here: the note is read from the settings alone.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.mcp.inspect.library.sh
NOTE_ID=214
WIN="inspect-window-1"

lib() { cad_call_lib "$LIB" "$@"; }
note() { lib mcp_inspect_box_note; }
run_in() { cad_call_lib aichat.mcp.servers.library.sh mcp_tools_set_run_in "$1" >/dev/null; }
box_set() { cad_call_lib aichat.mcp.servers.library.sh mcp_box_set_setting "$1" "$2"; }
prefs_reset() {
    cad_reset
    cad_call mcp_prefs_write_defaults >/dev/null 2>&1
}
# check_contains <description> <text> <part> - the text holds the part.
check_contains() {
    local found=no
    case "$2" in
        *"$3"*) found=yes ;;
    esac
    check "$1" "yes" "$found"
}

# -----------------------------------------------------------------------------------------
section "the id is the layout's"
check "the note's id in the library"  "$NOTE_ID" "$(cad_lib_var BOX_NOTE_ID "$LIB")"
check "the layout has it, hidden"     "true" "$(/usr/bin/jq -r --argjson id "$NOTE_ID" '.. | objects | select(.id? == $id) | .properties.hidden' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Base.lproj/aichat.mcp.inspect.json")"

# -----------------------------------------------------------------------------------------
section "tools on this Mac: nothing to say"
prefs_reset
check "no text"            "" "$(note)"
lib mcp_inspect_show_box_note "$WIN"
check "the note is hidden" "0" "$(ui_visible "$NOTE_ID" "$WIN")"
check "  and empty"        ""  "$(ui_value "$NOTE_ID" "$WIN")"

# -----------------------------------------------------------------------------------------
section "a kept box"
prefs_reset
run_in box:s3
text=$(note)
check_contains "names the box"                  "$text" "run in AgentVM box s3."
check_contains "the box pane's default servers" "$text" "there: Files and shell, PDF, Date & Time."
check_contains "says what the list is"          "$text" "The list above is what runs on this Mac."
check "one line"                                "1" "$(printf '%s\n' "$text" | /usr/bin/awk 'END { print NR }')"
lib mcp_inspect_show_box_note "$WIN"
check "the note is shown"   "1"     "$(ui_visible "$NOTE_ID" "$WIN")"
check "  with the text"     "$text" "$(ui_value "$NOTE_ID" "$WIN")"

# -----------------------------------------------------------------------------------------
section "a new box for each conversation"
prefs_reset
run_in new:dev-agents
check_contains "names the image" "$(note)" "run in a new AgentVM box made from image dev-agents for each conversation."

# -----------------------------------------------------------------------------------------
section "the servers are the box pane's, not this Mac's"
prefs_reset
run_in box:s3
cad_call mcp_prefs_set_bool servers/local/enabled false >/dev/null 2>&1
check_contains "this Mac's choice does not matter" "$(note)" "there: Files and shell, PDF, Date & Time."
box_set local false
box_set internet true
check_contains "the box pane's does"               "$(note)" "there: PDF, Date & Time, Internet."
box_set pdf false
box_set time false
box_set internet false
check_contains "no server at all"                  "$(note)" "there: none."

# -----------------------------------------------------------------------------------------
section "back to this Mac"
run_in mac
lib mcp_inspect_show_box_note "$WIN"
check "the note is hidden again" "0" "$(ui_visible "$NOTE_ID" "$WIN")"
check "  and empty"              ""  "$(ui_value "$NOTE_ID" "$WIN")"

# -----------------------------------------------------------------------------------------
section "a name edited by hand is not shown"
prefs_reset
"$cad_plister" insert runIn string 'box:x](http://example.com) `y`' "$cad_settings" /servers >/dev/null 2>&1
"$cad_plister" set string 'box:x](http://example.com) `y`' "$cad_settings" /servers/runIn >/dev/null 2>&1
check "the setting holds it"  'box:x](http://example.com) `y`' "$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_run_in)"
text=$(note)
check_contains "a box, unnamed" "$text" "run in an AgentVM box."
check "nothing of the name"     "" "$(printf '%s\n' "$text" | /usr/bin/grep -o 'example')"

# -----------------------------------------------------------------------------------------
section "a damaged setting"
prefs_reset
"$cad_plister" remove "$cad_settings" /servers/runIn >/dev/null 2>&1
"$cad_plister" insert runIn dict "$cad_settings" /servers >/dev/null 2>&1
check "reads as damaged"  "damaged" "$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_run_in)"
check_contains "says so"  "$(note)" "Where tools run cannot be read from the settings."

check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end

#!/bin/sh
# Tests/70-mcp-servers-dialog.test.sh - the MCP Servers window.
#
# This dialog is where the user decides what a sandboxed model may reach. Two things make it
# worth testing at the handler level rather than the library level: the toggles have a
# DEPENDENCY structure (a master network gate, and a nested PDF-editing switch) where the
# stored value and the interactive state must move independently, and the read-write table
# mixes persisted rows with one synthetic row whose removal means something entirely different
# from every other row's.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

cad_import_ids aichat.mcp.servers.init.sh MCP_

# The window as it opens, then the one thing each section is about. Blanking every control
# with omc_reset_controls would describe a window no user has ever seen - six toggles off is
# not a state this dialog can be in.
fresh_window() {
    omc_control_defaults aichat.mcp.servers
    ui_reset
    cad_journal_reset
}

# arm_launch <model> <tools> - arm the queue and WAIT until it is actually readable.
#
# The pasteboard is a server, not a file: two writes issued back to back from separate
# processes are not ordered against each other, so an arm can be overtaken by a clear that was
# issued first. That produced a genuinely intermittent failure - four checks, roughly every
# other run - which is exactly the kind of test nobody trusts afterwards. The predicate runs
# under a fresh /bin/sh, so the tool path is expanded here.
#
# It waits for THIS value, not merely for a non-empty one: the key is shared, so "something is
# there now" can be satisfied by a concurrent suite run or by a live Cadabra, and the wait would
# return before our own write landed.
# queue_settle <expected-substring> - wait until the queue really holds it.
# The confirm handler re-arms the queue from its own process, so reading it straight back is a
# race; and a read that loses leaves the arm to land AFTER this file's restore, where the next
# run's snapshot adopts it as "the original" and hands it on forever.
queue_settle() {
    omc_wait_for "\"$OMC_OMC_SUPPORT_PATH/pasteboard\" aichatv2_launch_queue get | /usr/bin/grep -qF '$1'" 5
}

arm_launch() {
    cad_call launch_queue_arm "$1" "$2"
    omc_wait_for "\"$OMC_OMC_SUPPORT_PATH/pasteboard\" aichatv2_launch_queue get | /usr/bin/grep -qF '$1|$2|'" 5
}

# Establish the precondition every section before the queued-launch ones relies on. Earlier
# files in this suite leave a launch armed on this shared key, and inheriting that would make
# the confirm button read "Start" in a section whose whole point is that it reads "Save".
cad_call launch_queue_clear

section "the window's declared defaults were found"
omc_control_defaults aichat.mcp.servers
check "the document's controls loaded" "yes" \
    "$([ "${OMCTEST_DEFAULTS_APPLIED:-0}" -gt 0 ] && echo yes || echo no)"

section "opening the dialog on a profile that has never been configured"
cad_reset
fresh_window
omc_run aichat.mcp.servers.init
check_status "init ran" 0
check "it seeded the servers subtree" "dict" "$(cad_type /servers)"
check "time shows on"    "true" "$(ui_value "$MCP_TIME_TOGGLE_ID")"
check "search shows on"  "true" "$(ui_value "$MCP_SEARCH_TOGGLE_ID")"
check "local shows on"   "true" "$(ui_value "$MCP_LOCAL_TOGGLE_ID")"
check "pdf shows on"     "true" "$(ui_value "$MCP_PDF_TOGGLE_ID")"
check "pdf editing shows on" "true" "$(ui_value "$MCP_PDF_WRITABLE_TOGGLE_ID")"
check "network shows on" "true" "$(ui_value "$MCP_NETWORK_TOGGLE_ID")"
check "the project field is empty" "" "$(ui_value "$MCP_PROJECT_FIELD_ID")"
check "both path tables are titled" "Path" "$(ui_columns "$MCP_RW_TABLE_ID")"
check "  the read-only one too"     "Path" "$(ui_columns "$MCP_RO_TABLE_ID")"
check "the read-write table is populated" "2" "$(ui_row_count "$MCP_RW_TABLE_ID")"
# Named paths rather than a count: the seeded read-only list is guarded by [ -d ] per entry, so
# its length is machine-dependent, but /usr/share exists everywhere and /usr/bin must never be
# in it (the sandbox baseline grants the system bin dirs, this array does not).
check "a system data dir is a row"   "1" \
    "$(ui_rows "$MCP_RO_TABLE_ID" | /usr/bin/grep -Fxq /usr/share && echo 1 || echo 0)"
check "  and a system bin dir is not" "0" \
    "$(ui_rows "$MCP_RO_TABLE_ID" | /usr/bin/grep -Fxq /usr/bin && echo 1 || echo 0)"
check "the - buttons start disabled" "0" "$(ui_enabled "$MCP_RW_REMOVE_BTN_ID")"
check "  both of them"               "0" "$(ui_enabled "$MCP_RO_REMOVE_BTN_ID")"

section "with nothing queued, the confirm button just saves"
check "the button says Save" "Save" "$(ui_prop "$MCP_CONFIRM_BTN_ID" title)"

section "the network gate greys the search server without forgetting it"
# The stored value must survive being greyed out: a user who turns network off and on again
# must get their Search choice back, not the default. Time is not gated: it uses no network.
cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1
cad_call mcp_prefs_set_bool servers/search/enabled false
cad_call mcp_prefs_set_bool allow-network false
fresh_window
omc_run aichat.mcp.servers.init
check "network shows off"        "false" "$(ui_value "$MCP_NETWORK_TOGGLE_ID")"
check "time stays interactive: it uses no network" "no" "$([ "$(ui_enabled "$MCP_TIME_TOGGLE_ID")" = 0 ] && echo greyed || echo no)"
check "search is greyed out"     "0"     "$(ui_enabled "$MCP_SEARCH_TOGGLE_ID")"
check "but time still reads on"  "true"  "$(ui_value "$MCP_TIME_TOGGLE_ID")"
check "and search still reads off" "false" "$(ui_value "$MCP_SEARCH_TOGGLE_ID")"
# The PDF server has no network, so the master gate must not touch it. Asserted because the
# obvious implementation - grey out everything under "servers" - would be wrong here.
check "pdf is untouched by the gate" "1" "$(ui_enabled "$MCP_PDF_WRITABLE_TOGGLE_ID")"

section "the PDF editing switch follows the PDF server"
cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1
cad_call mcp_prefs_set_bool servers/pdf/enabled false
fresh_window
omc_run aichat.mcp.servers.init
check "pdf shows off"                  "false" "$(ui_value "$MCP_PDF_TOGGLE_ID")"
check "editing is greyed out"          "0"     "$(ui_enabled "$MCP_PDF_WRITABLE_TOGGLE_ID")"
check "  but keeps its stored value"   "true"  "$(ui_value "$MCP_PDF_WRITABLE_TOGGLE_ID")"
check "the network toggle's dependent is not greyed" "1" "$(ui_enabled "$MCP_SEARCH_TOGGLE_ID")"

section "toggling network live moves the search server, and persists"
cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1
fresh_window
omc_control "$MCP_NETWORK_TOGGLE_ID" false
omc_run aichat.mcp.servers.toggle.network
check_status "the toggle handler ran" 0
check "the choice is stored"   "false" "$(cad_call mcp_prefs_get_bool allow-network)"
check "time does not grey out" "no"    "$([ "$(ui_enabled "$MCP_TIME_TOGGLE_ID")" = 0 ] && echo greyed || echo no)"
check "search greys out"       "0"     "$(ui_enabled "$MCP_SEARCH_TOGGLE_ID")"
omc_control "$MCP_NETWORK_TOGGLE_ID" true
omc_run aichat.mcp.servers.toggle.network
check "turning it back on stores that" "true" "$(cad_call mcp_prefs_get_bool allow-network)"
check "  and search too"                "1"   "$(ui_enabled "$MCP_SEARCH_TOGGLE_ID")"

section "toggling PDF live moves its nested switch, and persists"
fresh_window
omc_control "$MCP_PDF_TOGGLE_ID" false
omc_run aichat.mcp.servers.toggle.pdf
check_status "the toggle handler ran" 0
check "the choice is stored"    "false" "$(cad_call mcp_prefs_get_bool servers/pdf/enabled)"
check "editing greys out"       "0"     "$(ui_enabled "$MCP_PDF_WRITABLE_TOGGLE_ID")"
# The real claim: the handler moved the control's ENABLED state and never wrote its value.
# An empty ui_value would say the same thing after a ui_reset whether or not that is true.
check "  and its value is left alone" "" "$(cad_journal "$MCP_PDF_WRITABLE_TOGGLE_ID" | /usr/bin/grep -v '^omc_')"
omc_control "$MCP_PDF_TOGGLE_ID" true
omc_run aichat.mcp.servers.toggle.pdf
check "turning it back on stores that" "true" "$(cad_call mcp_prefs_get_bool servers/pdf/enabled)"
check "  and editing is interactive again" "1" "$(ui_enabled "$MCP_PDF_WRITABLE_TOGGLE_ID")"

section "the - buttons follow the selection"
fresh_window
omc_table_cell "$MCP_RO_TABLE_ID" 1 "/usr/share"
omc_run aichat.mcp.servers.ro.selection.changed
check "picking a read-only row enables -" "1" "$(ui_enabled "$MCP_RO_REMOVE_BTN_ID")"
omc_table_cell "$MCP_RO_TABLE_ID" 1 ""
omc_run aichat.mcp.servers.ro.selection.changed
check "clearing it disables - again"      "0" "$(ui_enabled "$MCP_RO_REMOVE_BTN_ID")"
omc_table_cell "$MCP_RW_TABLE_ID" 1 "/private/tmp"
omc_run aichat.mcp.servers.rw.selection.changed
check "and the read-write - too"          "1" "$(ui_enabled "$MCP_RW_REMOVE_BTN_ID")"
omc_table_cell "$MCP_RW_TABLE_ID" 1 ""
omc_run aichat.mcp.servers.rw.selection.changed
check "  and back"                        "0" "$(ui_enabled "$MCP_RW_REMOVE_BTN_ID")"

section "granting a read-only folder"
cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1
/bin/mkdir -p "$OMCTEST_WORK/grant me"
fresh_window
omc_dialog_answer choose_object "$OMCTEST_WORK/grant me"
omc_run aichat.mcp.servers.ro.add
check_status "the add handler ran" 0
check "the folder is granted" "1" \
    "$(cad_call mcp_prefs_array_list servers/local/allowed-read | /usr/bin/grep -Fxq "$OMCTEST_WORK/grant me" && echo 1 || echo 0)"
check "  and appears in the table" "1" \
    "$(ui_rows "$MCP_RO_TABLE_ID" | /usr/bin/grep -Fxq "$OMCTEST_WORK/grant me" && echo 1 || echo 0)"

section "a trailing slash is stripped before storing"
# Otherwise "/foo" and "/foo/" are two different entries in a list whose whole purpose is to
# be compared against, and the duplicate guard never fires.
count_before=$(cad_call mcp_prefs_array_count servers/local/allowed-read)
fresh_window
omc_dialog_answer choose_object "$OMCTEST_WORK/grant me/"
omc_run aichat.mcp.servers.ro.add
check "the same folder with a slash is a duplicate" "$count_before" \
    "$(cad_call mcp_prefs_array_count servers/local/allowed-read)"

section "cancelling the folder picker grants nothing"
count_before=$(cad_call mcp_prefs_array_count servers/local/allowed-read)
fresh_window
omc_dialog_answer choose_object ""
omc_run aichat.mcp.servers.ro.add
check_status "the handler exits cleanly" 0
check "nothing was granted" "$count_before" "$(cad_call mcp_prefs_array_count servers/local/allowed-read)"
check "  and the table was not repainted" "0" "$(cad_writes "$MCP_RO_TABLE_ID")"

section "revoking a read-only folder"
fresh_window
omc_table_cell "$MCP_RO_TABLE_ID" 1 "$OMCTEST_WORK/grant me"
omc_run aichat.mcp.servers.ro.remove
check_status "the remove handler ran" 0
check "the grant is gone" "0" \
    "$(cad_call mcp_prefs_array_list servers/local/allowed-read | /usr/bin/grep -Fxq "$OMCTEST_WORK/grant me" && echo 1 || echo 0)"
check "  and so is the row" "0" \
    "$(ui_rows "$MCP_RO_TABLE_ID" | /usr/bin/grep -Fxq "$OMCTEST_WORK/grant me" && echo 1 || echo 0)"
check "the - button disables itself" "0" "$(ui_enabled "$MCP_RO_REMOVE_BTN_ID")"

section "revoking with no selection does nothing at all"
fresh_window
omc_table_cell "$MCP_RO_TABLE_ID" 1 ""
omc_run aichat.mcp.servers.ro.remove
check_status "the handler exits cleanly" 0
check "the table was not repainted" "0" "$(cad_writes "$MCP_RO_TABLE_ID")"

section "the session temp row is a decision, not a path"
# Removing it must clear include-session-tmpdir rather than delete an array entry - the path
# itself is never stored, because it changes with every login session.
cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1
td=$(cad_call mcp_session_tmpdir)
fresh_window
omc_table_cell "$MCP_RW_TABLE_ID" 1 "$td"
omc_run aichat.mcp.servers.rw.remove
check_status "the remove handler ran" 0
check "the temp grant is revoked" "false" "$(cad_call mcp_prefs_get_bool servers/local/include-session-tmpdir)"
check "  and the stored path is untouched" "1" \
    "$(cad_call mcp_prefs_array_list servers/local/allowed-write | /usr/bin/grep -Fxq /private/tmp && echo 1 || echo 0)"
check "  and the row is gone"     "1" "$(ui_row_count "$MCP_RW_TABLE_ID")"

section "re-granting the session temp restores the decision, not the path"
fresh_window
omc_dialog_answer choose_object "$TMPDIR"
omc_run aichat.mcp.servers.rw.add
check_status "the add handler ran" 0
check "the temp grant is back"  "true" "$(cad_call mcp_prefs_get_bool servers/local/include-session-tmpdir)"
# The reason the handler canonicalizes what it was given: $TMPDIR is handed out in its /var
# form and resolves to /private/var, so a plain string comparison would miss and the volatile
# path would be persisted into the array - going stale at the next login.
# Asserted by RESOLVING every stored entry rather than by grepping for one spelling of the
# path: the handler is handed the /var form and the canonical one is /private/var, so a test
# looking only for the canonical string passes while the raw form sits in the array.
check "  and no stored path resolves to the temp dir" "0" \
    "$(cad_call mcp_prefs_array_list servers/local/allowed-write | while IFS= read -r p; do
           [ "$( (cd "$p" 2>/dev/null && pwd -P) )" = "$td" ] && echo hit
       done | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check "  the array is unchanged"  "1" "$(cad_call mcp_prefs_array_count servers/local/allowed-write)"
check "  and the row is back"     "2" "$(ui_row_count "$MCP_RW_TABLE_ID")"

section "granting an ordinary read-write folder still works"
/bin/mkdir -p "$OMCTEST_WORK/rw grant"
fresh_window
omc_dialog_answer choose_object "$OMCTEST_WORK/rw grant"
omc_run aichat.mcp.servers.rw.add
check "the folder is granted" "1" \
    "$(cad_call mcp_prefs_array_list servers/local/allowed-write | /usr/bin/grep -Fxq "$OMCTEST_WORK/rw grant" && echo 1 || echo 0)"
check "  and the table shows it with the temp row" "3" "$(ui_row_count "$MCP_RW_TABLE_ID")"
fresh_window
omc_table_cell "$MCP_RW_TABLE_ID" 1 "$OMCTEST_WORK/rw grant"
omc_run aichat.mcp.servers.rw.remove
check "revoking it leaves the temp decision alone" "true" \
    "$(cad_call mcp_prefs_get_bool servers/local/include-session-tmpdir)"
check "  and the grant is gone" "0" \
    "$(cad_call mcp_prefs_array_list servers/local/allowed-write | /usr/bin/grep -Fxq "$OMCTEST_WORK/rw grant" && echo 1 || echo 0)"

section "choosing a project workspace"
/bin/mkdir -p "$OMCTEST_WORK/My Workspace"
fresh_window
omc_dialog_answer choose_folder "$OMCTEST_WORK/My Workspace/"
omc_run aichat.mcp.servers.project.browse
check_status "the browse handler ran" 0
check "the field shows the folder"  "$OMCTEST_WORK/My Workspace" "$(ui_value "$MCP_PROJECT_FIELD_ID")"
check "  with the slash stripped"   "$OMCTEST_WORK/My Workspace" "$(cad_call mcp_prefs_get_string servers/local/project)"
fresh_window
omc_dialog_answer choose_folder ""
omc_run aichat.mcp.servers.project.browse
check "cancelling leaves it alone" "$OMCTEST_WORK/My Workspace" "$(cad_call mcp_prefs_get_string servers/local/project)"
check "  and writes nothing to the field" "0" "$(cad_writes "$MCP_PROJECT_FIELD_ID")"

section "Reset to Defaults restores every control and every table"
cad_call mcp_prefs_set_bool allow-network false
cad_call mcp_prefs_set_bool servers/pdf/enabled false
fresh_window
omc_run aichat.mcp.servers.reset
check_status "the reset handler ran" 0
check "network is allowed again" "true" "$(cad_call mcp_prefs_get_bool allow-network)"
check "  and shows it"           "true" "$(ui_value "$MCP_NETWORK_TOGGLE_ID")"
check "pdf is on again"          "true" "$(ui_value "$MCP_PDF_TOGGLE_ID")"
# cad_writes, not an empty ui_value: fresh_window called ui_reset, so "" is also what a field
# nobody wrote reads as - deleting the handler's clear leaves that form green.
check "the project field is cleared" "1"  "$(cad_writes "$MCP_PROJECT_FIELD_ID")"
check "  to the empty string"        ""   "$(ui_value "$MCP_PROJECT_FIELD_ID")"
check "  and so is the stored value" ""  "$(cad_call mcp_prefs_get_string servers/local/project)"
check "search is interactive"    "1" "$(ui_enabled "$MCP_SEARCH_TOGGLE_ID")"
check "pdf editing is interactive" "1" "$(ui_enabled "$MCP_PDF_WRITABLE_TOGGLE_ID")"
check "the tables are repainted"  "2" "$(ui_row_count "$MCP_RW_TABLE_ID")"
check "the - buttons are disabled again" "0" "$(ui_enabled "$MCP_RW_REMOVE_BTN_ID")"

section "confirming saves every toggle the window is showing"
cad_reset
fresh_window
# EVERY toggle set to the OPPOSITE of the seeded default, which is what makes a dropped save
# visible. The handler calls mcp_prefs_init_if_missing first, and that seeds every flag to true
# - so a section that expects "true" anywhere is indistinguishable from one where the handler
# never wrote that flag at all. Deleting the search save from the applet left the earlier
# version of this section, the one named "saves EVERY toggle", entirely green.
omc_control "$MCP_NETWORK_TOGGLE_ID"      false
omc_control "$MCP_TIME_TOGGLE_ID"         false
omc_control "$MCP_SEARCH_TOGGLE_ID"       false
omc_control "$MCP_PDF_TOGGLE_ID"          false
omc_control "$MCP_PDF_WRITABLE_TOGGLE_ID" false
omc_control "$MCP_LOCAL_TOGGLE_ID"        false
omc_control "$MCP_PROJECT_FIELD_ID"       "$OMCTEST_WORK/My Workspace"
chains_reset
omc_run aichat.mcp.servers.start
check_status "the confirm handler ran" 0
# Raw reads. Through mcp_prefs_get_bool the three "true" rows would assert its fallback for an
# absent key, and deleting the search and local writes from the handler left this section - the
# one named "saves EVERY toggle" - entirely green.
check "network saved"      "false" "$(cad_raw /allow-network)"
check "time saved"         "false" "$(cad_raw /servers/time/enabled)"
check "search saved"       "false" "$(cad_raw /servers/search/enabled)"
check "pdf saved"          "false" "$(cad_raw /servers/pdf/enabled)"
check "pdf editing saved"  "false" "$(cad_raw /servers/pdf/writable)"
check "local saved"        "false" "$(cad_raw /servers/local/enabled)"
check "the project saved"  "$OMCTEST_WORK/My Workspace" "$(cad_call mcp_prefs_get_string servers/local/project)"
check "the window closes"  "1"     "$(ui_calls omc_terminate_ok)"
check "and nothing is launched" "0" "$(chain_asked aichat.chat)"

# The section below reads the state this one stored, so say so as an assertion rather than as
# an assumption: reordering or deleting the section above would otherwise silently void it.
check "  precondition: the stored state is all-false" "false false false" \
    "$(cad_raw /allow-network) $(cad_raw /servers/search/enabled) $(cad_raw /servers/local/enabled)"

section "and confirming saves them back on again"
# The mirror of the section above, and it needs no reset: the stored state is all-false now, so
# "true" is the value that differs from disk. Between the two, every toggle is proven to save in
# both directions rather than only away from its default.
fresh_window
omc_control "$MCP_NETWORK_TOGGLE_ID"      true
omc_control "$MCP_TIME_TOGGLE_ID"         true
omc_control "$MCP_SEARCH_TOGGLE_ID"       true
omc_control "$MCP_PDF_TOGGLE_ID"          true
omc_control "$MCP_PDF_WRITABLE_TOGGLE_ID" true
omc_control "$MCP_LOCAL_TOGGLE_ID"        true
omc_control "$MCP_PROJECT_FIELD_ID"       ""
omc_run aichat.mcp.servers.start
check "network saved on"      "true" "$(cad_raw /allow-network)"
check "time saved on"         "true" "$(cad_raw /servers/time/enabled)"
check "search saved on"       "true" "$(cad_raw /servers/search/enabled)"
check "pdf saved on"          "true" "$(cad_raw /servers/pdf/enabled)"
check "pdf editing saved on"  "true" "$(cad_raw /servers/pdf/writable)"
check "local saved on"        "true" "$(cad_raw /servers/local/enabled)"
check "and the project cleared" "" "$(cad_call mcp_prefs_get_string servers/local/project)"

section "a queued launch is taken over by the window, and released on confirm"
# The dialog owns the launch for exactly as long as it is open: init moves it off the global
# queue into a window-scoped key so a second entry point cannot clobber it, and confirming
# re-arms the global queue with a FRESH epoch - the user may have spent minutes in here, and
# the original would have aged past its TTL.
cad_reset
fresh_window
arm_launch "/models/tiny.gguf" "true"
omc_run aichat.mcp.servers.init
check "the button says Start" "Start" "$(ui_prop "$MCP_CONFIRM_BTN_ID" title)"
check "the global queue was emptied" "" "$(cad_pb_get aichatv2_launch_queue)"
check "  and the window holds it" "/models/tiny.gguf|true" \
    "$(cad_pb_get "aichatv2_launch_$OMC_ACTIONUI_WINDOW_UUID" | /usr/bin/sed 's/|[0-9]*$//')"
chains_reset
omc_run aichat.mcp.servers.start
check "confirming opens the chat"  "1" "$(chain_asked aichat.chat)"
check "the window key is released" "" "$(cad_pb_get "aichatv2_launch_$OMC_ACTIONUI_WINDOW_UUID")"
queue_settle "/models/tiny.gguf|true|"
q=$(cad_call launch_queue_consume)
check "the launch is re-armed and fresh" "/models/tiny.gguf|true" "$q"

section "cancelling drops the launch this dialog owned"
cad_reset
fresh_window
arm_launch "/models/tiny.gguf" "true"
omc_run aichat.mcp.servers.init
chains_reset
omc_run aichat.mcp.servers.cancel
check_status "the cancel handler ran" 0
check "the window key is cleared" "" "$(cad_pb_get "aichatv2_launch_$OMC_ACTIONUI_WINDOW_UUID")"
check "nothing is queued globally" "" "$(cad_call launch_queue_consume)"
check "and no chat window opens"   "0" "$(chain_asked aichat.chat)"

section "a launch that runs the agent in a box shows the box panel instead of the servers"
cad_reset
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
cad_call acp_agent_set_run_in claude-code-acp new:dev-agents
cad_call acp_agent_set_read_only claude-code-acp yes
fresh_window
arm_launch "" "false"
omc_run aichat.mcp.servers.init
check "the servers and paths give way"   "0|1" "$(ui_visible "$MCP_SERVERS_AREA_ID")|$(ui_visible "$MCP_BOX_PANEL_ID")"
check "  and so does Reset to Defaults"  "0" "$(ui_visible "$MCP_RESET_BTN_ID")"
check "it says where the agent runs"     "Runs in a new disposable AgentVM box from dev-agents" "$(ui_value "$MCP_BOX_WHERE_TEXT_ID")"
check "  with the agent's read-only choice" "true" "$(ui_value "$MCP_BOX_READ_ONLY_TOGGLE_ID")"
check "the window keeps the agent for Start" "claude-code-acp" "$(cad_pb_get "aichatv2_toolsbox_$OMC_ACTIONUI_WINDOW_UUID")"
omc_control "$MCP_BOX_READ_ONLY_TOGGLE_ID" false
chains_reset
omc_run aichat.mcp.servers.start
check "Start stores the choice for the agent" "no" "$(cad_call acp_agent_read_only claude-code-acp)"
check "  forgets the agent"              "" "$(cad_pb_get "aichatv2_toolsbox_$OMC_ACTIONUI_WINDOW_UUID")"
check "  and opens the chat"             "1" "$(chain_asked aichat.chat)"
queue_settle "|false|"
cad_call launch_queue_clear

section "a kept box is named, and an unreadable place is said to be one"
cad_call acp_agent_set_run_in claude-code-acp box:s3
fresh_window
arm_launch "" "false"
omc_run aichat.mcp.servers.init
check "a kept box"                       "Runs in the kept AgentVM box s3" "$(ui_value "$MCP_BOX_WHERE_TEXT_ID")"
check "  shared read-write, as stored"   "false" "$(ui_value "$MCP_BOX_READ_ONLY_TOGGLE_ID")"
# The other direction: the section above stores "no", which a Start that ignored the toggle
# (or found it unset) would store too.
omc_control "$MCP_BOX_READ_ONLY_TOGGLE_ID" true
chains_reset
omc_run aichat.mcp.servers.start
check "Start stores a read-only choice"  "yes" "$(cad_call acp_agent_read_only claude-code-acp)"
queue_settle "|false|"
cad_call launch_queue_clear
"$cad_plister" set dict "$cad_settings" /agents/runIn/claude-code-acp >/dev/null 2>&1
fresh_window
arm_launch "" "false"
omc_run aichat.mcp.servers.init
check "a place that cannot be read is still box mode" "1|1" "$(ui_visible "$MCP_BOX_PANEL_ID")|$(cad_has "$(ui_value "$MCP_BOX_WHERE_TEXT_ID")" 'cannot be read')"
omc_run aichat.mcp.servers.cancel
check "cancel forgets the agent"         "" "$(cad_pb_get "aichatv2_toolsbox_$OMC_ACTIONUI_WINDOW_UUID")"
cad_call launch_queue_clear

section "a read-only choice that cannot be saved keeps the dialog open"
cad_reset
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
cad_call acp_agent_set_run_in claude-code-acp new:dev-agents
# A string where the per-agent dict belongs: the write under it cannot land.
"$cad_plister" set string blocked "$cad_settings" /agents/readOnly >/dev/null 2>&1
fresh_window
arm_launch "" "false"
omc_run aichat.mcp.servers.init
omc_control "$MCP_BOX_READ_ONLY_TOGGLE_ID" true
chains_reset
alerts_reset
omc_run aichat.mcp.servers.start
check "it says so"                       "1" "$(alerts_mention 'Could not save whether the project is shared read-only')"
check "  the window stays open"          "0" "$(ui_calls omc_terminate_ok)"
check "  nothing is launched"            "0" "$(chain_asked aichat.chat)"
check "  and the agent is kept for another try" "claude-code-acp" "$(cad_pb_get "aichatv2_toolsbox_$OMC_ACTIONUI_WINDOW_UUID")"
omc_run aichat.mcp.servers.cancel
cad_call launch_queue_clear

section "Start refuses when the agent, or where it runs, changed while the window was open"
# Chat init starts whatever agent is stored when it runs, so the choice made here must be for it.
cad_reset
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
cad_call acp_agent_set_run_in claude-code-acp new:dev-agents
fresh_window
arm_launch "" "false"
omc_run aichat.mcp.servers.init
check "the caption names the share"      "1" "$(cad_has "$(ui_value "$MCP_PROJECT_NOTE_ID")" 'shared with the AgentVM box')"
cad_call acp_agent_set_run_in codex-acp box:s3
cad_call acp_agent_store codex-acp "codex-acp"
cad_call acp_agent_set_read_only codex-acp no
omc_control "$MCP_BOX_READ_ONLY_TOGGLE_ID" true
chains_reset
alerts_reset
omc_run aichat.mcp.servers.start
check "another agent chosen meanwhile is refused" "1" "$(alerts_mention 'changed while this window was open')"
check "  storing nothing for either"     "no|no" "$(cad_call acp_agent_read_only claude-code-acp)|$(cad_call acp_agent_read_only codex-acp)"
check "  and starting nothing"           "0|0" "$(chain_asked aichat.chat)|$(ui_calls omc_terminate_ok)"
cad_call acp_agent_set_run_in codex-acp mac
alerts_reset
omc_run aichat.mcp.servers.start
check "  so is the agent moved to this Mac" "1|0" "$(alerts_mention 'changed while this window was open')|$(chain_asked aichat.chat)"
omc_run aichat.mcp.servers.cancel
cad_call launch_queue_clear

section "a toggle with no value keeps the stored share mode"
cad_reset
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
cad_call acp_agent_set_run_in claude-code-acp new:dev-agents
cad_call acp_agent_set_read_only claude-code-acp yes
fresh_window
arm_launch "" "false"
omc_run aichat.mcp.servers.init
omc_control "$MCP_BOX_READ_ONLY_TOGGLE_ID" ""
chains_reset
omc_run aichat.mcp.servers.start
check "read-only stays read-only"        "yes|1" "$(cad_call acp_agent_read_only claude-code-acp)|$(chain_asked aichat.chat)"
queue_settle "|false|"
cad_call launch_queue_clear

section "an agent in a box with Cadabra's tools gets the box pane"
cad_reset
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
cad_call acp_agent_set_run_in claude-code-acp new:dev-agents
cad_call acp_agent_set_read_only claude-code-acp yes
fresh_window
arm_launch "" "true"
omc_run aichat.mcp.servers.init
check "the box pane, not the agent panel" "1|no" \
    "$(ui_visible "$MCP_TOOLS_BOX_PANE_ID")|$([ "$(ui_visible "$MCP_BOX_PANEL_ID")" = 1 ] && echo yes || echo no)"
check "  saying where the agent runs, with the tools" "Runs in a new disposable AgentVM box from dev-agents, with Cadabra's tools" "$(ui_value "$MCP_TOOLS_BOX_WHERE_TEXT_ID")"
check "  with the agent's own read-only choice" "true" "$(ui_value "$MCP_TOOLS_BOX_READ_ONLY_TOGGLE_ID")"
check "  and no Where tools run row: the agent's place decides" "no" "$([ "$(ui_visible "$MCP_TOOLS_RUNIN_ROW_ID")" = 1 ] && echo yes || echo no)"
omc_control "$MCP_TOOLS_BOX_READ_ONLY_TOGGLE_ID" false
omc_control "$MCP_TOOLS_BOX_INTERNET_TOGGLE_ID" true
chains_reset
omc_run aichat.mcp.servers.start
check "Start stores the agent's read-only choice and the box settings" "no|true|1" \
    "$(cad_call acp_agent_read_only claude-code-acp)|$(cad_call_lib aichat.mcp.servers.library.sh mcp_box_setting internet)|$(chain_asked aichat.chat)"
check "  and forgets which panel was shown" "" "$(cad_pb_get "aichatv2_toolsboxpane_$OMC_ACTIONUI_WINDOW_UUID")"
queue_settle "|true|"
cad_call launch_queue_clear

section "the same agent on this Mac, a local model, and the Tools menu keep the servers"
cad_reset
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
fresh_window
arm_launch "" "true"
omc_run aichat.mcp.servers.init
# Untouched reads empty, so assert what the user meets: the servers not hidden, the panel not shown.
check "an agent on this Mac"             "servers|no panel" "$([ "$(ui_visible "$MCP_SERVERS_AREA_ID")" = 0 ] && echo hidden || echo servers)|$([ "$(ui_visible "$MCP_BOX_PANEL_ID")" = 1 ] && echo panel || echo 'no panel')"
check "  keeps no agent for Start"       "" "$(cad_pb_get "aichatv2_toolsbox_$OMC_ACTIONUI_WINDOW_UUID")"
omc_run aichat.mcp.servers.cancel
cad_call acp_agent_set_run_in claude-code-acp new:dev-agents
fresh_window
arm_launch "/models/tiny.gguf" "true"
omc_run aichat.mcp.servers.init
check "a local model, with a boxed agent stored" "" "$(cad_pb_get "aichatv2_toolsbox_$OMC_ACTIONUI_WINDOW_UUID")"
omc_run aichat.mcp.servers.cancel
cad_call launch_queue_clear
# "yes" stored first: a Save that stored the (unset) toggle would turn it into "no".
cad_call acp_agent_set_read_only claude-code-acp yes
fresh_window
omc_run aichat.mcp.servers.init
check "the Tools menu (nothing queued)"  "" "$(cad_pb_get "aichatv2_toolsbox_$OMC_ACTIONUI_WINDOW_UUID")"
chains_reset
omc_run aichat.mcp.servers.start
check "  whose Save stores no share mode" "yes" "$(cad_call acp_agent_read_only claude-code-acp)"
check "  and opens nothing"              "0" "$(chain_asked aichat.chat)"

section "where a local model's tools run: offered only where boxes can be used"
cad_reset
fresh_window
arm_launch "/models/tiny.gguf" "true"
omc_run aichat.mcp.servers.init
check "no agent-vm: the row stays hidden" "no" "$([ "$(ui_visible "$MCP_TOOLS_RUNIN_ROW_ID")" = 1 ] && echo yes || echo no)"
check "  and Start has nothing to store"  "" "$(cad_pb_get "aichatv2_toolsrunin_$OMC_ACTIONUI_WINDOW_UUID")"
omc_run aichat.mcp.servers.cancel
cad_call launch_queue_clear
cad_call_lib aichat.mcp.servers.library.sh mcp_tools_set_run_in new:dev
fresh_window
arm_launch "/models/tiny.gguf" "true"
omc_run aichat.mcp.servers.init
check "no agent-vm, but a box stored: the row offers the way back" "1|1|1" \
    "$(ui_visible "$MCP_TOOLS_RUNIN_ROW_ID")|$(cad_has "$(ui_prop "$MCP_TOOLS_RUNIN_PICKER_ID" options)" '"tag":"mac"')|$(cad_has "$(ui_prop "$MCP_TOOLS_RUNIN_PICKER_ID" options)" '"dev (not found)"')"
omc_control "$MCP_TOOLS_RUNIN_PICKER_ID" mac
chains_reset
omc_run aichat.mcp.servers.start
check "  and Start stores This Mac"       "mac" "$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_run_in)"
queue_settle "/models/tiny.gguf|true|"
cad_call launch_queue_clear

section "where a local model's tools run: This Mac, a kept box, or a new disposable box"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
/bin/rm -rf "$FAKE_AGENTVM_DIR"; /bin/mkdir -p "$FAKE_AGENTVM_DIR"
CADABRA_AGENT_VM="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
export FAKE_AGENTVM_DIR CADABRA_AGENT_VM
# tools_options  ->  the Where tools run picker's option tags, space-joined.
tools_options() {
    ui_prop "$MCP_TOOLS_RUNIN_PICKER_ID" options | "$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3" -c \
        'import json, sys; print(" ".join(o.get("tag", "|" + o.get("section", "-")) for o in json.load(sys.stdin)))' 2>&1
}
cad_reset
fresh_window
arm_launch "/models/tiny.gguf" "true"
omc_run aichat.mcp.servers.init
check "a local model's launch shows the row" "1" "$(ui_visible "$MCP_TOOLS_RUNIN_ROW_ID")"
check "  offering the places" \
    "mac |Kept AgentVM boxes box:cadabra-spike box:try1 |New disposable AgentVM box from new:dev new:dev-agents new:dev-node new:dev-xcode new:dev-xcode-ios" \
    "$(tools_options)"
check "  on this Mac by default, with this Mac's servers" "mac|1|0" \
    "$(ui_value "$MCP_TOOLS_RUNIN_PICKER_ID")|$(ui_visible "$MCP_MAC_SERVERS_ID")|$(ui_visible "$MCP_TOOLS_BOX_PANE_ID")"
check "  the box pane at its defaults" "true|false|true|true|true|false|false" \
    "$(for v in $MCP_TOOLS_BOX_LOCAL_TOGGLE_ID $MCP_TOOLS_BOX_CONFINE_TOGGLE_ID $MCP_TOOLS_BOX_PDF_TOGGLE_ID $MCP_TOOLS_BOX_PDF_WRITABLE_TOGGLE_ID $MCP_TOOLS_BOX_TIME_TOGGLE_ID $MCP_TOOLS_BOX_INTERNET_TOGGLE_ID $MCP_TOOLS_BOX_READ_ONLY_TOGGLE_ID; do printf "%s\n" "$(ui_value $v)"; done | /usr/bin/paste -sd'|' -)"
omc_control "$MCP_TOOLS_RUNIN_PICKER_ID" new:dev
omc_run aichat.mcp.servers.runin.changed
check "choosing a box swaps this Mac's servers for the box pane" "0|1" "$(ui_visible "$MCP_MAC_SERVERS_ID")|$(ui_visible "$MCP_TOOLS_BOX_PANE_ID")"
check "  saying which box"                "1" "$(cad_has "$(ui_value "$MCP_TOOLS_BOX_WHERE_TEXT_ID")" 'new disposable AgentVM box from dev')"
# sheet  ->  the Markdown of the information sheet last presented on the window.
sheet() { /usr/bin/jq -r '.children[0].properties.markdown' "$HOME/Library/Application Support/Cadabra/Run/tools-info.$OMC_ACTIONUI_WINDOW_UUID.json" 2>/dev/null; }
cad_journal_reset
omc_run aichat.mcp.servers.box.network
check "  Network Rules... presents a sheet" "1" "$(cad_has "$(cad_journal omc_window)" "omc_present_modal $HOME/Library/Application Support/Cadabra/Run/tools-info.$OMC_ACTIONUI_WINDOW_UUID.json")"
check "  saying what a new box reaches" "1|1" \
    "$(cad_has "$(sheet)" '## Network of a new AgentVM box from dev')|$(cad_has "$(sheet)" 'reaches nothing, or any public host with **Internet** on')"
omc_control "$MCP_TOOLS_RUNIN_PICKER_ID" box:cadabra-spike
omc_run aichat.mcp.servers.runin.changed
omc_run aichat.mcp.servers.box.network
check "a kept box's own rules are listed there, not in the pane" "1|1|1" \
    "$(cad_has "$(sheet)" '## Network of the AgentVM box cadabra-spike')|$(cad_has "$(sheet)" 'reach only these hosts and packs of hosts')|$(cad_has "$(sheet)" '- `pack:npm`')"
omc_control "$MCP_PROJECT_FIELD_ID" "/Users/me/src/app"
omc_run aichat.mcp.servers.box.sandbox
check "Paths... lists what the sandbox lets the tools change and read" "1|1|1|1" \
    "$(cad_has "$(sheet)" '- `/Users/me/src/app` (the project)')|$(cad_has "$(sheet)" '- `/private/tmp`')|$(cad_has "$(sheet)" '- `/opt/homebrew`')|$(cad_has "$(sheet)" 'home folder')"
check "  the sheet is valid JSON with a Done button" "aichat.mcp.servers.info.done" \
    "$(/usr/bin/jq -r '.children[1].children[1].properties.actionID' "$HOME/Library/Application Support/Cadabra/Run/tools-info.$OMC_ACTIONUI_WINDOW_UUID.json")"
cad_journal_reset
omc_run aichat.mcp.servers.info.done
check "Done dismisses it and removes its file" "1|gone" \
    "$(cad_has "$(cad_journal omc_window)" 'omc_dismiss_modal')|$([ -f "$HOME/Library/Application Support/Cadabra/Run/tools-info.$OMC_ACTIONUI_WINDOW_UUID.json" ] && echo there || echo gone)"
omc_control "$MCP_TOOLS_RUNIN_PICKER_ID" new:dev
omc_run aichat.mcp.servers.runin.changed
omc_control "$MCP_TOOLS_BOX_READ_ONLY_TOGGLE_ID" true
omc_control "$MCP_TOOLS_BOX_CONFINE_TOGGLE_ID" true
omc_control "$MCP_TOOLS_BOX_INTERNET_TOGGLE_ID" true
omc_control "$MCP_TOOLS_BOX_TIME_TOGGLE_ID" false
chains_reset
omc_run aichat.mcp.servers.start
check "Start stores the place and the box pane" "new:dev|yes|true|true|false|true" \
    "$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_run_in)|$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_read_only)|$(for n in confineLocal internet time local; do cad_call_lib aichat.mcp.servers.library.sh mcp_box_setting $n; done | /usr/bin/paste -sd'|' -)"
check "  and opens the chat"              "1" "$(chain_asked aichat.chat)"
queue_settle "/models/tiny.gguf|true|"
cad_call launch_queue_clear
fresh_window
arm_launch "/models/tiny.gguf" "true"
omc_run aichat.mcp.servers.init
check "the next launch shows the stored choice" "new:dev|true|true|true|0|1" \
    "$(ui_value "$MCP_TOOLS_RUNIN_PICKER_ID")|$(ui_value "$MCP_TOOLS_BOX_READ_ONLY_TOGGLE_ID")|$(ui_value "$MCP_TOOLS_BOX_CONFINE_TOGGLE_ID")|$(ui_value "$MCP_TOOLS_BOX_INTERNET_TOGGLE_ID")|$(ui_visible "$MCP_MAC_SERVERS_ID")|$(ui_visible "$MCP_TOOLS_BOX_PANE_ID")"
omc_control "$MCP_TOOLS_RUNIN_PICKER_ID" mac
omc_run aichat.mcp.servers.runin.changed
check "back to this Mac brings its servers back" "1|0" "$(ui_visible "$MCP_MAC_SERVERS_ID")|$(ui_visible "$MCP_TOOLS_BOX_PANE_ID")"
omc_control "$MCP_TOOLS_RUNIN_PICKER_ID" damaged
chains_reset
alerts_reset
omc_run aichat.mcp.servers.start
check "an unreadable choice keeps the dialog open" "0|1" "$(chain_asked aichat.chat)|$(alerts_mention 'Where the tools run cannot be read')"
check "  and stores nothing"              "new:dev" "$(cad_call_lib aichat.mcp.servers.library.sh mcp_tools_run_in)"
omc_run aichat.mcp.servers.reset
check "Reset to Defaults shows the box pane's defaults too" "true|false|true|true|true|false|false" \
    "$(for v in $MCP_TOOLS_BOX_LOCAL_TOGGLE_ID $MCP_TOOLS_BOX_CONFINE_TOGGLE_ID $MCP_TOOLS_BOX_PDF_TOGGLE_ID $MCP_TOOLS_BOX_PDF_WRITABLE_TOGGLE_ID $MCP_TOOLS_BOX_TIME_TOGGLE_ID $MCP_TOOLS_BOX_INTERNET_TOGGLE_ID $MCP_TOOLS_BOX_READ_ONLY_TOGGLE_ID; do printf "%s\n" "$(ui_value $v)"; done | /usr/bin/paste -sd'|' -)"
omc_run aichat.mcp.servers.cancel
cad_call launch_queue_clear
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
fresh_window
arm_launch "" "true"
omc_run aichat.mcp.servers.init
check "an external agent's launch has no such row" "no|" \
    "$([ "$(ui_visible "$MCP_TOOLS_RUNIN_ROW_ID")" = 1 ] && echo yes || echo no)|$(cad_pb_get "aichatv2_toolsrunin_$OMC_ACTIONUI_WINDOW_UUID")"
omc_run aichat.mcp.servers.cancel
cad_call launch_queue_clear
CADABRA_AGENT_VM="$OMCTEST_WORK/no-agent-vm-in-tests"

# Leave the shared key as this file found it, before the trap restores the snapshot. Anything
# this file armed is finished with by here, and letting it survive is what makes a lost race
# sticky across runs.
cad_call launch_queue_clear

section "snapshot the project first: one setting in a box, one on this Mac"
SNAPSHOT_TOGGLE_ID=313
check "  (the toggle's id is the library's)" "$SNAPSHOT_TOGGLE_ID" "$(cad_lib_var mcp_snapshot_toggle_view aichat.mcp.servers.library.sh)"
# snap  ->  the toggle's value, then 1 or 0 for whether it can be changed.
snap() { printf '%s|%s' "$(ui_value "$SNAPSHOT_TOGGLE_ID")" "$(ui_enabled "$SNAPSHOT_TOGGLE_ID")"; }
setting() { cad_call_lib aichat.mcp.servers.library.sh mcp_snapshot_setting "$1"; }
cad_reset
fresh_window
omc_run aichat.mcp.servers.init
check "without agent-vm it shows this Mac's setting, off, and cannot be changed" "false|0" "$(snap)"
check "  saying what it needs"           "1" "$(cad_has "$(ui_prop "$SNAPSHOT_TOGGLE_ID" help)" 'A snapshot needs AgentVM')"
omc_run aichat.mcp.servers.cancel
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
/bin/rm -rf "$FAKE_AGENTVM_DIR"; /bin/mkdir -p "$FAKE_AGENTVM_DIR"
CADABRA_AGENT_VM="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
export FAKE_AGENTVM_DIR CADABRA_AGENT_VM
check "the defaults: off on this Mac, on in a box" "false|true" "$(setting mac)|$(setting box)"
fresh_window
arm_launch "/models/tiny.gguf" "true"
omc_run aichat.mcp.servers.init
check "a local model's tools on this Mac: this Mac's setting, which can be changed" "false|1" "$(snap)"
omc_control "$MCP_TOOLS_RUNIN_PICKER_ID" new:dev
omc_run aichat.mcp.servers.runin.changed
check "tools in a box: the box's setting"  "true|1" "$(snap)"
omc_control "$MCP_TOOLS_BOX_READ_ONLY_TOGGLE_ID" true
omc_run aichat.mcp.servers.readonly.changed
check "a read-only project takes no snapshot" "true|0" "$(snap)"
check "  saying so"                       "1" "$(cad_has "$(ui_prop "$SNAPSHOT_TOGGLE_ID" help)" 'shared read-only')"
omc_control "$MCP_TOOLS_BOX_READ_ONLY_TOGGLE_ID" false
omc_run aichat.mcp.servers.readonly.changed
check "  and read-write again can"        "true|1" "$(snap)"
omc_control "$SNAPSHOT_TOGGLE_ID" false
chains_reset
omc_run aichat.mcp.servers.start
check "Start stores it for the box, not for this Mac" "false|false" "$(setting box)|$(setting mac)"
queue_settle "/models/tiny.gguf|true|"
cad_call launch_queue_clear
fresh_window
arm_launch "/models/tiny.gguf" "true"
omc_run aichat.mcp.servers.init
check "the next launch in a box shows it" "false|1" "$(snap)"
omc_control "$MCP_TOOLS_RUNIN_PICKER_ID" mac
omc_run aichat.mcp.servers.runin.changed
omc_control "$SNAPSHOT_TOGGLE_ID" true
chains_reset
omc_run aichat.mcp.servers.start
check "and on this Mac, for this Mac"     "true|false" "$(setting mac)|$(setting box)"
queue_settle "/models/tiny.gguf|true|"
cad_call launch_queue_clear
fresh_window
omc_run aichat.mcp.servers.init
omc_run aichat.mcp.servers.reset
check "Reset to Defaults shows the default of where the tools run" "false|1" "$(snap)"
check "  and stored it"                   "false|true" "$(setting mac)|$(setting box)"
omc_run aichat.mcp.servers.cancel
cad_call acp_agent_store claude-code-acp "claude-agent-acp"
cad_call acp_agent_set_run_in claude-code-acp new:dev-agents
cad_call acp_agent_set_read_only claude-code-acp yes
fresh_window
arm_launch "" "false"
omc_run aichat.mcp.servers.init
check "an agent in a box, read-only: the box's setting, fixed" "true|0" "$(snap)"
omc_control "$MCP_BOX_READ_ONLY_TOGGLE_ID" false
omc_run aichat.mcp.servers.readonly.changed
check "  read-write in its panel: it can be changed" "true|1" "$(snap)"
omc_control "$SNAPSHOT_TOGGLE_ID" false
chains_reset
omc_run aichat.mcp.servers.start
check "  and Start stores it for the box" "false|false" "$(setting box)|$(setting mac)"
queue_settle "|false|"
cad_call launch_queue_clear
cad_call acp_agent_set_run_in claude-code-acp mac
fresh_window
arm_launch "" "true"
omc_run aichat.mcp.servers.init
check "an agent on this Mac: this Mac's setting" "false|1" "$(snap)"
omc_control "$SNAPSHOT_TOGGLE_ID" true
chains_reset
omc_run aichat.mcp.servers.start
check "  which Start stores"              "true|false" "$(setting mac)|$(setting box)"
queue_settle "|true|"
cad_call launch_queue_clear
CADABRA_AGENT_VM="$OMCTEST_WORK/no-agent-vm-in-tests"

section "a link cannot run the dialog's handlers"
# OMC runs any command id for a link, cadabra://exe?commandID=<id>, with no window: the handlers
# that store the window's values would store their fallbacks (every server on, no project).
cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1
fresh_window
cad_call mcp_prefs_set_bool allow-network false
cad_call mcp_prefs_set_bool servers/pdf/enabled false
cad_call mcp_prefs_set_bool servers/local/enabled false
cad_call mcp_prefs_set_string servers/local/project "/Users/me/src/app"
link_settings() {
    printf '%s|%s|%s|%s' "$(cad_raw /allow-network)" "$(cad_raw /servers/pdf/enabled)" "$(cad_raw /servers/local/enabled)" "$(cad_raw /servers/local/project)"
}
agents_before="$(cad_call acp_custom_list | /usr/bin/awk 'END { print NR }')"
for link_command in aichat.mcp.servers.reset aichat.mcp.servers.toggle.network aichat.mcp.servers.toggle.pdf aichat.mcp.servers.start aichat.select.external.agent.add; do
    ( unset OMC_ACTIONUI_WINDOW_UUID ACTIONUI_WINDOW_UUID; omc_run "$link_command" )
done
check "reset, the toggles and Start change no setting without a window" "false|false|false|/Users/me/src/app" "$(link_settings)"
check "  and Add saves no agent"          "$agents_before" "$(cad_call acp_custom_list | /usr/bin/awk 'END { print NR }')"
omc_control "$MCP_NETWORK_TOGGLE_ID" true
omc_run aichat.mcp.servers.toggle.network
check "the window's own toggle still stores" "true" "$(cad_raw /allow-network)"

section "cumulative: no handler wrote to a view id the window does not declare"
# Cumulative across the whole file, which is what makes one check at the end meaningful.
# It was not always: ui_reset used to DELETE unknown_ids.log along with the windows, so this
# covered only what happened since the last reset - close to nothing in a file that resets per
# section, and a handler scribbling on a made-up view id went entirely unnoticed. omctest API 4
# carries the three diagnostic logs across a reset, and this lib asserts that minimum.
check "no undeclared ids" "" "$(ui_unknown_writes)"
check "no table clobbered by a bare value write" "" "$(ui_suspect_writes)"

omctest_end

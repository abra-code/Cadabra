#!/bin/sh
# aichat.mcp.servers.init.sh
# Populates the MCP servers dialog from $mcp_prefs (creating defaults if missing).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"
# For box mode: the agent a queued launch runs in a box, and its read-only choice.
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.acp.agents.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

TIME_TOGGLE_ID=210
SEARCH_TOGGLE_ID=220
LOCAL_TOGGLE_ID=230
NETWORK_TOGGLE_ID=240
PDF_TOGGLE_ID=260
PDF_WRITABLE_TOGGLE_ID=261
PROJECT_FIELD_ID=310
RW_TABLE_ID=320
RW_REMOVE_BTN_ID=322
RO_TABLE_ID=330
RO_REMOVE_BTN_ID=332

mcp_prefs_init_if_missing

# Toggles
"$dialog" "$window_uuid" $TIME_TOGGLE_ID   "$(mcp_prefs_get_bool servers/time/enabled)"
"$dialog" "$window_uuid" $SEARCH_TOGGLE_ID "$(mcp_prefs_get_bool servers/search/enabled)"
"$dialog" "$window_uuid" $LOCAL_TOGGLE_ID  "$(mcp_prefs_get_bool servers/local/enabled)"
# PDF (pdfutil): no network - not gated by the Allow Network switch below. Its nested
# "Allow PDF editing" toggle serves pdfutil's mutating tools (create-only outputs, each
# one permission-gated) and is only interactive while the PDF server itself is on.
pdf_enabled=$(mcp_prefs_get_bool servers/pdf/enabled)
"$dialog" "$window_uuid" $PDF_TOGGLE_ID          "$pdf_enabled"
"$dialog" "$window_uuid" $PDF_WRITABLE_TOGGLE_ID "$(mcp_prefs_get_bool servers/pdf/writable)"
if [ "$pdf_enabled" = "true" ]; then
    "$dialog" "$window_uuid" $PDF_WRITABLE_TOGGLE_ID omc_enable
else
    "$dialog" "$window_uuid" $PDF_WRITABLE_TOGGLE_ID omc_disable
fi

# Allow Network master gate. When off, the network-dependent server toggles are
# greyed out (their stored values are kept and restored when network is re-enabled).
allow_network=$(mcp_prefs_get_bool allow-network)
"$dialog" "$window_uuid" $NETWORK_TOGGLE_ID "$allow_network"
if [ "$allow_network" = "true" ]; then
    "$dialog" "$window_uuid" $TIME_TOGGLE_ID   omc_enable
    "$dialog" "$window_uuid" $SEARCH_TOGGLE_ID omc_enable
else
    "$dialog" "$window_uuid" $TIME_TOGGLE_ID   omc_disable
    "$dialog" "$window_uuid" $SEARCH_TOGGLE_ID omc_disable
fi

# Project workspace TextField
project_path=$(mcp_prefs_get_string servers/local/project)
"$dialog" "$window_uuid" $PROJECT_FIELD_ID "$project_path"

# Configure single-column tables
"$dialog" "$window_uuid" $RW_TABLE_ID omc_table_set_columns "Path"
"$dialog" "$window_uuid" $RW_TABLE_ID omc_table_set_column_widths 560
"$dialog" "$window_uuid" $RO_TABLE_ID omc_table_set_columns "Path"
"$dialog" "$window_uuid" $RO_TABLE_ID omc_table_set_column_widths 560

# Populate path tables from prefs. The read-write table also shows the session
# $TMPDIR as a removable (but unstored) row; see mcp_refresh_rw_table.
mcp_refresh_rw_table "$window_uuid" $RW_TABLE_ID
mcp_refresh_path_table "$window_uuid" $RO_TABLE_ID servers/local/allowed-read

# - buttons start disabled until the user picks a row
"$dialog" "$window_uuid" $RW_REMOVE_BTN_ID omc_disable
"$dialog" "$window_uuid" $RO_REMOVE_BTN_ID omc_disable

# Take ownership of a queued launch (the model selector routed here with tools enabled):
# move it from the global queue into this window's own key, so it lives exactly as long
# as this dialog - another entry point queueing a launch meanwhile can't clobber it, and
# a quit with the dialog open leaves nothing armed. The confirm button reflects what
# confirming does: launching the queued session ("Start") or just saving prefs ("Save",
# when opened from Tools > Configure MCP Servers with nothing queued).
CONFIRM_BTN_ID=393
queued=$(launch_queue_consume)
pb_set "aichatv2_launch_${window_uuid}" "$queued"
# The launch's destination travels with it, for the same reason and by the same route: a
# launch aimed at an already-open window (File > New Chat Window, then a model) must not
# still be aimed there if this dialog is cancelled, or the next ordinary pick would be
# delivered into that window instead of opening its own.
pb_set "aichatv2_loadtarget_${window_uuid}" "$(load_target_consume)"
if [ -n "$queued" ]; then
    "$dialog" "$window_uuid" $CONFIRM_BTN_ID omc_set_property "title" "Start"
else
    "$dialog" "$window_uuid" $CONFIRM_BTN_ID omc_set_property "title" "Save"
fi

# BOX MODE, for a launch that runs the external agent in an agent-vm box. Cadabra's servers and
# the sandbox paths do not apply there (the agent brings its own tools, and the box sees only the
# project), so their area gives way to the box panel: where the agent runs, what is shared, and
# whether the project is shared read-only. The two sit in one ZStack, since a hidden view keeps
# its space. Reset to Defaults goes too: it writes the hidden settings at once. The agent is kept
# for Start, which stores the read-only choice for it.
SERVERS_AREA_ID=150
BOX_PANEL_ID=500
BOX_WHERE_TEXT_ID=501
BOX_READ_ONLY_TOGGLE_ID=502
RESET_BTN_ID=391
PROJECT_NOTE_ID=312
box_agent="$(acp_agent_box_launch "$queued")"
pb_set "aichatv2_toolsbox_${window_uuid}" "$box_agent"
if [ -n "$box_agent" ]; then
    run_in="$(acp_agent_run_in "$box_agent")"
    case "$run_in" in
        box:?*) where="Runs in the kept box ${run_in#box:}" ;;
        new:?*) where="Runs in a new disposable box from ${run_in#new:}" ;;
        *)      where="Runs in a box whose setting cannot be read. Choose it again in Select ACP Agent." ;;
    esac
    case "$(acp_agent_read_only "$box_agent")" in
        yes) read_only=true ;;
        *)   read_only=false ;;
    esac
    "$dialog" "$window_uuid" $PROJECT_NOTE_ID "The folder shared with the box, at the same path. The agent works on it there."
    "$dialog" "$window_uuid" $SERVERS_AREA_ID omc_hide
    "$dialog" "$window_uuid" $RESET_BTN_ID omc_hide
    "$dialog" "$window_uuid" $BOX_WHERE_TEXT_ID "$where"
    "$dialog" "$window_uuid" $BOX_READ_ONLY_TOGGLE_ID "$read_only"
    "$dialog" "$window_uuid" $BOX_PANEL_ID omc_show
fi

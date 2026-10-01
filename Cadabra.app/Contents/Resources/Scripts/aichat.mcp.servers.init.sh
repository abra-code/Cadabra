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

# Allow Network master gate. When off, the search server's toggle is greyed out (its stored
# value is kept and restored when network is re-enabled). Date & Time uses no network, so the
# gate leaves it alone.
allow_network=$(mcp_prefs_get_bool allow-network)
"$dialog" "$window_uuid" $NETWORK_TOGGLE_ID "$allow_network"
if [ "$allow_network" = "true" ]; then
    "$dialog" "$window_uuid" $SEARCH_TOGGLE_ID omc_enable
else
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

# BOX MODE, for a launch that runs the external agent in an agent-vm box. This Mac's servers and
# the sandbox paths do not apply there (the box sees only the project), so their area gives way to
# the box panel: where the agent runs, what is shared, and whether the project is shared
# read-only. With Cadabra's tools for the agent (Use Tools on), the box pane takes the panel's
# place instead (see the end of this file). The two sit in one ZStack, since a hidden view keeps
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
        box:?*) where="Runs in the kept AgentVM box ${run_in#box:}" ;;
        new:?*) where="Runs in a new disposable AgentVM box from ${run_in#new:}" ;;
        *)      where="Runs in an AgentVM box whose setting cannot be read. Choose it again in Select ACP Agent." ;;
    esac
    case "$(acp_agent_read_only "$box_agent")" in
        yes) read_only=true ;;
        *)   read_only=false ;;
    esac
    "$dialog" "$window_uuid" $PROJECT_NOTE_ID "The folder shared with the AgentVM box, at the same path. The agent works on it there."
    "$dialog" "$window_uuid" $SERVERS_AREA_ID omc_hide
    "$dialog" "$window_uuid" $RESET_BTN_ID omc_hide
    "$dialog" "$window_uuid" $BOX_WHERE_TEXT_ID "$where"
    "$dialog" "$window_uuid" $BOX_READ_ONLY_TOGGLE_ID "$read_only"
    "$dialog" "$window_uuid" $BOX_PANEL_ID omc_show
fi

# WHERE A LOCAL MODEL'S TOOLS RUN (mcp_tools_run_in): This Mac, a kept AgentVM box, or a new
# disposable box from a ready image, offered where boxes can be used. Shown for a local model's
# launch and for the Tools menu (nothing queued: the choice applies to the next load), never for
# an external agent, which runs its own tools. In a box this Mac's servers and paths give way to
# the tools box pane, whose settings are its own (mcp_box_setting): the servers and the network
# mean different things there. aichatv2_toolsrunin_<window> says the row was offered, so Start
# stores the picker's choice and the box pane.
TOOLS_RUNIN_ROW_ID=290
TOOLS_RUNIN_PICKER_ID=292
MAC_SERVERS_ID=150
TOOLS_BOX_PANE_ID=520
TOOLS_BOX_WHERE_TEXT_ID=521
TOOLS_BOX_LOCAL_TOGGLE_ID=522
TOOLS_BOX_CONFINE_TOGGLE_ID=523
TOOLS_BOX_PDF_TOGGLE_ID=524
TOOLS_BOX_PDF_WRITABLE_TOGGLE_ID=525
TOOLS_BOX_TIME_TOGGLE_ID=526
TOOLS_BOX_INTERNET_TOGGLE_ID=527
TOOLS_BOX_READ_ONLY_TOGGLE_ID=528
pb_set "aichatv2_toolsrunin_${window_uuid}" ""
tools_launch=yes
if [ -n "$queued" ]; then
    queued_model="$(launch_queue_model "$queued")"
    external_on="$(acp_agent_enabled)"
    # The same test chat init makes: a launch with no model runs the external agent when one is on.
    if [ -z "$queued_model" ] && [ "$external_on" = "true" ]; then
        tools_launch=no
    fi
fi
if [ "$tools_launch" = "yes" ]; then
    source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.select.external.agent.library.sh"
    agent_load_places refresh
    places_status=$?
    tools_run_in="$(mcp_tools_run_in)"
    # Where boxes cannot be used the row still shows while a box is stored, offering This Mac
    # and the stored choice only: hiding it would leave every tools launch refused with no way
    # back to This Mac but Reset to Defaults.
    if [ "$places_status" -ne 0 ] && [ "$tools_run_in" != "mac" ]; then
        runin_boxes=""
        runin_images=""
        places_status=0
    fi
    if [ "$places_status" -eq 0 ]; then
        "$dialog" "$window_uuid" $TOOLS_RUNIN_PICKER_ID omc_set_property options "$(agent_run_in_options "$tools_run_in")"
        "$dialog" "$window_uuid" $TOOLS_RUNIN_PICKER_ID "$tools_run_in"
        "$dialog" "$window_uuid" $TOOLS_BOX_LOCAL_TOGGLE_ID "$(mcp_box_setting local)"
        "$dialog" "$window_uuid" $TOOLS_BOX_CONFINE_TOGGLE_ID "$(mcp_box_setting confineLocal)"
        "$dialog" "$window_uuid" $TOOLS_BOX_PDF_TOGGLE_ID "$(mcp_box_setting pdf)"
        "$dialog" "$window_uuid" $TOOLS_BOX_PDF_WRITABLE_TOGGLE_ID "$(mcp_box_setting pdfWritable)"
        "$dialog" "$window_uuid" $TOOLS_BOX_TIME_TOGGLE_ID "$(mcp_box_setting time)"
        "$dialog" "$window_uuid" $TOOLS_BOX_INTERNET_TOGGLE_ID "$(mcp_box_setting internet)"
        # A share mode that cannot be read shows read-only: Start then stores what is shown.
        case "$(mcp_tools_read_only)" in
            no) "$dialog" "$window_uuid" $TOOLS_BOX_READ_ONLY_TOGGLE_ID false ;;
            *)  "$dialog" "$window_uuid" $TOOLS_BOX_READ_ONLY_TOGGLE_ID true ;;
        esac
        "$dialog" "$window_uuid" $TOOLS_RUNIN_ROW_ID omc_show
        mcp_tools_apply_run_in "$window_uuid" "$tools_run_in"
        pb_set "aichatv2_toolsrunin_${window_uuid}" "yes"
    fi
fi

# AN AGENT IN A BOX WITH CADABRA'S TOOLS (Use Tools on in Select ACP Agent): the box pane takes
# the agent panel's place, since the same servers, copied into the box, are what the agent gets
# (the agent starts them there itself). Read-only project (528) is the agent's own choice, as in
# the agent panel; the server toggles are the box pane's settings. Start reads
# aichatv2_toolsboxpane_<window> to know which panel the user saw.
pb_set "aichatv2_toolsboxpane_${window_uuid}" ""
if [ -n "$box_agent" ]; then
    queued_tools="$(launch_queue_tools "$queued")"
    case "$queued_tools" in
        true|readonly)
            source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.select.external.agent.library.sh"
            # For the Network Rules... button; it says so when boxes cannot be listed.
            agent_load_places refresh
            "$dialog" "$window_uuid" $TOOLS_BOX_LOCAL_TOGGLE_ID "$(mcp_box_setting local)"
            "$dialog" "$window_uuid" $TOOLS_BOX_CONFINE_TOGGLE_ID "$(mcp_box_setting confineLocal)"
            "$dialog" "$window_uuid" $TOOLS_BOX_PDF_TOGGLE_ID "$(mcp_box_setting pdf)"
            "$dialog" "$window_uuid" $TOOLS_BOX_PDF_WRITABLE_TOGGLE_ID "$(mcp_box_setting pdfWritable)"
            "$dialog" "$window_uuid" $TOOLS_BOX_TIME_TOGGLE_ID "$(mcp_box_setting time)"
            "$dialog" "$window_uuid" $TOOLS_BOX_INTERNET_TOGGLE_ID "$(mcp_box_setting internet)"
            # A share mode that cannot be read shows read-only, as in the local tools' pane: Start
            # then stores what is shown, never a read-write share nobody chose.
            case "$(acp_agent_read_only "$box_agent")" in
                no) "$dialog" "$window_uuid" $TOOLS_BOX_READ_ONLY_TOGGLE_ID false ;;
                *)  "$dialog" "$window_uuid" $TOOLS_BOX_READ_ONLY_TOGGLE_ID true ;;
            esac
            case "$run_in" in
                box:?*|new:?*) "$dialog" "$window_uuid" $TOOLS_BOX_WHERE_TEXT_ID "$where, with Cadabra's tools" ;;
                *)             "$dialog" "$window_uuid" $TOOLS_BOX_WHERE_TEXT_ID "$where" ;;
            esac
            "$dialog" "$window_uuid" $BOX_PANEL_ID omc_hide
            "$dialog" "$window_uuid" $TOOLS_BOX_PANE_ID omc_show
            pb_set "aichatv2_toolsboxpane_${window_uuid}" "yes" ;;
    esac
fi

# SNAPSHOT THE PROJECT FIRST (313): the setting of the place this launch runs in (an agent's box,
# or Where tools run), and whether the project is shared read-only there (mcp_snapshot_apply).
# Start works the place out again the same way and stores the toggle there.
snapshot_place=mac
snapshot_read_only=false
if [ -n "$box_agent" ]; then
    snapshot_place=box
    case "$(acp_agent_read_only "$box_agent")" in
        no) snapshot_read_only=false ;;
        *)  snapshot_read_only=true ;;
    esac
elif [ "$(pb_get "aichatv2_toolsrunin_${window_uuid}")" = "yes" ]; then
    snapshot_place="$(mcp_snapshot_place "$tools_run_in")"
    case "$(mcp_tools_read_only)" in
        no) snapshot_read_only=false ;;
        *)  snapshot_read_only=true ;;
    esac
fi
mcp_snapshot_apply "$window_uuid" "$snapshot_place" "$snapshot_read_only" show

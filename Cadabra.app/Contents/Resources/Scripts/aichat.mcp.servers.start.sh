#!/bin/sh
# aichat.mcp.servers.start.sh
# Saves the dialog's toggle + project-path state to $mcp_prefs (table contents
# are already persisted incrementally by the add/remove handlers) and closes the
# window. When a model launch is queued on the pasteboard (the selector's OK routed
# here with tools enabled), chains to aichat.chat, whose init reads these prefs while
# building the agent transport. Opened from the menu (nothing queued), it just saves:
# the settings apply to the next model load; running windows keep their server set.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.acp.agents.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

mcp_prefs_init_if_missing

# Box mode (see init): the read-only choice is stored for the agent first, and a choice that
# does not land keeps the dialog open rather than starting the agent with the other share mode.
#
# The launch is checked again first. Chat init starts whatever agent is stored when it runs, so
# if another agent was chosen, or this one moved to or from a box, while this window was open,
# the choice made here would go to one agent and the chat would start another with its own.
box_agent="$(pb_get "aichatv2_toolsbox_${window_uuid}")"
box_agent_now="$(acp_agent_box_launch "$(pb_get "aichatv2_launch_${window_uuid}")")"
if [ "$box_agent_now" != "$box_agent" ]; then
    "$alert" --level "stop" --title "$APPLET_NAME" --ok "OK" \
        "The agent, or where it runs, changed while this window was open. Close this window and choose the agent again."
    exit 0
fi
if [ -n "$box_agent" ]; then
    # Which panel the user saw (init): the agent panel (502), or the box pane with Cadabra's tools
    # (528 for read-only, and the server toggles, stored as the box pane's settings).
    box_pane="$(pb_get "aichatv2_toolsboxpane_${window_uuid}")"
    # A toggle with no value keeps the stored choice: falling back to "no" would turn a
    # read-only share into a read-write one.
    read_only_value="${OMC_ACTIONUI_VIEW_502_VALUE:-}"
    if [ "$box_pane" = "yes" ]; then
        read_only_value="${OMC_ACTIONUI_VIEW_528_VALUE:-}"
    fi
    read_only=""
    case "$read_only_value" in
        true)  read_only=yes ;;
        false) read_only=no ;;
    esac
    status=0
    if [ -n "$read_only" ]; then
        acp_agent_set_read_only "$box_agent" "$read_only"
        status=$?
    fi
    if [ "$box_pane" = "yes" ]; then
        for pair in local:522 confineLocal:523 pdf:524 pdfWritable:525 time:526 internet:527; do
            [ "$status" -eq 0 ] || break
            name="${pair%%:*}"
            eval "value=\"\${OMC_ACTIONUI_VIEW_${pair#*:}_VALUE:-}\""
            case "$value" in
                true|false)
                    mcp_box_set_setting "$name" "$value"
                    status=$? ;;
            esac
        done
    fi
    if [ "$status" -ne 0 ]; then
        "$alert" --level "stop" --title "$APPLET_NAME" --ok "OK" \
            "Could not save whether the project is shared read-only, or the tools' AgentVM box settings. Check that ~/Library/Application Support/Cadabra is writable."
        exit 0
    fi
    echo "box mode: $box_agent read-only=$read_only"
fi
# Snapshot the project first, stored for the place the launch runs in: an agent's box, or Where
# tools run (as init worked it out). A toggle with no value keeps the stored setting.
snapshot_place=mac
if [ -n "$box_agent" ]; then
    snapshot_place=box
elif [ "$(pb_get "aichatv2_toolsrunin_${window_uuid}")" = "yes" ]; then
    snapshot_place="$(mcp_snapshot_place "${OMC_ACTIONUI_VIEW_292_VALUE:-mac}")"
fi
case "${OMC_ACTIONUI_VIEW_313_VALUE:-}" in
    true|false)
        mcp_snapshot_set_setting "$snapshot_place" "$OMC_ACTIONUI_VIEW_313_VALUE"
        status=$?
        if [ "$status" -ne 0 ]; then
            "$alert" --level "stop" --title "$APPLET_NAME" --ok "OK" \
                "Could not save whether to snapshot the project first. Check that ~/Library/Application Support/Cadabra is writable."
            exit 0
        fi
        echo "snapshot ($snapshot_place): $OMC_ACTIONUI_VIEW_313_VALUE" ;;
esac

pb_set "aichatv2_toolsbox_${window_uuid}" ""
pb_set "aichatv2_toolsboxpane_${window_uuid}" ""

# Where a local model's tools run, when init offered the choice. A choice that cannot be stored
# keeps the dialog open rather than start the tools somewhere other than where the user chose.
tools_runin_offered="$(pb_get "aichatv2_toolsrunin_${window_uuid}")"
if [ "$tools_runin_offered" = "yes" ]; then
    tools_run_in="${OMC_ACTIONUI_VIEW_292_VALUE:-}"
    case "$tools_run_in" in
        mac|box:?*|new:?*) ;;
        *)
            "$alert" --level "stop" --title "$APPLET_NAME" --ok "OK" \
                "Where the tools run cannot be read from Cadabra's settings. Choose This Mac or an AgentVM box in Where tools run."
            exit 0 ;;
    esac
    mcp_tools_set_run_in "$tools_run_in"
    status=$?
    # The box pane's settings, each from its toggle. A toggle with no value keeps the stored
    # setting: falling back to a default would, for one, turn a read-only share into a read-write one.
    for pair in local:522 confineLocal:523 pdf:524 pdfWritable:525 time:526 internet:527 readOnly:528; do
        [ "$status" -eq 0 ] || break
        name="${pair%%:*}"
        eval "value=\"\${OMC_ACTIONUI_VIEW_${pair#*:}_VALUE:-}\""
        case "$value" in
            true|false)
                mcp_box_set_setting "$name" "$value"
                status=$? ;;
        esac
    done
    if [ "$status" -ne 0 ]; then
        "$alert" --level "stop" --title "$APPLET_NAME" --ok "OK" \
            "Could not save where the tools run. Check that ~/Library/Application Support/Cadabra is writable."
        exit 0
    fi
    echo "tools run in: $tools_run_in; box: local=$(mcp_box_setting local) confine=$(mcp_box_setting confineLocal) internet=$(mcp_box_setting internet) read-only=$(mcp_box_setting readOnly)"
fi
pb_set "aichatv2_toolsrunin_${window_uuid}" ""
# The boxes and images listed for Where tools run (agent_load_places).
/bin/rm -f "${TMPDIR:-/tmp}/cadabra-runin-places.${window_uuid}"

mcp_prefs_set_bool   allow-network          "${OMC_ACTIONUI_VIEW_240_VALUE:-true}"
mcp_prefs_set_bool   servers/time/enabled   "${OMC_ACTIONUI_VIEW_210_VALUE:-true}"
mcp_prefs_set_bool   servers/search/enabled "${OMC_ACTIONUI_VIEW_220_VALUE:-true}"
mcp_prefs_set_bool   servers/pdf/enabled    "${OMC_ACTIONUI_VIEW_260_VALUE:-true}"
mcp_prefs_set_bool   servers/pdf/writable   "${OMC_ACTIONUI_VIEW_261_VALUE:-true}"
mcp_prefs_set_bool   servers/local/enabled  "${OMC_ACTIONUI_VIEW_230_VALUE:-true}"
mcp_prefs_set_string servers/local/project  "${OMC_ACTIONUI_VIEW_310_VALUE:-}"

echo "saved MCP prefs: allow-network=${OMC_ACTIONUI_VIEW_240_VALUE} time=${OMC_ACTIONUI_VIEW_210_VALUE} search=${OMC_ACTIONUI_VIEW_220_VALUE} pdf=${OMC_ACTIONUI_VIEW_260_VALUE} pdf-writable=${OMC_ACTIONUI_VIEW_261_VALUE} local=${OMC_ACTIONUI_VIEW_230_VALUE} project=${OMC_ACTIONUI_VIEW_310_VALUE}"

"$dialog" "$window_uuid" omc_window omc_terminate_ok

# If this dialog owns a queued launch (stashed window-scoped by init), re-arm the global
# queue with a fresh epoch - the user may have spent minutes in here - and open the chat
# window on it.
queued=$(pb_get "aichatv2_launch_${window_uuid}")
pb_set "aichatv2_launch_${window_uuid}" ""
load_target=$(pb_get "aichatv2_loadtarget_${window_uuid}")
pb_set "aichatv2_loadtarget_${window_uuid}" ""
if [ -n "$queued" ]; then
    launch_queue_arm "$(launch_queue_model "$queued")" "$(launch_queue_tools "$queued")"
    # A launch that names a window goes INTO it - that window is open, empty, and waiting for
    # its first engine. Everything else opens a window of its own, which is what a launch
    # meant before empty windows existed.
    if [ -n "$load_target" ]; then
        load_target_arm "$load_target"
        "$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.chat.load.model"
    else
        "$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.chat"
    fi
fi

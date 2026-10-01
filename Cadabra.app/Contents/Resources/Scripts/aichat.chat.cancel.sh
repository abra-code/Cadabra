#!/bin/sh
# aichat.cancel.sh
# Called when a chat window is closed. Stops only the server for that window.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.server.library.sh"

echo "[$(/usr/bin/basename "$0")]"
echo "OMC_FRONT_PROCESS_ID: $OMC_FRONT_PROCESS_ID"
echo "OMC_ACTIONUI_WINDOW_UUID: $OMC_ACTIONUI_WINDOW_UUID"

# If this window's Model button armed an in-place switch that was never consumed, drop it:
# the selector must not offer to "switch" a conversation that no longer exists.
model_switch_disarm_for "$OMC_ACTIONUI_WINDOW_UUID"
# Same for a first-model launch aimed at this window: it would be delivered to a window that
# is gone, and until something consumed it the next ordinary model pick would be diverted
# here instead of opening its own window.
load_target_disarm_for "$OMC_ACTIONUI_WINDOW_UUID"
# And say so, for the launch that disarming cannot reach: one parked in the MCP servers dialog
# is held in that dialog's own scope and will be delivered from there regardless.
chat_window_open_clear "$OMC_ACTIONUI_WINDOW_UUID"
srvlog "WINDOW-CANCEL enter front=${OMC_FRONT_PROCESS_ID} win=$OMC_ACTIONUI_WINDOW_UUID app_pids=[$(srvlog_apppids)] hosts=[$(srvlog_hosts)] v2_servers=[$(srvlog_servers)]"

# This window's own llama-server, and only it: the registry records which window each server was
# launched for, and every other window's server stays running under its own entry. The loop that
# does it lives in the server library now, because it is wanted somewhere this handler cannot
# reach - ending a window's server without closing the window.
stop_window_server "$OMC_ACTIONUI_WINDOW_UUID" WINDOW-CANCEL

# Safety net: reap any of this bundle's llama-server / MCP server (bundled python,
# replay) / mlx-agent processes left orphaned on launchd — children stranded by an
# agent that died without tearing them down, or leftovers from an earlier crash.
# Other windows' servers stay registered to a live host, so they are protected and
# left running.
reap_orphaned_bundle_processes
srvlog "WINDOW-CANCEL exit hosts_after=[$(srvlog_hosts)] v2_servers_after=[$(srvlog_servers)]"

# The window's project snapshot: its session ends once no window uses it, keeping the snapshot for
# review and undo, or is discarded when the project did not change. Before the box question below,
# which waits for the user. Only when the snapshot registry exists.
if [ -f "$mcp_app_support/snapshot-sessions.tsv" ]; then
    source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.snapshot.library.sh"
    snapshot_release "$OMC_ACTIONUI_WINDOW_UUID"
fi

# The window's agent-vm box, when its agent ran in one: a disposable box goes once no window uses
# it; for a running kept box no window uses any more, the user is asked whether to stop it. Last,
# because that question waits for the window's own programs in the box to end and then for the
# user, and the server stop and the sweep above should not wait with it. Only when the registry
# exists, so a Mac that never used a box never loads the box-session library here.
if [ -f "$mcp_app_support/box-sessions.tsv" ]; then
    source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxsession.library.sh"
    boxsession_close "$OMC_ACTIONUI_WINDOW_UUID"
fi

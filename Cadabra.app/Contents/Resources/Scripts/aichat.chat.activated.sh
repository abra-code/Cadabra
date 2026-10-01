#!/bin/sh
# aichat.chat.activated.sh
# A chat window became the active window (WINDOW_DID_ACTIVATE_SUBCOMMAND_ID). A window whose agent
# runs in an AgentVM box restates its box line, what the box's programs reached and were refused,
# unless it did so moments ago (boxsession_line_focus). In the background, like the refresh after
# each message: reading agent-vm's logs must not hold up the window. The registry test keeps a Mac
# that never used a box from asking the pasteboard at all.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"

win="$OMC_ACTIONUI_WINDOW_UUID"
if [ -n "$win" ] && [ -f "$mcp_app_support/box-sessions.tsv" ]; then
    box_line=$(pb_get "aichatv2_boxline_${win}")
    if [ -n "$box_line" ]; then
        (
            source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxsession.library.sh"
            boxsession_line_focus "$win"
        ) >/dev/null 2>&1 &
    fi
fi
# The same for a window on this Mac with a project snapshot (aichat.snapshot.library.sh).
if [ -n "$win" ] && [ -f "$mcp_app_support/snapshot-sessions.tsv" ]; then
    snap_line=$(pb_get "aichatv2_snapline_${win}")
    if [ -n "$snap_line" ]; then
        (
            source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.snapshot.library.sh"
            snapshot_line_focus "$win"
        ) >/dev/null 2>&1 &
    fi
fi

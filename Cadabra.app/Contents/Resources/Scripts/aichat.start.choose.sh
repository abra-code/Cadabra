#!/bin/sh
# aichat.start.choose.sh
# The four buttons of the window Cadabra opens at launch (aichat.start): each opens what the
# File menu item of the same name opens, and the start window closes, its job done.
#
# One handler for the four, told apart by the button that ran it, so that the window closes the
# same way after each and the choice is made in one place.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.model.library.sh"

echo "[$(/usr/bin/basename "$0")]"

aichat_window_only

START_LOCAL_MODEL_ID=11
START_ACP_AGENT_ID=12
START_NEW_CHAT_ID=13
START_DOWNLOAD_ID=14

case "${OMC_ACTIONUI_TRIGGER_VIEW_ID:-}" in
    "$START_LOCAL_MODEL_ID") next="aichat.select.local.model" ;;
    "$START_ACP_AGENT_ID")   next="aichat.select.external.agent" ;;
    "$START_NEW_CHAT_ID")    next="aichat.chat.window" ;;
    "$START_DOWNLOAD_ID")    next="aichat.hf.browse" ;;
    *)
        echo "[aichat.start.choose] not run by one of the window's buttons; nothing done"
        exit 0 ;;
esac

# Download Models on a Mac with no model yet: the browser says why it is the place to start, and
# closing it opens the Local Models list with the new model in it (hf_first_run_arm). With a
# model installed it is the plain browser, as from the File menu.
if [ "$next" = "aichat.hf.browse" ]; then
    model_any_installed
    has_models=$?
    if [ "$has_models" -ne 0 ]; then
        hf_first_run_arm
    fi
fi

# The window closes and the next one opens after this script ends (omc_next_command only
# schedules), in the order the other handlers that close their window use.
"$dialog" "$OMC_ACTIONUI_WINDOW_UUID" omc_window omc_terminate_ok
"$next_command" "$OMC_CURRENT_COMMAND_GUID" "$next"

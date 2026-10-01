#!/bin/sh
# aichat.history.review.sh
# Review Changes on a history row: opens Review Changes on the selected conversation's project
# snapshot, the newest one still kept (review_pick_session).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.history.library.sh"
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.review.library.sh"

echo "[$(/usr/bin/basename "$0")]"

sid="${OMC_ACTIONUI_TABLE_510_COLUMN_2_VALUE:-}"
history_valid_sid "$sid"
valid=$?
if [ -z "$sid" ] || [ "$valid" -ne 0 ]; then
    exit 0
fi
id="$(review_pick_session "$history_root/$sid/meta.json")"
review_request "$id"
status=$?
if [ "$status" -ne 0 ]; then
    "$alert" --level caution --title "$APPLET_NAME" --ok "OK" \
        "This conversation has no project snapshot to review."
    exit 0
fi
"$next_command" "$OMC_CURRENT_COMMAND_GUID" "aichat.review"

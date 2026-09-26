#!/bin/sh
# aichat.boxes.image.new.ipsw.browse.sh
# Choose... for the restore image. OMC shows its file chooser (CHOOSE_FILE_DIALOG in Command.json)
# because this script reads $OMC_DLG_CHOOSE_FILE_PATH; Cancel leaves it empty.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
chosen="$OMC_DLG_CHOOSE_FILE_PATH"
[ -n "$chosen" ] || exit 0
"$dialog" "$window_uuid" "$BOXES_NI_IPSW_ID" "$chosen"

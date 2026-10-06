#!/bin/sh
# aichat.packs.record.choose.folder.sh
# Choose... beside Run in: a folder chooser (CHOOSE_FOLDER_DIALOG in Command.json, presented
# because this script reads $OMC_DLG_CHOOSE_FOLDER_PATH).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.packs.record.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

chosen="$OMC_DLG_CHOOSE_FOLDER_PATH"
[ -z "$chosen" ] && exit 0
"$dialog" "$window_uuid" $record_folder_view "${chosen%/}"

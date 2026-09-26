#!/bin/sh
# aichat.boxes.image.new.input.browse.sh
# Choose Input File...: the file for the recipe's input (the Xcode .xip, for the Xcode recipe)
# goes into its name=value line.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
chosen="$OMC_DLG_CHOOSE_FILE_PATH"
[ -n "$chosen" ] || exit 0
recipe="$(boxes_ni_recipe_path "$window_uuid" "$OMC_ACTIONUI_VIEW_720_VALUE" "$OMC_ACTIONUI_VIEW_721_VALUE")"
[ -n "$recipe" ] || exit 0
"$dialog" "$window_uuid" "$BOXES_NI_VALUES_ID" "$(boxes_ni_set_input "$OMC_ACTIONUI_VIEW_741_VALUE" "$recipe" "$chosen")"

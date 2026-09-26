#!/bin/sh
# aichat.boxes.image.new.recipe.browse.sh
# Choose... for a recipe file of your own (a file chooser, as for the restore image); the
# recipe's inputs and parameters are shown at once.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
chosen="$OMC_DLG_CHOOSE_FILE_PATH"
[ -n "$chosen" ] || exit 0
"$dialog" "$window_uuid" "$BOXES_NI_RECIPE_FILE_ID" "$chosen"
boxes_ni_show_recipe "$window_uuid" "$OMC_ACTIONUI_VIEW_720_VALUE" "$chosen" "$OMC_ACTIONUI_VIEW_732_VALUE"

#!/bin/sh
# aichat.boxes.image.new.recipe.changed.sh
# The recipe picker: shows the recipe's description and fills in its inputs and parameters.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.boxes.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
boxes_ni_show_recipe "$window_uuid" "$OMC_ACTIONUI_VIEW_720_VALUE" "$OMC_ACTIONUI_VIEW_721_VALUE" "$OMC_ACTIONUI_VIEW_732_VALUE"

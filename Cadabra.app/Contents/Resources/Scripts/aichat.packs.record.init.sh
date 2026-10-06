#!/bin/sh
# aichat.packs.record.init.sh
# The Record a Pack window opens: the folder to run in starts as the Project folder, and the
# window takes over the Agentic Session Tools window that opened it, to refresh it after a save,
# and the packs that were ticked in its Choose Packs sheet, to record on top of.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.packs.record.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

mcp_prefs_init_if_missing
"$dialog" "$window_uuid" $record_folder_view "$(mcp_prefs_get_string servers/local/project)"
pb_set "aichatv2_packsrecord_parent_${window_uuid}" "$(pb_get "$RECORD_PARENT_KEY")"
pb_set "$RECORD_PARENT_KEY" ""
record_forget "$window_uuid"

# The switch names the packs the recording would start with. Only the ones usable on this Mac
# count; with none, the switch is off and cannot be turned on.
base="$(pb_get "$RECORD_BASE_KEY")"
pb_set "$RECORD_BASE_KEY" ""
base_titles=""
if [ -n "$base" ]; then
    base_titles="$(record_py titles --bundle "$OMC_APP_BUNDLE_PATH" --user-dir "$record_user_packs" --ids="$base")"
fi
if [ -n "$base_titles" ]; then
    pb_set "aichatv2_packsrecord_base_${window_uuid}" "$base"
    "$dialog" "$window_uuid" $record_base_view omc_set_property "title" "Start with the packs ticked in Choose Packs: $base_titles"
    "$dialog" "$window_uuid" $record_base_view true
    "$dialog" "$window_uuid" $record_base_view omc_enable
else
    pb_set "aichatv2_packsrecord_base_${window_uuid}" ""
    if [ -n "$base" ]; then
        "$dialog" "$window_uuid" $record_base_view omc_set_property "title" "None of the packs ticked in Choose Packs can be used on this Mac"
    else
        "$dialog" "$window_uuid" $record_base_view omc_set_property "title" "No pack was ticked in Choose Packs to start with"
    fi
    "$dialog" "$window_uuid" $record_base_view false
    "$dialog" "$window_uuid" $record_base_view omc_disable
fi

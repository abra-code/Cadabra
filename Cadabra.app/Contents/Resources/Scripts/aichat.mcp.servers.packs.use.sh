#!/bin/sh
# aichat.mcp.servers.packs.use.sh
# Use These Packs in the Choose Packs sheet: the ticked packs are stored (/servers/local/packs),
# the sheet goes, and the two tables of Agentic Session Tools show the folders they grant. Like
# the tables' own + and - buttons, this is stored at once, not at Start or Save.
#
# In the sheet a chat window opened (aichat.chat.packs.sh) the packs are stored the same way,
# and the window's running tools are then started again with them (allow_packs_apply).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.allow.folder.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

list="$(mcp_packs_list_file "$window_uuid")"
[ -f "$list" ] || exit 0

in_chat=0
if [ -f "$(mcp_packs_chat_file "$window_uuid")" ]; then
    in_chat=1
fi

mcp_prefs_init_if_missing
before="$(mcp_prefs_array_list servers/local/packs)"
chosen="$(mcp_packs_view chosen --list "$list" --ticked "$(mcp_packs_ticked_file "$window_uuid")")"
status=$?
if [ "$status" -eq 0 ]; then
    mcp_prefs_set_packs "$chosen"
    status=$?
fi
if [ "$status" -ne 0 ]; then
    "$alert" --level "stop" --title "$APPLET_NAME" --ok "OK" \
        "Could not save the chosen sandbox packs. Check that ~/Library/Application Support/Cadabra is writable."
    exit 0
fi
echo "sandbox packs: $(printf '%s' "$chosen" | /usr/bin/tr '\n' ' ')"

"$dialog" "$window_uuid" omc_window omc_dismiss_modal
mcp_packs_forget "$window_uuid"
if [ "$in_chat" -eq 1 ]; then
    allow_packs_apply "$window_uuid" "$before" "$chosen"
    exit 0
fi
mcp_refresh_granted "$window_uuid"
# The rows were replaced, so nothing is selected in either table.
"$dialog" "$window_uuid" 322 omc_disable
"$dialog" "$window_uuid" 332 omc_disable

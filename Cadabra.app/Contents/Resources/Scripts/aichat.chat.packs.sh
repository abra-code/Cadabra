#!/bin/sh
# aichat.chat.packs.sh
# Allow Packs... in a chat window's model bar: the Choose Packs sheet of Agentic Session Tools,
# over the chat window. Its handlers are the sheet's own (aichat.mcp.servers.packs.*); a file
# beside the sheet's draft tells Use These Packs that the window's running tools are to follow
# (aichat.allow.folder.library.sh). Record a Pack... is not offered here: it belongs to the
# settings, and it would close the sheet to open a window of its own.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.allow.folder.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

win="$OMC_ACTIONUI_WINDOW_UUID"

allow_packs_applies "$win"
applies=$?
if [ "$applies" -ne 0 ]; then
    echo "choose packs: window $win has no Local server on this Mac to choose packs for"
    exit 0
fi
allow_folder_agent_reloads
reloads=$?
if [ "$reloads" -ne 0 ]; then
    echo "choose packs: this mlx-agent has no reload"
    exit 0
fi

mcp_prefs_init_if_missing
# The mark is written before the sheet is up, so Use These Packs never finds the sheet without
# it, however soon it is clicked; a sheet that cannot be marked is not opened. printf, not
# ": >": a redirection that fails on ":" ends a /bin/sh script on the spot.
marker="$(mcp_packs_chat_file "$win")"
printf '' > "$marker"
if [ ! -f "$marker" ]; then
    echo "choose packs: the sheet could not be marked as a chat window's"
    "$alert" --level "stop" --title "$APPLET_NAME" --ok "OK" \
        "The sandbox packs could not be listed. Check that ~/Library/Application Support/Cadabra is writable."
    exit 0
fi
mcp_packs_sheet_open "$win"
opened=$?
if [ "$opened" -ne 0 ]; then
    exit 0
fi
"$dialog" "$win" "$allow_packs_record_id" omc_hide
"$dialog" "$win" "$allow_packs_intro_id" "A pack is a set of folders for one kind of work. Tick the packs whose folders the tools on this Mac may use, and select a pack to see what it holds. Use These Packs applies them to this conversation from your next message, and to every new conversation."

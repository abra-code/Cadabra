#!/bin/sh
# aichat.chat.allow.folder.sh
# Allow a Folder... in a chat window's model bar: lets the window's tools use one more folder of
# this Mac while the conversation goes on (aichat.allow.folder.library.sh).
#
# OMC shows its folder chooser first (CHOOSE_FOLDER_DIALOG in Command.json), because this script
# reads $OMC_DLG_CHOOSE_FOLDER_PATH. The folder is the user's choice in that chooser and nothing
# else: no value of the window or of the conversation reaches this handler.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.allow.folder.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

win="$OMC_ACTIONUI_WINDOW_UUID"
chosen="${OMC_DLG_CHOOSE_FOLDER_PATH:-}"
if [ -z "$chosen" ]; then
    exit 0
fi

allow_folder_applies "$win"
applies=$?
if [ "$applies" -ne 0 ]; then
    echo "allow folder: window $win has no tools on this Mac to allow a folder for"
    exit 0
fi
allow_folder_agent_reloads
reloads=$?
if [ "$reloads" -ne 0 ]; then
    echo "allow folder: this mlx-agent has no reload"
    exit 0
fi

folder="$(allow_folder_real "${chosen%/}")"
why="$(allow_folder_refusal "$folder")"
if [ -n "$why" ]; then
    echo "allow folder: refused ${folder:-$chosen}: $why"
    "$alert" --level caution --title "This folder cannot be allowed" --ok "OK" "$why"
    exit 0
fi

"$alert" --level note --title "Allow $folder?" --ok "Read Only" --other "Read and Write" --cancel "Cancel" \
    "The tools of this window will be able to use the folder from your next message, until the window closes."
answer=$?
case "$answer" in
    0) access="read-only" ;;
    2) access="read-write" ;;
    *) echo "allow folder: canceled"; exit 0 ;;
esac

allow_folder_add "$win" "$folder" "$access"
added=$?
if [ "$added" -ne 0 ]; then
    echo "allow folder: the window's list could not be written"
    "$alert" --level caution --title "The folder was not allowed" --ok "OK" "Cadabra could not save this window's list of folders."
    exit 0
fi

allow_folder_apply "$win"
applied=$?
if [ "$applied" -ne 0 ]; then
    echo "allow folder: not applied (status $applied): $allow_folder_error"
    allow_folder_undo "$win"
    "$alert" --level caution --title "The folder was not allowed" --ok "OK" "$allow_folder_error"
    exit 0
fi

allow_folder_button_help "$win"
# The line that offered a folder after a refused tool call goes once that folder is allowed.
offered="$(pb_get "aichatv2_folder_offer_$win")"
if [ -n "$offered" ]; then
    _allow_folder_within "$offered" "$folder"
    covers=$?
    if [ "$covers" -eq 0 ]; then
        allow_folder_offer_hide "$win"
    fi
fi
echo "allow folder: $folder ($access) for window $win"

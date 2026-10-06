#!/bin/sh
# aichat.packs.record.save.sh
# Save Pack: the ticked rows become a pack of the user's own, which is ticked for the sandbox at
# once; the window closes, and the Agentic Session Tools window that opened it shows the pack.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.packs.record.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

state="$(record_state_file "$window_uuid")"
[ -f "$state" ] || exit 0
title="${OMC_ACTIONUI_VIEW_720_VALUE:-}"
pack_id="${OMC_ACTIONUI_VIEW_721_VALUE:-}"
description="${OMC_ACTIONUI_VIEW_722_VALUE:-}"
if [ -z "$pack_id" ]; then
    pack_id="$(record_py slug --title="$title")"
fi

problem_file="$(cadabra_run_file "packs-record.$window_uuid.problem")"
record_py save --state "$state" --user-dir "$record_user_packs" --seed-dir "$record_seed_packs" \
    --id="$pack_id" --title="$title" --description="$description" > /dev/null 2> "$problem_file"
status=$?
if [ "$status" -eq 2 ]; then
    # What the pack would replace, as save said it: one of the user's own, or one of Cadabra's.
    replaced=""
    IFS= read -r replaced < "$problem_file"
    "$alert" --level caution --title "Replace the pack $pack_id?" --ok "Replace" --cancel "Cancel" "$replaced"
    answer=$?
    if [ "$answer" -ne 0 ]; then
        /bin/rm -f "$problem_file"
        exit 0
    fi
    record_py save --state "$state" --user-dir "$record_user_packs" --id="$pack_id" --title="$title" \
        --description="$description" --replace > /dev/null 2> "$problem_file"
    status=$?
fi
if [ "$status" -ne 0 ]; then
    problem=""
    IFS= read -r problem < "$problem_file"
    /bin/rm -f "$problem_file"
    "$alert" --level "stop" --title "The pack was not saved" --ok "OK" "${problem:-The pack could not be written.}"
    exit 0
fi
/bin/rm -f "$problem_file"

# Ticked at once: a pack just recorded is one the user means to use. A tick that cannot be
# stored leaves a saved pack to tick in Choose Packs...
mcp_prefs_init_if_missing
packs_type="$("$plister" get type "$mcp_prefs" /servers/local/packs 2>/dev/null)"
if [ "$packs_type" != "array" ]; then
    "$plister" remove "$mcp_prefs" /servers/local/packs >/dev/null 2>&1
    "$plister" insert "packs" array "$mcp_prefs" /servers/local >/dev/null 2>&1
fi
# 1 when it is ticked already, which a replaced pack is.
mcp_prefs_array_append servers/local/packs "$pack_id" >/dev/null 2>&1
echo "saved sandbox pack: $pack_id"

parent="$(pb_get "aichatv2_packsrecord_parent_${window_uuid}")"
pb_set "aichatv2_packsrecord_parent_${window_uuid}" ""
pb_set "aichatv2_packsrecord_base_${window_uuid}" ""
record_forget "$window_uuid"
"$dialog" "$window_uuid" omc_window omc_terminate_ok
if [ -n "$parent" ]; then
    mcp_refresh_granted "$parent"
fi

#!/bin/sh
# aichat.agent.keys.login.sh
# Open a Shell in <box>: Terminal gets a shell in the kept box the agent runs in, so the user can
# run the agent's own login there. A stopped box is started first (10-30 s), owned by Cadabra like
# every box it starts.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agent.keys.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
keys_context "$window_uuid" || exit 0
case "$keys_run_in" in
    box:?*) box="${keys_run_in#box:}" ;;
    *) exit 0 ;;
esac
agentvm_valid_name "$box" || exit 0
"$dialog" "$window_uuid" "$KEYS_LOGIN_BUTTON_ID" omc_disable
keys_status "$window_uuid" "Starting $box..."
agentvm_box_start "$box"
status=$?
if [ "$status" -ne 0 ]; then
    keys_status "$window_uuid" "Could not start $box: $(agentvm_last_error "$status")"
    "$dialog" "$window_uuid" "$KEYS_LOGIN_BUTTON_ID" omc_enable
    exit 0
fi
agentvm_box_shell "$box"
status=$?
"$dialog" "$window_uuid" "$KEYS_LOGIN_BUTTON_ID" omc_enable
if [ "$status" -ne 0 ]; then
    keys_status "$window_uuid" "Could not open a shell in $box: $(agentvm_last_error "$status")"
    exit 0
fi
keys_status "$window_uuid" "Terminal has a shell in $box."

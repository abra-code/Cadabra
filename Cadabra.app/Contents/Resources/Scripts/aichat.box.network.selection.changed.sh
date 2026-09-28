#!/bin/sh
# aichat.box.network.selection.changed.sh
# A row is selected: Allow in This Box is offered for a refused host that has a rule.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.box.network.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
rule="$OMC_ACTIONUI_TABLE_801_COLUMN_6_VALUE"
decision="$OMC_ACTIONUI_TABLE_801_COLUMN_7_VALUE"
if [ "$decision" = "denied" ] && [ -n "$rule" ] && [ "$rule" != "-" ]; then
    "$dialog" "$window_uuid" "$BOXNET_ALLOW_ID" omc_enable
    boxnet_status "$window_uuid" ""
elif [ "$decision" = "denied" ]; then
    "$dialog" "$window_uuid" "$BOXNET_ALLOW_ID" omc_disable
    boxnet_status "$window_uuid" "No rule can be made for this host here: it is not a plain host name, or it asked for a raw connection to port 80, which rules leave out."
else
    "$dialog" "$window_uuid" "$BOXNET_ALLOW_ID" omc_disable
    boxnet_status "$window_uuid" ""
fi

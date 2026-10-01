#!/bin/sh
# aichat.mcp.servers.toggle.network.sh
# Handles the "Allow Network" master checkbox. Persists the flag and, in the live
# dialog, enables or disables the Web Search & Fetch toggle so it is visually clear it won't
# start when network is off. Date & Time uses no network and is left alone.
# The actual gating + replay's --deny-network are applied in generate_mcp_configs.py.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.server.library.sh"

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

SEARCH_TOGGLE_ID=220

allow_network="${OMC_ACTIONUI_VIEW_240_VALUE:-true}"

mcp_prefs_init_if_missing
mcp_prefs_set_bool allow-network "$allow_network"

if [ "$allow_network" = "true" ]; then
    "$dialog" "$window_uuid" $SEARCH_TOGGLE_ID omc_enable
else
    "$dialog" "$window_uuid" $SEARCH_TOGGLE_ID omc_disable
fi

echo "saved allow-network=$allow_network"

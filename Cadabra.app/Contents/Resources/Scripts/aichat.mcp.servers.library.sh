#!/bin/sh
# aichat.mcp.servers.library.sh
# MCP server settings (the /servers and /allow-network subtrees of the shared settings file,
# see cadabra_settings in aichat.library.sh): read/written by the
# aichat.mcp.servers.* dialog handlers and read by the launch flow
# (generate_stdio_mcp_config / aichat_acp_transport_json below). Sourced by those
# handlers, by the MCP inspector, and — transitively — by aichat.server.library.sh.
# Sources the base library for $plister/$dialog.
[ -n "${__AICHAT_MCP_SERVERS_LIB:-}" ] && return 0
__AICHAT_MCP_SERVERS_LIB=1
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.library.sh"

# ──────────────────────────────────────────────────────────────
# MCP servers preferences
# ──────────────────────────────────────────────────────────────
# User-editable settings for the bundled MCP servers, written by the
# aichat.mcp.servers dialog and read by aichat.init.sh / generate_mcp_configs.py.
#
# Schema:
#   /allow-network                : bool  (session-wide network master gate)
#   /servers/time/enabled         : bool
#   /servers/search/enabled       : bool
#   /servers/pdf/enabled          : bool  (pdfutil - PDF tools, no network)
#   /servers/pdf/writable         : bool  (also serve pdfutil's mutating tools)
#   /servers/local/enabled        : bool
#   /servers/local/project        : string  (primary read-write workspace)
#   /servers/local/allowed-write  : array<string>  (additional RW paths)
#   /servers/local/allowed-read   : array<string>  (additional RO paths)
#   /servers/local/include-session-tmpdir : bool  (grant the login session $TMPDIR RW)
#
# allow-network is a master switch surfaced as the "Allow Network" checkbox. When
# false, the Web Search & Fetch server is not started and the local (replay) server is
# launched with --deny-network, cutting off all outbound/inbound
# network for the sandboxed shell. When true, each server follows its own toggle.
#
# allowed-write and allowed-read are seeded by mcp_prefs_write_defaults() with the
# temp dir, Homebrew, nvm, and third-party tool/data dirs, and are fully editable in
# the dialog — so the tables show every extra path the sandbox can touch and nothing
# is granted invisibly. The system executable dirs (/bin, /usr/bin, /sbin, /usr/sbin)
# and macOS system libraries (/usr/lib, /System/Library) are NOT listed: the replay
# sandbox baseline grants exec + system-dylib loading for those automatically. The
# app bundle is NOT listed either: replay self-sandboxes at startup and the local
# server has no playlist to re-read, so nothing under it is read once the sandbox is
# live. No private user dirs (Documents/Desktop/Downloads) are added by default.

# Was ~/Library/Preferences/com.abracode.Cadabra-mcp.plist. Now the shared settings file -
# see cadabra_settings in aichat.library.sh for why, and for the two-owners rule this file has
# to respect.
mcp_prefs="$cadabra_settings"

# mcp_prefs_write_defaults
# Resets the MCP subtree to built-in defaults, leaving the rest of the settings file alone.
#
# This used to open with `rm -f "$mcp_prefs"`, which was correct while the file held nothing
# but MCP settings. It shares the file with /agents now, and this runs from Reset to Defaults
# in the servers dialog - so the old line would have answered "reset my MCP servers" by also
# silently discarding the user's external-agent choice.
mcp_prefs_write_defaults() {
    cadabra_settings_init || return 1
    # Remove only what this function owns, then rebuild it.
    "$plister" remove "$mcp_prefs" /servers       >/dev/null 2>&1
    "$plister" remove "$mcp_prefs" /allow-network >/dev/null 2>&1
    "$plister" insert "allow-network" bool true "$mcp_prefs" /
    "$plister" insert "servers" dict "$mcp_prefs" /
    "$plister" insert "time"   dict "$mcp_prefs" /servers
    "$plister" insert "enabled" bool true "$mcp_prefs" /servers/time
    "$plister" insert "search" dict "$mcp_prefs" /servers
    "$plister" insert "enabled" bool true "$mcp_prefs" /servers/search
    "$plister" insert "pdf"    dict "$mcp_prefs" /servers
    "$plister" insert "enabled" bool true "$mcp_prefs" /servers/pdf
    # Serve pdfutil's mutating tools (merge/extract/delete/rotate/metadata/forms-fill/
    # watermark/reduce) too. On by default: their outputs are create-only - a NEW file
    # under one of the granted paths, refused if anything already exists there, with no
    # overwrite option - so they can add a PDF but never modify or destroy an existing
    # file, and each call still asks for permission (they travel as gatedTools).
    "$plister" insert "writable" bool true "$mcp_prefs" /servers/pdf
    "$plister" insert "local"  dict "$mcp_prefs" /servers
    "$plister" insert "enabled" bool true "$mcp_prefs" /servers/local
    "$plister" insert "project" string "" "$mcp_prefs" /servers/local

    # Additional read-write paths (editable). Temp dir only — tools that create
    # scratch files need somewhere to write. /tmp is a symlink to /private/tmp and
    # the sandbox canonicalizes via realpath, so we seed the real path only. No
    # private user dirs by default. The per-login-session $TMPDIR (a random
    # /var/folders path) is intentionally NOT seeded into this array: it changes per
    # user login session, so generate_mcp_configs.py grants it read-write fresh from
    # the environment on each launch instead of persisting a value that would go
    # stale. Only the user's decision to include it is stored, in
    # include-session-tmpdir below; the dialog shows it as a removable row
    # (mcp_refresh_rw_table) so the temp grant can be revoked without saving its path.
    "$plister" insert "allowed-write" array "$mcp_prefs" /servers/local
    local d
    for d in /private/tmp; do
        [ -d "$d" ] && "$plister" append string "$d" "$mcp_prefs" /servers/local/allowed-write
    done

    # Grant the login session $TMPDIR read-write by default. This stores only the
    # on/off decision, never the (per-session) path; generate_mcp_configs.py and the
    # dialog recompute the path from the environment. Removing the temp row in the
    # dialog clears this flag.
    "$plister" insert "include-session-tmpdir" bool true "$mcp_prefs" /servers/local

    # Additional read-only paths (editable). These are paths the replay sandbox does
    # NOT grant on its own: Homebrew, nvm, third-party tool dirs, data dirs, and temp
    # — so shell tools (git, node, …) can load their non-system dylibs and data, and
    # so the dialog shows exactly what the sandbox can read. The system executable
    # dirs (/bin, /usr/bin, /sbin, /usr/sbin) and the macOS system libraries
    # (/usr/lib, /System/Library) are granted automatically by the sandbox baseline
    # and are intentionally NOT listed here. The app bundle is NOT listed either:
    # replay self-sandboxes at startup (its binary and dylibs are already mapped) and
    # the local server has no playlist to re-read, so nothing under Cadabra.app is
    # read once the sandbox is live. (Only if a sandboxed child had to run the
    # *bundled* python3 would Contents/Library be needed — not a current case, and
    # system /usr/bin/python3 is already reachable.) Only paths that exist on this
    # machine are added.
    "$plister" insert "allowed-read"  array "$mcp_prefs" /servers/local
    for d in \
        /usr/libexec /usr/share \
        /usr/local/bin /usr/local/lib \
        /Library/Developer/CommandLineTools/usr/bin \
        /private/etc/ssl /private/tmp /var/folders \
        /opt/homebrew "$HOME/.nvm"; do
        [ -d "$d" ] && "$plister" append string "$d" "$mcp_prefs" /servers/local/allowed-read
    done
    # Explicit, because the loop above ends on a [ -d ] test: without this the function
    # reports failure on any machine that happens to lack the last directory in that list.
    # It only became worth stating once the head of the function grew a real `|| return 1`,
    # which makes the exit status look like it means something.
    return 0
}

# mcp_prefs_init_if_missing
#
# Tests for the MCP SUBTREE, not for the file. The file may already exist because the
# external-agent dialog wrote /agents into it, and a file-existence test would then decide the
# servers were already configured - leaving every mcp_prefs_get_* silently on its fallback and
# the servers dialog showing defaults it had not actually stored.
mcp_prefs_init_if_missing() {
    "$plister" get type "$mcp_prefs" /servers >/dev/null 2>&1 && return 0
    mcp_prefs_write_defaults
}

# mcp_prefs_get_bool <key-path>  ->  "true" | "false"
# Falls back to "true" if key missing (defaults assume bundled servers are on).
mcp_prefs_get_bool() {
    local val=$("$plister" get value "$mcp_prefs" "/$1" 2>/dev/null)
    case "$val" in true|false) echo "$val" ;; *) echo "true" ;; esac
}

# mcp_prefs_get_string <key-path>
mcp_prefs_get_string() {
    "$plister" get string "$mcp_prefs" "/$1" 2>/dev/null
}

# mcp_prefs_set_bool <key-path> <true|false>
mcp_prefs_set_bool() {
    "$plister" set bool "$2" "$mcp_prefs" "/$1" 2>/dev/null
}

# mcp_prefs_set_string <key-path> <value>
mcp_prefs_set_string() {
    "$plister" set string "$2" "$mcp_prefs" "/$1" 2>/dev/null
}

# mcp_prefs_array_count <key-path>
mcp_prefs_array_count() {
    "$plister" get count "$mcp_prefs" "/$1" 2>/dev/null
}

# mcp_prefs_array_list <key-path>  ->  values, one per line
mcp_prefs_array_list() {
    "$plister" iterate "$mcp_prefs" "/$1" get string / 2>/dev/null
}

# mcp_prefs_array_append <key-path> <value>
# Refuses duplicates. Returns 0 if appended, 1 if already present.
mcp_prefs_array_append() {
    local found=$("$plister" find string "$2" "$mcp_prefs" "/$1" 2>/dev/null)
    [ -n "$found" ] && return 1
    "$plister" append string "$2" "$mcp_prefs" "/$1"
}

# mcp_prefs_array_remove_value <key-path> <value>
mcp_prefs_array_remove_value() {
    local idx=$("$plister" find string "$2" "$mcp_prefs" "/$1" 2>/dev/null)
    [ -z "$idx" ] && return 1
    "$plister" delete "$mcp_prefs" "/$1/$idx"
}

# WHERE A LOCAL MODEL'S TOOLS RUN, chosen in Agentic Session Tools (plan D6, D11):
#   /servers/runIn : string - "mac" (this Mac, the default: the servers under replay's sandbox,
#                    with the settings above), "box:<name>" (a kept agent-vm box) or "new:<image>"
#                    (a disposable box made from the image for each chat window)
# The model itself always runs on this Mac. External agents keep their own choice
# (/agents/runIn/<id>), since an agent in a box starts its tools in the box itself.
#
# THE TOOLS IN A BOX have settings of their own, since in a box the servers and the network mean
# different things (the box pane of Agentic Session Tools), each a bool under /servers/box:
#   local        (true)  the Local server: files and shell, anywhere in the box
#   confineLocal (false) the Local server also applies its own sandbox (the project and the box's
#                        temporary folders); off, the box is the boundary
#   pdf          (true)  the PDF server, on the project and the box's /private/tmp
#   pdfWritable  (true)  with its editing tools
#   time         (true)  the time server, which needs no network
#   internet     (false) the search server; a new box then allows any public host (agent-vm's
#                        "public" rule, logged), and a kept box gets that rule added at the start
#   readOnly     (false) the project is shared read-only (`exec --read-only`)
# A missing value is its default. A value of another type (a hand-edited file) also reads as the
# default, except readOnly, which reads as "damaged" and is refused at chat start rather than
# share the project read-write.

# _mcp_prefs_choice <key-path> <default>  ->  the stored text, the default when nothing is
# stored, or "damaged" when something that is not text is stored there (a hand-edited file),
# which every consumer refuses rather than read as the default: for runIn, this Mac.
_mcp_prefs_choice() {
    local kind="$("$plister" get type "$mcp_prefs" "/$1" 2>/dev/null)"
    case "$kind" in
        '')     printf '%s\n' "$2" ;;
        string) local val
                val=$(mcp_prefs_get_string "$1")
                printf '%s\n' "${val:-$2}" ;;
        *)      printf 'damaged\n' ;;
    esac
}

# mcp_tools_run_in  ->  "mac", "box:<name>", "new:<image>", or "damaged" for anything else.
mcp_tools_run_in() {
    local val="$(_mcp_prefs_choice servers/runIn mac)"
    case "$val" in
        mac|box:?*|new:?*) printf '%s\n' "$val" ;;
        *)                 printf 'damaged\n' ;;
    esac
}

# _mcp_prefs_set_choice <key-path> <value>  ->  0 once stored and read back; 1 when the write
# did not land (plister exits 0 having written nothing on a read-only file).
_mcp_prefs_set_choice() {
    mcp_prefs_init_if_missing
    local kind="$("$plister" get type "$mcp_prefs" "/$1" 2>/dev/null)"
    # Something that is not text (a damaged value) is replaced, so choosing again repairs it.
    if [ -n "$kind" ] && [ "$kind" != "string" ]; then
        "$plister" remove "$mcp_prefs" "/$1" >/dev/null 2>&1
        kind=""
    fi
    if [ -z "$kind" ]; then
        "$plister" insert "${1##*/}" string "" "$mcp_prefs" "/${1%/*}" >/dev/null 2>&1
    fi
    mcp_prefs_set_string "$1" "$2"
    local back="$(mcp_prefs_get_string "$1")"
    [ "$back" = "$2" ]
}

# mcp_tools_set_run_in <mac|box:NAME|new:IMAGE>  ->  0 once stored; 2 for another value; 1 when
# the write did not land.
mcp_tools_set_run_in() {
    case "$1" in
        mac|box:?*|new:?*) ;;
        *) return 2 ;;
    esac
    _mcp_prefs_set_choice servers/runIn "$1"
}

# mcp_box_setting <name>  ->  "true" or "false": /servers/box/<name> when it is a bool, else the
# name's default; "damaged" for readOnly stored as something other than a bool. The reading
# generate_mcp_configs.py makes too (box_flag), so the pane never shows what the servers do not do.
mcp_box_setting() {
    local default
    case "$1" in
        local|pdf|pdfWritable|time|snapshot) default=true ;;
        confineLocal|internet|readOnly) default=false ;;
        *) return 2 ;;
    esac
    local kind="$("$plister" get type "$mcp_prefs" "/servers/box/$1" 2>/dev/null)"
    local val="$("$plister" get value "$mcp_prefs" "/servers/box/$1" 2>/dev/null)"
    if [ "$kind" = "bool" ]; then
        case "$val" in
            true|false) printf '%s\n' "$val"; return 0 ;;
        esac
    fi
    if [ -n "$kind" ] && [ "$1" = "readOnly" ]; then
        printf 'damaged\n'
        return 0
    fi
    printf '%s\n' "$default"
}

# mcp_box_set_setting <name> <true|false>  ->  0 once stored and read back; 2 for another name or
# value; 1 when the write did not land. A value of another type is replaced.
mcp_box_set_setting() {
    case "$1" in
        local|pdf|pdfWritable|time|confineLocal|internet|readOnly|snapshot) ;;
        *) return 2 ;;
    esac
    case "$2" in
        true|false) ;;
        *) return 2 ;;
    esac
    mcp_prefs_init_if_missing
    local parent="$("$plister" get type "$mcp_prefs" /servers/box 2>/dev/null)"
    if [ "$parent" != "dict" ]; then
        "$plister" remove "$mcp_prefs" /servers/box >/dev/null 2>&1
        "$plister" insert box dict "$mcp_prefs" /servers >/dev/null 2>&1
    fi
    local kind="$("$plister" get type "$mcp_prefs" "/servers/box/$1" 2>/dev/null)"
    if [ -n "$kind" ] && [ "$kind" != "bool" ]; then
        "$plister" remove "$mcp_prefs" "/servers/box/$1" >/dev/null 2>&1
        kind=""
    fi
    if [ -z "$kind" ]; then
        "$plister" insert "$1" bool "$2" "$mcp_prefs" /servers/box >/dev/null 2>&1
    fi
    mcp_prefs_set_bool "servers/box/$1" "$2"
    local back="$(mcp_box_setting "$1")"
    [ "$back" = "$2" ]
}

# mcp_tools_read_only  ->  "yes", "no", or "damaged": whether a box shares the project read-only.
mcp_tools_read_only() {
    case "$(mcp_box_setting readOnly)" in
        true)  printf 'yes\n' ;;
        false) printf 'no\n' ;;
        *)     printf 'damaged\n' ;;
    esac
}

# THE PROJECT SNAPSHOT. Agentic Session Tools' "Snapshot the project first" (toggle 313, under the
# Project folder) has one setting for sessions in an AgentVM box, /servers/box/snapshot (on by
# default: the box is where an agent is let work without asking), and one for sessions on this Mac,
# /servers/snapshot (off by default). The window's place decides which one the toggle shows and
# Start stores: an agent's box, or Where tools run. aichat.snapshot.library.sh takes the snapshot.
mcp_snapshot_toggle_view=313

# mcp_snapshot_setting <mac|box>  ->  "true" or "false": the stored setting when it is a bool,
# else the place's default.
mcp_snapshot_setting() {
    case "$1" in
        box) mcp_box_setting snapshot
             return $? ;;
        mac) ;;
        *) return 2 ;;
    esac
    local kind="$("$plister" get type "$mcp_prefs" /servers/snapshot 2>/dev/null)"
    local val="$("$plister" get value "$mcp_prefs" /servers/snapshot 2>/dev/null)"
    if [ "$kind" = "bool" ]; then
        case "$val" in
            true|false) printf '%s\n' "$val"; return 0 ;;
        esac
    fi
    printf 'false\n'
}

# mcp_snapshot_set_setting <mac|box> <true|false>  ->  0 once stored and read back; 2 for another
# place or value; 1 when the write did not land. A value of another type is replaced.
mcp_snapshot_set_setting() {
    case "$2" in
        true|false) ;;
        *) return 2 ;;
    esac
    case "$1" in
        box) mcp_box_set_setting snapshot "$2"
             return $? ;;
        mac) ;;
        *) return 2 ;;
    esac
    mcp_prefs_init_if_missing
    local kind="$("$plister" get type "$mcp_prefs" /servers/snapshot 2>/dev/null)"
    if [ -n "$kind" ] && [ "$kind" != "bool" ]; then
        "$plister" remove "$mcp_prefs" /servers/snapshot >/dev/null 2>&1
        kind=""
    fi
    if [ -z "$kind" ]; then
        "$plister" insert snapshot bool "$2" "$mcp_prefs" /servers >/dev/null 2>&1
    fi
    mcp_prefs_set_bool servers/snapshot "$2"
    local back="$(mcp_snapshot_setting mac)"
    [ "$back" = "$2" ]
}

# mcp_snapshot_place <run-in>  ->  "box" for an AgentVM box choice (box:NAME, new:IMAGE), else "mac".
mcp_snapshot_place() {
    case "$1" in
        box:?*|new:?*) printf 'box\n' ;;
        *) printf 'mac\n' ;;
    esac
}

# mcp_snapshot_apply <window_uuid> <mac|box> [<read-only true|false>] [show]  ->  toggle 313 shows
# the place's setting (with "show"), and can be changed only where a snapshot can be taken: not
# without a usable agent-vm, which takes it (the tooltip then says why), and not for a project
# shared read-only, which nothing in the session can change.
mcp_snapshot_apply() {
    if [ "${4:-}" = "show" ]; then
        "$dialog" "$1" $mcp_snapshot_toggle_view "$(mcp_snapshot_setting "$2")"
    fi
    # Here rather than at the top: only Agentic Session Tools' handlers call this.
    source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agentvm.library.sh"
    local why
    why="$(agentvm_available 2>/dev/null)"
    local status=$?
    if [ "$status" -ne 0 ]; then
        "$dialog" "$1" $mcp_snapshot_toggle_view omc_disable
        "$dialog" "$1" $mcp_snapshot_toggle_view omc_set_property help "A snapshot needs AgentVM. ${why:-agent-vm cannot be used on this Mac.}"
        return 0
    fi
    if [ "$2" = "box" ] && [ "${3:-false}" = "true" ]; then
        "$dialog" "$1" $mcp_snapshot_toggle_view omc_disable
        "$dialog" "$1" $mcp_snapshot_toggle_view omc_set_property help "No snapshot is taken of a project shared read-only: nothing in the session can change it."
        return 0
    fi
    "$dialog" "$1" $mcp_snapshot_toggle_view omc_enable
    "$dialog" "$1" $mcp_snapshot_toggle_view omc_set_property help "An instant copy of the project folder when the session starts (APFS copy-on-write: it takes space only as files change), so you can see what the session changed and undo all or part of it. Taken by AgentVM; the project must be on the same disk as your home folder."
}

# THE TWO PANES. Agentic Session Tools shows the servers of this Mac (HStack 150: the server
# toggles, Allow Network, the sandbox paths) or the tools box pane (GroupBox 520), never both;
# they sit in one ZStack with the external agent's box panel (500). The ids are
# aichat.mcp.servers.init.sh's MAC_SERVERS_ID, TOOLS_BOX_PANE_ID and TOOLS_BOX_WHERE_TEXT_ID.
mcp_mac_servers_view=150
mcp_tools_box_pane_view=520
mcp_tools_box_where_view=521

# mcp_tools_box_network_text <window_uuid> <run-in> [agent]  ->  what the box may reach, as
# Markdown for the Network Rules... button's sheet (the pane itself says nothing of it: a rule list
# is too much for its small print). A kept box's mode and rules, a list item each, from the places
# Where tools run listed (agent_load_places); for a new box, what it will get, which with [agent]
# (an agent's own box) includes the agent's hosts. Nothing when the box is not among the places.
# A box with no mode recorded ("-", made before agent-vm had network rules) runs open: agent-vm's
# BoxNetwork.legacy.
mcp_tools_box_network_text() {
    case "$2" in
        new:?*)
            if [ -n "${3:-}" ]; then
                printf '%s\n' "A new box reaches the hosts the agent needs and those saved for it, and any public host with **Internet** on."
            else
                printf '%s\n' "A new box reaches nothing, or any public host with **Internet** on."
            fi
            return 0 ;;
        box:?*) ;;
        *) return 0 ;;
    esac
    local file="$(cadabra_run_file "runin-places.$1")"
    [ -f "$file" ] || return 0
    /usr/bin/awk -F'\t' -v box="${2#box:}" '$1 == "box" && $2 == box {
        mode = $3; rules = $4
        if (mode == "off") print "Its network is **off**: programs in it reach no host."
        else if (mode == "open" || mode == "-" || mode == "") print "Its network is **open**: programs in it reach any host, also on your local network."
        else if (mode != "allowlist") { gsub(/[^a-z-]/, "", mode); print "Its network mode is **" mode "**." }
        else if (rules == "" || rules == "-") print "Its network is an **allowlist with no rules**: programs in it reach no host."
        else {
            print "Programs in it reach only these hosts and packs of hosts:"
            print ""
            n = split(rules, list, ",")
            for (i = 1; i <= n; i++) { gsub(/\140/, "\047", list[i]); print "- `" list[i] "`" }
        }
        exit
    }' "$file"
}

# mcp_markdown_code <text>  ->  the text for a Markdown code span (between backticks) in an
# information sheet (mcp_info_sheet), on one line: a backtick in it would end the span, and a line break the paragraph, and
# what follows would be read as Markdown of its own (a link, a heading). A folder can be named so.
mcp_markdown_code() {
    printf '%s' "$1" | /usr/bin/tr '\140\n\r' "'  "
}

# mcp_info_sheet <window_uuid> <markdown>  ->  0 once a sheet showing the Markdown (a RichText
# view and a Done button, aichat.mcp.servers.info.done.sh) is presented on the window; 1 when its
# JSON could not be written. The sheet is a file of the window's own (cadabra_run_file), written
# anew each time, since omc_present_modal takes a resource or a path; its two ids (590, 591) are
# apart from the window's.
mcp_info_sheet_file() {
    cadabra_run_file "tools-info.$1.json"
}

mcp_info_sheet() {
    local file="$(mcp_info_sheet_file "$1")"
    /usr/bin/jq -n --arg markdown "$2" '{
        type: "VStack",
        properties: { spacing: 12, alignment: "leading", padding: "default", frame: { width: 520 } },
        children: [
            { type: "RichText", id: 590,
              properties: { markdown: $markdown, remoteImages: "never",
                            frame: { maxWidth: "infinity", alignment: "leading" } } },
            { type: "HStack", children: [
                { type: "Spacer" },
                { type: "Button", id: 591,
                  properties: { title: "Done", buttonStyle: "borderedProminent",
                                keyboardShortcut: { key: "return" },
                                actionID: "aichat.mcp.servers.info.done" } } ] }
        ]
    }' > "$file" 2>/dev/null
    local status=$?
    if [ "$status" -ne 0 ]; then
        return 1
    fi
    "$dialog" "$1" omc_window omc_present_modal "$file"
}

# mcp_tools_apply_run_in <window_uuid> <run-in>  ->  Agentic Session Tools follows where the tools
# run: this Mac's servers, or the box pane saying which box.
mcp_tools_apply_run_in() {
    local where=""
    case "$2" in
        mac|'') ;;
        box:?*)   where="In the kept AgentVM box ${2#box:}" ;;
        new:?*)   where="In a new disposable AgentVM box from ${2#new:}, made for each chat window" ;;
        *)        where="In an AgentVM box whose setting cannot be read. Choose where the tools run again." ;;
    esac
    if [ -z "$where" ]; then
        "$dialog" "$1" $mcp_tools_box_pane_view omc_hide
        "$dialog" "$1" $mcp_mac_servers_view omc_show
        return 0
    fi
    "$dialog" "$1" $mcp_tools_box_where_view "$where"
    "$dialog" "$1" $mcp_mac_servers_view omc_hide
    "$dialog" "$1" $mcp_tools_box_pane_view omc_show
}

# A CHAT WINDOW'S TOOLS IN A BOX. Once a local model's box runs with Cadabra's tools copied in
# (boxsession_start_tools), the window's pasteboard key aichatv2_boxtools_<window> holds, tab
# separated: box, project, read-only (yes or no), the tools' folder in the box, and the bytecode
# cache folder there. aichat_acp_transport_json generates the window's MCP config in box mode
# while it is set - at the first load and at every in-place model switch after it, so a switch
# keeps the tools in the same box. boxsession_release clears it with the window's registry row.
mcp_box_tools_set() {
    local tab="$(printf '\t')"
    pb_set "aichatv2_boxtools_$1" "$2$tab$3$tab$4$tab$5$tab$6"
}

mcp_box_tools_get() {
    pb_get "aichatv2_boxtools_$1"
}

mcp_box_tools_clear() {
    pb_set "aichatv2_boxtools_$1" ""
}

# mcp_refresh_path_table <window_uuid> <table_id> <prefs_key>
# Repopulates a single-column path table from the prefs array.
mcp_refresh_path_table() {
    local window_uuid="$1"
    local table_id="$2"
    local key="$3"
    "$dialog" "$window_uuid" "$table_id" omc_table_remove_all_rows
    local buffer=$(mcp_prefs_array_list "$key")
    if [ -n "$buffer" ]; then
        printf "%s\n" "$buffer" | "$dialog" "$window_uuid" "$table_id" omc_table_set_rows_from_stdin
    fi
}

# mcp_session_tmpdir  ->  canonical realpath of $TMPDIR, or empty
# The per-login-session scratch dir offered as a removable read-write grant. Its
# value (a random /var/folders path) changes per login session, so it is NEVER stored
# in the prefs plist — only the include-session-tmpdir decision is. `cd && pwd -P`
# resolves the /var -> /private/var symlink to the same path os.path.realpath($TMPDIR)
# yields in generate_mcp_configs.py, so the row shown matches what is granted.
mcp_session_tmpdir() {
    [ -n "${TMPDIR:-}" ] || return 0
    ( cd "$TMPDIR" 2>/dev/null && pwd -P )
}

# mcp_refresh_rw_table <window_uuid> <table_id>
# Repopulates the read-write table from the persisted allowed-write array, then
# appends the session $TMPDIR as a synthetic (non-persisted) row when
# include-session-tmpdir is on. The row is shown so the user can see the temp grant
# and, by removing it, deny it — only that decision is stored, never the volatile path.
mcp_refresh_rw_table() {
    local window_uuid="$1"
    local table_id="$2"
    mcp_refresh_path_table "$window_uuid" "$table_id" servers/local/allowed-write
    if [ "$(mcp_prefs_get_bool servers/local/include-session-tmpdir)" = "true" ]; then
        local td=$(mcp_session_tmpdir)
        [ -n "$td" ] && printf "%s\n" "$td" \
            | "$dialog" "$window_uuid" "$table_id" omc_table_add_rows_from_stdin
    fi
}

# ──────────────────────────────────────────────────────────────
# ACP transport (stdio-direct MCP for the bundled mlx-agent)
# ──────────────────────────────────────────────────────────────
# generate_stdio_mcp_config writes the mlx-agent --mcp-config file for one window;
# aichat_acp_transport_json turns it into the Chat element's states["config"] transport,
# selecting agent mode iff at least one server ends up enabled.

# aichat_session_config_dir <window_uuid>
# Per-window dir holding this window's generated mcp-config.json and the replay sandbox
# profile. Overwritten on every launch / model switch, so nothing here is durable state.
aichat_session_config_dir() {
    printf '%s/Sessions/%s' "$mcp_app_support" "$1"
}

# generate_stdio_mcp_config <out_config_json>
# Emit the mlx-agent --mcp-config (stdio-direct) file into <out_config_json>, honoring the
# current MCP-servers prefs (per-server enabled flags, the allow-network master gate, and
# the replay sandbox read/write paths). The replay sandbox profile is written next to
# <out_config_json>. Returns 0 when the file is written (possibly {"servers":[]} if the
# user disabled everything), non-zero if the bundled Python or the generator is missing.
generate_stdio_mcp_config() {
    local out_json="$1"
    shift
    local python3="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
    local script="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/generate_mcp_configs.py"
    if [ ! -f "$python3" ] || [ ! -f "$script" ]; then
        echo "generate_stdio_mcp_config: bundled Python/generator missing ($python3 / $script)"
        return 1
    fi

    # Seed the prefs plist with defaults on first run so the config the model sees matches
    # exactly what the MCP Servers dialog shows. No-op when prefs already exist.
    mcp_prefs_init_if_missing

    local tz="$(/usr/bin/readlink /etc/localtime 2>/dev/null | /usr/bin/sed 's|.*/zoneinfo/||')"
    [ -z "$tz" ] && tz="UTC"

    local out_dir="$(/usr/bin/dirname "$out_json")"
    /bin/mkdir -p "$out_dir" 2>/dev/null

    # The generator writes the mlx-agent config to <out_json> and the replay sandbox
    # profile beside it in the same session dir. Named options after these (--box ...) select
    # its box mode.
    "$python3" "$script" "$out_json" "$OMC_APP_BUNDLE_PATH" "$tz" "$mcp_prefs" "$@"
}

# _mcp_box_config_args <window_uuid>  ->  sets mcp_box_args (generate_mcp_configs.py's box
# options, one per line) and mcp_box_project from the window's tools record; both empty when
# its tools run on this Mac. 1 when the record is unusable, which the caller refuses rather
# than generate a config that would run the tools on this Mac under a box window's name.
mcp_box_args=""
mcp_box_project=""
_mcp_box_config_args() {
    mcp_box_args=""
    mcp_box_project=""
    local record="$(mcp_box_tools_get "$1")"
    if [ -z "$record" ]; then
        return 0
    fi
    local box project read_only guest cache
    IFS="$(printf '\t')" read -r box project read_only guest cache <<EOF
$record
EOF
    case "$box:$project:$read_only:$guest:$cache" in
        ?*:/?*:yes:/?*:/?*|?*:/?*:no:/?*:/?*) ;;
        *) return 1 ;;
    esac
    source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agentvm.library.sh"
    local nl="
"
    mcp_box_args="--box${nl}$box${nl}--agent-vm${nl}$(agentvm_bin)${nl}--project${nl}$project${nl}--guest-tools${nl}$guest${nl}--guest-pycache${nl}$cache"
    local home="$(agentvm_setting agent-vm-home)"
    if [ -n "$home" ]; then
        mcp_box_args="$mcp_box_args${nl}--agent-vm-home${nl}$home"
    fi
    if [ "$read_only" = "yes" ]; then
        mcp_box_args="$mcp_box_args${nl}--read-only"
    fi
    mcp_box_project="$project"
    return 0
}

# aichat_acp_transport_json <agent_bin> <engine> <target> <window_uuid> [use_tools]
# Generate this window's MCP config, then echo the ACP transport JSON for the Chat
# element's states["config"].
#
# <engine> selects how mlx-agent generates, and what <target> means:
#   openai - <target> is the llama-server base-url (e.g. http://127.0.0.1:8099/v1). The
#            APPLET owns that server (launch, restart on model switch, reaping); mlx-agent
#            only talks to it. This is V2's path today.
#   mlx    - <target> is a safetensors model directory loaded in-process by mlx-agent.
#            Unused until M2, but built now so M2 is a config change, not a port.
#
# When the config has at least one server, the transport adds --mcp-config <cfg> (which
# defaults mlx-agent to agent mode); otherwise it is a plain chat transport with no tools.
# use_tools is the per-session decision (the selector's Tools picker, or the caller's
# auto-detection) and is TRI-STATE: "true" hands over every enabled server, "readonly" hands
# over only those with no permission-gated tools, and anything else skips config generation
# entirely - removing any config left by a previous launch of the same window - so the session
# is plain chat regardless of which servers the prefs enable. Omitted means "true" (prefs
# decide). "readonly" is meaningful only for an EXTERNAL agent: the bundled mlx-agent honors
# gatedTools and gates those tools through the approval card, so it needs no server filtering,
# and the local model picker still passes a plain true/false.
# Argv/JSON encoding is done in Python (json.dumps) so paths with spaces or quotes are safe;
# if the bundled Python is somehow absent it falls back to a sed-escaped hand-built chat
# transport rather than wedging the window. Echoes only the JSON on stdout; any generator
# diagnostics go to stderr.
aichat_acp_transport_json() {
    local agent_bin="$1"
    local engine="$2"
    local target="$3"
    local window_uuid="$4"
    local use_tools="${5:-true}"

    local python3="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
    local cfg="$(aichat_session_config_dir "$window_uuid")/mcp-config.json"

    # The agent's working directory: the user's chosen Project workspace. ChatView launches
    # mlx-agent with this as the process cwd AND sends it as session/new's `cwd`, so relative
    # paths resolve here and mlx-agent tells the model where it is (a model cannot call getcwd).
    # ACP requires cwd to be an ABSOLUTE path. The Project field is an editable TextField (the
    # folder picker only pre-fills it), so the stored value can be anything the user typed -
    # validate it here rather than trusting it. A relative value would otherwise be anchored by
    # ChatView against the host's cwd ("/" for a launchd-launched GUI app), yielding e.g.
    # "/Documents" and possibly a failed process launch - worse than the old "rooted at /". Fall
    # back to $HOME for anything not absolute-and-existing, so the agent is never rooted at "/".
    local cwd="$(mcp_prefs_get_string servers/local/project)"
    case "$cwd" in
        /*) [ -d "$cwd" ] || cwd="$HOME" ;;
        *)  cwd="$HOME" ;;
    esac

    # TOOLS IN A BOX: the window's tools record (mcp_box_tools_get) names the box its servers run
    # in, and the project shared there, which is then also the agent's cwd - the project the box
    # was started with, not whatever the settings say now (an in-place switch rebuilds this
    # transport long after the dialog). An unusable record refuses the transport: the caller
    # alerts, rather than the window's tools quietly moving to this Mac.
    _mcp_box_config_args "$window_uuid"
    local box_record_status=$?
    if [ "$box_record_status" -ne 0 ]; then
        echo "aichat_acp_transport_json: this window's AgentVM box record is unreadable" 1>&2
        return 1
    fi
    if [ -n "$mcp_box_project" ]; then
        cwd="$mcp_box_project"
    fi

    case "$use_tools" in
        true|readonly)
            # Generate the config; its diagnostics go to stderr so stdout stays pure JSON.
            # "readonly" generates the FULL config on purpose: the gatedTools lists inside it
            # are exactly what the builder reads to decide which servers qualify, so filtering
            # here instead would throw away the evidence the filter needs.
            if [ -n "$mcp_box_args" ]; then
                # The box options become the generator's arguments, one per line. A here-document
                # rather than a pipe, so the loop runs in this shell and its `set` stays.
                local arg
                set --
                while IFS= read -r arg; do
                    set -- "$@" "$arg"
                done <<EOF
$mcp_box_args
EOF
                generate_stdio_mcp_config "$cfg" "$@" 1>&2
            else
                generate_stdio_mcp_config "$cfg" 1>&2
            fi
            ;;
        *)
            # Tools off for this session: no config, and drop a stale one from a previous
            # launch of this window so the argv builder below sees no servers.
            /bin/rm -f "$cfg"
            ;;
    esac

    # Build the transport argv + JSON in a helper (json.dumps keeps paths with spaces/quotes
    # safe): agent mode only when the config parsed and lists >=1 server (a missing/empty/broken
    # config falls back to chat — never wedges the window).
    local builder="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/acp_transport_json.py"
    if [ -x "$python3" ] && [ -f "$builder" ]; then
        "$python3" "$builder" "$agent_bin" "$engine" "$target" "$cfg" "$cwd" "$use_tools" \
            && return 0
    fi

    # Bundled Python missing (or the builder above failed): emit a plain chat-only transport by
    # hand. mlx-agent needs no Python to run, so chat still works even if the interpreter is gone
    # — this is the honest "never wedges the window" path. JSON-escape the path values (backslash
    # then quote) so spaces/quotes are safe. agent_bin/target are program-controlled and never
    # hold control chars; cwd is user-supplied and validated absolute-and-existing above, so a raw
    # control char in a folder name (APFS permits it) would still slip through unescaped here — a
    # tolerated gap on this rare degraded path (json.dumps on the primary path handles it fully).
    local ae="$(printf '%s' "$agent_bin" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g')"
    local te="$(printf '%s' "$target"    | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g')"
    local ce="$(printf '%s' "$cwd"       | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g')"
    # Dispatched explicitly, matching the builder: the on-device engine carries no target, so
    # an "openai or else --model" split would emit `--model ""` here and launch an agent that
    # fails on an empty model path rather than using the model the user picked.
    if [ "$engine" = "external" ]; then
        # No bundled Python, so there is nothing here that can safely split a user-typed
        # command line - shlex lives in the builder, and word-splitting it in the shell would
        # glob-expand and re-split whatever the user wrote. Refuse instead of guessing: an
        # empty transport makes the caller alert and leave the composer disabled, which is a
        # far better outcome than launching a command nobody typed.
        echo "external agent needs the bundled python3 to parse its command line" 1>&2
        return 1
    elif [ "$engine" = "openai" ]; then
        printf '{"protocol":"acp","transport":{"command":["%s","acp","--backend","openai","--base-url","%s"],"cwd":"%s"}}\n' "$ae" "$te" "$ce"
    elif [ "$engine" = "foundation" ]; then
        printf '{"protocol":"acp","transport":{"command":["%s","acp","--backend","foundation"],"cwd":"%s"}}\n' "$ae" "$ce"
    else
        printf '{"protocol":"acp","transport":{"command":["%s","acp","--model","%s"],"cwd":"%s"}}\n' "$ae" "$te" "$ce"
    fi
}

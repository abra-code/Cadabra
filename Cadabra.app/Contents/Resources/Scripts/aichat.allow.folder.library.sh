#!/bin/sh
# aichat.allow.folder.library.sh
# ALLOW A FOLDER, for a chat window whose local model runs its tools on this Mac. The Local
# server (replay) and the PDF server are confined to the folders of Agentic Session Tools, fixed
# when the conversation starts. A command that needs another folder fails, and until now the
# only way to allow it was to change the settings and start again.
#
# The button in the window's model bar (aichat.chat.allow.folder.sh) adds one folder to the
# WINDOW'S OWN LIST, a file beside the window's MCP config:
#   Sessions/<window>/window-folders.json   {"read_only": [...], "read_write": [...]}
# The config is then generated again with that list (generate_mcp_configs.py --window-folders)
# and the window's mlx-agent is sent SIGHUP: between turns it reads the config again and
# restarts only the servers whose command line changed, keeping the model and the conversation.
#
# Only the user adds a folder, and only through the folder chooser: no tool, model output or
# link can. The list lasts as long as the window (its Sessions folder goes when it closes) and
# changes no setting; a folder wanted in every conversation is added in Agentic Session Tools.
#
# Not offered: for tools in an AgentVM box (the box sees one folder of this Mac, its project,
# fixed when it starts), for an external agent (it starts the servers itself and cannot be
# asked to restart one), and when this mlx-agent has no reload (SIGHUP would end it).

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"

# The empty slot beside the model button in aichat.chat.json, and the button put into it.
allow_folder_slot_id=548
allow_folder_button_id=549
allow_folder_agent="$OMC_APP_BUNDLE_PATH/Contents/Support/MLX/mlx-agent"
allow_folder_newline="
"

# allow_folder_file <window>  ->  the path of the window's own list.
allow_folder_file() {
    printf '%s/window-folders.json\n' "$(aichat_session_config_dir "$1")"
}

# allow_folder_list <window>  ->  one line per folder of the window's list, "read-only" or
# "read-write", a tab, the path. Nothing when there is no list or it cannot be read.
allow_folder_list() {
    local _file="$(allow_folder_file "$1")"
    if [ ! -f "$_file" ]; then
        return 0
    fi
    /usr/bin/jq -r '((.read_write // [])[] | "read-write\t" + .), ((.read_only // [])[] | "read-only\t" + .)' "$_file" 2>/dev/null
}

# allow_folder_real <path>  ->  the folder's real path (links followed), or nothing when it is
# not a folder that can be entered.
#
# The path is the one the system itself gives for the folder (/bin/pwd, not the shell's own pwd,
# which keeps the spelling it was given): on a file system that ignores case ~/library comes
# back as ~/Library, and /System/Volumes/Data/Users/x as /Users/x, so allow_folder_refusal
# compares the names the folders really have. Nothing as well for a folder whose path has a
# line break, a tab or another control character: this function's answer and the window's list
# are one line per folder, and a line break at the end would be lost here, giving the path of
# another folder.
allow_folder_real() {
    case "$1" in
        /*) ;;
        *)  return 0 ;;
    esac
    if [ ! -d "$1" ]; then
        return 0
    fi
    local _real
    _real="$( cd "$1" 2>/dev/null && /bin/pwd -P && printf '.' )"
    _real="${_real%$allow_folder_newline.}"
    case "$_real" in
        /*) ;;
        *)  return 0 ;;
    esac
    case "$_real" in
        *[[:cntrl:]]*) return 0 ;;
    esac
    printf '%s\n' "$_real"
}

# _allow_folder_within <path> <folder>  ->  0 when path is folder or inside it.
_allow_folder_within() {
    case "$1/" in
        "${2%/}/"*) return 0 ;;
    esac
    return 1
}

# allow_folder_refusal <real path>  ->  why this folder is never allowed from a chat window, as
# one sentence, or nothing when it may be. The folders refused are the ones that hold more than
# a task needs or that sandboxed tools must not reach:
#   - the home folder and every folder that contains it (which includes "/");
#   - the home folder's Library itself, and its Application Support: they hold every
#     application's data, Cadabra's own among it (conversations, the files its handlers read);
#   - Cadabra's own folder and anything in it;
#   - a hidden folder of the home folder and anything in it (.ssh, .aws, .config ...).
# A folder inside Library that belongs to one tool (Library/Developer, a cache) may be allowed.
allow_folder_refusal() {
    local _path="$1"
    local _home="$(allow_folder_real "$HOME")"
    if [ -z "$_path" ]; then
        printf '%s\n' "That is not a folder."
        return 0
    fi
    if [ -z "$_home" ]; then
        printf '%s\n' "The home folder cannot be found, so no folder can be checked against it."
        return 0
    fi
    _allow_folder_within "$_home" "$_path"
    local _contains_home=$?
    # The disk's data volume holds the home folder too, under a second name the real path of a
    # folder inside it never shows (/System/Volumes/Data/Users/...), and so do /System/Volumes
    # and /System.
    _allow_folder_within "/System/Volumes/Data" "$_path"
    local _contains_data=$?
    if [ "$_contains_home" -eq 0 ] || [ "$_contains_data" -eq 0 ]; then
        printf '%s\n' "The home folder, and a folder that contains it, cannot be allowed. Choose the folder the task needs."
        return 0
    fi
    case "$_path" in
        "$_home/Library"|"$_home/Library/Application Support")
            printf '%s\n' "This folder holds the data of every application. Choose the folder of the one tool the task needs."
            return 0 ;;
    esac
    local _own="$(allow_folder_real "$mcp_app_support")"
    if [ -n "$_own" ]; then
        _allow_folder_within "$_path" "$_own"
        local _in_own=$?
        if [ "$_in_own" -eq 0 ]; then
            printf '%s\n' "This is Cadabra's own folder, which tools are kept out of."
            return 0
        fi
    fi
    case "$_path/" in
        "$_home"/.*)
            printf '%s\n' "Hidden folders of the home folder hold keys and settings of other programs and cannot be allowed from here. Agentic Session Tools can add one for every conversation."
            return 0 ;;
    esac
    return 0
}

# allow_folder_config <window>  ->  the window's MCP config path.
allow_folder_config() {
    printf '%s/mcp-config.json\n' "$(aichat_session_config_dir "$1")"
}

# _allow_folder_server_names <config>  ->  the config's server names, sorted, on one line.
_allow_folder_server_names() {
    /usr/bin/jq -r '[.servers[].name] | sort | join(" ")' "$1" 2>/dev/null
}

# allow_folder_agent_reloads  ->  0 when the bundled mlx-agent reloads its servers on SIGHUP.
# One without the reload is ENDED by the signal, so the answer decides whether the button exists.
allow_folder_agent_reloads() {
    local _count
    _count="$("$allow_folder_agent" --help 2>&1 | /usr/bin/grep -c 'SIGHUP')"
    if [ "${_count:-0}" = "0" ]; then
        return 1
    fi
    return 0
}

# allow_folder_applies <window>  ->  0 when the window's tools are a local model's, on this Mac,
# with a server that is confined to folders (the Local or the PDF server).
allow_folder_applies() {
    if [ -n "$(mcp_box_tools_get "$1")" ]; then
        return 1
    fi
    if [ -n "$(pb_get "aichatv2_agent_$1")" ]; then
        return 1
    fi
    local _config="$(allow_folder_config "$1")"
    if [ ! -f "$_config" ]; then
        return 1
    fi
    case " $(_allow_folder_server_names "$_config") " in
        *" local "*|*" pdf "*) return 0 ;;
    esac
    return 1
}

# allow_folder_agent_pid <window>  ->  the pid of the window's mlx-agent, or nothing. The process
# is identified by what only it has: the bundled agent's path as its program and this window's
# config path after --mcp-config. Read from the process table at the moment of use, never kept.
allow_folder_agent_pid() {
    local _config="$(allow_folder_config "$1")"
    local _pid _args
    for _pid in $(/usr/bin/pgrep -f "[/]mlx-agent" 2>/dev/null); do
        _args="$(/bin/ps -p "$_pid" -o args= 2>/dev/null)"
        case "$_args" in
            "$allow_folder_agent "*" --mcp-config $_config"|"$allow_folder_agent "*" --mcp-config $_config "*)
                printf '%s\n' "$_pid"
                return 0 ;;
        esac
    done
    return 0
}

# allow_folder_button <window>  ->  0. Puts the button into the window's model bar when a folder
# can be allowed for it, and takes it out when not (after a switch to a model without tools,
# say). Its tooltip lists the folders already allowed for the window.
allow_folder_button() {
    "$dialog" "$1" "$allow_folder_button_id" omc_remove_element 2>/dev/null
    allow_folder_applies "$1"
    local _applies=$?
    if [ "$_applies" -ne 0 ]; then
        # An offer made after a refused tool call goes with the button.
        if [ -n "$(pb_get "aichatv2_folder_offer_$1")" ]; then
            allow_folder_offer_hide "$1"
        fi
        return 0
    fi
    allow_folder_agent_reloads
    local _reloads=$?
    if [ "$_reloads" -ne 0 ]; then
        echo "allow folder: this mlx-agent has no reload; the button is not offered"
        return 0
    fi
    "$dialog" "$1" "$allow_folder_slot_id" omc_insert_element "{\"type\":\"Button\",\"id\":$allow_folder_button_id,\"properties\":{\"title\":\"Allow a Folder...\",\"systemImage\":\"folder.badge.plus\",\"buttonStyle\":\"bordered\",\"controlSize\":\"small\",\"actionID\":\"aichat.chat.allow.folder\"}}"
    allow_folder_button_help "$1"
    return 0
}

# allow_folder_button_help <window>  ->  0. Restates the button's tooltip from the window's list.
allow_folder_button_help() {
    local _help="Let the tools of this window use one more folder of this Mac, without starting the conversation again"
    local _list="$(allow_folder_list "$1" | /usr/bin/awk -F'\t' '{ print $2 " (" $1 ")" }')"
    if [ -n "$_list" ]; then
        _help="Allowed for this window:$allow_folder_newline$_list"
    fi
    "$dialog" "$1" "$allow_folder_button_id" omc_set_property help "$_help"
    return 0
}

# allow_folder_add <window> <real path> <read-only|read-write>  ->  0 when the folder is in the
# window's list with that access (added, or moved from the other list), 1 when the list could
# not be written. The previous list is kept as window-folders.json.before for allow_folder_undo.
allow_folder_add() {
    local _file="$(allow_folder_file "$1")"
    local _dir="$(aichat_session_config_dir "$1")"
    /bin/mkdir -p "$_dir" 2>/dev/null
    local _current='{}'
    if [ -f "$_file" ]; then
        _current="$(/bin/cat "$_file" 2>/dev/null)"
    fi
    local _key=read_only _other=read_write
    if [ "$3" = "read-write" ]; then
        _key=read_write
        _other=read_only
    fi
    local _next
    _next="$(printf '%s\n' "$_current" | /usr/bin/jq --arg path "$2" --arg key "$_key" --arg other "$_other" \
        '{read_only: (.read_only // []), read_write: (.read_write // [])}
         | .[$other] -= [$path]
         | .[$key] = ((.[$key] - [$path]) + [$path])' 2>/dev/null)"
    local _status=$?
    if [ "$_status" -ne 0 ] || [ -z "$_next" ]; then
        return 1
    fi
    printf '%s\n' "$_current" > "$_file.before"
    printf '%s\n' "$_next" > "$_file.new"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        return 1
    fi
    /bin/mv -f "$_file.new" "$_file"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        return 1
    fi
    return 0
}

# allow_folder_undo <window>  ->  0. Puts back the list as it was before the last allow_folder_add.
allow_folder_undo() {
    local _file="$(allow_folder_file "$1")"
    if [ -f "$_file.before" ]; then
        /bin/mv -f "$_file.before" "$_file"
    fi
    return 0
}

# allow_folder_apply <window>  ->  0 when the window's servers will follow its list: the config
# was generated again and the window's mlx-agent was told to read it. Otherwise the config is
# left as it was and allow_folder_error says why:
#   1  the config could not be generated, or a server of the running session is missing from it
#      (a server that cannot start with the new folder would otherwise be taken away);
#   2  the window's mlx-agent is not running.
# The new config is generated beside the old one and moved over it in one step, since the agent
# may read the file at any moment (it reads it first when a tool is first needed).
allow_folder_error=""
allow_folder_apply() {
    allow_folder_error=""
    local _config="$(allow_folder_config "$1")"
    local _next="$(aichat_session_config_dir "$1")/mcp-config.next.json"
    local _before="$(_allow_folder_server_names "$_config")"
    generate_stdio_mcp_config "$_next" --window-folders "$(allow_folder_file "$1")" 1>&2
    local _after=""
    if [ -f "$_next" ]; then
        _after="$(_allow_folder_server_names "$_next")"
    fi
    if [ -z "$_after" ] || [ "$_after" != "$_before" ]; then
        /bin/rm -f "$_next"
        allow_folder_error="The tools could not be prepared with this folder (servers before: ${_before:-none}; after: ${_after:-none})."
        return 1
    fi
    local _pid="$(allow_folder_agent_pid "$1")"
    if [ -z "$_pid" ]; then
        /bin/rm -f "$_next"
        allow_folder_error="This window's model is not running."
        return 2
    fi
    # The old config is kept beside until the agent has been told: when the signal cannot be
    # sent, it goes back, so a failure never leaves a config with a folder the user was told
    # was not allowed.
    local _kept="$(aichat_session_config_dir "$1")/mcp-config.before.json"
    /bin/cp -f "$_config" "$_kept" 2>/dev/null
    local _status=$?
    if [ "$_status" -ne 0 ]; then
        /bin/rm -f "$_next" "$_kept"
        allow_folder_error="The tools' settings file could not be replaced."
        return 1
    fi
    /bin/mv -f "$_next" "$_config"
    _status=$?
    if [ "$_status" -ne 0 ]; then
        /bin/rm -f "$_next" "$_kept"
        allow_folder_error="The tools' settings file could not be replaced."
        return 1
    fi
    /bin/kill -HUP "$_pid" 2>/dev/null
    _status=$?
    if [ "$_status" -ne 0 ]; then
        /bin/mv -f "$_kept" "$_config"
        allow_folder_error="This window's model ended before it could be told."
        return 2
    fi
    /bin/rm -f "$_kept"
    echo "allow folder: window $1 config regenerated, SIGHUP to mlx-agent $_pid"
    return 0
}

# THE OFFER AFTER A REFUSED TOOL CALL. When a tool call of the window ends refused a path (the
# Local server's "Path not allowed: ...", the PDF server's "... outside allowed roots: ...", or
# a command's "...: Operation not permitted"), a line
# under the chat names the folder and offers Allow a Folder... with the chooser opened there.
# The path comes from a tool's output, which the model shapes, so it is a HINT and nothing more:
# it decides where the chooser opens and what the line says. The folder allowed is still the one
# the user chooses, and the refusals of allow_folder_refusal still apply to it. A hint that is
# itself a folder never allowed (the home folder, "/") makes no offer.
#
# The line is one per window, the latest refusal's. Dismiss takes it away and the same folder
# is not offered again in this window.
allow_folder_offer_slot_id=562
allow_folder_offer_row_id=563
allow_folder_offer_path_id=564
allow_folder_offer_button_id=565
allow_folder_offer_dismiss_id=566
# The two programs the offer runs that are not shell: what a result's text says was refused,
# and the line's element.
allow_folder_refused_awk="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.allow.folder.refused.awk"
allow_folder_offer_jq="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.allow.folder.offer.jq"

# allow_folder_refused_path <envelope>  ->  the path a finished tool call says it was refused, as
# the tool wrote it, or nothing. A server's own refusal is looked for first, then the first
# "Operation not permitted" line of a command's output that names an absolute path.
allow_folder_refused_path() {
    printf '%s\n' "$1" | /usr/bin/jq -r '.data.toolCall.contentText // ""' 2>/dev/null | /usr/bin/awk -f "$allow_folder_refused_awk"
}

# allow_folder_hint <path>  ->  the folder to offer for a refused path: the path itself when it is
# a folder, otherwise the nearest folder above it that exists, as its real path. Nothing when the
# path is not absolute.
allow_folder_hint() {
    local _path="$1"
    case "$_path" in
        /*) ;;
        *)  return 0 ;;
    esac
    local _steps=0
    while [ ! -d "$_path" ] && [ "$_steps" -lt 64 ]; do
        _path="${_path%/*}"
        if [ -z "$_path" ]; then
            _path="/"
        fi
        _steps=$((_steps + 1))
    done
    allow_folder_real "$_path"
}

# _allow_folder_dismissed_file <window>  ->  the folders whose offer was dismissed in the window.
_allow_folder_dismissed_file() {
    printf '%s/window-folders-dismissed.txt\n' "$(aichat_session_config_dir "$1")"
}

# allow_folder_offer_hide <window>  ->  0. Takes the offer line away. Safe when there is none.
allow_folder_offer_hide() {
    "$dialog" "$1" "$allow_folder_offer_row_id" omc_remove_element 2>/dev/null
    pb_set "aichatv2_folder_offer_$1" ""
    return 0
}

# allow_folder_offer_dismiss <window>  ->  0. Dismiss on the line: it goes, and its folder is not
# offered again in this window.
allow_folder_offer_dismiss() {
    local _folder="$(pb_get "aichatv2_folder_offer_$1")"
    if [ -n "$_folder" ]; then
        printf '%s\n' "$_folder" >> "$(_allow_folder_dismissed_file "$1")"
    fi
    allow_folder_offer_hide "$1"
}

# _allow_folder_offer_show <window> <folder>  ->  0. The part of allow_folder_offer done while it
# holds the window's offer lock: what the window is offered now, what was dismissed and what it
# already has are read here, so that two calls refused at the same moment cannot both pass.
_allow_folder_offer_show() {
    local _folder="$2"
    if [ "$(pb_get "aichatv2_folder_offer_$1")" = "$_folder" ]; then
        return 0
    fi
    local _dismissed="$(_allow_folder_dismissed_file "$1")"
    local _count=0
    if [ -f "$_dismissed" ]; then
        _count="$(/usr/bin/grep -c -F -x -e "$_folder" "$_dismissed" 2>/dev/null)"
    fi
    if [ "${_count:-0}" != "0" ]; then
        return 0
    fi
    local _covered
    _covered="$(allow_folder_list "$1" | FOLDER="$_folder" /usr/bin/awk -F'\t' '$1 == "read-write" && index(ENVIRON["FOLDER"] "/", $2 "/") == 1 { n++ } END { print n + 0 }')"
    if [ "${_covered:-0}" != "0" ]; then
        return 0
    fi

    # The line shows the folder with the home folder as "~", which the chooser's starting
    # folder (DEFAULT_LOCATION of aichat.chat.allow.folder.choose) reads as well.
    local _shown="$_folder"
    local _home="$(allow_folder_real "$HOME")"
    case "$_folder" in
        "$_home"/*) _shown="~${_folder#"$_home"}" ;;
    esac
    local _row
    _row="$(/usr/bin/jq -c -n \
        --argjson row "$allow_folder_offer_row_id" --argjson path "$allow_folder_offer_path_id" \
        --argjson button "$allow_folder_offer_button_id" --argjson dismiss "$allow_folder_offer_dismiss_id" \
        --arg help "$_folder" \
        -f "$allow_folder_offer_jq")"
    if [ -n "$_row" ]; then
        "$dialog" "$1" "$allow_folder_offer_row_id" omc_remove_element 2>/dev/null
        "$dialog" "$1" "$allow_folder_offer_slot_id" omc_insert_element "$_row"
        "$dialog" "$1" "$allow_folder_offer_path_id" "$_shown"
        pb_set "aichatv2_folder_offer_$1" "$_folder"
        echo "allow folder: offered $_folder to window $1"
    fi
    return 0
}

# allow_folder_offer <window> <envelope>  ->  0. Shows the offer line for the folder a finished
# tool call was refused, when a folder can be allowed for the window at all, the folder is one
# that may be allowed, the window does not already have it read-write, and its offer was not
# dismissed. One offer is made at a time: a call that finishes while another offer is being put
# up is left out, and the next refusal offers again.
allow_folder_offer() {
    local _path="$(allow_folder_refused_path "$2")"
    if [ -z "$_path" ]; then
        return 0
    fi
    allow_folder_applies "$1"
    local _applies=$?
    if [ "$_applies" -ne 0 ]; then
        return 0
    fi
    allow_folder_agent_reloads
    local _reloads=$?
    if [ "$_reloads" -ne 0 ]; then
        return 0
    fi
    local _folder="$(allow_folder_hint "$_path")"
    if [ -z "$_folder" ] || [ -n "$(allow_folder_refusal "$_folder")" ]; then
        return 0
    fi
    local _lock="$(aichat_session_config_dir "$1")/window-folders-offer.lock"
    /bin/mkdir "$_lock" 2>/dev/null
    local _locked=$?
    if [ "$_locked" -ne 0 ]; then
        # A lock left by a handler that was ended is taken over after half a minute.
        local _made="$(/usr/bin/stat -f %m "$_lock" 2>/dev/null)"
        local _now="$(/bin/date +%s)"
        if [ -z "$_made" ] || [ $((_now - _made)) -lt 30 ]; then
            return 0
        fi
    fi
    _allow_folder_offer_show "$1" "$_folder"
    /bin/rmdir "$_lock" 2>/dev/null
    return 0
}

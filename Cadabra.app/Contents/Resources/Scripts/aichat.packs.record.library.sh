#!/bin/sh
# aichat.packs.record.library.sh
# The Record a Pack window (aichat.packs.record.json): a command is run under a sandbox that
# allows only the folder it runs in, again and again with what it was refused, and the folders
# found are reviewed and saved as a sandbox pack of the user's own. sandbox_packs_record.py does
# the running (through replay's sandbox-discover.py) and keeps what was found; the handlers
# (aichat.packs.record.*.sh) show it. Sourced by those handlers.
[ -n "${__AICHAT_PACKS_RECORD_LIB:-}" ] && return 0
__AICHAT_PACKS_RECORD_LIB=1
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.mcp.servers.library.sh"

record_command_view=701
record_folder_view=702
record_start_view=704
record_stop_view=705
record_status_view=706
record_progress_view=707
record_table_view=710
record_title_view=720
record_id_view=721
record_description_view=722
record_save_view=730

# replay's recorder, copied into the application with replay (update-cadabra.sh).
record_discover="${CADABRA_SANDBOX_DISCOVER:-$OMC_APP_BUNDLE_PATH/Contents/Support/sandbox-discover.py}"
# Where the user's own packs are kept, beside the settings file (sandbox_packs.py).
record_user_packs="$mcp_app_support/SandboxPacks"
# The packs that come with the application; a user pack with the id of one takes its place.
record_seed_packs="$OMC_APP_BUNDLE_PATH/Contents/Resources/SandboxPacks"
# The Agentic Session Tools window Record a Pack... was clicked in, handed to the next Record a
# Pack window to open; that window keeps it under its own key and refreshes it after a save.
RECORD_PARENT_KEY="aichatv2_packsrecord_parent"

# record_state_file <window>  ->  what the window's last recording found (sandbox_packs_record.py).
record_state_file() {
    cadabra_run_file "packs-record.$1.json"
}

# record_pid_file <window>  ->  holds the recording's process id while one runs.
record_pid_file() {
    cadabra_run_file "packs-record.$1.pid"
}

# record_mark_dir <window>  ->  a folder that is there while the window's Record handler runs. The
# handler makes it, so a second click on Record that comes before the first disabled the button
# starts nothing; record_forget removes it when the window closes, which the handler takes as
# the word to end its recording.
record_mark_dir() {
    cadabra_run_file "packs-record.$1.recording"
}

# record_py <command> [options...]  ->  runs sandbox_packs_record.py; 1 when the bundled Python
# or the script is missing.
record_py() {
    local python3="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
    local script="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/sandbox_packs_record.py"
    if [ ! -f "$python3" ] || [ ! -f "$script" ]; then
        echo "record_py: bundled Python or sandbox_packs_record.py missing" >&2
        return 1
    fi
    "$python3" -B "$script" "$@"
}

# record_running_pid <window>  ->  the process id of the window's recording, or nothing. The id
# in the pid file counts only while the process table shows it running this window's recording
# (its state file among its arguments): a number left by a recording that ended is never signaled.
record_running_pid() {
    local pid_file="$(record_pid_file "$1")"
    local pid=""
    if [ -f "$pid_file" ]; then
        IFS= read -r pid < "$pid_file"
    fi
    case "$pid" in
        ''|*[!0-9]*) return 0 ;;
    esac
    local args="$(/bin/ps -p "$pid" -o args= 2>/dev/null)"
    local state="$(record_state_file "$1")"
    case "$args" in
        *"sandbox_packs_record.py run "*" --state $state "*)
            printf '%s\n' "$pid" ;;
    esac
    return 0
}

# record_stop <window>  ->  0. Ends the window's recording, if one runs: the command and all it
# started go with it (sandbox_packs_record.py passes the signal on).
record_stop() {
    local pid="$(record_running_pid "$1")"
    if [ -n "$pid" ]; then
        /bin/kill -TERM "$pid" 2>/dev/null
    fi
    return 0
}

# record_show_rows <window>  ->  the review table from the window's state file.
record_show_rows() {
    local state="$(record_state_file "$1")"
    "$dialog" "$1" $record_table_view omc_table_remove_all_rows
    if [ -f "$state" ]; then
        record_py rows --state "$state" | "$dialog" "$1" $record_table_view omc_table_set_rows_from_stdin
    fi
}

# record_busy <window> <yes|no>  ->  the controls while a recording runs, and after.
record_busy() {
    if [ "$2" = "yes" ]; then
        "$dialog" "$1" $record_start_view omc_disable
        "$dialog" "$1" $record_stop_view omc_enable
        "$dialog" "$1" $record_save_view omc_disable
        "$dialog" "$1" $record_progress_view omc_show
    else
        "$dialog" "$1" $record_progress_view omc_hide
        "$dialog" "$1" $record_stop_view omc_disable
        "$dialog" "$1" $record_start_view omc_enable
    fi
}

# record_forget <window>  ->  the window's files go.
record_forget() {
    /bin/rm -f "$(record_state_file "$1")" "$(record_pid_file "$1")"
    /bin/rmdir "$(record_mark_dir "$1")" 2>/dev/null
    return 0
}

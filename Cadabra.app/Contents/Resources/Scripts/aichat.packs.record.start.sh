#!/bin/sh
# aichat.packs.record.start.sh
# Record: runs the command of the window under the recorder until it succeeds or nothing more is
# found, showing each pass, then fills the review table. The handler lasts as long as the
# recording; Stop (aichat.packs.record.stop.sh) ends it from another handler.

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.packs.record.library.sh"
aichat_window_only

echo "[$(/usr/bin/basename "$0")]"

window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

command_line="${OMC_ACTIONUI_VIEW_701_VALUE:-}"
folder="${OMC_ACTIONUI_VIEW_702_VALUE:-}"
folder="${folder%/}"
if [ -z "$command_line" ]; then
    "$dialog" "$window_uuid" $record_status_view "Type the command to record first."
    exit 0
fi
case "$folder" in
    /*) ;;
    *)  folder="" ;;
esac
if [ -z "$folder" ] || [ ! -d "$folder" ]; then
    "$dialog" "$window_uuid" $record_status_view "Choose the folder to run the command in first."
    exit 0
fi
if [ -n "$(record_running_pid "$window_uuid")" ]; then
    exit 0
fi

# One Record handler per window: two clicks can both get here before either has a recording to show.
mark="$(record_mark_dir "$window_uuid")"
/bin/mkdir "$mark" 2>/dev/null
marked=$?
if [ "$marked" -ne 0 ]; then
    echo "a recording is being started already, or $mark cannot be made"
    exit 0
fi

state="$(record_state_file "$window_uuid")"
/bin/rm -f "$state"
"$dialog" "$window_uuid" $record_table_view omc_table_remove_all_rows
record_busy "$window_uuid" yes
"$dialog" "$window_uuid" $record_status_view "Pass 1: running the command..."

# Homebrew's tools are where a user's shell finds them; the application's own PATH has neither.
run_path="$PATH"
for extra in /opt/homebrew/bin /usr/local/bin; do
    if [ -d "$extra" ]; then
        run_path="$run_path:$extra"
    fi
done

tab="$(printf '\t')"
outcome=""
message=""
PATH="$run_path" record_py run --discover "$record_discover" --folder "$folder" --state "$state" \
    --pid-file "$(record_pid_file "$window_uuid")" -- "$command_line" > "$state.steps" &
runner=$!
# The steps are read as they come: one line per pass or check, the last one the outcome.
shown=0
abandoned=0
while :; do
    # The window closed (its close handler took the mark away) or Cadabra is gone: there is
    # nobody to show a result to, and the command must not run on. Asked on every turn, since
    # the recording's process id may not have been written when the window closed.
    app_gone=0
    case "${OMC_APP_PROCESS_ID:-}" in
        ''|*[!0123456789]*) ;;
        *)  /bin/kill -0 "$OMC_APP_PROCESS_ID" 2>/dev/null
            app_gone=$? ;;
    esac
    if [ ! -d "$mark" ] || [ "$app_gone" -ne 0 ]; then
        abandoned=1
        record_stop "$window_uuid"
    fi
    /bin/kill -0 "$runner" 2>/dev/null
    alive=$?
    total=0
    if [ -f "$state.steps" ]; then
        total="$(/usr/bin/wc -l < "$state.steps" | /usr/bin/tr -d ' ')"
    fi
    if [ "$total" -gt "$shown" ] && [ "$abandoned" -eq 0 ]; then
        shown="$total"
        IFS="$tab" read -r kind one two three <<EOF_STEP
$(/usr/bin/tail -n 1 "$state.steps")
EOF_STEP
        case "$kind" in
            pass)
                if [ "$two" = "0" ]; then
                    "$dialog" "$window_uuid" $record_status_view "Pass $one: the command ran. $three folders found."
                else
                    "$dialog" "$window_uuid" $record_status_view "Pass $one: the command failed (status $two). $three folders found so far; running it again..."
                fi ;;
            check)
                "$dialog" "$window_uuid" $record_status_view "Checking whether the command needs $one..." ;;
            end)
                outcome="$one"
                message="$two" ;;
        esac
    fi
    if [ "$alive" -ne 0 ]; then
        break
    fi
    /bin/sleep "${CADABRA_RECORD_POLL_SECONDS:-0.5}"
done
wait "$runner" 2>/dev/null
/bin/rmdir "$mark" 2>/dev/null
if [ "$abandoned" -ne 0 ]; then
    /bin/rm -f "$state" "$state.steps"
    exit 0
fi
if [ -z "$outcome" ] && [ -f "$state.steps" ]; then
    IFS="$tab" read -r kind outcome message three <<EOF_STEP
$(/usr/bin/tail -n 1 "$state.steps")
EOF_STEP
    if [ "$kind" != "end" ]; then
        outcome=""
    fi
fi
/bin/rm -f "$state.steps"

record_busy "$window_uuid" no
case "$outcome" in
    success|partial)
        record_show_rows "$window_uuid"
        "$dialog" "$window_uuid" $record_status_view "$message"
        "$dialog" "$window_uuid" $record_save_view omc_enable ;;
    *)
        /bin/rm -f "$state"
        "$dialog" "$window_uuid" $record_status_view "${message:-The recording could not be run.}" ;;
esac

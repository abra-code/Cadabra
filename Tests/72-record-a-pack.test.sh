#!/bin/sh
# Tests/72-record-a-pack.test.sh - the Record a Pack window: a command is recorded, the folders
# found are reviewed (kept or not, read or changed, the ones no pack may hold shown locked), and
# the ticked ones are saved as a pack of the user's own, ticked for the sandbox at once.
#
# replay's recorder is replaced by Tests/helpers/fake_sandbox_discover.py, which writes the real
# tool's events from a scenario file: what the window does with a result is tested here, not the
# recording itself, which needs sandbox-exec and the system log.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.packs.record.library.sh
for name in command folder start stop status progress table title id description save; do
    value="$(cad_lib_var "record_${name}_view" $LIB)"
    if [ -z "$value" ]; then
        printf '%s: record_%s_view was not found in the record library\n' "$0" "$name" >&2
        exit 1
    fi
    eval "V_$name=\$value"
done
SUMMARY_ID="$(cad_lib_var mcp_packs_summary_view aichat.mcp.servers.library.sh)"

SUPPORT="$HOME/Library/Application Support/Cadabra"
USER_PACKS="$SUPPORT/SandboxPacks"
RUN="$SUPPORT/Run"
HOME_REAL="$(cd "$HOME" && pwd -P)"
WORK="$(cd "$OMCTEST_WORK" && pwd -P)/record-a-pack"
/bin/rm -rf "$WORK" "$USER_PACKS"
/bin/mkdir -p "$WORK/project/sub" "$WORK/cache" "$WORK/tools" "$WORK/Tool.app/Contents/bin" "$WORK/Tool.app/Contents/share" "$HOME/dev/tools" "$HOME/.ssh" "$HOME/Library/Caches"
printf 'settings\n' > "$WORK/tools/settings.conf"

# A found path is shown with a token where one fits, and the scratch folder is inside the user's
# temporary folder on most Macs: SHOWN is $WORK as the review table and the pack spell it.
TEMP_REAL="$(cd "$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)" 2>/dev/null && pwd -P)"
case "$WORK" in
    "$TEMP_REAL"/*) SHOWN="\$DARWIN_USER_TEMP_DIR${WORK#"$TEMP_REAL"}" ;;
    *)              SHOWN="$WORK" ;;
esac

CADABRA_SANDBOX_DISCOVER="$OMCTEST_TESTS/helpers/fake_sandbox_discover.py"
CADABRA_RECORD_POLL_SECONDS=0.1
FAKE_DISCOVER_SCENARIO="$WORK/scenario.json"
FAKE_DISCOVER_ARGV="$WORK/argv.txt"
# The recording is given the temporary folders, and what is in them is left out of what is found.
# This file's own folders are all in the temporary folder, so it names another as the only one.
/bin/mkdir -p "$WORK/temp/scratch"
CADABRA_RECORD_TEMP_FOLDERS="$WORK/temp"
export CADABRA_SANDBOX_DISCOVER CADABRA_RECORD_POLL_SECONDS FAKE_DISCOVER_SCENARIO FAKE_DISCOVER_ARGV CADABRA_RECORD_TEMP_FOLDERS

# scenario <stopped> <exit>  ->  the recorder finds the same folders and ends that way.
scenario() {
    /usr/bin/jq -n --arg work "$WORK" --arg above "${WORK%/*}" --arg home "$HOME_REAL" --arg stopped "$1" --argjson exit "$2" '{
        exit: $exit,
        events: [
            { event: "pass", pass: 1, exit: 1, read_only: [($work + "/tools")], read_write: [] },
            { event: "hint", pass: 1, source: "output", paths: [($work + "/Tool.app/Contents/share")] },
            { event: "check", without: [($home + "/dev/tools")], exit: 1 },
            { event: "done", passes: 2, exit: $exit, stopped: $stopped,
              read_write: [($work + "/cache"), ($work + "/project/sub"), ($work + "/temp/scratch")],
              read_only: [($home + "/dev/tools"), ($work + "/tools/settings.conf"), ($home + "/.ssh"), ($home + "/Library/Caches"), "/bin/sh", "/usr/lib/dyld", "/System/Library/Frameworks", "/dev/tty",
                          ($work + "/Tool.app/Contents/bin"), ($work + "/Tool.app/Contents/share"), $work],
              folder_only: [$above, ($work + "/Tool.app"), ($work + "/Tool.app/Contents")],
              unverified: [($home + "/dev/tools")],
              hinted: [($work + "/tools/settings.conf"), ($work + "/Tool.app/Contents/share")] } ] }' > "$FAKE_DISCOVER_SCENARIO"
}
fresh_window() {
    omc_control_defaults aichat.packs.record
    ui_reset
    cad_journal_reset
}
record() {
    omc_control "$V_command" "$1"
    omc_control "$V_folder" "$WORK/project"
    omc_run aichat.packs.record.start
}
# row_with <text>  ->  the review table's row holding it.
row_with() {
    ui_rows "$V_table" | /usr/bin/grep -F -- "$1"
}
index_of() {
    ui_rows "$V_table" | /usr/bin/awk -F'\t' -v path="$1" '$2 == path { print NR - 1 }'
}
click() {
    omc_trigger "$V_table" "" "$(index_of "$2")"
    omc_run "aichat.packs.record.$1"
}
stored() {
    cad_call mcp_prefs_array_list servers/local/packs | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//'
}

section "the window opens on the project folder"
cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1
cad_call mcp_prefs_set_string servers/local/project "$WORK/project"
cad_pb_set aichatv2_packsrecord_parent "tools-window"
fresh_window
omc_run aichat.packs.record.init
check_status "init ran" 0
check "Run in is the project folder" "$WORK/project" "$(ui_value "$V_folder")"
check "the window that opened it is taken over" "tools-window|" \
    "$(cad_pb_get "aichatv2_packsrecord_parent_$OMC_ACTIONUI_WINDOW_UUID")|$(cad_pb_get aichatv2_packsrecord_parent)"

section "Record needs a command and a folder"
/bin/rm -f "$FAKE_DISCOVER_ARGV"
omc_control "$V_command" ""
omc_control "$V_folder" "$WORK/project"
omc_run aichat.packs.record.start
check "no command: said so"        "Type the command to record first." "$(ui_value "$V_status")"
omc_control "$V_command" "make"
omc_control "$V_folder" "$WORK/no-such-folder"
omc_run aichat.packs.record.start
check "no folder: said so"         "Choose the folder to run the command in first." "$(ui_value "$V_status")"
check "  and nothing was run"      "no" "$([ -f "$FAKE_DISCOVER_ARGV" ] && echo yes || echo no)"

section "a recording that succeeds fills the review table"
scenario success 0
fresh_window
record "make all"
check_status "the handler ran" 0
check "the recorder ran the command with /bin/sh, in a loop, the folder allowed" "1|1|1" \
    "$(/usr/bin/tail -n 3 "$FAKE_DISCOVER_ARGV" | /usr/bin/tr '\n' ' ' | /usr/bin/grep -c '^/bin/sh -c make all $')|$(/usr/bin/grep -c -x -- '--loop' "$FAKE_DISCOVER_ARGV")|$(/usr/bin/grep -A1 -x -- '--allow-write' "$FAKE_DISCOVER_ARGV" | /usr/bin/grep -c -x "$WORK/project")"
check "the status says how it ended"        "The command ran after 2 passes." "$(ui_value "$V_status")"
check "a folder to change is kept"          "checkmark.square.fill	$SHOWN/cache	Read and change	" "$(row_with "$SHOWN/cache")"
check "a folder in the home folder is written with ~, and its doubt noted" \
    "checkmark.square.fill	~/dev/tools	Read	Unverified: may have been refused to another program." "$(row_with '~/dev/tools')"
check "a single file is one"                "checkmark.square.fill	$SHOWN/tools/settings.conf	Read (one file)	" "$(row_with settings.conf)"
check "a folder of keys is locked"          "minus.square	~/.ssh	Read	Never in a pack: in ~/.ssh, which holds keys or private data" "$(row_with '~/.ssh')"
check "a wide folder starts unticked"       "square" "$(row_with '~/Library/Caches' | /usr/bin/cut -f1)"
check "what was read inside an application is one row, the application" "checkmark.square.fill	$SHOWN/Tool.app	Read	|1" \
    "$(row_with "$SHOWN/Tool.app")|$(ui_rows "$V_table" | /usr/bin/grep -c -F "Tool.app")"
check "the temporary folder is given to change, and what is in it is left out" "1|0" \
    "$(/usr/bin/grep -A1 -x -- '--allow-write' "$FAKE_DISCOVER_ARGV" | /usr/bin/grep -c -x "$WORK/temp")|$(ui_rows "$V_table" | /usr/bin/grep -c -F '/temp/scratch')"
check "the system's program and library folders are given to the recording from the start" "/bin /sbin /usr/bin /usr/sbin /usr/lib /System/Library" \
    "$(/usr/bin/grep -A1 -x -- '--allow-read' "$FAKE_DISCOVER_ARGV" | /usr/bin/grep '^/' | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
check "a folder needed only as itself is locked" "minus.square" "$(ui_rows "$V_table" | /usr/bin/awk -F'\t' -v path="${SHOWN%/*}" '$2 == path { print $1 }')"
check "the folder above the run's folder starts unticked, and says why" "square|1" \
    "$(ui_rows "$V_table" | /usr/bin/awk -F'\t' -v path="$SHOWN" '$2 == path { print $1 }')|$(ui_rows "$V_table" | /usr/bin/awk -F'\t' -v path="$SHOWN" '$2 == path { print $4 }' | /usr/bin/grep -c 'Contains the folder the command ran in')"
check "what is inside the run's folder is left out" "" "$(row_with "$SHOWN/project/sub")"
check "what replay's sandbox always allows, and devices, are left out" "0" "$(ui_rows "$V_table" | /usr/bin/grep -c -E '	(/bin/sh|/usr/lib/dyld|/System/Library/Frameworks|/dev/tty)	')"
check "Save Pack is on, Record on again, Stop off" "1|1|0" "$(ui_enabled "$V_save")|$(ui_enabled "$V_start")|$(ui_enabled "$V_stop")"
check "the progress view is hidden again"   "0" "$(ui_visible "$V_progress")"

section "the steps of a recording, as the window is told them"
steps="$("$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3" -B "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/sandbox_packs_record.py" run \
    --discover "$CADABRA_SANDBOX_DISCOVER" --folder "$WORK/project" --state "$WORK/steps-state.json" --pid-file "$WORK/steps.pid" -- "make all")"
check "a pass counts what was found beyond what is always allowed" "pass	1	1	1" "$(printf '%s\n' "$steps" | /usr/bin/sed -n 1p)"
check "a hint says where the folders tried come from"              "hint	output	1" "$(printf '%s\n' "$steps" | /usr/bin/sed -n 2p)"
check "the last line is the outcome"                               "end	success	The command ran after 2 passes." "$(printf '%s\n' "$steps" | /usr/bin/tail -n 1)"

section "reviewing: keep, and the access"
click keep "$SHOWN/cache"
check "a click unticks"                     "square" "$(row_with "$SHOWN/cache" | /usr/bin/cut -f1)"
click keep "$SHOWN/cache"
check "  and ticks again"                   "checkmark.square.fill" "$(row_with "$SHOWN/cache" | /usr/bin/cut -f1)"
click keep '~/.ssh'
check "a locked row stays locked"           "minus.square" "$(row_with '~/.ssh' | /usr/bin/cut -f1)"
click access '~/dev/tools'
check "a folder to read becomes one to change" "Read and change" "$(row_with '~/dev/tools' | /usr/bin/cut -f3)"
click access '~/dev/tools'
check "  and back"                          "Read" "$(row_with '~/dev/tools' | /usr/bin/cut -f3)"
click access "$SHOWN/tools/settings.conf"
check "a single file stays read-only"       "Read (one file)" "$(row_with settings.conf | /usr/bin/cut -f3)"
omc_trigger "$V_table" "" "not a row"
omc_run aichat.packs.record.keep
check_status "a click with no row is ignored" 0

section "Save Pack needs a title"
alerts_reset
omc_control "$V_title" ""
omc_control "$V_id" ""
omc_control "$V_description" ""
omc_run aichat.packs.record.save
check "the user is told"    "1" "$(alerts_mention 'needs a title')"
check "  and nothing is written" "0" "$(/bin/ls "$USER_PACKS" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "Save Pack writes the pack, ticks it and closes the window"
alerts_reset
cad_journal_reset
omc_control "$V_title" "My Build: tools"
omc_control "$V_id" ""
omc_control "$V_description" "Building with make."
omc_run aichat.packs.record.save
check_status "the handler ran" 0
PACK="$USER_PACKS/my-build-tools.json"
check "no alert"                        "0" "$(alerts_count)"
check "the id comes from the title"     "yes" "$([ -f "$PACK" ] && echo yes || echo no)"
check "its title and description"       "My Build: tools|Building with make." "$(/usr/bin/jq -r '.title + "|" + .description' "$PACK")"
check "the folders to change"           "$SHOWN/cache" "$(/usr/bin/jq -r '.read_write | join(" ")' "$PACK")"
check "the folders to read, the application and the one with ~" "$SHOWN/Tool.app ~/dev/tools" "$(/usr/bin/jq -r '.read_only | join(" ")' "$PACK")"
check "the single files"                "$SHOWN/tools/settings.conf" "$(/usr/bin/jq -r '.read_only_files | join(" ")' "$PACK")"
check "how it was recorded"             "sandbox-discover|make all" "$(/usr/bin/jq -r '.recorded.by + "|" + .recorded.command' "$PACK")"
check "the application reads it as a usable pack" "ok" \
    "$("$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3" -B "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/sandbox_packs.py" check "$PACK" | /usr/bin/jq -r .state)"
check "the pack is ticked"              "my-build-tools" "$(stored)"
check "the window closes"               "1" "$(cad_has "$(cad_journal omc_window)" 'omc_terminate_ok')"
check "the window that opened it shows the pack" "Sandbox packs: My Build: tools" "$(ui_value "$SUMMARY_ID" tools-window)"
check "the recording is forgotten"      "0" "$(/bin/ls "$RUN" 2>/dev/null | /usr/bin/grep -c "^packs-record\.$OMC_ACTIONUI_WINDOW_UUID")"

section "a pack with the same id is replaced only when the user says so"
fresh_window
record "make all"
click keep "$SHOWN/cache"
omc_control "$V_title" "Changed"
omc_control "$V_id" "my-build-tools"
omc_control "$V_description" ""
alerts_reset
alert_answers_reset
alert_answer 1
omc_run aichat.packs.record.save
check "the user is asked"               "1" "$(alerts_mention 'Replace the pack my-build-tools')"
check "Cancel keeps the pack"           "My Build: tools" "$(/usr/bin/jq -r .title "$PACK")"
alerts_reset
alert_answer 0
omc_run aichat.packs.record.save
check "Replace writes the new one"      "Changed|" "$(/usr/bin/jq -r '.title + "|" + (.read_write | join(" "))' "$PACK")"
check "  and it is ticked once"         "my-build-tools" "$(stored)"

section "the id of a pack that comes with Cadabra asks too"
fresh_window
record "make all"
omc_control "$V_title" "Xcode"
omc_control "$V_id" ""
omc_control "$V_description" ""
alerts_reset
alert_answers_reset
alert_answer 1
omc_run aichat.packs.record.save
check "the user is asked, and told whose pack it is" "1" "$(alerts_mention 'comes with Cadabra has this id')"
check "Cancel writes no such pack"      "no" "$([ -f "$USER_PACKS/xcode.json" ] && echo yes || echo no)"
alert_answers_reset

section "an id that is not one is refused"
fresh_window
record "make all"
alerts_reset
alert_answers_reset
omc_control "$V_title" "Odd"
omc_control "$V_id" "Not An Id"
omc_run aichat.packs.record.save
check "the user is told"                "1" "$(alerts_mention 'lowercase letters')"
check "  and no such pack is written"   "1" "$(/bin/ls "$USER_PACKS" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "a command that still fails keeps what was found, and says so"
scenario no-new-paths 1
fresh_window
record "make all"
check "the status says it still fails"  "1" "$(cad_has "$(ui_value "$V_status")" 'The command still fails (status 1) and nothing more was refused.')"
check "the folders found are shown"     "1" "$([ -n "$(row_with "$SHOWN/cache")" ] && echo 1 || echo 0)"
check "what the recorder only guessed starts unticked, and says so" "square|1" \
    "$(row_with settings.conf | /usr/bin/cut -f1)|$(row_with settings.conf | /usr/bin/cut -f4 | /usr/bin/grep -c '^A guess: ')"
check "  an application is a guess only when all found in it was" "checkmark.square.fill" "$(row_with "$SHOWN/Tool.app" | /usr/bin/cut -f1)"
check "  and can be saved"              "1" "$(ui_enabled "$V_save")"

section "a recorder that ends without a result leaves nothing to save"
printf '{"events": [], "exit": 1}\n' > "$FAKE_DISCOVER_SCENARIO"
fresh_window
record "make all"
check "the status says so"              "The recorder ended without a result. Nothing was kept." "$(ui_value "$V_status")"
check "the table is empty"              "0" "$(ui_row_count "$V_table")"
check "Save Pack is not turned on"      "" "$(ui_enabled "$V_save" | /usr/bin/grep 1)"
cad_journal_reset
omc_run aichat.packs.record.save
check "  and Save Pack does nothing"    "0" "$(cad_has "$(cad_journal omc_window)" 'omc_terminate_ok')"

section "Stop ends a running recording"
fresh_window
omc_control "$V_command" "hang"
omc_control "$V_folder" "$WORK/project"
omc_run aichat.packs.record.start &
runner=$!
PID_FILE="$RUN/packs-record.$OMC_ACTIONUI_WINDOW_UUID.pid"
check "the recording is running" "yes" "$(omc_wait_for "[ -s \"$PID_FILE\" ]" 10 && echo yes || echo no)"
recorded_pid="$(/bin/cat "$PID_FILE" 2>/dev/null)"
omc_run aichat.packs.record.stop
wait "$runner"
check "the recording's process is gone" "gone" "$(/bin/kill -0 "$recorded_pid" 2>/dev/null && echo there || echo gone)"
check "the status says it was stopped"  "Recording was stopped. Nothing was kept." "$(ui_value "$V_status")"
check "Record is on again"              "1" "$(ui_enabled "$V_start")"
check "the pid file is gone"            "no" "$([ -f "$PID_FILE" ] && echo yes || echo no)"

section "a stale process id is never signaled"
printf '%s\n' "$$" > "$PID_FILE"
omc_run aichat.packs.record.stop
check "this test's own shell is still here" "here" "$(/bin/kill -0 "$$" 2>/dev/null && echo here || echo gone)"

section "two clicks on Record start one recording"
fresh_window
omc_control "$V_command" "hang"
omc_control "$V_folder" "$WORK/project"
FAKE_DISCOVER_RUNS="$WORK/runs.txt"
export FAKE_DISCOVER_RUNS
/bin/rm -f "$FAKE_DISCOVER_RUNS"
omc_run aichat.packs.record.start &
first=$!
omc_run aichat.packs.record.start &
second=$!
check "a recording is running" "yes" "$(omc_wait_for "[ -s \"$PID_FILE\" ]" 10 && echo yes || echo no)"
/bin/sleep 1
omc_run aichat.packs.record.stop
wait "$first"
wait "$second"
check "the recorder was started once" "1" "$(/usr/bin/wc -l < "$FAKE_DISCOVER_RUNS" | /usr/bin/tr -d ' ')"
check "nothing of the recording is left" "0" "$(/bin/ls "$RUN" | /usr/bin/grep -c "^packs-record\.$OMC_ACTIONUI_WINDOW_UUID")"
unset FAKE_DISCOVER_RUNS

section "closing the window ends a running recording"
fresh_window
omc_control "$V_command" "hang"
omc_control "$V_folder" "$WORK/project"
omc_run aichat.packs.record.start &
runner=$!
check "the recording is running" "yes" "$(omc_wait_for "[ -s \"$PID_FILE\" ]" 10 && echo yes || echo no)"
recorded_pid="$(/bin/cat "$PID_FILE" 2>/dev/null)"
omc_run aichat.packs.record.close
wait "$runner"
check "the recording's process is gone" "gone" "$(/bin/kill -0 "$recorded_pid" 2>/dev/null && echo there || echo gone)"
check "nothing of the recording is left" "0" "$(/bin/ls "$RUN" | /usr/bin/grep -c "^packs-record\.$OMC_ACTIONUI_WINDOW_UUID")"

section "a folder found under another spelling is held under the disk's own"
if [ -d "$WORK/CACHE" ]; then
    /usr/bin/jq -n --arg work "$WORK" '{ exit: 0, events: [
        { event: "done", passes: 1, exit: 0, stopped: "success",
          read_write: [($work + "/CACHE"), ($work + "/PROJECT/sub")], read_only: [], folder_only: [], unverified: [] } ] }' > "$FAKE_DISCOVER_SCENARIO"
    fresh_window
    record "make all"
    check "the row has the disk's spelling"  "checkmark.square.fill	$SHOWN/cache	Read and change	" "$(ui_rows "$V_table")"
else
    check "(skipped: the test volume tells upper case from lower)" "skipped" "skipped"
fi

section "closing the window forgets the recording"
scenario success 0
fresh_window
record "make all"
check "there is a recording"            "1" "$(/bin/ls "$RUN" | /usr/bin/grep -c "^packs-record\.$OMC_ACTIONUI_WINDOW_UUID\.json$")"
omc_run aichat.packs.record.close
check "  and none after the window closed" "0" "$(/bin/ls "$RUN" | /usr/bin/grep -c "^packs-record\.$OMC_ACTIONUI_WINDOW_UUID")"

section "recording on top of packs"
V_base="$(cad_lib_var record_base_view $LIB)"
/bin/mkdir -p "$USER_PACKS"
printf '{"formatVersion": 1, "id": "basepack", "title": "Base pack", "read_only": ["%s"], "read_write": ["%s"]}\n' "$WORK/tools" "$WORK/cache" > "$USER_PACKS/basepack.json"
printf '{"formatVersion": 1, "id": "awaypack", "title": "Away pack", "read_only": ["%s"], "requires": ["%s/not-here"]}\n' "$WORK/tools" "$WORK" > "$USER_PACKS/awaypack.json"
scenario success 0
cad_pb_set aichatv2_packsrecord_base "basepack,awaypack,no-such-pack"
fresh_window
omc_run aichat.packs.record.init
check "the switch names the usable packs handed over, and is on" "Start with the packs ticked in Choose Packs: Base pack|true|1" \
    "$(ui_prop "$V_base" title)|$(ui_value "$V_base")|$(ui_enabled "$V_base")"
check "  and the handover is taken"  "" "$(cad_pb_get aichatv2_packsrecord_base)"
omc_control "$V_base" true
record "make all"
check "the recording is given what the pack holds" "1|1" \
    "$(/usr/bin/grep -A1 -x -- '--allow-read' "$FAKE_DISCOVER_ARGV" | /usr/bin/grep -c -x "$WORK/tools")|$(/usr/bin/grep -A1 -x -- '--allow-write' "$FAKE_DISCOVER_ARGV" | /usr/bin/grep -c -x "$WORK/cache")"
check "  and that is left out of what is found" "0|0" "$(ui_rows "$V_table" | /usr/bin/grep -c -F 'settings.conf')|$(ui_rows "$V_table" | /usr/bin/grep -c -F "$SHOWN/cache")"
check "  what the pack does not hold is still found" "1" "$(ui_rows "$V_table" | /usr/bin/grep -c -F '~/dev/tools')"
alerts_reset
omc_control "$V_title" "On top"
omc_control "$V_id" ""
omc_control "$V_description" ""
omc_run aichat.packs.record.save
check "the saved pack names the pack it was recorded on top of" "basepack" "$(/usr/bin/jq -r '.uses | join(" ")' "$USER_PACKS/on-top.json")"
check "  and does not repeat its folders"                       "0" "$(/usr/bin/grep -c -F '/tools/settings.conf' "$USER_PACKS/on-top.json")"
check "  and the application reads it as usable"                "ok" \
    "$("$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3" -B "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/sandbox_packs.py" check "$USER_PACKS/on-top.json" | /usr/bin/jq -r .state)"

# Saved under the base pack's own id, the new pack would replace it with only what was found
# beyond it.
fresh_window
cad_pb_set aichatv2_packsrecord_base "basepack"
omc_run aichat.packs.record.init
omc_control "$V_base" true
record "make all"
alerts_reset
alert_answers_reset
alert_answer 0
omc_control "$V_title" "Base pack"
omc_control "$V_id" "basepack"
omc_control "$V_description" ""
omc_run aichat.packs.record.save
check "the id of a pack it was recorded on top of is refused" "1|0" "$(alerts_mention 'on top of the pack with this id')|$(alerts_mention 'Replace the pack')"
check "  and that pack keeps its folders" "$WORK/tools" "$(/usr/bin/jq -r '.read_only | join(" ")' "$USER_PACKS/basepack.json")"
alert_answers_reset
omc_run aichat.packs.record.close

# The recorder reports the folders it was given with the ones it found. A base pack's folder
# inside an application is not a need for the whole application.
printf '{"formatVersion": 1, "id": "binpack", "title": "Bin pack", "read_only": ["%s"]}\n' "$WORK/Tool.app/Contents/bin" > "$USER_PACKS/binpack.json"
/usr/bin/jq -n --arg work "$WORK" '{ exit: 0, events: [ { event: "done", passes: 1, exit: 0, stopped: "success",
    read_write: [], read_only: [($work + "/Tool.app/Contents/bin"), ($work + "/tools")], folder_only: [], unverified: [], hinted: [] } ] }' > "$FAKE_DISCOVER_SCENARIO"
fresh_window
cad_pb_set aichatv2_packsrecord_base "binpack"
omc_run aichat.packs.record.init
omc_control "$V_base" true
record "make all"
check "a base pack's folder inside an application makes no row for the application" "0|1" \
    "$(ui_rows "$V_table" | /usr/bin/grep -c -F 'Tool.app')|$(ui_rows "$V_table" | /usr/bin/grep -c -F "$SHOWN/tools")"
omc_run aichat.packs.record.close
/bin/rm -f "$USER_PACKS/binpack.json"
scenario success 0

fresh_window
cad_pb_set aichatv2_packsrecord_base "basepack"
omc_run aichat.packs.record.init
omc_control "$V_base" false
record "make all"
check "with the switch off the recording starts without the pack" "0|1" \
    "$(/usr/bin/grep -A1 -x -- '--allow-read' "$FAKE_DISCOVER_ARGV" | /usr/bin/grep -c -x "$WORK/tools")|$(ui_rows "$V_table" | /usr/bin/grep -c -F 'settings.conf')"

fresh_window
cad_pb_set aichatv2_packsrecord_base "awaypack"
omc_run aichat.packs.record.init
check "with no usable pack handed over the switch is off and cannot be turned on" "None of the packs ticked in Choose Packs can be used on this Mac|false|0" \
    "$(ui_prop "$V_base" title)|$(ui_value "$V_base")|$(ui_enabled "$V_base")"
fresh_window
cad_pb_set aichatv2_packsrecord_base ""
omc_run aichat.packs.record.init
check "  and with none ticked it says that" "No pack was ticked in Choose Packs to start with|false|0" \
    "$(ui_prop "$V_base" title)|$(ui_value "$V_base")|$(ui_enabled "$V_base")"
omc_run aichat.packs.record.close

section "Record a Pack... in the Choose Packs sheet"
omc_control_defaults aichat.mcp.servers
ui_reset
cad_journal_reset
chains_reset
omc_run aichat.mcp.servers.packs
PACKS_TABLE_ID="$(cad_lib_var mcp_packs_table_view aichat.mcp.servers.library.sh)"
omc_trigger "$PACKS_TABLE_ID" "" "$(ui_rows "$PACKS_TABLE_ID" | /usr/bin/awk -F'\t' '$3 == "basepack" { print NR - 1 }')"
omc_run aichat.mcp.servers.packs.toggle
omc_run aichat.mcp.servers.packs.record
# The sheet's ticks start from the stored packs (the two saved above), so those go along too.
check "the packs ticked in the sheet go with it: the stored ones and the one just ticked, which is not stored" "my-build-tools,on-top,basepack|" \
    "$(cad_pb_get aichatv2_packsrecord_base)|$(cad_call mcp_prefs_array_list servers/local/packs | /usr/bin/grep -x basepack)"
cad_pb_set aichatv2_packsrecord_base ""
check "the sheet goes"                   "1" "$(cad_has "$(cad_journal omc_window)" 'omc_dismiss_modal')"
check "the Record a Pack window is asked for" "1" "$(chain_asked aichat.packs.record)"
check "  and told which window to refresh" "$OMC_ACTIONUI_WINDOW_UUID" "$(cad_pb_get aichatv2_packsrecord_parent)"
cad_pb_set aichatv2_packsrecord_parent ""

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"

/bin/rm -rf "$USER_PACKS"
omctest_end

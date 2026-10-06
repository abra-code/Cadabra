#!/bin/sh
# Tests/71-sandbox-packs-sheet.test.sh - sandbox packs in Agentic Session Tools: the Choose Packs
# sheet (a checkbox for each pack beside a preview of what the selected one holds, the ticks a
# draft until Use These Packs), and the two tables of granted folders, which say where each
# folder comes from and keep a pack's folders out of reach of the - buttons.
#
# The packs asserted on are user packs written here: what a seed pack grants depends on the Mac
# (whether Xcode or Homebrew is installed).
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.mcp.servers.library.sh
RW_TABLE_ID="$(cad_lib_var mcp_rw_table_view $LIB)"
RO_TABLE_ID="$(cad_lib_var mcp_ro_table_view $LIB)"
SUMMARY_ID="$(cad_lib_var mcp_packs_summary_view $LIB)"
PACKS_TABLE_ID="$(cad_lib_var mcp_packs_table_view $LIB)"
PREVIEW_ID="$(cad_lib_var mcp_packs_preview_view $LIB)"
for id in "$RW_TABLE_ID" "$RO_TABLE_ID" "$SUMMARY_ID" "$PACKS_TABLE_ID" "$PREVIEW_ID"; do
    if [ -z "$id" ]; then
        printf '%s: a view id was not found in the servers library\n' "$0" >&2
        exit 1
    fi
done
RW_REMOVE_BTN_ID=322
RO_REMOVE_BTN_ID=332

SUPPORT="$HOME/Library/Application Support/Cadabra"
USER_PACKS="$SUPPORT/SandboxPacks"
RUN="$SUPPORT/Run"
WORK="$(cd "$OMCTEST_WORK" && pwd -P)/packs-sheet"
/bin/rm -rf "$WORK" "$USER_PACKS"
/bin/mkdir -p "$WORK/tools" "$WORK/cache" "$WORK/mine" "$USER_PACKS"
printf 'settings\n' > "$WORK/tools/settings.conf"

cat_pack() {
    printf '{"formatVersion": 1, "id": "%s", %s}\n' "$1" "$2" > "$USER_PACKS/$1.json"
}
cat_pack work "\"title\": \"Work tools\", \"description\": \"Tools for *work*.\", \"read_only\": [\"$WORK/tools\", \"$WORK/absent\"], \"read_write\": [\"$WORK/cache\"], \"read_only_files\": [\"$WORK/tools/settings.conf\"], \"notes\": [\"Covers no network.\"]"
# A file whose name would add a ticked row to the sheet's table, were it shown as it is.
printf '{}\n' > "$USER_PACKS/$(printf 'odd\tname\ncheckmark.square.fill\tFake\tfake').json"
cat_pack away "\"title\": \"Away tools\", \"read_only\": [\"$WORK/tools\"], \"requires\": [\"$WORK/not-here\"]"

fresh_window() {
    omc_control_defaults aichat.mcp.servers
    ui_reset
    cad_journal_reset
}
# row_of <pack id>  ->  the 0-based row of that pack in the sheet's table.
row_of() {
    ui_rows "$PACKS_TABLE_ID" | /usr/bin/awk -F'\t' -v id="$1" '$3 == id { print NR - 1 }'
}
# image_of <pack id>  ->  its checkbox image.
image_of() {
    ui_rows "$PACKS_TABLE_ID" | /usr/bin/awk -F'\t' -v id="$1" '$3 == id { print $1 }'
}
# click <pack id>  ->  the checkbox of that pack is clicked.
click() {
    omc_trigger "$PACKS_TABLE_ID" "" "$(row_of "$1")"
    omc_run aichat.mcp.servers.packs.toggle
}
stored() {
    cad_call mcp_prefs_array_list servers/local/packs | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//'
}
sheet_files() {
    /bin/ls "$RUN" 2>/dev/null | /usr/bin/grep -c "^tools-packs\.$OMC_ACTIONUI_WINDOW_UUID\."
}

section "opening Choose Packs"
cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1
fresh_window
omc_run aichat.mcp.servers.packs
check_status "the handler ran" 0
check "the sheet is presented" "1" "$(cad_has "$(cad_journal omc_window)" 'omc_present_modal aichat.mcp.servers.packs')"
check "the seed packs and the user's own are listed" "1|1|1" \
    "$([ -n "$(row_of xcode)" ] && echo 1 || echo 0)|$([ -n "$(row_of work)" ] && echo 1 || echo 0)|$([ -n "$(row_of away)" ] && echo 1 || echo 0)"
check "a usable pack starts unticked, with its title" "square	Work tools	work" "$(ui_rows "$PACKS_TABLE_ID" | /usr/bin/grep '	work$')"
check "a pack that is not installed says so"          "minus.square	Away tools (not installed)	away" "$(ui_rows "$PACKS_TABLE_ID" | /usr/bin/grep '	away$')"
check "a file name with a tab and a line end is one row, not two" "0|1" \
    "$(ui_rows "$PACKS_TABLE_ID" | /usr/bin/grep -c '	fake$')|$(ui_rows "$PACKS_TABLE_ID" | /usr/bin/grep -c '^minus.square	odd name ')"
check "the first pack is selected"   "0" "$(ui_selection "$PACKS_TABLE_ID")"
check "  and previewed, so the preview is not empty" "1" "$(cad_has "$(ui_value "$PREVIEW_ID")" '## ')"
check "the sheet keeps two files while it is up" "2" "$(sheet_files)"

section "selecting a pack previews what it holds"
omc_table_cell "$PACKS_TABLE_ID" 3 work
omc_run aichat.mcp.servers.packs.selection.changed
preview="$(ui_value "$PREVIEW_ID")"
check "its title and description, not read as Markdown" "1|1" "$(cad_has "$preview" '## Work tools')|$(cad_has "$preview" 'Tools for \*work\*.')"
check "the folders to read and change" "1" "$(cad_has "$preview" "- \`$WORK/cache\`")"
check "the folders to read"            "1" "$(cad_has "$preview" "- \`$WORK/tools\`")"
check "the single files"               "1" "$(cad_has "$preview" "- \`$WORK/tools/settings.conf\`")"
check "what is left out here, and why" "1" "$(cad_has "$preview" "- \`$WORK/absent\` (not on this Mac)")"
check "its notes"                      "1" "$(cad_has "$preview" '- Covers no network.')"
check "nothing is ticked by looking"   "square" "$(image_of work)"
omc_table_cell "$PACKS_TABLE_ID" 3 away
omc_run aichat.mcp.servers.packs.selection.changed
check "a pack that is not installed says what is missing" "1" "$(cad_has "$(ui_value "$PREVIEW_ID")" "**Not installed on this Mac:** $WORK/not-here is not on this Mac")"

section "ticking is a draft until Use These Packs"
click work
check_status "the checkbox handler ran" 0
check "the pack shows ticked"           "checkmark.square.fill" "$(image_of work)"
check "  its row is selected"           "$(row_of work)" "$(ui_selection "$PACKS_TABLE_ID")"
check "  and it is the one previewed"   "1" "$(cad_has "$(ui_value "$PREVIEW_ID")" '## Work tools')"
check "nothing is stored yet"           "" "$(stored)"
check "  and the pane's tables are untouched" "0|0" "$(cad_writes "$RW_TABLE_ID")|$(cad_writes "$RO_TABLE_ID")"
click work
check "a second click unticks it"       "square" "$(image_of work)"
click away
check "a pack that is not installed cannot be ticked" "minus.square" "$(image_of away)"
check "  but is previewed, to say why"  "1" "$(cad_has "$(ui_value "$PREVIEW_ID")" '## Away tools')"
omc_trigger "$PACKS_TABLE_ID" "" "not a row"
omc_run aichat.mcp.servers.packs.toggle
check_status "a click with no row is ignored" 0
omc_trigger "$PACKS_TABLE_ID" "" "99"
omc_run aichat.mcp.servers.packs.toggle
check "  and so is a row past the end"  "square" "$(image_of work)"

section "Cancel keeps what was stored"
click work
cad_journal_reset
omc_run aichat.mcp.servers.packs.cancel
check "the sheet goes"                  "1" "$(cad_has "$(cad_journal omc_window)" 'omc_dismiss_modal')"
check "nothing is stored"               "" "$(stored)"
check "the draft is forgotten"          "0" "$(sheet_files)"
check "the pane's tables are untouched" "0|0" "$(cad_writes "$RW_TABLE_ID")|$(cad_writes "$RO_TABLE_ID")"
omc_run aichat.mcp.servers.packs
check "  and the next sheet starts from the stored packs" "square" "$(image_of work)"

section "Use These Packs stores the ticks and shows the folders"
cad_call mcp_prefs_array_append servers/local/allowed-write "$WORK/mine" >/dev/null 2>&1
cad_call mcp_prefs_array_append servers/local/allowed-read "$WORK/tools" >/dev/null 2>&1
# Shown as stored: the - button removes the entry whose text is the row's.
/bin/mkdir -p "$WORK/two  spaces"
cad_call mcp_prefs_array_append servers/local/allowed-write "$WORK/two  spaces" >/dev/null 2>&1
click work
cad_journal_reset
omc_run aichat.mcp.servers.packs.use
check_status "the handler ran" 0
check "the pack is stored"              "work" "$(stored)"
check "the sheet goes"                  "1" "$(cad_has "$(cad_journal omc_window)" 'omc_dismiss_modal')"
check "  and its files with it"         "0" "$(sheet_files)"
check "the line names the pack"         "Sandbox packs: Work tools" "$(ui_value "$SUMMARY_ID")"
check "the user's own folder says You"  "$WORK/mine	You	user" "$(ui_rows "$RW_TABLE_ID" | /usr/bin/grep "^$WORK/mine	")"
check "  with its spaces as stored"      "$WORK/two  spaces	You	user" "$(ui_rows "$RW_TABLE_ID" | /usr/bin/grep "^$WORK/two ")"
check "the pack's read-write folder names the pack" "$WORK/cache	Work tools	pack" "$(ui_rows "$RW_TABLE_ID" | /usr/bin/grep "^$WORK/cache	")"
check "a folder of both is one row, still the user's" "$WORK/tools	You, Work tools	user" "$(ui_rows "$RO_TABLE_ID" | /usr/bin/grep "^$WORK/tools	")"
check "the pack's single file is a read-only row" "$WORK/tools/settings.conf	Work tools	pack" "$(ui_rows "$RO_TABLE_ID" | /usr/bin/grep "^$WORK/tools/settings.conf	")"
check "the - buttons are off, with nothing selected" "0|0" "$(ui_enabled "$RW_REMOVE_BTN_ID")|$(ui_enabled "$RO_REMOVE_BTN_ID")"

section "the next sheet shows the stored ticks"
fresh_window
omc_run aichat.mcp.servers.packs
check "the stored pack is ticked" "checkmark.square.fill" "$(image_of work)"
omc_run aichat.mcp.servers.packs.cancel

section "a pack's folder is not removed with the - button"
fresh_window
omc_table_cell "$RW_TABLE_ID" 1 "$WORK/cache"
omc_table_cell "$RW_TABLE_ID" 3 pack
omc_run aichat.mcp.servers.rw.selection.changed
check "selecting it leaves - off"       "0" "$(ui_enabled "$RW_REMOVE_BTN_ID")"
omc_run aichat.mcp.servers.rw.remove
check "  and removing does nothing"     "0" "$(cad_writes "$RW_TABLE_ID")"
omc_table_cell "$RW_TABLE_ID" 1 "$WORK/mine"
omc_table_cell "$RW_TABLE_ID" 3 user
omc_run aichat.mcp.servers.rw.selection.changed
check "the user's own folder turns - on" "1" "$(ui_enabled "$RW_REMOVE_BTN_ID")"
omc_table_cell "$RO_TABLE_ID" 1 "$WORK/tools/settings.conf"
omc_table_cell "$RO_TABLE_ID" 3 pack
omc_run aichat.mcp.servers.ro.selection.changed
check "the read-only table does the same" "0" "$(ui_enabled "$RO_REMOVE_BTN_ID")"
omc_run aichat.mcp.servers.ro.remove
check "  and removes nothing"           "0" "$(cad_writes "$RO_TABLE_ID")"
omc_table_cell "$RO_TABLE_ID" 1 "$WORK/tools"
omc_table_cell "$RO_TABLE_ID" 3 user
omc_run aichat.mcp.servers.ro.remove
check "removing a folder of both leaves the pack's row" "$WORK/tools	Work tools	pack" "$(ui_rows "$RO_TABLE_ID" | /usr/bin/grep "^$WORK/tools	")"
omc_table_cell "$RW_TABLE_ID" 1 ""
omc_table_cell "$RW_TABLE_ID" 3 ""
omc_table_cell "$RO_TABLE_ID" 1 ""
omc_table_cell "$RO_TABLE_ID" 3 ""

section "unticking a pack takes its folders out"
fresh_window
omc_run aichat.mcp.servers.packs
click work
omc_run aichat.mcp.servers.packs.use
check "nothing is stored"               "" "$(stored)"
check "the line says None"              "Sandbox packs: None" "$(ui_value "$SUMMARY_ID")"
check "the pack's folder is gone"       "" "$(ui_rows "$RW_TABLE_ID" | /usr/bin/grep "^$WORK/cache	")"
check "  the user's own stays"          "$WORK/mine	You	user" "$(ui_rows "$RW_TABLE_ID" | /usr/bin/grep "^$WORK/mine	")"

section "a ticked pack that cannot be used is named as such"
"$OMC_OMC_SUPPORT_PATH/plister" insert packs array "$cad_settings" /servers/local >/dev/null 2>&1
"$OMC_OMC_SUPPORT_PATH/plister" append string away "$cad_settings" /servers/local/packs
"$OMC_OMC_SUPPORT_PATH/plister" append string gone "$cad_settings" /servers/local/packs
fresh_window
cad_call mcp_refresh_granted "$OMC_ACTIONUI_WINDOW_UUID"
check "in the pane's line" "Sandbox packs: Away tools (not installed), gone (missing)" "$(ui_value "$SUMMARY_ID")"
check "  and it grants nothing" "0" "$(ui_rows "$RO_TABLE_ID" | /usr/bin/grep -c '	pack$')"
omc_run aichat.mcp.servers.packs
check "it shows ticked in the sheet" "checkmark.square.fill" "$(image_of away)"
click away
check "  and can be unticked"        "minus.square" "$(image_of away)"
omc_run aichat.mcp.servers.packs.use
check "a tick with no pack is dropped when the packs are stored" "" "$(stored)"

section "Reset to Defaults unticks every pack"
fresh_window
omc_run aichat.mcp.servers.packs
click work
omc_run aichat.mcp.servers.packs.use
check "a pack is stored first" "work" "$(stored)"
fresh_window
omc_run aichat.mcp.servers.reset
check "none is stored after"   "" "$(stored)"
check "  and the line says so" "Sandbox packs: None" "$(ui_value "$SUMMARY_ID")"

section "closing Agentic Session Tools with the sheet up forgets the draft"
fresh_window
omc_run aichat.mcp.servers.packs
check "the sheet's files are there" "2" "$(sheet_files)"
omc_run aichat.mcp.servers.cancel
check "  and gone with the window"  "0" "$(sheet_files)"

section "Use These Packs with no sheet does nothing"
fresh_window
omc_run aichat.mcp.servers.packs.use
check_status "the handler exits cleanly" 0
check "nothing is written to the window" "0" "$(cad_writes omc_window)"

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"

/bin/rm -rf "$USER_PACKS"
omctest_end

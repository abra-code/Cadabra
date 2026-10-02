#!/bin/bash
# aichat.select.external.agent.library.sh
# View ids and the shared pane painting for the External ACP Agent dialog.
#
# WHY THIS EXISTS: the dialog now has six handlers - init, selection changed, +, -, the rename,
# and OK - and they all address the same views by numeric id. Each one used to carry its own
# copy of those numbers. That is fine until a view moves, at which point one script keeps
# writing to the id the view used to have and fails SILENTLY: omc_dialog_control has no view to
# talk to, says nothing, and the pane simply stops updating. The hidden table columns make it
# worse, since a shifted column index means a handler reads the wrong VALUE rather than none.
#
# So the ids live here once, under the names the handlers already used.

[ -n "${__AICHAT_EXT_AGENT_LIB:-}" ] && return 0
__AICHAT_EXT_AGENT_LIB=1

source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.acp.agents.library.sh"
source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agentvm.library.sh"

OK_BUTTON_ID=3
TABLE_ID=10
INFO_TEXT_ID=12
ADD_BUTTON_ID=14
REMOVE_BUTTON_ID=15
COMMAND_FIELD_ID=20
RESULT_TEXT_ID=24
USE_TOOLS_PICKER_ID=30
# Where the agent runs (this Mac or an agent-vm box) and, in a box, how much it asks. The row is
# shown only where boxes can be used.
BOX_ROW_ID=31
RUN_IN_PICKER_ID=32
LEVEL_PICKER_ID=34
# Keys...: the Keys window for the agent, shown in a box when the catalog names keys or a login.
KEYS_BUTTON_ID=36
# The ZStack and its two children. Exactly one child is ever visible: they overlap, so showing
# both draws the editor on top of the About text.
ABOUT_PANE_ID=51
CUSTOM_PANE_ID=52
NAME_FIELD_ID=53
CUSTOM_TEXT_ID=54
# A hidden, zero-sized Text carrying the id of the agent the detail pane is currently showing.
# See the pane-owner note below - it is state, not decoration, and it is the identity every
# edit in this dialog acts on.
PANE_OWNER_ID=55

dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

# THE PANE OWNER: which agent the detail pane belongs to.
#
# The obvious answer is "whatever row is selected", and that is what these handlers used to ask.
# It is wrong, and the reason is worth writing down because nothing about it is visible in this
# file.
#
# Every handler runs as a separate process with a SNAPSHOT of the dialog's values, taken when
# the command was dispatched. Two handlers can be in flight at once: OMC runs a nested run loop
# while a script executes, so a second action dispatches and runs while the first is still
# going. The Name field commits on losing focus, so the commonest way to finish a rename is to
# CLICK ANOTHER ROW - which fires the rename AND a selection change, in an order neither script
# can observe.
#
# The table selection is therefore not stable across a handler's own lifetime. A rename whose
# snapshot was taken a moment too late reads the row the user just clicked and renames THAT
# record - the typed name lands on somebody else's agent. Silent, and a plausible-looking wrong
# answer rather than an error.
#
# So the pane carries its own identity. It is written only by the code that paints the pane,
# CLEARED FIRST and set LAST, which is what makes a snapshot trustworthy: a handler that sees a
# non-empty owner knows the fields beside it were painted for that owner and finished. A handler
# that catches a paint mid-flight sees an empty owner and declines to write anything, which
# costs one keystroke's worth of typing and never costs a record.
agent_pane_begin() {
    "$dialog_tool" "$window_uuid" $PANE_OWNER_ID ""
}

agent_pane_commit() {
    "$dialog_tool" "$window_uuid" $PANE_OWNER_ID "$1"
}

# Read from the snapshot, never live: it has to agree with the field values this same handler
# was handed. Empty means "no agent" or "a repaint is in flight" - both are "do not write".
#
# The 55 in the variable name is PANE_OWNER_ID spelled out, because the environment names the
# view rather than taking a number - so the two move together or this reads an id that is never
# written, which looks exactly like "a repaint is in flight" and quietly disables every edit.
agent_pane_owner() {
    printf '%s\n' "${OMC_ACTIONUI_VIEW_55_VALUE:-}"
}

# agent_save_pane_edits <owner-id> <typed-name> <typed-command>
#   0 = saved and read back, or there was nothing to save (not a saved agent)
#   1 = no record behind this id - it was deleted out from under this window
#   2 = a write went missing; the record does not hold what was just written
#
# WHY A BUTTON HAS TO DO THIS AT ALL. The two fields commit on focus loss, which covers every
# way of leaving them EXCEPT pressing a button: on macOS an AppKit button does not normally take
# key focus when clicked, so the field never blurs and its handler never runs. Anything the user
# typed and then immediately clicked a button about would be dropped without a sound. So every
# button that acts on the editor saves it first, from its OWN snapshot - which is the same
# snapshot it is about to act on, so the two cannot disagree.
#
# Idempotent by construction: when the blur DOES fire, it and the button write the same values
# from the same snapshot. Both fields are cleaned exactly as the OK handler cleans them, so the
# record holds the same bytes whichever path saved it.
#
# An empty name is skipped rather than stored, matching the rename's refusal - a record keeps
# the name it has. An empty COMMAND is written, because "nothing typed in yet" is a real state.
agent_save_pane_edits() {
    local id="$1" name cmd
    case "$id" in
        custom:*) ;;
        *) return 0 ;;
    esac
    name=$(acp_clean_one_line "$2")
    cmd=$(acp_clean_one_line "$3")

    # "Is there a record?" is asked DIRECTLY, not inferred from a failed write. acp_custom_set
    # returns the same non-zero for a missing record and for a settings file it could not write,
    # and the two need opposite answers: a missing record means "store this as an unnamed
    # command", while an unwritable file means "stop and tell the user". Inferring one from the
    # other made an unwritable settings file silently throw away the name of a perfectly good
    # saved agent. Measured, not assumed: plister does report THIS failure non-zero, unlike the
    # exits-0-having-written-nothing case the read-backs below exist for.
    acp_custom_index "$id" >/dev/null 2>&1 || return 1

    # Both writes are proven by reading them back, and the exit status is deliberately ignored:
    # plister reports SOME failed writes by exiting 0 having written nothing, so the status is
    # necessary but not sufficient and the read-back is the only thing that settles it.
    acp_custom_set "$id" command "$cmd" >/dev/null 2>&1
    [ "$(acp_custom_get "$id" command)" = "$cmd" ] || return 2

    if [ -n "$name" ]; then
        acp_custom_set "$id" label "$name" >/dev/null 2>&1
        # Checked separately, and not merely for symmetry: when the command is UNCHANGED its
        # read-back passes without proving anything was writable, so a rename-only edit would
        # sail through the check above on a settings file that cannot be written at all.
        [ "$(acp_custom_get "$id" label)" = "$name" ] || return 2
    fi
    return 0
}

# Hide before show, in both directions, so the two panes are never both visible - not even for
# the frame between the two calls.
agent_show_about_pane() {
    "$dialog_tool" "$window_uuid" $CUSTOM_PANE_ID omc_hide
    "$dialog_tool" "$window_uuid" $ABOUT_PANE_ID omc_show
}

agent_show_custom_pane() {
    "$dialog_tool" "$window_uuid" $ABOUT_PANE_ID omc_hide
    "$dialog_tool" "$window_uuid" $CUSTOM_PANE_ID omc_show
}

# agent_paint_custom_pane <custom-id> - fill the editor from the saved record
#
# The name field and the command field both come from the RECORD, not from the table row, so
# this says the same thing whether it was reached by clicking a row, pressing +, or renaming.
# The prose underneath is catalog data - see acp_agent_custom_template.
#
# EVERYTHING SLOW HAPPENS BEFORE THE PANE IS CLAIMED, and that ordering is load-bearing rather
# than tidy. Two of these can be running at once - click one row and then another quickly, and
# the second selection handler starts while the first is still going - and the clear-first,
# sign-last protocol only proves anything while ONE painter is inside its bracket. Two
# overlapping brackets can interleave their writes and leave one agent's command sitting in
# another agent's signed editor, which the next commit would then believe.
#
# Nothing here can make that impossible without a compare-and-set verb in omc_dialog_control.
# What it can do is make the window small: the record reads and the catalog's python call happen
# up front, so the claimed span is the three writes below rather than everything above them too.
agent_paint_custom_pane() {
    local id="$1" label cmd t_label t_url t_summary t_note info
    label=$(acp_custom_get "$id" label)
    cmd=$(acp_custom_get "$id" command)
    IFS='	' read -r t_label t_url t_summary t_note <<EOF
$(acp_agent_custom_template)
EOF
    info=""
    [ -n "$t_summary" ] && [ "$t_summary" != "-" ] && info="$t_summary"
    [ -n "$t_note" ] && [ "$t_note" != "-" ] && info="${info}

${t_note}"
    # Markdown links survive this pane: the renderer flattens block structure, but a link is an
    # inline attribute and comes through clickable. This is the registry the old Custom row
    # linked to - the right thing to offer someone about to type a command from memory.
    [ -n "$t_url" ] && [ "$t_url" != "-" ] && info="${info}

[Browse the ACP agent registry](${t_url})"
    # Piped through acp_md_paragraphs because a bare blank line is a paragraph break this
    # renderer parses and then discards, gluing the paragraphs together. Rendered BEFORE the
    # claim below, for the reason in the header: nothing slow belongs inside the bracket.
    info=$(printf '%s' "$info" | acp_md_paragraphs)

    # From here down is the claimed span. The caller signs it once it has finished its own
    # writes - showing the pane, setting the buttons - so the owner appears last, as promised.
    agent_pane_begin
    "$dialog_tool" "$window_uuid" $CUSTOM_TEXT_ID markdown "$info"
    "$dialog_tool" "$window_uuid" $NAME_FIELD_ID "$label"
    "$dialog_tool" "$window_uuid" $COMMAND_FIELD_ID "$cmd"
}

# agent_sync_remove_button <selected-id> - only a saved agent can be removed
#
# A built-in row is not the user's to delete, and no selection at all has nothing to delete, so
# both leave the button dead. It starts disabled in the JSON, which is the state the dialog
# opens in whenever the remembered selection is not a saved agent.
agent_sync_remove_button() {
    case "$1" in
        custom:*) "$dialog_tool" "$window_uuid" $REMOVE_BUTTON_ID omc_enable ;;
        *)        "$dialog_tool" "$window_uuid" $REMOVE_BUTTON_ID omc_disable ;;
    esac
}

# agent_refresh_list <table-id> <id-to-keep-highlighted>
#
# Rebuild the rows from the records and put the highlight back on <id>. The re-select is not
# optional and not defensive: a row's FIRST column is its display name, and the framework keeps
# a selection across a repaint only while the selected row's first column is unchanged. Renaming
# changes exactly that column, so the highlight goes out from under the row being renamed unless
# it is restored here by index.
#
# A vanished id leaves the selection alone rather than forcing it somewhere. The caller that
# wants a definite answer for a row that may be gone is agent_restore_configured_view, which
# deselects explicitly.
agent_refresh_list() {
    local table_id="$1" keep_id="$2" row
    row=$(acp_agent_fill_table "$table_id" "$keep_id")
    [ "$row" -ge 0 ] && "$dialog_tool" "$window_uuid" "$table_id" omc_select_row "$row"
    return 0
}

# agent_paint_default_about - the About text for "here is what you have configured"
#
# Not tied to a selected row: it describes the STORED setup, which is what the pane should say
# when the dialog opens and when a list edit leaves no meaningful row selected.
agent_paint_default_about() {
    local stored_command shown_command info
    stored_command=$(acp_agent_stored_command)
    if [ -n "$stored_command" ]; then
        # Backticks neutralized for the code span only. The FIELD gets the command unaltered -
        # that is what will be run - but one backtick in the displayed copy closes the span
        # early and the rest of the pane renders as garbage, in the one place whose job is
        # showing the user exactly what is configured.
        shown_command=$(printf '%s' "$stored_command" | /usr/bin/tr '`' "'")
        info="**Currently configured:** \`${shown_command}\`

Select a row to change it, or press **Test** to check this one."
    else
        info="Cadabra normally talks to its own bundled agent. Pick a different local ACP agent here to use it instead - it brings its own model and its own credentials.

Select one from the list to see what it needs, or press + to add an agent of your own."
    fi
    # Piped through acp_md_paragraphs because a bare blank line is a paragraph break the
    # renderer parses and then drops, gluing the two paragraphs together. Rendered before the
    # claim, so the claimed span holds writes only - see agent_paint_custom_pane's header.
    info=$(printf '%s' "$info" | acp_md_paragraphs)
    agent_pane_begin
    "$dialog_tool" "$window_uuid" $INFO_TEXT_ID markdown "$info"
}

# agent_restore_configured_view <table-id> - repaint the whole dialog to describe what is stored
#
# This is the dialog's resting state, and it is needed twice: when it opens, and after the -
# button has changed the list out from under whatever was selected. Both want the same answer -
# show the configured agent - and writing it twice is how the two would drift.
#
# Re-selecting the configured row also matters for a reason that is not cosmetic: OK is enabled
# only by the selection-changed handler, so a dialog that repaints with nothing selected leaves
# a perfectly good stored setup uncommittable until the user clicks something.
# IT SETS EVERY PIECE OF STATE IT OWNS, INCLUDING THE EMPTY CASES. This is the whole point: it
# runs after the list has changed under whatever was selected, so anything it leaves alone keeps
# the value the PREVIOUS selection put there. Deleting the row you just typed a command into
# used to leave that command sitting in the field and OK still live, under a pane saying nothing
# was configured - press the button and it stored the command belonging to the row you deleted.
# So the field is always written, OK is always enabled or disabled, and the selection is either
# set or explicitly cleared.
agent_restore_configured_view() {
    local table_id="$1" stored_id stored_command stored_row selected_id
    # The claim is NOT taken here. The two painters below take it themselves, after their own
    # slow work, so the span between claiming and signing holds pane writes and nothing else -
    # the reasoning is in agent_paint_custom_pane's header. The table rebuild, the selection and
    # the buttons are all outside it on purpose: none of them carries the pane's identity, so a
    # late-landing write to any of them costs a highlight, never a record.
    stored_id=$(acp_agent_stored_id)
    stored_command=$(acp_agent_stored_command)
    stored_row=$(acp_agent_fill_table "$table_id" "$stored_id")
    if [ "$stored_row" -ge 0 ]; then
        "$dialog_tool" "$window_uuid" "$table_id" omc_select_row "$stored_row"
        selected_id="$stored_id"
    else
        # No row for what is stored: an ad-hoc command typed over a built-in row and committed,
        # a saved agent removed since, or a stored id whose record is gone. The repaint may have
        # PRESERVED a selection - it keeps one whose row survived - so say explicitly that
        # nothing is selected rather than leaving a highlight the panes do not describe.
        "$dialog_tool" "$window_uuid" "$table_id" omc_deselect
        selected_id=""
    fi

    # OK follows the command, not the selection: with a command in the field there is something
    # to commit even when no row is highlighted, and with none there is not.
    if [ -n "$stored_command" ]; then
        "$dialog_tool" "$window_uuid" $OK_BUTTON_ID omc_enable
    else
        "$dialog_tool" "$window_uuid" $OK_BUTTON_ID omc_disable
    fi

    # The minus button follows the SELECTION, not the stored id. Keying it off the stored id
    # armed it for a saved agent whose record no longer exists - a live button with no row
    # selected - and put the editor on screen for an agent that was not there, with a blank name
    # field that quietly discarded anything typed into it.
    agent_sync_remove_button "$selected_id"

    # The command field is written INSIDE whichever painter runs, never before it, so it cannot
    # land in a pane somebody else has since signed. It always reflects the stored command,
    # empty included: empty is the honest answer when nothing is configured, and it is what
    # stops a deleted row's command from being committed by a button the user reasonably
    # believes applies to what the pane is showing.
    case "$selected_id" in
        custom:*)
            agent_paint_custom_pane "$selected_id"
            # agent_paint_custom_pane fills the field from the RECORD. The record's command and
            # the live one are written together by the OK handler, so they agree; if they ever do
            # not, the LIVE one wins, because this field's contract is showing what Cadabra will
            # actually run.
            "$dialog_tool" "$window_uuid" $COMMAND_FIELD_ID "$stored_command"
            agent_show_custom_pane
            ;;
        *)
            agent_paint_default_about
            "$dialog_tool" "$window_uuid" $COMMAND_FIELD_ID "$stored_command"
            agent_show_about_pane
            ;;
    esac
    # Last, and only once everything beside it is painted.
    agent_pane_commit "$selected_id"
    return 0
}

# -- Where the agent runs ------------------------------------------------------------------
# The choice and the level are stored per agent (acp_agent_run_in, acp_agent_level) and read by
# chat init, which starts the box. The picker's tags are the stored values: "mac", "box:<name>"
# (a kept box) and "new:<image>" (a disposable box made from the image for each window).

# agent_run_in_options <stored run-in>  ->  the Runs in picker's options as JSON: This Mac, the
# kept boxes, then a disposable box from each ready image. A stored choice that is no longer on
# the list (its box or image was deleted) stays, marked "not found": showing This Mac instead
# would let Continue quietly move an agent that was set to a box onto this Mac. A stored value
# that is not a choice at all is offered as "Setting not readable" (tag "damaged"), which
# Continue refuses. Box and image names are embedded as they are: agent-vm's names are letters,
# digits, ".", "_" and "-", and a name that is not one is never embedded. A kept box is any box
# not marked disposable: agent-vm writes "disposable" only for disposable boxes, so a kept one
# reads "-" in that column, not "false".
agent_run_in_options() {
    local stored="$1"
    local boxes="$runin_boxes"
    local images="$runin_images"
    local name
    local json='[{"title":"This Mac","tag":"mac"}'
    local found=no
    if [ "$stored" = "mac" ]; then
        found=yes
    fi
    if [ -n "$boxes" ]; then
        json="$json"',{"section":"Kept AgentVM boxes"}'
        while IFS= read -r name; do
            agentvm_valid_name "$name" || continue
            json="$json"',{"title":"'"$name"'","tag":"box:'"$name"'"}'
            if [ "box:$name" = "$stored" ]; then
                found=yes
            fi
        done <<BOXES
$boxes
BOXES
    fi
    if [ -n "$images" ]; then
        json="$json"',{"section":"New disposable AgentVM box from"}'
        while IFS= read -r name; do
            agentvm_valid_name "$name" || continue
            json="$json"',{"title":"'"$name"'","tag":"new:'"$name"'"}'
            if [ "new:$name" = "$stored" ]; then
                found=yes
            fi
        done <<IMAGES
$images
IMAGES
    fi
    if [ "$found" = "no" ]; then
        name="${stored#*:}"
        local named=no
        case "$stored" in
            box:?*|new:?*)
                agentvm_valid_name "$name"
                if [ $? -eq 0 ]; then
                    named=yes
                fi ;;
        esac
        if [ "$named" = "yes" ]; then
            json="$json"',{"divider":true},{"title":"'"$name"' (not found)","tag":"'"$stored"'"}'
        else
            json="$json"',{"divider":true},{"title":"Setting not readable","tag":"damaged"}'
        fi
    fi
    printf '%s]\n' "$json"
}

# agent_apply_run_in <run-in> [yes|no keys]  ->  the rest of the window follows where the agent
# runs. In a box, the level picker shows; Use Tools stays available either way (in a box,
# Cadabra's servers are copied there and the agent starts them there). Keys... shows in a box
# when the agent has keys or a login to offer (agent_has_keys), and never on this Mac.
agent_apply_run_in() {
    case "$1" in
        ''|mac)
            "$dialog_tool" "$window_uuid" $LEVEL_PICKER_ID omc_hide
            "$dialog_tool" "$window_uuid" $KEYS_BUTTON_ID omc_hide
            "$dialog_tool" "$window_uuid" $USE_TOOLS_PICKER_ID omc_enable
            ;;
        *)
            "$dialog_tool" "$window_uuid" $LEVEL_PICKER_ID omc_show
            if [ "${2:-no}" = "yes" ]; then
                "$dialog_tool" "$window_uuid" $KEYS_BUTTON_ID omc_show
            else
                "$dialog_tool" "$window_uuid" $KEYS_BUTTON_ID omc_hide
            fi
            "$dialog_tool" "$window_uuid" $USE_TOOLS_PICKER_ID omc_enable
            ;;
    esac
}

# agent_has_keys <agent id>  ->  "yes" when the Keys window has something for the agent in a box
# (a key the catalog says it can use, or a way to log in inside one), else "no". A saved or
# edited command has no catalog entry, so "no".
agent_has_keys() {
    case "$1" in
        ''|custom|custom:*) printf 'no\n'; return 0 ;;
    esac
    local _keys="$("$acp_python" "$acp_catalog_py" box-keys "$1" 2>/dev/null)"
    if [ -n "$_keys" ]; then
        printf 'yes\n'
        return 0
    fi
    local _login="$("$acp_python" "$acp_catalog_py" box-login "$1" 2>/dev/null)"
    if [ -n "$_login" ]; then
        printf 'yes\n'
        return 0
    fi
    printf 'no\n'
}

# agent_prepare_run_in <agent id> [refresh|cached]  ->  what the Runs in row shows for this agent: its stored
# choice and level, among the boxes and images agent-vm has now, left in runin_options,
# runin_value, runin_level and runin_keys for agent_paint_run_in. Where boxes cannot be used (agentvm_available
# says why), an agent on this Mac gets an empty runin_options: the row stays hidden and the picker
# holds no value, which Continue reads as "leave the stored choice alone". An agent set to a box
# gets the row with This Mac and its stored place only, so the user can move it back to this Mac;
# kept in the box, it fails at chat start with the reason, rather than quietly running here.
#
# SPLIT FROM THE PAINT FOR THE PANE-OWNER PROTOCOL. This is the slow half - agent-vm's version,
# box list and image list, about 2.5 s together on a Mac with a few images - and the picker is a
# pane field: Continue stores its value for the pane owner. So the handlers that paint the pane
# call this BEFORE claiming it and agent_paint_run_in inside the claimed span, like every other
# pane field. Painted outside the span, a slow paint for the row clicked first could land after
# the pane was signed for the row clicked next, and Continue would store the first agent's place
# for the second - This Mac, say, for an agent set to a box.
runin_options=""
runin_value=""
runin_level="free"
runin_keys="no"
runin_boxes=""
runin_images=""

# THE PLACES ARE READ ONCE PER WINDOW. agentvm_available, box list and image list take about
# 2.5 s together (image list alone 1.9 s), and every click on a row would otherwise pay it again
# before the pane can update. So init reads them ("refresh") into a file named after the window,
# and every later handler reuses it ("cached"), reading it again only when it is missing. A box
# made or deleted in the AgentVM app meanwhile shows the next time this window opens.
#   line 1: "available" or "unavailable"; then "box<TAB>name<TAB>network mode<TAB>rules" and
#   "image<TAB>name" lines (the rules comma-joined, "-" for none; Agentic Session Tools shows a
#   kept box's network from them).
agent_places_file() {
    cadabra_run_file "runin-places.${window_uuid}"
}

# agent_load_places <refresh|cached>  ->  0 with runin_boxes (kept boxes) and runin_images (ready
# images) set, one name per line; 1 when boxes cannot be used here.
agent_load_places() {
    local file="$(agent_places_file)"
    if [ "$1" != "cached" ] || [ ! -f "$file" ]; then
        local tmp="$file.$$"
        agentvm_available >/dev/null
        local status=$?
        if [ "$status" -ne 0 ]; then
            printf 'unavailable\n' > "$tmp"
        else
            {
                printf 'available\n'
                agentvm_boxes 2>/dev/null | /usr/bin/awk -F'\t' '$12 != "true" { print "box\t" $1 "\t" $17 "\t" $18 }'
                agentvm_images 2>/dev/null | /usr/bin/awk -F'\t' '$2 == "ready" { print "image\t" $1 }'
            } > "$tmp"
            /bin/rm -f "$agentvm_err_file"
        fi
        /bin/mv -f "$tmp" "$file"
    fi
    local first="$(/usr/bin/head -n 1 "$file" 2>/dev/null)"
    if [ "$first" != "available" ]; then
        return 1
    fi
    runin_boxes="$(/usr/bin/awk -F'\t' '$1 == "box" { print $2 }' "$file")"
    runin_images="$(/usr/bin/awk -F'\t' '$1 == "image" { print $2 }' "$file")"
    return 0
}

# agent_forget_places  ->  the window's file removed, when the window closes.
agent_forget_places() {
    /bin/rm -f "$(agent_places_file)"
}

agent_prepare_run_in() {
    runin_options=""
    runin_value=""
    runin_level="free"
    runin_keys="no"
    agent_load_places "${2:-cached}"
    local status=$?
    local stored="$(acp_agent_run_in "$1")"
    # Where boxes cannot be used, the row still shows for an agent set to a box, offering This Mac
    # and its stored place only: hiding it would leave every launch of the agent refused, with no
    # way back to This Mac in this window.
    if [ "$status" -ne 0 ] && [ "$stored" = "mac" ]; then
        return 0
    fi
    if [ "$status" -ne 0 ]; then
        runin_boxes=""
        runin_images=""
    fi
    runin_value="$stored"
    case "$runin_value" in
        mac|box:?*|new:?*) ;;
        *) runin_value="damaged" ;;
    esac
    # An unreadable level selects nothing, and Continue refuses a box with no level, rather than
    # showing it as "works without asking" and storing the freest level for it.
    runin_level="$(acp_agent_level "$1")"
    case "$runin_level" in
        free|ask|plan) ;;
        *) runin_level="" ;;
    esac
    runin_options="$(agent_run_in_options "$runin_value")"
    runin_keys="$(agent_has_keys "$1")"
}

# agent_paint_run_in  ->  the Runs in row as agent_prepare_run_in left it. Writes only.
agent_paint_run_in() {
    if [ -z "$runin_options" ]; then
        "$dialog_tool" "$window_uuid" $BOX_ROW_ID omc_hide
        "$dialog_tool" "$window_uuid" $RUN_IN_PICKER_ID ""
        agent_apply_run_in mac
        return 0
    fi
    "$dialog_tool" "$window_uuid" $RUN_IN_PICKER_ID omc_set_property options "$runin_options"
    "$dialog_tool" "$window_uuid" $RUN_IN_PICKER_ID "$runin_value"
    "$dialog_tool" "$window_uuid" $LEVEL_PICKER_ID "$runin_level"
    "$dialog_tool" "$window_uuid" $BOX_ROW_ID omc_show
    agent_apply_run_in "$runin_value" "$runin_keys"
}

# agent_carry_run_in <from id> <to id>  ->  <to> takes <from>'s place to run and, in a box, its
# level; 0 once stored, 2 when <from>'s cannot be read (a damaged value, which no setter takes),
# 1 when a write did not land. For an agent that goes on under another id with no Runs in value
# to store for it - a saved agent removed while configured, or an agent committed as the bare
# "custom" where boxes cannot be used - so that it keeps the place it had instead of taking over
# whatever "custom" had, which may be this Mac.
agent_carry_run_in() {
    local run_in="$(acp_agent_run_in "$1")"
    acp_agent_set_run_in "$2" "$run_in"
    local run_in_status=$?
    if [ "$run_in_status" -ne 0 ] || [ "$run_in" = "mac" ]; then
        return "$run_in_status"
    fi
    acp_agent_set_level "$2" "$(acp_agent_level "$1")"
}

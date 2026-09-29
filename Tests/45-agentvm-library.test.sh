#!/bin/sh
# Tests/45-agentvm-library.test.sh - which agent-vm Cadabra runs, when boxes are available at
# all, and how agent-vm's answers and failures reach the rest of the applet.
#
# agent-vm itself never runs here: CADABRA_AGENT_VM points the library at fake_agent_vm.sh,
# which answers from JSON captured from a real agent-vm (Tests/fixtures/agentvm/). The
# converter, agentvm_json.py, is tested against the same fixtures directly, and its drift checks
# are what fail when a refreshed fixture lost a field the library reads.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

LIB=aichat.agentvm.library.sh
FAKE="$OMCTEST_TESTS/helpers/fake_agent_vm.sh"
FIXTURES="$OMCTEST_TESTS/fixtures/agentvm"
PY="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
CONVERT="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/agentvm_json.py"
INSTALLED="$HOME/.local/bin/agent-vm"
FAKE_AGENTVM_DIR="$OMCTEST_WORK/fakevm"
# The oldest agent-vm Cadabra accepts, as the library declares it (it is raised with every
# agent-vm version, so no expectation here names the number).
MIN_VERSION=$(/usr/bin/sed -n 's/^AGENTVM_MIN_VERSION="\(.*\)"$/\1/p' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/aichat.agentvm.library.sh")
export FAKE_AGENTVM_DIR
TAB=$(printf '\t')
# Where the library leaves agent-vm's stderr. cad_call_lib sources it in a subshell of this file,
# so its $$ is this file's pid too.
ERR_FILE="${TMPDIR:-/tmp}/cadabra-agentvm.$$.stderr"

# The developer's own environment must not decide which binary the library picks.
unset CADABRA_AGENT_VM AGENT_VM_HOME

# lib <function> [args...] - the library under test, in a subshell (cad_call_lib).
lib() { cad_call_lib "$LIB" "$@"; }

# with_fake <function> [args...] - the same, with the test seam pointing at the fake.
# A subshell, because in POSIX mode an assignment before a FUNCTION call outlives the call.
with_fake() {
    ( CADABRA_AGENT_VM="$FAKE"; export CADABRA_AGENT_VM; lib "$@" )
}

# fake_reset - a fake with no overrides and an empty log.
fake_reset() {
    /bin/rm -rf "$FAKE_AGENTVM_DIR"
    /bin/mkdir -p "$FAKE_AGENTVM_DIR"
}

# convert <command> <fixture-file>  ->  agentvm_json.py's rows for that fixture.
convert() {
    "$PY" "$CONVERT" "$1" < "$2"
}

# col <n>  ->  one tab-separated column of stdin.
col() { /usr/bin/cut -f"$1"; }

# set_developer <key> <value> - /developer/<key> in the isolated settings file.
set_developer() {
    [ -f "$cad_settings" ] || {
        /bin/mkdir -p "$(/usr/bin/dirname "$cad_settings")"
        "$cad_plister" set dict "$cad_settings" / >/dev/null 2>&1
    }
    "$cad_plister" get type "$cad_settings" /developer >/dev/null 2>&1 || \
        "$cad_plister" insert developer dict "$cad_settings" / >/dev/null 2>&1
    "$cad_plister" get type "$cad_settings" "/developer/$1" >/dev/null 2>&1 || \
        "$cad_plister" insert "$1" string "" "$cad_settings" /developer >/dev/null 2>&1
    "$cad_plister" set string "$2" "$cad_settings" "/developer/$1" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------------------
section "agentvm_json.py: the version row"
row=$(convert version "$FIXTURES/version.json")
check "version"                  "0.1.8" "$(printf '%s\n' "$row" | col 1)"
check "the guest daemon version" "0.1.8" "$(printf '%s\n' "$row" | col 3)"
check "its features, comma-joined" "terminal,prompt-notices,wallpaper" "$(printf '%s\n' "$row" | col 4)"
check "no guest error is \"-\""  "-"     "$(printf '%s\n' "$row" | col 6)"
check "exactly six fields"       "6"     "$(printf '%s\n' "$row" | /usr/bin/awk -F'\t' '{ print NF }')"

section "agentvm_json.py: the status of a running box"
row=$(convert status "$FIXTURES/box-status-running.json")
check "state"            "running"                                      "$(printf '%s\n' "$row" | col 1)"
check "the supervisor's pid" "44847"                                    "$(printf '%s\n' "$row" | col 2)"
check "its version"      "0.1.8"                                        "$(printf '%s\n' "$row" | col 3)"
check "its path"         "/Users/you/Development/agent-vm/.build/signed/release/agent-vm" "$(printf '%s\n' "$row" | col 4)"
check "the project"      "/Users/you/Development/cadabra-spike-project" "$(printf '%s\n' "$row" | col 6)"
check "read-only"        "true"                                         "$(printf '%s\n' "$row" | col 7)"
check "one program runs" "1"                                            "$(printf '%s\n' "$row" | col 8)"
check "the image, from the nested box record" "dev-agents"              "$(printf '%s\n' "$row" | col 11)"
check "no status error"  "-"                                            "$(printf '%s\n' "$row" | col 12)"
check "no owner in this capture" "-"                                    "$(printf '%s\n' "$row" | col 13)"
check "its memory, from the nested box record" "4"                     "$(printf '%s\n' "$row" | col 14)"

section "drift: every status field the library reads is in the running box's fixture"
# The check the fixture refresh exists for. A field agent-vm renamed or dropped comes out as "-",
# and this names it instead of letting a lifecycle decision read "-" as an answer.
missing=$(printf '%s\n' "$row" | /usr/bin/awk -F'\t' '
    BEGIN { split("state pid supervisorVersion supervisorPath startedAt project projectReadOnly activeExecs guestVersion guestFeatures image", name, " ") }
    { for (i = 1; i <= 11; i++) if ($i == "-") printf "%s ", name[i] }')
check "no field is absent" "" "$missing"
missing=$(convert version "$FIXTURES/version.json" | /usr/bin/awk -F'\t' '
    BEGIN { split("version path guestVersion guestFeatures guestDigest", name, " ") }
    { for (i = 1; i <= 5; i++) if ($i == "-") printf "%s ", name[i] }')
check "and none of the version row's" "" "$missing"

section "agentvm_json.py: a stopped box and a wedged one"
row=$(convert status "$FIXTURES/box-status-stopped.json")
check "stopped"                       "stopped" "$(printf '%s\n' "$row" | col 1)"
check "  has no pid"                  "-"       "$(printf '%s\n' "$row" | col 2)"
check "  and no project"              "-"       "$(printf '%s\n' "$row" | col 6)"
check "  but still names its image"   "dev"     "$(printf '%s\n' "$row" | col 11)"
row=$(convert status "$FIXTURES/box-status-unresponsive.json")
check "unresponsive"                  "unresponsive" "$(printf '%s\n' "$row" | col 1)"
check "  has no pid to signal"        "-"            "$(printf '%s\n' "$row" | col 2)"
check "  and says why"                "no answer from the supervisor within 5 s" "$(printf '%s\n' "$row" | col 12)"

section "agentvm_json.py: doctor rows"
rows=$(convert doctor "$FIXTURES/doctor.json")
check "one row per check"          "6" "$(printf '%s\n' "$rows" | /usr/bin/awk 'END { print NR }')"
check "name, status and detail"    "macOS${TAB}ok${TAB}macOS 27.0.0" "$(printf '%s\n' "$rows" | /usr/bin/head -1)"
check "the running VMs check is there" "1" "$(printf '%s\n' "$rows" | /usr/bin/grep -c "^running VMs${TAB}")"

section "agentvm_json.py never emits an empty field or a line break inside one"
# The invariant that keeps `IFS=<tab> read` from shifting fields. Each hostile value is paired
# with the column it must land in, so a collapse shows up as a value in the wrong place.
printf '%s' '{"state":"running","pid":7,"supervisorVersion":"","supervisorPath":"/a\tb","project":"/p\nq","projectReadOnly":false,"activeExecs":0,"guestFeatures":[],"box":{"image":"x"}}' \
    > "$OMCTEST_WORK/hostile.json"
row=$(convert status "$OMCTEST_WORK/hostile.json")
check "one line"                         "1"     "$(printf '%s\n' "$row" | /usr/bin/awk 'END { print NR }')"
check "fourteen fields"                  "14"    "$(printf '%s\n' "$row" | /usr/bin/awk -F'\t' '{ print NF }')"
check "an empty string is \"-\""         "-"     "$(printf '%s\n' "$row" | col 3)"
check "a tab inside a value is \"?\""    "/a?b"  "$(printf '%s\n' "$row" | col 4)"
check "a newline inside a value is \"?\"" "/p?q" "$(printf '%s\n' "$row" | col 6)"
check "false is spelled out"             "false" "$(printf '%s\n' "$row" | col 7)"
check "zero is a value, not absent"      "0"     "$(printf '%s\n' "$row" | col 8)"
check "an empty list is \"-\""           "-"     "$(printf '%s\n' "$row" | col 10)"
check "the image still lands in column 11" "x"   "$(printf '%s\n' "$row" | col 11)"

section "agentvm_json.py refuses what is not agent-vm's JSON, with nothing on stdout"
printf 'Error: not json\n' > "$OMCTEST_WORK/text.json"
out=$(convert status "$OMCTEST_WORK/text.json" 2>/dev/null); rc=$?
check "text is refused"      "1" "$rc"
check "  and prints no row"  ""  "$out"
printf '[]\n' > "$OMCTEST_WORK/list.json"
out=$(convert status "$OMCTEST_WORK/list.json" 2>/dev/null); rc=$?
check "a list where an object belongs is refused" "1" "$rc"
check "  and prints no row"                       ""  "$out"
printf '{"checks": "none"}\n' > "$OMCTEST_WORK/badchecks.json"
out=$(convert doctor "$OMCTEST_WORK/badchecks.json" 2>/dev/null); rc=$?
check "doctor without a checks list is refused"   "1" "$rc"

# -----------------------------------------------------------------------------------------
section "which agent-vm: the installed one unless something says otherwise"
cad_reset
check "no seam, no setting: the installed link" "$INSTALLED" "$(lib agentvm_bin)"
check "  and it says so"                        "installed" "$(lib agentvm_origin)"
set_developer agent-vm "/Users/you/Development/agent-vm/.build/signed/release/agent-vm"
check "the developer setting wins over it" "/Users/you/Development/agent-vm/.build/signed/release/agent-vm" "$(lib agentvm_bin)"
check "  and it says so"                   "developer" "$(lib agentvm_origin)"
check "the test seam wins over both"       "$FAKE"     "$(with_fake agentvm_bin)"
check "  and it says so"                   "test"      "$(with_fake agentvm_origin)"
set_developer agent-vm ""
check "an empty setting means the installed one" "$INSTALLED" "$(lib agentvm_bin)"
cad_reset
lib agentvm_bin >/dev/null
check "reading the setting did not create the settings file" "0" "$([ -e "$cad_settings" ] && echo 1 || echo 0)"

section "the store setting reaches agent-vm as AGENT_VM_HOME, and only when set"
fake_reset
cad_reset
with_fake agentvm_run --version >/dev/null
check "unset by default"   "(unset)" "$(/bin/cat "$FAKE_AGENTVM_DIR/home")"
set_developer agent-vm-home "/Volumes/Work/agent-vm"
with_fake agentvm_run --version >/dev/null
check "set from /developer/agent-vm-home" "/Volumes/Work/agent-vm" "$(/bin/cat "$FAKE_AGENTVM_DIR/home")"
cad_reset

section "names agent-vm accepts, and nothing that could be read as an option"
valid() { lib agentvm_valid_name "$1" && echo yes || echo no; }
name63=$(printf '%063d' 0)
check "dev"                      "yes" "$(valid dev)"
check "cadabra-opencode-3f2a91"  "yes" "$(valid cadabra-opencode-3f2a91)"
check "dots and underscores"     "yes" "$(valid a.b_c-1)"
check "63 characters"            "yes" "$(valid "$name63")"
check "64 characters"            "no"  "$(valid "${name63}1")"
check "empty"                    "no"  "$(valid "")"
check "a leading dash"           "no"  "$(valid -rf)"
check "a leading dot"            "no"  "$(valid .hidden)"
check "upper case"               "no"  "$(valid Dev)"
check "a space"                  "no"  "$(valid "a b")"
check "a slash"                  "no"  "$(valid a/b)"

section "version comparison"
atleast() { lib agentvm_version_at_least "$1" "$2" && echo yes || echo no; }
check "equal"                      "yes" "$(atleast 0.1.6 0.1.6)"
check "a later patch"              "yes" "$(atleast 0.1.8 0.1.6)"
check "compared as numbers"        "yes" "$(atleast 0.1.10 0.1.6)"
check "an earlier patch"           "no"  "$(atleast 0.1.5 0.1.6)"
check "a later minor"              "yes" "$(atleast 0.2 0.1.6)"
check "a missing part counts as 0" "no"  "$(atleast 0.1 0.1.6)"
check "a later major"              "yes" "$(atleast 1.0.0 0.1.6)"
check "a suffix is not a version"  "no"  "$(atleast 0.1.8-dev 0.1.6)"
check "nothing is not a version"   "no"  "$(atleast "" 0.1.6)"

section "macOS gate"
check "macOS 26 is refused, naming both versions" "Boxes need macOS 27 or later. This Mac runs macOS 26.4." "$(lib agentvm_macos_reason 26.4)"
check "macOS 27 passes"         "" "$(lib agentvm_macos_reason 27.0)"
check "macOS 28 passes"         "" "$(lib agentvm_macos_reason 28.1)"
check "no answer is refused"    "1" "$(cad_has "$(lib agentvm_macos_reason "")" "did not report its macOS version")"

section "binary gate: what each origin says when its agent-vm is missing"
/bin/mkdir -p "$OMCTEST_WORK/adir"
check "a relative developer path"   "1" "$(cad_has "$(lib agentvm_bin_reason agent-vm developer)" "not an absolute path")"
check "a developer path that is not there" "1" "$(cad_has "$(lib agentvm_bin_reason /nowhere/agent-vm developer)" "points at /nowhere/agent-vm, which is not an executable file")"
check "a directory is not an agent-vm" "1" "$(cad_has "$(lib agentvm_bin_reason "$OMCTEST_WORK/adir" developer)" "not an executable file")"
check "the installed one missing"   "1" "$(cad_has "$(lib agentvm_bin_reason /nowhere/agent-vm installed)" "AgentVM is not installed: there is no agent-vm at /nowhere/agent-vm. Install AgentVM from https://github.com/abra-code/agent-vm/releases.")"
check "the seam missing"            "1" "$(cad_has "$(lib agentvm_bin_reason /nowhere/agent-vm test)" "CADABRA_AGENT_VM is /nowhere/agent-vm")"
check "the fake passes"             ""  "$(lib agentvm_bin_reason "$FAKE" test)"

section "agentvm_available against the fake"
host_macos=$(/usr/bin/sw_vers -productVersion 2>/dev/null)
host_reason=$(lib agentvm_macos_reason "$host_macos")
if [ -n "$host_reason" ]; then
    # On a Mac older than macOS 27 the gate must refuse before running anything.
    fake_reset
    out=$(with_fake agentvm_available); rc=$?
    check "this Mac is too old: refused"       "1" "$rc"
    check "  with the macOS reason"            "$host_reason" "$out"
    check "  and agent-vm never ran"           "0" "$([ -s "$FAKE_AGENTVM_DIR/log" ] && echo 1 || echo 0)"
else
    fake_reset
    out=$(with_fake agentvm_available); rc=$?
    check "a current agent-vm is available"    "0" "$rc"
    check "  silently"                         ""  "$out"
    check "  after asking its version"         "--version" "$(/bin/cat "$FAKE_AGENTVM_DIR/log")"
    printf '0.1.11\n' > "$FAKE_AGENTVM_DIR/version"
    out=$(with_fake agentvm_available); rc=$?
    check "0.1.11 is too old"                  "1" "$rc"
    check "  and the reason names both versions" "1" "$(cad_has "$out" "Cadabra needs agent-vm $MIN_VERSION or later, and $FAKE is 0.1.11.")"
    fake_reset
    printf '3\n' > "$FAKE_AGENTVM_DIR/exit"
    printf 'dyld: Library not loaded\n' > "$FAKE_AGENTVM_DIR/stderr"
    out=$(with_fake agentvm_available); rc=$?
    check "an agent-vm that cannot run is unavailable" "1" "$rc"
    check "  and its own words are in the reason"      "1" "$(cad_has "$out" "did not report its version (status 3: dyld: Library not loaded)")"
    fake_reset
    printf '3\n' > "$FAKE_AGENTVM_DIR/exit"
    printf 'dyld: Library not loaded\n  Referenced from: agent-vm\n' > "$FAKE_AGENTVM_DIR/stderr"
    out=$(with_fake agentvm_available)
    check "  a reason is one line, however many the binary printed" "1" "$(printf '%s\n' "$out" | /usr/bin/awk 'END { print NR }')"
    fake_reset
    out=$( ( CADABRA_AGENT_VM="$OMCTEST_WORK/adir"; export CADABRA_AGENT_VM; lib agentvm_available ) ); rc=$?
    check "a seam at a directory is unavailable" "1" "$rc"

    # No seam and no setting: the installed agent-vm, in the layout AgentVM's package makes
    # (~/.local/bin/agent-vm, a link into the version's own folder), played by the fake.
    cad_reset
    fake_reset
    out=$(lib agentvm_available); rc=$?
    check "nothing installed: unavailable"     "1" "$rc"
    check "  AgentVM is not installed, and where to get it" "AgentVM is not installed: there is no agent-vm at $INSTALLED. Install AgentVM from https://github.com/abra-code/agent-vm/releases." "$out"
    check "  and no folder for its files"      "" "$(lib agentvm_real_dir)"
    VERSION_DIR="$HOME/.local/share/agent-vm/versions/$MIN_VERSION"
    /bin/mkdir -p "$VERSION_DIR" "$HOME/.local/bin"
    /bin/ln -s "$FAKE" "$VERSION_DIR/agent-vm"
    /bin/ln -s "../share/agent-vm/versions/$MIN_VERSION/agent-vm" "$INSTALLED"
    out=$(lib agentvm_available); rc=$?
    check "installed: available"               "0" "$rc"
    check "  run through the link"             "--version" "$(/bin/cat "$FAKE_AGENTVM_DIR/log")"
    check "  its files are beside the real program, where the links end" "$(cd "$OMCTEST_TESTS/helpers" && pwd -P)" "$(lib agentvm_real_dir)"
    printf '0.1.11\n' > "$FAKE_AGENTVM_DIR/version"
    out=$(lib agentvm_available); rc=$?
    check "an installed 0.1.11 is too old"     "1" "$rc"
    check "  and the reason says to install the newest" "Cadabra needs agent-vm $MIN_VERSION or later, and $INSTALLED is 0.1.11. Install the newest AgentVM from https://github.com/abra-code/agent-vm/releases." "$out"
    /bin/rm -rf "$HOME/.local"
    fake_reset
fi

section "box status through the fake"
fake_reset
/bin/cp "$FIXTURES/box-status-running.json" "$FAKE_AGENTVM_DIR/box-cadabra-x.json"
row=$(with_fake agentvm_box_status cadabra-x); rc=$?
check "succeeds"                   "0"     "$rc"
check "  with the converted row"   "running" "$(printf '%s\n' "$row" | col 1)"
check "  after asking exactly this" "box status cadabra-x --json" "$(/bin/cat "$FAKE_AGENTVM_DIR/log")"
check "  leaving no error file behind" "0" "$([ -e "$ERR_FILE" ] && echo 1 || echo 0)"

section "a missing box fails with agent-vm's own message"
fake_reset
out=$(with_fake agentvm_box_status nope); rc=$?
check "status 1, agent-vm's"  "1" "$rc"
check "  no row"              ""  "$out"
check "  the message waits in the error file" "1" "$([ -s "$ERR_FILE" ] && echo 1 || echo 0)"
check "  the message, without \"Error: \"" 'no box nope; `agent-vm box list` shows the existing ones' "$(lib agentvm_last_error "$rc")"
check "  read once, then forgotten" "agent-vm failed (status 1) and gave no reason." "$(lib agentvm_last_error 1)"

section "a name agent-vm would read as an option never reaches it"
fake_reset
out=$(with_fake agentvm_box_status --help); rc=$?
check "refused"                  "2" "$rc"
check "  with a reason"          "1" "$(cad_has "$(lib agentvm_last_error "$rc")" "is not a box name agent-vm accepts")"
check "  and agent-vm never ran" "0" "$([ -s "$FAKE_AGENTVM_DIR/log" ] && echo 1 || echo 0)"
# Positive control for the check above: the same log does fill when the name is fine.
with_fake agentvm_box_status nope >/dev/null 2>&1
lib agentvm_last_error >/dev/null
check "  (the log does record a real call)" "1" "$([ -s "$FAKE_AGENTVM_DIR/log" ] && echo 1 || echo 0)"

section "progress lines are not part of an error message"
fake_reset
printf '1\n' > "$FAKE_AGENTVM_DIR/exit"
printf '{"event":"progress","step":"starting"}\nError: the box is busy\n' > "$FAKE_AGENTVM_DIR/stderr"
with_fake agentvm_doctor >/dev/null; rc=$?
check "the call failed"              "1" "$rc"
check "  and the message is the error line alone" "the box is busy" "$(lib agentvm_last_error "$rc")"

section "an error's later lines stay with it, even ones that look like progress"
fake_reset
printf '1\n' > "$FAKE_AGENTVM_DIR/exit"
printf '{"event":"progress","step":"starting"}\nError: the program failed:\n{"guest": "output"}\nsecond line\n' > "$FAKE_AGENTVM_DIR/stderr"
with_fake agentvm_doctor >/dev/null; rc=$?
check "everything from the Error: line on" "the program failed:
{\"guest\": \"output\"}
second line" "$(lib agentvm_last_error "$rc")"
fake_reset
printf '1\n' > "$FAKE_AGENTVM_DIR/exit"
printf '{"event":"progress","step":"starting"}\nSegmentation fault\n' > "$FAKE_AGENTVM_DIR/stderr"
with_fake agentvm_doctor >/dev/null; rc=$?
check "with no Error: line, the lines that are not progress" "Segmentation fault" "$(lib agentvm_last_error "$rc")"

section "a conversion failure is reported like an agent-vm failure"
fake_reset
printf 'not json\n' > "$FAKE_AGENTVM_DIR/version.json"
out=$(with_fake agentvm_version_info); rc=$?
check "fails"                      "1" "$rc"
check "  with no row"              ""  "$out"
check "  and names the converter"  "1" "$(cad_has "$(lib agentvm_last_error "$rc")" "agentvm_json.py version")"

section "doctor and version rows through the fake"
fake_reset
check "six doctor rows" "6" "$(with_fake agentvm_doctor | /usr/bin/awk 'END { print NR }')"
check "the version row" "0.1.8" "$(with_fake agentvm_version_info | col 1)"
check "  asked as version --json" "version --json" "$(/usr/bin/tail -1 "$FAKE_AGENTVM_DIR/log")"

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end

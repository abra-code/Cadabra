#!/bin/sh
# Tests/46-reaper-allowlist.test.sh - which orphaned processes the bundle sweep may kill.
#
# reap_orphaned_bundle_processes kills every process at PPID 1 whose command line
# _bundle_managed_process accepts. For most bundle executables PPID 1 means "orphaned". For
# agent-vm it usually means "detached on purpose": a box's supervisor (`box serve`) owns a running
# virtual machine, and image jobs run for up to an hour without a parent. Only `agent-vm exec`,
# the client that runs one program in a box for its parent, is an orphan there. This file pins
# that allowlist, including a subcommand that does not exist yet.
#
# The sweep itself is never run here: it scans every process on the Mac, and the harness runs
# the real bundle, so it would reach the developer's own running Cadabra.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

unset CADABRA_AGENT_VM AGENT_VM_HOME

B="$OMC_APP_BUNDLE_PATH/Contents"
AVM="$B/Support/AgentVM/agent-vm"
DEV="/Users/you/Development/agent-vm/.build/signed/release/agent-vm"

# swept <command line> [other agent-vm]  ->  yes or no
swept() {
    cad_call_lib aichat.server.library.sh _bundle_managed_process "$@" && echo yes || echo no
}

section "the existing bundle executables are still swept"
check "llama-server"       "yes" "$(swept "$B/Support/Llama.cpp/llama-server --port 8150 -m /m/x.gguf")"
check "the bundled Python" "yes" "$(swept "$B/Library/Python/bin/python3 -m mcp_server_time")"
check "replay"             "yes" "$(swept "$B/Support/replay --mcp-server --allow-write /p")"
check "mlx-agent"          "yes" "$(swept "$B/Support/MLX/mlx-agent acp --model m")"

section "agent-vm: exec clients are swept"
check "an exec client of the embedded agent-vm" "yes" "$(swept "$AVM exec --box b --project /p -- opencode acp")"
check "  also with the developer override set"  "yes" "$(swept "$AVM exec --box b -- /usr/bin/true" "$DEV")"

section "agent-vm: nothing else is, however it looks"
check "a box supervisor"                "no" "$(swept "$AVM box serve cadabra-opencode-3f2a91")"
check "an image build"                  "no" "$(swept "$AVM image create dev --ipsw /i.ipsw")"
check "a guest update"                  "no" "$(swept "$AVM image update-guest dev dev-node")"
check "Full Disk Access setup"          "no" "$(swept "$AVM image setup dev")"
check "a box start"                     "no" "$(swept "$AVM box start b --owner-pid 42")"
check "a box shell"                     "no" "$(swept "$AVM box shell b")"
check "a subcommand that does not exist yet" "no" "$(swept "$AVM future-thing --exec")"
check "exec as a later argument"        "no" "$(swept "$AVM box execlog b")"
check "no subcommand at all"            "no" "$(swept "$AVM")"
check "the guest daemon beside it"      "no" "$(swept "$B/Support/AgentVM/agent-vm-guest exec x")"
check "the path only as an argument"    "no" "$(swept "/bin/sh -c $AVM exec --box b")"

section "the agent-vm job runner is the one bundled Python never swept"
JOBPY="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/agentvm_job.py"
PYBIN="$B/Library/Python/bin/python3"
check "the detached runner"              "no"  "$(swept "$PYBIN $JOBPY run /Users/you/Library/Application Support/Cadabra/Jobs 20260925-092829-9660ef 3")"
check "  but a list call is an ordinary helper" "yes" "$(swept "$PYBIN $JOBPY list /j")"
check "  and so is a start that lost its parent" "yes" "$(swept "$PYBIN $JOBPY start /j box-start box:b Start -- $AVM box start b")"
check "  the runner run with other interpreter options is not the runner" "yes" "$(swept "$PYBIN -I $JOBPY run /j 20260925-092829-9660ef 3")"
check "  nor is the same name elsewhere" "yes" "$(swept "$PYBIN /tmp/agentvm_job.py run /j x 3")"
check "the MCP servers' Python is still swept" "yes" "$(swept "$PYBIN -m mcp_server_time")"
# 48-agentvm-jobs.test.sh checks the same verdict on a real runner's command line, from ps.

section "the developer override: its exec clients, and only with it set"
check "its exec client, with it set"    "yes" "$(swept "$DEV exec --box b -- x" "$DEV")"
check "  but not its supervisor"        "no"  "$(swept "$DEV box serve b" "$DEV")"
check "  nor its image builds"          "no"  "$(swept "$DEV image create dev --from base" "$DEV")"
check "its exec client, with it unset"  "no"  "$(swept "$DEV exec --box b -- x")"
check "another agent-vm entirely"       "no"  "$(swept "/usr/local/bin/agent-vm exec --box b -- x" "$DEV")"

section "which other agent-vm the sweep passes"
# The second argument above comes from _bundle_other_agentvm, asked once per sweep.
other() { cad_call_lib aichat.server.library.sh _bundle_other_agentvm; }
set_developer() {
    [ -f "$cad_settings" ] || {
        /bin/mkdir -p "$(/usr/bin/dirname "$cad_settings")"
        "$cad_plister" set dict "$cad_settings" / >/dev/null 2>&1
    }
    "$cad_plister" get type "$cad_settings" /developer >/dev/null 2>&1 || \
        "$cad_plister" insert developer dict "$cad_settings" / >/dev/null 2>&1
    "$cad_plister" get type "$cad_settings" /developer/agent-vm >/dev/null 2>&1 || \
        "$cad_plister" insert agent-vm string "" "$cad_settings" /developer >/dev/null 2>&1
    "$cad_plister" set string "$1" "$cad_settings" /developer/agent-vm >/dev/null 2>&1
}
cad_reset
check "none by default: the embedded one is always covered" "" "$(other)"
set_developer "$DEV"
check "the developer override"                              "$DEV" "$(other)"
set_developer "$AVM"
check "an override naming the embedded one adds nothing"    "" "$(other)"
# Cadabra never runs a relative override (agentvm_available refuses it), so every exec client
# carrying that name is someone else's: "agent-vm exec" found through a PATH, at PPID 1.
set_developer "agent-vm"
check "a relative override adds nothing"                    "" "$(other)"
cad_reset

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end

#!/bin/sh
# Tests/47-agent-sandbox.test.sh - the bundled agent's own sandbox: which profile the transport
# builder writes for each engine and each place the tools run, when it writes none, and that the
# agent is never started unconfined because a profile could not be made.
#
# mlx-agent itself is not started here (it would need a model); the profile's effect on a real
# process is mlx-agent's own test (its sandbox smoke test), and 47-inference-sandbox covers the
# setting these launches share with llama-server.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

PY="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
BUILDER="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/acp_transport_json.py"
AGENT="$OMC_APP_BUNDLE_PATH/Contents/Support/MLX/mlx-agent"
RUN_DIR="$HOME/Library/Application Support/Cadabra/Run"

WORK="$(cd "$OMCTEST_WORK" && pwd -P)/agent-sandbox"
/bin/rm -rf "$WORK"
/bin/mkdir -p "$WORK/model" "$WORK/blobs" "$WORK/plain-model" "$WORK/project" "$WORK/store"
echo '{}' > "$WORK/blobs/abc"
/bin/ln -s "../blobs/abc" "$WORK/model/config.json"
echo '{}' > "$WORK/plain-model/config.json"
VM="$WORK/agent-vm"
printf '#!/bin/sh\n' > "$VM"
/bin/chmod +x "$VM"
OUT="$WORK/profile.json"
NO_CFG="$WORK/no-config.json"

# A config whose servers run on this Mac, and one whose servers are agent-vm exec into box b1.
MAC_CFG="$WORK/mac-config.json"
printf '{"servers": [{"name": "local", "command": "/usr/bin/true", "args": []}]}\n' > "$MAC_CFG"
BOX_CFG="$WORK/box-config.json"
printf '{"servers": [{"name": "local", "command": "%s", "args": ["exec", "--box", "b1", "--project", "/p", "--", "replay"]}, {"name": "pdf", "command": "%s", "args": ["exec", "--box", "b1", "--project", "/p", "--", "pdfutil"]}]}\n' "$VM" "$VM" > "$BOX_CFG"
MIXED_CFG="$WORK/mixed-config.json"
printf '{"servers": [{"name": "local", "command": "%s", "args": ["exec", "--box", "b1", "--", "replay"]}, {"name": "x", "command": "/usr/bin/true", "args": []}]}\n' "$VM" > "$MIXED_CFG"
OTHER_BOX_CFG="$WORK/other-box-config.json"
printf '{"servers": [{"name": "local", "command": "%s", "args": ["exec", "--box", "b2", "--", "replay"]}]}\n' "$VM" > "$OTHER_BOX_CFG"

# build <engine> <target> <config> [named options...]  ->  the transport JSON; messages dropped.
build() {
    build_engine="$1"; build_target="$2"; build_cfg="$3"
    shift 3
    /bin/rm -f "$OUT"
    PYTHONDONTWRITEBYTECODE=1 "$PY" "$BUILDER" "$AGENT" "$build_engine" "$build_target" "$build_cfg" "$WORK/project" true "$@" 2>/dev/null
}
# argv_of <transport-json>  ->  the agent's arguments, one per line.
argv_of() { printf '%s' "$1" | /usr/bin/jq -r '.transport.command[]' 2>/dev/null; }
# flagged <transport-json>  ->  the profile path after --sandbox-profile, or nothing.
flagged() { argv_of "$1" | /usr/bin/awk 'take { print; exit } $0 == "--sandbox-profile" { take = 1 }'; }
# prof <jq-filter>  ->  that value of the written profile.
prof() { /usr/bin/jq -c "$1" "$OUT" 2>/dev/null; }
# written  ->  yes when a profile was written.
written() { if [ -f "$OUT" ]; then echo yes; else echo no; fi; }

section "without the option nothing changes"
t="$(build mlx "$WORK/plain-model" "$NO_CFG")"
check "the mlx transport is the old one" "acp --model $WORK/plain-model" "$(argv_of "$t" | /usr/bin/sed 1d | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
check "no profile is written" "no" "$(written)"

section "an MLX model, no tools"
t="$(build mlx "$WORK/model" "$NO_CFG" --sandbox-out "$OUT")"
check "the agent is told its profile" "$OUT" "$(flagged "$t")"
check "the GPU" "true" "$(prof .gpu)"
check "the model's folder" "[\"$WORK/model\"]" "$(prof .read_only)"
check "and the one file its link leads to, not that file's folder" "[\"$WORK/blobs/abc\"]" "$(prof .read_only_files)"
check "Apple's model service, for a summary" "true" "$(prof .foundation_models)"
check "no network, no program, no tool rules" "null null null null" \
    "$(prof '[.network_connect, .exec_files, .allow_network, .unix_socket_connect] | map(tostring) | join(" ")' | /usr/bin/tr -d '"')"
check "the file is this user's only" "-rw-------" "$(/bin/ls -l "$OUT" | /usr/bin/cut -c1-10)"
t="$(build mlx "$WORK/plain-model" "$NO_CFG" --sandbox-out "$OUT")"
check "a model in a plain folder grants that folder alone" "[\"$WORK/plain-model\"]" "$(prof .read_only)"
# A link in the model folder must not reach the home folder: one to the home folder itself has
# its parent ("/Users") as the folder it is really in, and one to a file in it the home folder.
/bin/mkdir -p "$WORK/link-model"
/bin/ln -s "$HOME" "$WORK/link-model/extra"
/usr/bin/touch "$HOME/agent-sandbox-probe"
/bin/ln -s "$HOME/agent-sandbox-probe" "$WORK/link-model/config.json"
t="$(build mlx "$WORK/link-model" "$NO_CFG" --sandbox-out "$OUT")"
check "a link to the home folder grants neither it nor its parent" "[\"$WORK/link-model\"]" "$(prof .read_only)"
check "a link to a file there grants that file alone" "[\"$(cd "$HOME" && pwd -P)/agent-sandbox-probe\"]" "$(prof .read_only_files)"
# A snapshot in a Hugging Face repository: a linked folder inside the repository is followed.
/bin/mkdir -p "$WORK/repo/snapshots/rev1" "$WORK/repo/blobs/shards" "$WORK/elsewhere"
echo '{}' > "$WORK/repo/snapshots/rev1/config.json"
/bin/ln -s "../../blobs/shards" "$WORK/repo/snapshots/rev1/shards"
/bin/ln -s "$WORK/elsewhere" "$WORK/repo/snapshots/rev1/outside"
t="$(build mlx "$WORK/repo/snapshots/rev1" "$NO_CFG" --sandbox-out "$OUT")"
check "a linked folder inside the repository is granted, one outside it is not" \
    "[\"$WORK/repo/snapshots/rev1\",\"$WORK/repo/blobs/shards\"]" "$(prof .read_only)"
/bin/rm -f "$HOME/agent-sandbox-probe"

section "a GGUF model: the agent talks to llama-server"
t="$(build openai "http://127.0.0.1:18455/v1" "$NO_CFG" --sandbox-out "$OUT")"
check "the agent is told its profile" "$OUT" "$(flagged "$t")"
check "one port of this Mac" '["localhost:18455"]' "$(prof .network_connect)"
check "no GPU, no folder" "null null" "$(prof '[.gpu, .read_only] | map(tostring) | join(" ")' | /usr/bin/tr -d '"')"
t="$(build openai "http://example.com:8080/v1" "$NO_CFG" --sandbox-out "$OUT")"
check "a server elsewhere gets no profile" "" "$(flagged "$t")"
check "  and the agent still starts" "acp" "$(argv_of "$t" | /usr/bin/sed -n 2p)"

section "Apple's on-device model"
t="$(build foundation "" "$NO_CFG" --sandbox-out "$OUT")"
check "the agent is told its profile" "$OUT" "$(flagged "$t")"
check "the model service and nothing else" '{"foundation_models":true}' "$(prof .)"

section "tools on this Mac: no profile"
t="$(build mlx "$WORK/model" "$MAC_CFG" --sandbox-out "$OUT")"
check "the agent gets its tools" "$MAC_CFG" "$(argv_of "$t" | /usr/bin/awk 'take { print; exit } $0 == "--mcp-config" { take = 1 }')"
check "and no profile" "" "$(flagged "$t")"
check "none is written" "no" "$(written)"

section "tools in an AgentVM box"
t="$(build openai "http://127.0.0.1:18455/v1" "$BOX_CFG" --sandbox-out "$OUT" --tools-box b1 --agent-vm "$VM" --agent-vm-home "$WORK/store")"
check "the agent is told its profile" "$OUT" "$(flagged "$t")"
check "it may start agent-vm, and only that" "[\"$VM\"]" "$(prof .exec_files)"
check "read the config and the box's record" "[\"$BOX_CFG\",\"$WORK/store/Boxes/b1\",\"$WORK/store/Boxes/b1/box.json\"]" "$(prof .read_only_files)"
check "connect to the box's control socket" "[\"$WORK/store/Boxes/b1/control.sock\"]" "$(prof .unix_socket_connect)"
check "append to the box's exec log" "[\"$WORK/store/Boxes/b1/exec.jsonl\"]" "$(prof .read_write_files)"
check "and still reach its model server" '["localhost:18455"]' "$(prof .network_connect)"
check "no leave to start any program" "null" "$(prof .allow_exec)"
t="$(build foundation "" "$BOX_CFG" --sandbox-out "$OUT" --tools-box b1 --agent-vm "$VM")"
check "agent-vm's own store when none is named" "[\"$HOME/Library/Application Support/agent-vm/Boxes/b1/control.sock\"]" "$(prof .unix_socket_connect)"

section "a config that is not what a box session writes gets no profile"
t="$(build foundation "" "$MIXED_CFG" --sandbox-out "$OUT" --tools-box b1 --agent-vm "$VM")"
check "a server that is not agent-vm" "" "$(flagged "$t")"
check "  and the agent still starts" "acp" "$(argv_of "$t" | /usr/bin/sed -n 2p)"
t="$(build foundation "" "$OTHER_BOX_CFG" --sandbox-out "$OUT" --tools-box b1 --agent-vm "$VM")"
check "a server in another box" "" "$(flagged "$t")"
check "  and the agent still starts" "acp" "$(argv_of "$t" | /usr/bin/sed -n 2p)"
t="$(build foundation "" "$BOX_CFG" --sandbox-out "$OUT" --tools-box b1)"
check "no agent-vm path" "" "$(flagged "$t")"
check "the agent still starts with its tools" "$BOX_CFG" "$(argv_of "$t" | /usr/bin/awk 'take { print; exit } $0 == "--mcp-config" { take = 1 }')"

section "a profile that cannot be written refuses the transport"
t="$(build foundation "" "$NO_CFG" --sandbox-out "$WORK/no-such-folder/profile.json")"
check "nothing to inject" "" "$t"
t="$(build foundation "" "$NO_CFG" --sandbox-out "profile.json")"
check "a relative path the same" "" "$t"
t="$(build foundation "" "$NO_CFG" --sandbox-out)"
check "an option with no value the same" "" "$t"
t="$(build foundation "" "$NO_CFG" --box b1 --agent-vm "$VM" --project "$WORK/project" --level free)"
check "an external agent's options on a bundled engine the same" "" "$t"
t="$(build external "/usr/bin/true" "$NO_CFG" --sandbox-out "$OUT")"
check "and the sandbox option on an external agent" "" "$t"

section "from the applet: the setting decides"
cad_reset
lib() { cad_call_lib aichat.server.library.sh "$@"; }
t="$(lib aichat_acp_transport_json "$AGENT" foundation "" WIN-A false 2>/dev/null)"
check "on by default: the profile is in Cadabra's own folder" "$RUN_DIR/agent-sandbox-WIN-A.json" "$(flagged "$t")"
check "  and written" "true" "$(/usr/bin/jq -c .foundation_models "$RUN_DIR/agent-sandbox-WIN-A.json" 2>/dev/null)"
lib inference_sandbox_set false
t="$(lib aichat_acp_transport_json "$AGENT" foundation "" WIN-B false 2>/dev/null)"
check "off: no profile" "" "$(flagged "$t")"
check "  the agent starts as before" "acp --backend foundation" "$(argv_of "$t" | /usr/bin/sed 1d | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
lib inference_sandbox_set true
# An agent that cannot confine itself (an older build): its help does not name the option.
OLD_AGENT="$WORK/old-agent"
printf '#!/bin/sh\necho "usage: old-agent acp"\n' > "$OLD_AGENT"
/bin/chmod +x "$OLD_AGENT"
t="$(lib aichat_acp_transport_json "$OLD_AGENT" foundation "" WIN-C false 2>/dev/null)"
check "an agent without the option is not given it" "" "$(flagged "$t")"
check "  and still starts" "acp" "$(argv_of "$t" | /usr/bin/sed -n 2p)"
t="$(lib aichat_acp_transport_json "$AGENT" external "/usr/bin/true" WIN-D false 2>/dev/null)"
check "an external agent's transport is untouched" "/usr/bin/true" "$(argv_of "$t")"

omctest_end

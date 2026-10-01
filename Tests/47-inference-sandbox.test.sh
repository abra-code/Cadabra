#!/bin/sh
# Tests/47-inference-sandbox.test.sh - the model engine's sandbox: the profile written for
# llama-server, what that profile really allows (a stand-in engine run under it by
# /usr/bin/sandbox-exec), the setting that turns it off, and how a refused launch is told from an
# unsupported model.
#
# llama-server itself never runs here; the stand-in engine is a copy of /bin/cat, which is enough
# to ask the kernel what a profile lets its process read. A process under a sandbox cannot apply
# another one, so this file needs a test run that is not itself sandboxed.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

PY="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
BUILDER="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/inference_sandbox.py"
LIB=aichat.server.library.sh
RUN_DIR="$HOME/Library/Application Support/Cadabra/Run"
SANDBOX_TOGGLE_ID=31

# Real paths throughout: the kernel compares real paths, and the test folder is under a link
# (/var -> /private/var, or /tmp -> /private/tmp).
WORK="$(cd "$OMCTEST_WORK" && pwd -P)/sandbox"
ENGINE="$WORK/engine"
MODELS="$WORK/models"
/bin/rm -rf "$WORK"
/bin/mkdir -p "$ENGINE" "$MODELS/blobs" "$MODELS/snapshot" "$WORK/other"
/bin/cp /bin/cat "$ENGINE/cat"
# A copy of a system program keeps Apple's signature, which does not hold outside its place: the
# kernel kills it at launch. Signed again ad hoc, it runs.
/usr/bin/codesign -s - -f "$ENGINE/cat" >/dev/null 2>&1
printf 'model' > "$MODELS/plain.gguf"
printf 'blob' > "$MODELS/blobs/abc123"
/bin/ln -s "../blobs/abc123" "$MODELS/snapshot/linked.gguf"
printf 'one' > "$MODELS/split-00001-of-00002.gguf"
printf 'two' > "$MODELS/split-00002-of-00002.gguf"
printf 'unrelated' > "$MODELS/neighbor.gguf"
printf 'secret' > "$WORK/other/secret.txt"

# build <model> <port> <out>  ->  the generator's exit status; its messages are dropped.
# build_status holds it too, for a check on the next line.
build() {
    PYTHONDONTWRITEBYTECODE=1 "$PY" "$BUILDER" llama --engine-dir "$ENGINE" --model "$1" --port "$2" --out "$3" 2>/dev/null
    build_status=$?
    return "$build_status"
}

# reads <profile> <file>  ->  "read" when the stand-in engine can read the file under the
# profile, "refused" when it cannot.
reads() {
    /usr/bin/sandbox-exec -f "$1" "$ENGINE/cat" "$2" >/dev/null 2>&1
    reads_status=$?
    if [ "$reads_status" -eq 0 ]; then echo read; else echo refused; fi
}

lib() { cad_call_lib "$LIB" "$@"; }

section "the profile written for llama-server"
PROFILE="$WORK/plain.sb"
build "$MODELS/plain.gguf" 18431 "$PROFILE"
check "the generator ran" "0" "$build_status"
check "it denies by default" "1" "$(/usr/bin/grep -c '^(deny default)$' "$PROFILE")"
check "the engine's folder may be read and run" "1" \
    "$(/usr/bin/grep -c "^(allow file-read\* process-exec (subpath \"$ENGINE\"))\$" "$PROFILE")"
check "the model may be read" "1" \
    "$(/usr/bin/grep -c "^(allow file-read\* (literal \"$MODELS/plain.gguf\"))\$" "$PROFILE")"
check "the network is denied" "1" "$(/usr/bin/grep -c '^(deny network\*)$' "$PROFILE")"
check "but for listening on its port" "2" "$(/usr/bin/grep -c 'local ip "localhost:18431"' "$PROFILE")"
check "no outgoing connection is allowed" "0" "$(/usr/bin/grep -c 'network-outbound' "$PROFILE")"
check "nothing may be written but Metal's caches" "1" "$(/usr/bin/grep -c 'file-write' "$PROFILE")"
check "  and that rule names them" "1" "$(/usr/bin/grep 'file-write' "$PROFILE" | /usr/bin/grep -c 'com.apple.metal')"
check "the GPU's driver connections are named" "1" \
    "$(/usr/bin/grep -c 'iokit-user-client-class "AGXDeviceUserClient" "IOSurfaceRootUserClient"' "$PROFILE")"
check "the file is this user's only" "-rw-------" "$(/bin/ls -l "$PROFILE" | /usr/bin/cut -c1-10)"

section "a model that is a link is readable under both of its paths"
build "$MODELS/snapshot/linked.gguf" 18431 "$WORK/linked.sb"
check "the path given" "1" "$(/usr/bin/grep -c "(literal \"$MODELS/snapshot/linked.gguf\")" "$WORK/linked.sb")"
check "the file it leads to" "1" "$(/usr/bin/grep -c "(literal \"$MODELS/blobs/abc123\")" "$WORK/linked.sb")"

section "what the generator refuses"
build "models/plain.gguf" 18431 "$WORK/refused.sb"
check "a relative model path" "1" "$build_status"
build "$MODELS/missing.gguf" 18431 "$WORK/refused.sb"
check "a model that does not exist" "1" "$build_status"
build "$MODELS" 18431 "$WORK/refused.sb"
check "a folder as the model" "1" "$build_status"
build "$MODELS/plain.gguf" 0 "$WORK/refused.sb"
check "port 0" "1" "$build_status"
build "$MODELS/plain.gguf" 70000 "$WORK/refused.sb"
check "a port past 65535" "1" "$build_status"
check "none of them left a profile" "no" "$([ -e "$WORK/refused.sb" ] && echo yes || echo no)"

section "a path with a quote in it stays one string"
/bin/mkdir -p "$MODELS/odd\"name"
printf 'model' > "$MODELS/odd\"name/m.gguf"
build "$MODELS/odd\"name/m.gguf" 18431 "$WORK/quote.sb"
check "the generator ran" "0" "$build_status"
check "the model is readable under it" "read" "$(reads "$WORK/quote.sb" "$MODELS/odd\"name/m.gguf")"
check "  and nothing else is" "refused" "$(reads "$WORK/quote.sb" "$WORK/other/secret.txt")"

section "the kernel's answer: what a process under the profile can read"
check "its model" "read" "$(reads "$PROFILE" "$MODELS/plain.gguf")"
check "not the model beside it" "refused" "$(reads "$PROFILE" "$MODELS/neighbor.gguf")"
check "not a file elsewhere" "refused" "$(reads "$PROFILE" "$WORK/other/secret.txt")"
check "not the user's settings" "refused" "$(reads "$PROFILE" "$HOME/Library/Application Support/Cadabra/settings.plist")"
check "a linked model, through the link" "read" "$(reads "$WORK/linked.sb" "$MODELS/snapshot/linked.gguf")"
check "  but not another blob" "refused" "$(reads "$WORK/linked.sb" "$MODELS/plain.gguf")"
# The control for every "refused" above: the same read with no profile.
check "the stand-in engine reads that file when unconfined" "secret" "$("$ENGINE/cat" "$WORK/other/secret.txt")"

section "a model split into parts"
build "$MODELS/split-00001-of-00002.gguf" 18431 "$WORK/split.sb"
check "the first part" "read" "$(reads "$WORK/split.sb" "$MODELS/split-00001-of-00002.gguf")"
check "the second part" "read" "$(reads "$WORK/split.sb" "$MODELS/split-00002-of-00002.gguf")"
check "not an unrelated model in the same folder" "refused" "$(reads "$WORK/split.sb" "$MODELS/neighbor.gguf")"
# The folder and the name are matched as text, not as a pattern: a dot, a bracket, a quote.
/bin/mkdir -p "$MODELS/v1.5 [q4] \"x\""
printf 'one' > "$MODELS/v1.5 [q4] \"x\"/m.k-00001-of-00003.gguf"
printf 'three' > "$MODELS/v1.5 [q4] \"x\"/m.k-00003-of-00003.gguf"
printf 'other' > "$MODELS/v1.5 [q4] \"x\"/mxk-00003-of-00003.gguf"
build "$MODELS/v1.5 [q4] \"x\"/m.k-00001-of-00003.gguf" 18431 "$WORK/split-odd.sb"
check "a later part in an oddly named folder" "read" "$(reads "$WORK/split-odd.sb" "$MODELS/v1.5 [q4] \"x\"/m.k-00003-of-00003.gguf")"
check "  where the dot in the name is a dot" "refused" "$(reads "$WORK/split-odd.sb" "$MODELS/v1.5 [q4] \"x\"/mxk-00003-of-00003.gguf")"

# A Hugging Face snapshot: every part is a link of its own into the blobs folder, and the kernel
# checks the blob's path.
/bin/mkdir -p "$MODELS/hf/blobs" "$MODELS/hf/snapshot"
printf 'one' > "$MODELS/hf/blobs/aaa"
printf 'two' > "$MODELS/hf/blobs/bbb"
printf 'other' > "$MODELS/hf/blobs/ccc"
/bin/ln -s "../blobs/aaa" "$MODELS/hf/snapshot/s-00001-of-00002.gguf"
/bin/ln -s "../blobs/bbb" "$MODELS/hf/snapshot/s-00002-of-00002.gguf"
/bin/ln -s "../blobs/ccc" "$MODELS/hf/snapshot/t-00002-of-00002.gguf"
build "$MODELS/hf/snapshot/s-00001-of-00002.gguf" 18431 "$WORK/split-linked.sb"
check "a linked first part" "read" "$(reads "$WORK/split-linked.sb" "$MODELS/hf/snapshot/s-00001-of-00002.gguf")"
check "a linked second part" "read" "$(reads "$WORK/split-linked.sb" "$MODELS/hf/snapshot/s-00002-of-00002.gguf")"
check "  but not another model's linked part" "refused" "$(reads "$WORK/split-linked.sb" "$MODELS/hf/snapshot/t-00002-of-00002.gguf")"

section "it cannot start another program or write"
/usr/bin/sandbox-exec -f "$PROFILE" "$ENGINE/cat" "$MODELS/plain.gguf" > /dev/null 2>&1
check "the engine itself starts" "0" "$?"
/usr/bin/sandbox-exec -f "$PROFILE" /bin/cat "$MODELS/plain.gguf" > /dev/null 2>&1
check "a program outside its folder does not" "no" "$([ $? -eq 0 ] && echo yes || echo no)"

section "the setting"
cad_reset
check "on for a profile that never chose" "true" "$(lib inference_sandbox_enabled)"
lib inference_sandbox_set false
check "off once turned off" "false" "$(lib inference_sandbox_enabled)"
check "  stored as a boolean" "false" "$(cad_raw /inference/sandbox)"
lib inference_sandbox_set true
check "and on again" "true" "$(lib inference_sandbox_enabled)"
"$cad_plister" set string "maybe" "$cad_settings" /inference/sandbox >/dev/null 2>&1
check "a value that is neither reads as on" "true" "$(lib inference_sandbox_enabled)"

section "the checkbox in Select Local Model"
cad_reset
omc_control_defaults aichat.select.local.model
ui_reset
omc_run aichat.select.local.model.init
check "shows on by default" "true" "$(ui_value "$SANDBOX_TOGGLE_ID")"
omc_control "$SANDBOX_TOGGLE_ID" false
omc_run aichat.select.local.model.toggle.sandbox
check_status "the handler ran" 0
check "turning it off is stored" "false" "$(lib inference_sandbox_enabled)"
ui_reset
omc_run aichat.select.local.model.init
check "the next picker shows it off" "false" "$(ui_value "$SANDBOX_TOGGLE_ID")"
# A link (cadabra://exe?commandID=...) runs the handler with no window and no value.
( unset OMC_ACTIONUI_WINDOW_UUID ACTIONUI_WINDOW_UUID OMC_ACTIONUI_VIEW_31_VALUE; omc_run aichat.select.local.model.toggle.sandbox )
check "a link cannot turn it back on, or off" "false" "$(lib inference_sandbox_enabled)"
omc_control "$SANDBOX_TOGGLE_ID" true
omc_run aichat.select.local.model.toggle.sandbox
check "the window's own checkbox turns it on" "true" "$(lib inference_sandbox_enabled)"

section "the profile for a launch goes to Cadabra's own folder"
launch_profile="$(lib llama_sandbox_profile "$MODELS/plain.gguf" 18432 2>/dev/null)"
check "the library wrote one" "0" "$?"
check "in the Run folder, named for the port" "$RUN_DIR/llama-sandbox-18432.sb" "$launch_profile"
check "  with that port in it" "2" "$(/usr/bin/grep -c 'localhost:18432' "$launch_profile")"
check "  and the bundle's engine folder" "1" \
    "$(/usr/bin/grep -c 'process-exec (subpath ".*/Contents/Support/Llama.cpp")' "$launch_profile")"
lib llama_sandbox_profile "$MODELS/missing.gguf" 18433 >/dev/null 2>&1
check "no profile, no success" "1" "$?"

section "what the sandbox refused, read from the log"
# summary <pid>  ->  llama_denials_summary over a captured log.
DENIALS="$WORK/denials.log"
summary() {
    ( . "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/$LIB" >/dev/null 2>&1
      llama_denials_file="$DENIALS"
      llama_denials_summary "$1" )
}
/bin/cat > "$DENIALS" <<'LOG_END'
Filtering the log data using "sender == "Sandbox" AND composedMessage CONTAINS "llama-server(""
2026-10-01 11:26:44.245 E  kernel[0:d31a6f5] (Sandbox) Sandbox: llama-server(4242) deny(1) mach-lookup com.apple.windowserver.active
2026-10-01 11:26:44.246 E  kernel[0:d31a6f5] (Sandbox) Sandbox: llama-server(4242) deny(1) file-read-data /Users/me/models/a b.gguf
2026-10-01 11:26:44.247 E  kernel[0:d31a6f5] (Sandbox) Sandbox: llama-server(4242) deny(1) file-read-data /Users/me/models/a b.gguf
2026-10-01 11:26:44.248 E  kernel[0:d31a6f5] (Sandbox) Sandbox: llama-server(7777) deny(1) file-read-data /Users/me/other.gguf
2026-10-01 11:26:44.249 E  kernel[0:d31a6f5] (Sandbox) Sandbox: llama-server(4242) deny(1) network-bind local:*:8080
2026-10-01 11:26:44.250 E  kernel[0:d31a6f5] (Sandbox) Sandbox: llama-server(4242) deny(1) file-write-create /Users/me/x
2026-10-01 11:26:44.251 E  kernel[0:d31a6f5] (Sandbox) Sandbox: llama-server(4242) deny(1) file-read-data /Users/me/fourth
LOG_END
check "this server's refusals, once each, three at most, no service lookups" \
    "file-read-data /Users/me/models/a b.gguf; network-bind local:*:8080; file-write-create /Users/me/x" \
    "$(summary 4242)"
check "another server's are its own" "file-read-data /Users/me/other.gguf" "$(summary 7777)"
check "a server refused only service lookups was not stopped by them" "" "$(summary 9999)"
/bin/cat > "$DENIALS" <<'LOG_END'
2026-10-01 11:26:44.245 E  kernel[0:d31a6f5] (Sandbox) Sandbox: llama-server(4242) deny(1) mach-lookup com.apple.tccd.system
LOG_END
check "lookups alone give nothing" "" "$(summary 4242)"
/bin/rm -f "$DENIALS"
check "no log, nothing" "" "$(summary 4242)"

section "the tuning file is read from Cadabra's own folder, not the temporary one"
check "the launch does not source anything under TMPDIR" "0" \
    "$(/usr/bin/grep -c 'TMPDIR.*srvtune' "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/$LIB")"

omctest_end

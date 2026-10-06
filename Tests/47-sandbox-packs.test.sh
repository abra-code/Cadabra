#!/bin/sh
# Tests/47-sandbox-packs.test.sh - sandbox packs: the pack file format, the tokens a path may
# start with, the paths no pack may grant, what a pack grants on this Mac, user packs, and the
# Local server's sandbox profile generated with the ticked packs.
#
# The generator starts the real replay and pdfutil to list their tools, so the last section also
# shows that replay starts with a pack's folders and single files in its profile.
#
# POSIX sh only. Validate with "sh -n", never "bash -n".
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.cadabra.sh"

PY="$OMC_APP_BUNDLE_PATH/Contents/Library/Python/bin/python3"
PACKS_PY="$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/sandbox_packs.py"
SEEDS="$OMC_APP_BUNDLE_PATH/Contents/Resources/SandboxPacks"
SUPPORT="$HOME/Library/Application Support/Cadabra"
USER_PACKS="$SUPPORT/SandboxPacks"
SESSION="$SUPPORT/Sessions/w1"
CFG="$SESSION/mcp-config.json"
PLISTER="$OMC_OMC_SUPPORT_PATH/plister"

WORK="$(cd "$OMCTEST_WORK" && pwd -P)/sandbox-packs"
/bin/rm -rf "$WORK"
/bin/mkdir -p "$WORK/packs" "$WORK/project" "$WORK/xcode/Xcode.app/Contents/Developer" "$WORK/brew/bin" \
    "$WORK/cache" "$WORK/tools" "$WORK/build" "$WORK/target" "$WORK/fake-app/Contents/Resources/SandboxPacks"
: > "$WORK/brew/bin/brew"
printf 'settings\n' > "$WORK/tools/settings.conf"
/bin/ln -s "$WORK/target" "$WORK/link"
HOME_REAL="$(cd "$HOME" && pwd -P)"
/bin/mkdir -p "$HOME/.ssh" "$HOME/Library/Keychains" "$HOME/Library/Developer/Xcode/DerivedData" "$HOME/Documents" "$SUPPORT"
printf 'key\n' > "$HOME/.ssh/id_test"
printf '[user]\n' > "$HOME/.gitconfig"
/bin/ln -s "$HOME/.ssh" "$WORK/ssh-link"

# write_pack <id> <the pack's members after "id", as JSON text>  ->  the file's path.
write_pack() {
    printf '{"formatVersion": 1, "id": "%s", %s}\n' "$1" "$2" > "$WORK/packs/$1.json"
    printf '%s\n' "$WORK/packs/$1.json"
}
# pack_check <file> [options...]  ->  the pack as sandbox_packs.py reads it here, as JSON.
pack_check() {
    "$PY" -B "$PACKS_PY" check "$@" 2>&1
}
# field <jq filter> <file> [options...]  ->  one value of that.
field() {
    local _filter="$1"
    shift
    pack_check "$@" | /usr/bin/jq -r "$_filter" 2>/dev/null
}
# state_of <id> <members>  ->  "state: reason" of a pack written with them.
state_of() {
    field '.state + ": " + .reason' "$(write_pack "$1" "$2")"
}
TOKENS="--token DEVELOPER_DIR=$WORK/xcode/Xcode.app/Contents/Developer --token HOMEBREW_PREFIX=$WORK/brew --token DARWIN_USER_CACHE_DIR=$WORK/cache --token DARWIN_USER_TEMP_DIR=$WORK/build"

section "the packs that ship with the application"
check "there are five"                         "cmake git homebrew make xcode" "$(/bin/ls "$SEEDS" | /usr/bin/sed 's/\.json$//' | /usr/bin/tr '\n' ' ' | /usr/bin/sed 's/ $//')"
for seed in git homebrew xcode; do
    check "$seed is usable where its tools are" "ok" "$(field .state "$SEEDS/$seed.json" $TOKENS)"
    check "  and has a title and a description" "2" "$(field '[.title, .description] | map(select(length > 3)) | length' "$SEEDS/$seed.json" $TOKENS)"
done
check "xcode's developer folder is the application" "$WORK/xcode/Xcode.app" "$(field '.read_only[0]' "$SEEDS/xcode.json" $TOKENS)"
check "  its build folder is read-write"       "1" "$(field '[.read_write[] | select(endswith("/Library/Developer/Xcode/DerivedData"))] | length' "$SEEDS/xcode.json" $TOKENS)"
check "  without Xcode it is not installed"    "not-installed" "$(field .state "$SEEDS/xcode.json" --token DEVELOPER_DIR=)"
check "  and then grants nothing"              "0" "$(field '[.read_only[], .read_write[], .read_only_files[]] | length' "$SEEDS/xcode.json" --token DEVELOPER_DIR=)"
check "homebrew without brew is not installed" "not-installed" "$(field .state "$SEEDS/homebrew.json" --token HOMEBREW_PREFIX=)"
check "git grants one file to read"            "$HOME_REAL/.gitconfig" "$(field '.read_only_files | join(" ")' "$SEEDS/git.json")"
check "  and no folder: a credentials file can be beside git's settings" "0" "$(field '.read_only | length' "$SEEDS/git.json")"
check "the list has all five, none invalid"    "cmake:seed git:seed homebrew:seed make:seed xcode:seed|0" \
    "$("$PY" -B "$PACKS_PY" list --bundle "$OMC_APP_BUNDLE_PATH" $TOKENS | /usr/bin/jq -r '([.[] | .id + ":" + .source] | join(" ")) + "|" + ([.[] | select(.state == "invalid")] | length | tostring)')"

# cmake's own folders are where this Mac has them or not; what is tested is its two keys.
check "cmake needs any one of the places a cmake is installed" "3" "$(/usr/bin/jq -r '.requires_any | length' "$SEEDS/cmake.json")"
check "  and comes with the pack for make and the compiler, and Homebrew's" "make homebrew" "$(/usr/bin/jq -r '.uses | join(" ")' "$SEEDS/cmake.json")"
check "  both of which ship with the application"              "2" "$(for used in $(/usr/bin/jq -r '.uses[]' "$SEEDS/cmake.json"); do [ -f "$SEEDS/$used.json" ] && echo yes; done | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

/usr/bin/sed 's|/Library/Developer/CommandLineTools|/Library/Developer/NoSuchTools|g' "$SEEDS/make.json" > "$WORK/packs/make.json"
check "make is usable where Xcode or the Command Line Tools are, and not installed with neither" "ok|not-installed" \
    "$(field .state "$SEEDS/make.json" $TOKENS)|$(field .state "$WORK/packs/make.json" --token DEVELOPER_DIR=)"
check "  and grants the developer folder to read, nothing to change" "$WORK/xcode/Xcode.app|0" \
    "$(field '.read_only[0]' "$SEEDS/make.json" $TOKENS)|$(field '.read_write | length' "$SEEDS/make.json" $TOKENS)"

section "a pack usable where any one of several things is"
check "one of them is enough"          "ok: " "$(state_of anyone "\"title\": \"Any\", \"read_only\": [\"$WORK/tools\"], \"requires_any\": [\"$WORK/no-such-tool\", \"$WORK/tools\"]")"
check "none of them is not installed"  "not-installed: none of $WORK/no-such-tool, $WORK/nor-this is on this Mac" \
    "$(state_of anyone "\"title\": \"Any\", \"read_only\": [\"$WORK/tools\"], \"requires_any\": [\"$WORK/no-such-tool\", \"$WORK/nor-this\"]")"
check "an empty list asks for nothing" "ok: " "$(state_of anyone "\"title\": \"Any\", \"read_only\": [\"$WORK/tools\"], \"requires_any\": []")"
check "what must all be there still must" "not-installed" \
    "$(state_of anyone "\"title\": \"Any\", \"requires\": [\"$WORK/no-such-tool\"], \"requires_any\": [\"$WORK/tools\"]" | /usr/bin/cut -d: -f1)"

section "a pack that uses other packs: the file"
check "their ids are kept, each once"  "a b" "$(field '.uses | join(" ")' "$(write_pack user "\"title\": \"User\", \"uses\": [\"a\", \"b\", \"a\"]")")"
check "a pack cannot use itself"       "invalid" "$(state_of selfish "\"title\": \"Selfish\", \"uses\": [\"selfish\"]" | /usr/bin/cut -d: -f1)"
check "what it uses must be pack ids"  "invalid" "$(state_of sloppy "\"title\": \"Sloppy\", \"uses\": [\"../x\"]" | /usr/bin/cut -d: -f1)"
check "  and a list"                   "invalid" "$(state_of sloppy "\"title\": \"Sloppy\", \"uses\": \"xcode\"" | /usr/bin/cut -d: -f1)"

section "the pack file"
check "a plain pack is usable"                 "ok: " "$(state_of plain "\"title\": \"Plain\", \"read_only\": [\"$WORK/tools\"]")"
check "  unknown keys are ignored"             "ok: " "$(state_of plain "\"title\": \"Plain\", \"later\": {\"a\": 1}, \"read_only\": [\"$WORK/tools\"]")"
check "no title: invalid"                      "1" "$(cad_has "$(state_of untitled "\"read_only\": []")" "invalid: \"title\"")"
printf '{"id": "noversion", "title": "T"}\n' > "$WORK/packs/noversion.json"
check "no format version: invalid"             "1" "$(cad_has "$(field '.state + ": " + .reason' "$WORK/packs/noversion.json")" "invalid: \"formatVersion\"")"
printf '{"formatVersion": 2, "id": "newer", "title": "T"}\n' > "$WORK/packs/newer.json"
check "a newer format: invalid, and says so"   "invalid: it was made for a newer Cadabra" "$(field '.state + ": " + .reason' "$WORK/packs/newer.json")"
printf '{"formatVersion": 1, "id": "other", "title": "T"}\n' > "$WORK/packs/renamed.json"
check "an id that is not the file's name: invalid" "1" "$(cad_has "$(field '.state + ": " + .reason' "$WORK/packs/renamed.json")" "is not its file's name")"
printf '{"formatVersion": 1, "id": "Caps", "title": "T"}\n' > "$WORK/packs/Caps.json"
check "a file name that is no pack id: invalid" "1" "$(cad_has "$(field .reason "$WORK/packs/Caps.json")" "not a pack id")"
printf 'not json\n' > "$WORK/packs/broken.json"
check "a file that is not JSON: invalid"       "invalid" "$(field .state "$WORK/packs/broken.json")"
printf '[1, 2]\n' > "$WORK/packs/list.json"
check "  nor is a JSON list a pack"            "invalid" "$(field .state "$WORK/packs/list.json")"
check "a missing file: invalid"                "invalid" "$(field .state "$WORK/packs/nowhere.json")"
check "paths that are not text: invalid"       "1" "$(cad_has "$(state_of numbers '"title": "T", "read_only": [1, 2]')" "not a list of text")"
check "the check's status says usable or not"  "0|1" "$(pack_check "$WORK/packs/plain.json" >/dev/null; echo $?)|$(pack_check "$WORK/packs/newer.json" >/dev/null; echo $?)"

section "tokens"
check "~ is the home folder"                   "$HOME_REAL/Documents" "$(field '.read_only[0]' "$(write_pack home "\"title\": \"T\", \"read_only\": [\"~/Documents\"]")")"
check "\$PROJECT is the session's project"      "$WORK/project" "$(field '.read_write[0]' "$(write_pack proj '"title": "T", "read_write": ["$PROJECT"]')" --project "$WORK/project")"
check "  with no project the path is left out" "\$PROJECT: \$PROJECT has no value here" "$(field '.dropped[0] | .path + ": " + .reason' "$WORK/packs/proj.json")"
check "  and the pack is still usable"         "ok" "$(field .state "$WORK/packs/proj.json")"
check "a token gives the folder under it"      "$WORK/brew/bin" "$(field '.read_only[0]' "$(write_pack under '"title": "T", "read_only": ["$HOMEBREW_PREFIX/bin"]')" $TOKENS)"
check "an unknown token: invalid"              "1" "$(cad_has "$(state_of badtoken '"title": "T", "read_only": ["$SECRETS/x"]')" "a token this version does not know")"
check "  also in what the pack requires"       "invalid" "$(field .state "$(write_pack badreq '"title": "T", "requires": ["$NOPE"]')")"
check "a token inside a path is not one"       "not on this Mac" "$(field '.dropped[0].reason' "$(write_pack inside "\"title\": \"T\", \"read_only\": [\"$WORK/\$PROJECT\"]")" --project "$WORK/project")"
check "a relative path: invalid"               "1" "$(cad_has "$(state_of relative '"title": "T", "read_only": ["Documents"]')" "neither absolute nor starts with a token")"
check "a path with ..: invalid"                "1" "$(cad_has "$(state_of dots "\"title\": \"T\", \"read_only\": [\"$WORK/tools/../..\"]")" "\"..\" part")"
check "half a character pair is not text: invalid" "1" "$(cad_has "$(state_of halfpair '"title": "T", "read_only": ["$PROJECT/x\ud800", "/x\udc80"]')" "not text")"
check "~name is not the home folder"           "1" "$(cad_has "$(state_of tilde '"title": "T", "read_only": ["~root/x"]')" "neither absolute")"

section "what no pack may grant"
# never <path as written in the pack> [key]  ->  the reason the pack is invalid, or its state.
never() {
    field 'if .state == "invalid" then .reason else .state end' "$(write_pack never "\"title\": \"T\", \"${2:-read_only}\": [\"$1\"]")"
}
check "the home folder"                        "1" "$(cad_has "$(never "~")" "home folder")"
check "  the folder that contains it"          "1" "$(cad_has "$(never "$(/usr/bin/dirname "$HOME_REAL")")" "home folder")"
check "  the whole disk"                       "1" "$(cad_has "$(never "/")" "whole disk")"
check "  and its second name"                  "1" "$(cad_has "$(never "/System/Volumes/Data")" "whole disk")"
check "the home folder's Library"              "1" "$(cad_has "$(never "~/Library")" "contains ~/Library/")"
check "keys"                                   "1" "$(cad_has "$(never "~/.ssh")" "~/.ssh, which no pack may open")"
check "  a folder inside them"                 "1" "$(cad_has "$(never "~/.ssh/sub")" "~/.ssh")"
check "  one this Mac does not have"           "1" "$(cad_has "$(never "~/.aws")" "~/.aws")"
check "  a file among them"                    "1" "$(cad_has "$(never "~/.ssh/id_test" read_only_files)" "~/.ssh")"
check "  for writing as well"                  "1" "$(cad_has "$(never "~/Library/Keychains" read_write)" "Keychains")"
check "  in another spelling"                  "1" "$(cad_has "$(never "~/.SSH")" "~/.ssh")"
check "  through a link"                       "1" "$(cad_has "$(never "$WORK/ssh-link")" "~/.ssh")"
check "  with a doubled first slash"            "1" "$(cad_has "$(never "/$HOME_REAL/.aws")" "~/.aws")"
check "  git's stored passwords, so not its whole folder" "1" "$(cad_has "$(never "~/.config/git")" "contains ~/.config/git/credentials")"
/bin/mkdir -p "$WORK/dotfiles/kube"
/bin/ln -s "$WORK/dotfiles/kube" "$HOME/.kube"
check "  where a guarded folder really is, when it is a link" "1" "$(cad_has "$(never "$WORK/dotfiles/kube")" "~/.kube")"
check "  and the folder that holds that place"  "1" "$(cad_has "$(never "$WORK/dotfiles")" "contains ~/.kube")"
/bin/rm -f "$HOME/.kube"
check "Cadabra's own folder"                   "1" "$(cad_has "$(never "~/Library/Application Support/Cadabra/Sessions")" "Cadabra")"
check "one tool's folder in Library is fine"   "ok" "$(never "~/Library/Developer/Xcode/DerivedData")"
check "a pack with one such path grants nothing at all" "invalid|0" \
    "$(field '.state + "|" + ([.read_only[], .read_write[], .read_only_files[]] | length | tostring)' "$(write_pack mixed "\"title\": \"T\", \"read_only\": [\"$WORK/tools\", \"~/.ssh\"], \"read_write\": [\"$WORK/build\"]")")"

section "what a pack grants here"
GRANT="$(write_pack grant "\"title\": \"T\", \"read_only\": [\"$WORK/tools\", \"$WORK/link\", \"$WORK/nowhere\", \"$WORK/tools/settings.conf\", \"$WORK/build\"], \"read_write\": [\"$WORK/build\", \"$WORK/link\", \"$WORK/tools/../tools\"], \"read_only_files\": [\"$WORK/tools/settings.conf\", \"$WORK/tools\", \"$WORK/nofile\"]")"
/usr/bin/sed -i '' 's|/tools/\.\./tools|/build/.|' "$GRANT"
check "folders to read: the folder, and a link's target" "$WORK/tools $WORK/target" "$(field '.read_only | join(" ")' "$GRANT")"
check "folders to write, once"                 "$WORK/build" "$(field '.read_write | join(" ")' "$GRANT")"
check "  one in both lists is read-write only" "0" "$(field '[.read_only[] | select(endswith("/build"))] | length' "$GRANT")"
check "files to read"                          "$WORK/tools/settings.conf" "$(field '.read_only_files | join(" ")' "$GRANT")"
dropped() { field ".dropped[] | select(.path == \"$1\") | .reason" "$GRANT" | /usr/bin/tr '\n' '|'; }
check "a missing folder is left out"           "not on this Mac|" "$(dropped "$WORK/nowhere")"
check "a link is not granted for writing, only for reading" "a link, or reached through one: not granted for writing|" "$(dropped "$WORK/link")"
check "a file is not a folder"                 "not a folder|" "$(dropped "$WORK/tools/settings.conf")"
check "a folder is not a file, and a missing file is left out" "not a file|not on this Mac|" "$(dropped "$WORK/tools")$(dropped "$WORK/nofile")"
if [ -d "$HOME/DOCUMENTS" ]; then
    check "a folder spelled in another case is granted under its own name" "$HOME_REAL/Documents" "$(field '.read_only[0]' "$(write_pack spelled '"title": "T", "read_only": ["~/DOCUMENTS"]')")"
fi
REQ="$(write_pack req "\"title\": \"T\", \"read_only\": [\"$WORK/tools\"], \"requires\": [\"$WORK/tools\", \"$WORK/not-installed\"]")"
check "something required is missing: not installed" "not-installed: $WORK/not-installed is not on this Mac" "$(field '.state + ": " + .reason' "$REQ")"
check "  and nothing is granted"               "0" "$(field '.read_only | length' "$REQ")"

section "user packs"
packs_list() { "$PY" -B "$PACKS_PY" list --bundle "$WORK/fake-app" --user-dir "$USER_PACKS" "$@" 2>&1; }
/bin/mkdir -p "$USER_PACKS"
/bin/cp "$SEEDS/homebrew.json" "$WORK/fake-app/Contents/Resources/SandboxPacks/"
printf '{"formatVersion": 1, "id": "mine", "title": "Mine", "read_only": ["%s"]}\n' "$WORK/tools" > "$USER_PACKS/mine.json"
: > "$USER_PACKS/.hidden.json"
printf 'note\n' > "$USER_PACKS/readme.txt"
check "the list has the seed pack and the user's" "homebrew:seed mine:user" "$(packs_list | /usr/bin/jq -r '[.[] | .id + ":" + .source] | join(" ")')"
printf '{"formatVersion": 1, "id": "homebrew", "title": "My Homebrew", "read_only": ["%s"]}\n' "$WORK/brew" > "$USER_PACKS/homebrew.json"
check "a user pack with a seed pack's id replaces it" "user|My Homebrew|1" "$(packs_list | /usr/bin/jq -r '[.[] | select(.id == "homebrew")] | (.[0].source + "|" + .[0].title + "|" + (length | tostring))')"
printf 'broken\n' > "$USER_PACKS/homebrew.json"
check "  also when it is invalid: the seed pack does not come back" "user|invalid" "$(packs_list | /usr/bin/jq -r '.[] | select(.id == "homebrew") | .source + "|" + .state')"
/bin/rm -f "$USER_PACKS/homebrew.json"

section "the Local server's sandbox with ticked packs"
generate() {
    ( PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE
      cad_call_lib aichat.mcp.servers.library.sh generate_stdio_mcp_config "$CFG" "$@" 2>&1 )
}
server_args() { /usr/bin/jq -r --arg n "$2" '.servers[] | select(.name == $n) | .args[]' "$1" 2>/dev/null; }
profile_of() { server_args "$1" local | /usr/bin/awk 'take { print; exit } $0 == "--sandbox-profile" { take = 1 }'; }
names() { /usr/bin/jq -r '[.servers[].name] | join(" ")' "$1" 2>/dev/null; }
in_profile() { /usr/bin/jq --arg p "$2" "[.$1[]? | select(. == \$p)] | length" "$(profile_of "$CFG")" 2>/dev/null; }
tick() {
    "$PLISTER" delete "$SUPPORT/settings.plist" /servers/local/packs >/dev/null 2>&1
    "$PLISTER" insert packs array "$SUPPORT/settings.plist" /servers/local >/dev/null 2>&1
    for _id in "$@"; do
        "$PLISTER" append string "$_id" "$SUPPORT/settings.plist" /servers/local/packs >/dev/null 2>&1
    done
}
cad_reset
cad_call mcp_prefs_write_defaults >/dev/null 2>&1
cad_call mcp_prefs_set_string servers/local/project "$WORK/project"
cad_call mcp_prefs_set_bool allow-network false
/bin/mkdir -p "$USER_PACKS"
printf '{"formatVersion": 1, "id": "mine", "title": "Mine", "read_only": ["%s", "$PROJECT/../nowhere-at-all"], "read_write": ["%s", "$PROJECT"], "read_only_files": ["~/.gitconfig"]}\n' "$WORK/tools" "$WORK/build" > "$USER_PACKS/mine.json"
/usr/bin/sed -i '' 's|"\$PROJECT/\.\./nowhere-at-all"|"'"$WORK"'/nowhere-at-all"|' "$USER_PACKS/mine.json"
printf '{"formatVersion": 1, "id": "greedy", "title": "Greedy", "read_only": ["%s", "~/.ssh"]}\n' "$WORK/target" > "$USER_PACKS/greedy.json"
printf '{"formatVersion": 1, "id": "odd", "title": "Odd", "read_only": ["%s", "/nowhere/x\\udc80", "$DARWIN_USER_TEMP_DIR/x\\ud800"]}\n' "$WORK/target" > "$USER_PACKS/odd.json"

# A pack that uses another, which uses a third and, to close a ring, the first; one that is not
# installed; and one that is not there.
/bin/mkdir -p "$WORK/chain-a" "$WORK/chain-b" "$WORK/chain-c"
printf '{"formatVersion": 1, "id": "chain-a", "title": "Chain A", "read_only": ["%s"], "uses": ["chain-b", "absent-pack", "away-pack"]}\n' "$WORK/chain-a" > "$USER_PACKS/chain-a.json"
printf '{"formatVersion": 1, "id": "chain-b", "title": "Chain B", "read_write": ["%s"], "uses": ["chain-c"]}\n' "$WORK/chain-b" > "$USER_PACKS/chain-b.json"
printf '{"formatVersion": 1, "id": "chain-c", "title": "Chain C", "read_only": ["%s"], "uses": ["chain-a"]}\n' "$WORK/chain-c" > "$USER_PACKS/chain-c.json"
printf '{"formatVersion": 1, "id": "away-pack", "title": "Away", "read_only": ["%s"], "requires": ["%s/not-here"]}\n' "$WORK/target" "$WORK" > "$USER_PACKS/away-pack.json"

generate >/dev/null
check "with no pack ticked: the three servers" "local pdf time" "$(names "$CFG")"
BASE_SUM="$(/usr/bin/shasum "$(profile_of "$CFG")" | /usr/bin/cut -d' ' -f1)"
check "  and no pack folder in the profile"    "0|0" "$(in_profile read_only "$WORK/tools")|$(in_profile read_write "$WORK/build")"
check "the system's program folders are always readable, so a tool can look for another" "1|1|1|1" \
    "$(in_profile read_only /bin)|$(in_profile read_only /sbin)|$(in_profile read_only /usr/bin)|$(in_profile read_only /usr/sbin)"

tick mine
OUT="$(generate)"
check "a ticked pack: replay still starts"     "local pdf time" "$(names "$CFG")"
check "  its folder to read is in the profile" "1" "$(in_profile read_only "$WORK/tools")"
check "  and its file to read"                 "1" "$(in_profile read_only "$HOME_REAL/.gitconfig")"
check "  its folder to write is read-write"    "1|0" "$(in_profile read_write "$WORK/build")|$(in_profile read_only "$WORK/build")"
check "  the project stays replay's one --allow-write" "$WORK/project" "$(server_args "$CFG" local | /usr/bin/awk 'take { print; exit } $0 == "--allow-write" { take = 1 }')"
check "  and is not repeated in the profile"   "0" "$(in_profile read_write "$WORK/project")"
check "  a path that is not there is named in the log" "1" "$(cad_has "$OUT" "nowhere-at-all left out (not on this Mac)")"
check "the PDF server's roots are not widened" "0" "$(server_args "$CFG" pdf | /usr/bin/grep -c -e "^$WORK/tools\$" -e "^$WORK/build\$")"
check "the settings' own lists are untouched"  "0" "$(/usr/bin/grep -c "sandbox-packs/tools" "$SUPPORT/settings.plist")"

tick greedy nosuch odd mine mine
OUT="$(generate)"
check "a pack whose path cannot be written to the log grants nothing" "1" "$(cad_has "$OUT" "sandbox pack 'odd' grants nothing")"
check "a pack that asks for keys grants nothing" "0|0" "$(in_profile read_only "$WORK/target")|$(in_profile read_only "$HOME_REAL/.ssh")"
check "  and the log says why"                 "1" "$(cad_has "$OUT" "sandbox pack 'greedy' grants nothing")"
check "  a ticked id with no pack is named too" "1" "$(cad_has "$OUT" "'nosuch' is ticked but there is no such pack")"
check "  the good pack beside them still applies, once" "1|1" "$(in_profile read_only "$WORK/tools")|$(in_profile read_write "$WORK/build")"

tick chain-a
said="$(generate 2>&1)"
check "a ticked pack brings the packs it uses, and theirs" "1|1|1" \
    "$(in_profile read_only "$WORK/chain-a")|$(in_profile read_write "$WORK/chain-b")|$(in_profile read_only "$WORK/chain-c")"
check "  a used pack that is not installed grants nothing, and the log says who uses it" "0|1" \
    "$(in_profile read_only "$WORK/target")|$(cad_has "$said" "'away-pack' (used by 'Chain A') grants nothing")"
check "  and one that is not there is said to be missing" "1" "$(cad_has "$said" "'absent-pack' is used by 'Chain A' but there is no such pack")"
tick chain-c
generate >/dev/null
check "a ring of packs ends: each is taken once" "1|1|1" \
    "$(in_profile read_only "$WORK/chain-a")|$(in_profile read_write "$WORK/chain-b")|$(in_profile read_only "$WORK/chain-c")"

check "  and the servers start"                "local pdf time" "$(names "$CFG")"

/bin/rm -rf "$WORK/build"
/bin/ln -s "$HOME/Documents" "$WORK/build"
generate >/dev/null
check "a folder to write that became a link is no longer granted" "0|0" "$(in_profile read_write "$WORK/build")|$(in_profile read_write "$HOME_REAL/Documents")"
/bin/rm -f "$WORK/build"
/bin/mkdir -p "$WORK/build"

tick
generate >/dev/null
check "nothing ticked again: the profile is as it was" "$BASE_SUM" "$(/usr/bin/shasum "$(profile_of "$CFG")" | /usr/bin/cut -d' ' -f1)"
"$PLISTER" delete "$SUPPORT/settings.plist" /servers/local/packs >/dev/null 2>&1
"$PLISTER" set string "xcode" "$SUPPORT/settings.plist" /servers/local/packs >/dev/null 2>&1 || "$PLISTER" insert packs string "xcode" "$SUPPORT/settings.plist" /servers/local >/dev/null 2>&1
generate >/dev/null
check "a setting that is not a list ticks nothing" "$BASE_SUM" "$(/usr/bin/shasum "$(profile_of "$CFG")" | /usr/bin/cut -d' ' -f1)"

check "no bytecode was left in the application" "0" "$(/usr/bin/find "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts" -name '__pycache__' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

/bin/rm -rf "$WORK"
omctest_end

#!/usr/bin/env bash
# Checks the installer and the hook gate inside a throwaway HOME.
# Never touches your real ~/.claude. Needs jq.
# The check strings are evaluated lazily on purpose, so shellcheck sees their variables as unused.
# shellcheck disable=SC2016,SC2034
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aidw-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bundle"
(cd "$REPO" && tar --exclude=.git -cf - .) | tar -xf - -C "$WORK/bundle"

H="$WORK/home/.claude"
B="$WORK/bin"
mkdir -p "$H" "$B"
printf '{"theme":"dark","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/usr/bin/true"}]}]}}\n' >"$H/settings.json"
printf '# my CLAUDE.md\n\n## Output Style\n\nterse\n' >"$H/CLAUDE.md"

fail=0
ok() { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

INSTALL="$WORK/bundle/install.sh"
OPTS=(--claude-home "$H" --bin-dir "$B")

echo "installer"
before="$(cksum "$H/settings.json" "$H/CLAUDE.md")"
"$INSTALL" "${OPTS[@]}" >/dev/null
check "dry run writes nothing" '[ "$(cksum "$H/settings.json" "$H/CLAUDE.md")" = "$before" ]'

"$INSTALL" "${OPTS[@]}" --apply >/dev/null
check "apply adds the three PACS hooks" '[ "$(jq "[.hooks[][].hooks[].command | select(test(\"pacs-\"))] | length" "$H/settings.json")" = 3 ]'
check "apply keeps the existing hook and other keys" 'jq -e ".theme == \"dark\" and ([.hooks.SessionStart[].hooks[].command] | index(\"/usr/bin/true\"))" "$H/settings.json" >/dev/null'
check "apply links pacs" '[ -L "$B/pacs" ]'
check "apply appends the PACS section" 'grep -q "^## PACS" "$H/CLAUDE.md"'
check "apply backs up both files" '[ "$(ls "$H"/*.bak.* | wc -l | tr -d " ")" = 2 ]'

"$INSTALL" "${OPTS[@]}" --apply >/dev/null
check "second apply adds nothing" '[ "$(jq "[.hooks[][].hooks[].command | select(test(\"pacs-\"))] | length" "$H/settings.json")" = 3 ]'

echo "installer edge cases"
E="$WORK/edge"
mkdir -p "$E/empty" "$E/mode" "$E/bad" "$E/matcher" "$E/lookalike"
EB="$E/bin"
mkdir -p "$EB"

: >"$E/empty/settings.json"
"$INSTALL" --claude-home "$E/empty" --bin-dir "$EB" --apply >/dev/null
check "an empty settings.json still gets the three hooks" '[ "$(jq "[.hooks[][].hooks[].command] | length" "$E/empty/settings.json")" = 3 ]'

printf '{"theme":"dark"}\n' >"$E/mode/settings.json"
chmod 644 "$E/mode/settings.json"
"$INSTALL" --claude-home "$E/mode" --bin-dir "$EB" --apply >/dev/null
check "file mode of settings.json is preserved" '[ "$(stat -c %a "$E/mode/settings.json" 2>/dev/null || stat -f %Lp "$E/mode/settings.json")" = 644 ]'

printf '{ not json' >"$E/bad/settings.json"
"$INSTALL" --claude-home "$E/bad" --bin-dir "$EB" --apply >/dev/null 2>&1; rc=$?
check "invalid JSON is refused and left untouched" '[ "$rc" != 0 ] && [ "$(cat "$E/bad/settings.json")" = "{ not json" ]'

printf '{"hooks":{"PreToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"%s/pacs/pacs-hooks/hooks/pacs-enforce-read.sh"}]}]}}\n' "$WORK/bundle" >"$E/matcher/settings.json"
"$INSTALL" --claude-home "$E/matcher" --bin-dir "$EB" --apply >/dev/null
check "same command under a narrower matcher still gets the full matcher" 'jq -e "[.hooks.PreToolUse[] | select(.matcher == \"Edit|Write|MultiEdit\")] | length == 1" "$E/matcher/settings.json" >/dev/null'

printf '## PACSomething\n' >"$E/lookalike/CLAUDE.md"
"$INSTALL" --claude-home "$E/lookalike" --bin-dir "$EB" --apply >/dev/null
check "a heading that merely starts with PACS does not count as the section" '[ "$(grep -c "^## PACS" "$E/lookalike/CLAUDE.md")" = 2 ]'

"$INSTALL" --claude-home --apply >/dev/null 2>&1; rc=$?
check "--claude-home refuses a flag as its value" '[ "$rc" = 2 ]'

echo
echo "hook gate"
G="$WORK/bundle/pacs/pacs-hooks/hooks"
P="$WORK/proj"
mkdir -p "$P/sub"
cp "$WORK/bundle/pacs/test/fixture/AGENTS.md" "$P/AGENTS.md"
payload() { printf '{"cwd":"%s"}' "$1"; }
read_payload() { printf '{"cwd":"%s","tool_input":{"file_path":"%s/AGENTS.md"%s}}' "$P" "$P" "$1"; }

payload "$P" | "$G/pacs-enforce-read.sh" >/dev/null 2>&1; rc=$?
check "edit is blocked before the registry is read (exit 2)" '[ "$rc" = 2 ]'

read_payload ',"limit":5' | "$G/pacs-mark-read.sh"
payload "$P" | "$G/pacs-enforce-read.sh" >/dev/null 2>&1; rc=$?
check "a partial read does not clear the gate" '[ "$rc" = 2 ]'

read_payload '' | "$G/pacs-mark-read.sh"
payload "$P" | "$G/pacs-enforce-read.sh" >/dev/null 2>&1; rc=$?
check "a full read clears the gate" '[ "$rc" = 0 ]'

payload "$P" | "$G/pacs-reset-marker.sh"
payload "$P" | "$G/pacs-enforce-read.sh" >/dev/null 2>&1; rc=$?
check "SessionStart (compaction) blocks again" '[ "$rc" = 2 ]'

payload "$P/sub" | "$G/pacs-enforce-read.sh" >/dev/null 2>&1; rc=$?
check "a session that has cd'd into a subfolder is still gated (exit 2)" '[ "$rc" = 2 ]'

echo
if [ "$fail" -eq 0 ]; then echo "all checks passed"; else echo "$fail check(s) failed"; exit 1; fi

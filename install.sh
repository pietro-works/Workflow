#!/usr/bin/env bash
# Install the bundle: PACS hooks, the pacs CLI link, and the PACS section of CLAUDE.md.
# Dry run by default. Nothing is written until you pass --apply.
set -euo pipefail

BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLAUDE_HOME="${HOME}/.claude"
BIN_DIR="${HOME}/.local/bin"
APPLY=0
WITH_HEADROOM=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--apply] [--with-headroom] [--claude-home DIR] [--bin-dir DIR]

  --apply            write changes (default is a dry run that only prints the plan)
  --with-headroom    also run `headroom init -g claude` if headroom is installed
  --claude-home DIR  Claude config directory (default: ~/.claude)
  --bin-dir DIR      where to link the pacs command (default: ~/.local/bin)

Steps, in order:
  1. add the three PACS hooks to settings.json (existing hooks are kept, reruns add nothing)
  2. link pacs into the bin directory
  3. append the PACS section to CLAUDE.md if it has none
  4. optionally hand off to headroom's own installer
Every file that gets modified is backed up next to itself first.
EOF
}

need_value() {
  case "${2:-}" in
    "" | -*) echo "$1 needs a directory, got: ${2:-nothing}" >&2; exit 2 ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --with-headroom) WITH_HEADROOM=1 ;;
    --claude-home) need_value "$1" "${2:-}"; CLAUDE_HOME="$2"; shift ;;
    --bin-dir) need_value "$1" "${2:-}"; BIN_DIR="$2"; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
act() { if [ "$APPLY" -eq 1 ]; then say "  do:    $*"; else say "  would: $*"; fi; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SETTINGS="$CLAUDE_HOME/settings.json"
CLAUDE_MD="$CLAUDE_HOME/CLAUDE.md"

# Copy a file to <file>.bak.<stamp>, adding a counter if that name is taken. Prints the path.
backup() {
  local f="$1" b="$1.bak.$STAMP" n=1
  while [ -e "$b" ]; do
    b="$f.bak.$STAMP.$n"
    n=$((n + 1))
  done
  cp -p "$f" "$b"
  printf '%s' "$b"
}

say "bundle:      $BUNDLE"
say "claude home: $CLAUDE_HOME"
say "bin dir:     $BIN_DIR"
say "mode:        $([ "$APPLY" -eq 1 ] && echo APPLY || echo "dry run")"
say ""

# 0. preflight
missing=()
for tool in jq rg yq; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ "${#missing[@]}" -gt 0 ]; then
  formulas=()
  for tool in "${missing[@]}"; do
    case "$tool" in rg) formulas+=(ripgrep) ;; *) formulas+=("$tool") ;; esac
  done
  say "missing tools: ${missing[*]}  (try: brew install ${formulas[*]})"
  [ "$APPLY" -eq 1 ] && exit 1
  say "continuing because this is a dry run"
  say ""
fi
case "$BUNDLE" in
  *[!A-Za-z0-9._/+@:-]*)
    say "warning: the bundle path has characters that are unsafe in an unquoted hook command"
    say "         (spaces, quotes, ; & | \$ and similar). Clone to a plainer path before --apply."
    [ "$APPLY" -eq 1 ] && exit 1
    say ""
    ;;
esac
if [ "$APPLY" -eq 1 ]; then
  mkdir -p "$CLAUDE_HOME" "$BIN_DIR"
fi

# 1. hooks
say "[1/4] PACS hooks -> $SETTINGS"
if ! command -v jq >/dev/null 2>&1; then
  say "  skipped: jq is required"
else
  new_hooks="$(jq --arg b "$BUNDLE" 'walk(if type == "string" then gsub("\\{\\{BUNDLE\\}\\}"; $b) else . end)' "$BUNDLE/hooks/settings.hooks.json")"
  base='{}'
  if [ -s "$SETTINGS" ] && grep -q '[^[:space:]]' "$SETTINGS"; then
    base="$(cat "$SETTINGS")"
    if ! printf '%s' "$base" | jq -e . >/dev/null 2>&1; then
      say "  error: $SETTINGS is not valid JSON. Leaving it alone."
      exit 1
    fi
  fi
  merged="$(printf '%s' "$base" | jq --argjson new "$new_hooks" '
    def pairs: [ .[]? | (.matcher // "") as $m | .hooks[]? | {m: $m, c: .command} ];
    reduce ($new.hooks | to_entries[]) as $e (.;
      .hooks[$e.key] = (
        (.hooks[$e.key] // []) as $cur
        | ($cur | pairs) as $have
        | $cur + [ $e.value[]
            | select((.matcher // "") as $m | .hooks[0].command as $c
                     | ($have | any(.m == $m and .c == $c)) | not) ]
      ))')"
  if [ -z "$merged" ]; then
    say "  error: merge produced no output. Leaving settings alone."
    exit 1
  fi
  count() { jq '[(.hooks // {})[] | length] | add // 0'; }
  before="$(printf '%s' "$base" | count)"
  after="$(printf '%s' "$merged" | count)"
  added=$((after - before))

  stale="$(printf '%s' "$base" | jq -r --arg b "$BUNDLE/pacs/pacs-hooks/hooks/" '
    [ .hooks[]?[]?.hooks[]?.command
      | select(test("/pacs-(reset-marker|mark-read|enforce-read)\\.sh$"))
      | select(startswith($b) | not) ] | unique[]?')"
  if [ -n "$stale" ]; then
    say "  note: PACS hooks from another location are already wired and will run alongside these:"
    printf '%s\n' "$stale" | sed 's/^/        /'
  fi

  if [ "$added" -eq 0 ]; then
    say "  already wired, nothing to add"
  else
    act "add $added hook entr$([ "$added" -eq 1 ] && echo y || echo ies) (existing hooks untouched)"
    if [ "$APPLY" -eq 1 ]; then
      target="$SETTINGS"
      [ -L "$SETTINGS" ] && target="$(readlink -f "$SETTINGS" 2>/dev/null || echo "$SETTINGS")"
      mode=600
      if [ -f "$target" ]; then
        mode="$(stat -c %a "$target" 2>/dev/null || stat -f %Lp "$target")"
        bak="$(backup "$target")"
        say "  backup: $bak"
      fi
      tmp="$(mktemp "$(dirname "$target")/settings.json.XXXXXX")"
      printf '%s\n' "$merged" >"$tmp"
      jq -e . "$tmp" >/dev/null
      chmod "$mode" "$tmp"
      mv "$tmp" "$target"
    fi
  fi
fi

# 2. pacs command
say "[2/4] pacs command -> $BIN_DIR/pacs"
target="$BUNDLE/pacs/bin/pacs"
link="$BIN_DIR/pacs"
if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
  say "  already linked"
elif [ -L "$link" ] && [ ! -e "$link" ]; then
  say "  left alone: $link is a dangling symlink to $(readlink "$link"). Remove it and rerun."
elif [ -L "$link" ]; then
  say "  left alone: $link already points to $(readlink "$link")"
elif [ -e "$link" ]; then
  say "  left alone: $link is a regular file"
else
  act "ln -s $target $link"
  if [ "$APPLY" -eq 1 ]; then
    ln -s "$target" "$link"
  fi
fi

# 3. CLAUDE.md
say "[3/4] PACS section -> $CLAUDE_MD"
if [ ! -f "$CLAUDE_MD" ]; then
  say "  no CLAUDE.md there. Copy instructions/CLAUDE.md to adopt the full set."
elif rg -q '^## PACS( |$)' "$CLAUDE_MD"; then
  say "  PACS section already present"
else
  section="$(awk '/^## PACS/ { p = 1; print; next } p && /^## / { exit } p' "$BUNDLE/instructions/CLAUDE.md")"
  act "append the PACS section ($(printf '%s\n' "$section" | wc -l | tr -d ' ') lines)"
  if [ "$APPLY" -eq 1 ]; then
    bak="$(backup "$CLAUDE_MD")"
    say "  backup: $bak"
    printf '\n%s\n' "$section" >>"$CLAUDE_MD"
  fi
fi

# 4. headroom
say "[4/4] headroom"
if [ "$WITH_HEADROOM" -eq 0 ]; then
  say "  skipped (pass --with-headroom to run its own installer)"
elif [ "$CLAUDE_HOME" != "${HOME}/.claude" ]; then
  say "  skipped: headroom writes to the real ~/.claude and --claude-home points elsewhere"
elif command -v headroom >/dev/null 2>&1; then
  act "headroom init -g claude"
  [ "$APPLY" -eq 1 ] && headroom init -g claude
else
  say "  headroom is not installed, nothing to do"
fi

say ""
if [ "$APPLY" -eq 1 ]; then
  say "done. Start a new Claude Code session so the hooks load."
else
  say "dry run only. Re-run with --apply to make these changes."
fi

# Functions shared by the g:graphify:* tasks (sourced, not a task).
#
# Everything graphify needs lives in the repository, but stays out of version control:
# the paths below are listed in a marked block of .git/info/exclude (never committed).
# The only change a teammate can see is one import line appended to an existing CLAUDE.md.

GRAPHIFY_EXCLUDE_BEGIN='# >>> graphify (mise run graph)'
GRAPHIFY_EXCLUDE_END='# <<< graphify'
# Agent instructions written by graphify, imported from CLAUDE.md.
GRAPHIFY_MD='.claude/graphify.md'
# The line appended to CLAUDE.md. A missing import is skipped by Claude Code.
GRAPHIFY_IMPORT="Local graphify setup (ignore if the file is missing): @$GRAPHIFY_MD"
# jq: true for a hook group that runs a graphify hook command
GRAPHIFY_JQ_IS_OURS='def ours: (.hooks // []) | any((.command // "") | test("graphify hook-"));'

# Moves to the top of the git repository the task was started from (global tasks start in ~).
graphify_enter_repo() {
  cd "${MISE_ORIGINAL_CWD:-$PWD}" || exit 1
  if ! repo="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    echo "not inside a git repository: $PWD" >&2
    exit 1
  fi
  cd "$repo" || exit 1
  exclude_file="$(git rev-parse --git-path info/exclude)"
}

# Prints the paths listed in our exclude block, one per line.
graphify_excluded() {
  [[ -f "$exclude_file" ]] || return 0
  sed -n "/^$GRAPHIFY_EXCLUDE_BEGIN\$/,/^$GRAPHIFY_EXCLUDE_END\$/p" "$exclude_file" | grep -v '^#' || true
}

# Removes our block from .git/info/exclude.
graphify_exclude_remove() {
  [[ -f "$exclude_file" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  sed "/^$GRAPHIFY_EXCLUDE_BEGIN\$/,/^$GRAPHIFY_EXCLUDE_END\$/d" "$exclude_file" >"$tmp"
  cat "$tmp" >"$exclude_file"
  rm -f "$tmp"
}

# Replaces our block in .git/info/exclude with the given paths.
graphify_exclude_write() {
  graphify_exclude_remove
  mkdir -p "$(dirname "$exclude_file")"
  {
    echo "$GRAPHIFY_EXCLUDE_BEGIN"
    printf '%s\n' "$@"
    echo "$GRAPHIFY_EXCLUDE_END"
  } >>"$exclude_file"
}

# Removes the import line from CLAUDE.md; deletes the file when nothing else is left in it.
graphify_claude_md_unlink() {
  [[ -f CLAUDE.md ]] || return 0
  local tmp
  tmp="$(mktemp)"
  grep -vxF -- "$GRAPHIFY_IMPORT" CLAUDE.md >"$tmp" || true
  if ! grep -q '[^[:space:]]' "$tmp"; then
    rm -f CLAUDE.md "$tmp"
    echo "removed: CLAUDE.md"
    return 0
  fi
  # Drop the blank line the install added before the import
  sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp" >CLAUDE.md
  rm -f "$tmp"
}

# Removes the graphify hooks from .claude/settings.local.json; deletes the file when it ends up empty.
graphify_hooks_remove() {
  local file=.claude/settings.local.json tmp
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)"
  jq "$GRAPHIFY_JQ_IS_OURS"'
    if .hooks then
      .hooks |= (map_values(map(select(ours | not))) | with_entries(select(.value | length > 0)))
      | if .hooks == {} then del(.hooks) else . end
    else . end' "$file" >"$tmp"
  if [[ "$(jq -c . "$tmp")" == "{}" ]]; then
    rm -f "$file" "$tmp"
  else
    mv "$tmp" "$file"
  fi
}

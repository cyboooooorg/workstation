#!/usr/bin/env bash
# Claude Code PreToolUse hook (Bash): keeps the agent off the default branch.
#
# Denies:
#   - a push to the default branch (explicit refspec, or the current branch when it is the
#     default one and no refspec is given);
#   - a force push without --force-with-lease (--force, -f, or a +refspec);
#   - a `git merge` while the default branch is checked out.
# Allows everything else, merging a pull request on the forge (`gh pr merge`, `glab mr merge`)
# included: when to merge stays the user's decision, written in each project's instructions.
#
# The default branch is origin/HEAD, else main or master. A command is split on && || ; |,
# and a `cd` moves the following parts. After a `git checkout` or `git switch` in the same
# command, the current branch is no longer known: only explicit refspecs are checked.
#
# Written for bash 3.2 (macOS /bin/bash) and BSD tools. Needs jq and git.
set -u

input=$(cat)
[ "$(jq -r '.tool_name // empty' <<<"$input")" = "Bash" ] || exit 0
command=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$command" ] || exit 0
[ -n "$cwd" ] || cwd=$PWD

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Default branch of the repository at $1: origin/HEAD, else main or master.
default_branch() {
  local ref b
  if ref=$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null); then
    echo "${ref#origin/}"
    return
  fi
  for b in main master; do
    if git -C "$1" show-ref --verify --quiet "refs/heads/$b"; then
      echo "$b"
      return
    fi
  done
}

# Absolute path of $1, relative to $2 when it is not absolute ("~" is expanded).
resolve() {
  local path=$1
  path=${path#[\"\']}
  path=${path%[\"\']}
  case "$path" in
    \~) path=$HOME ;;
    \~/*) path="$HOME/${path#\~/}" ;;
  esac
  case "$path" in
    /*) echo "$path" ;;
    *) echo "$2/$path" ;;
  esac
}

# Start of a command: optional subshell or group, VAR=value assignments, wrappers.
PREFIX='^[[:space:]]*[({]*[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*((command|env|sudo|exec|builtin) +)*'
GIT="${PREFIX}git( +(-c|-C) +[^ ]+)*"

switched=0
while IFS= read -r seg; do
  [ -n "$seg" ] || continue

  if grep -Eq "${PREFIX}cd( |\$)" <<<"$seg"; then
    target=$(sed -nE 's/.*cd +([^ ]+).*/\1/p' <<<"$seg")
    [ -n "$target" ] || target=$HOME
    [ "$target" = "-" ] || cwd=$(resolve "$target" "$cwd")
    continue
  fi

  if grep -Eq "$GIT +(checkout|switch)( |\$)" <<<"$seg"; then
    switched=1
    continue
  fi

  is_push=0
  is_merge=0
  grep -Eq "$GIT +push( |\$)" <<<"$seg" && is_push=1
  grep -Eq "$GIT +merge( |\$)" <<<"$seg" && is_merge=1
  [ $is_push = 1 ] || [ $is_merge = 1 ] || continue

  dir=$cwd
  c=$(sed -nE 's/.*git( +-c +[^ ]+)* +-C +([^ ]+).*/\2/p' <<<"$seg")
  [ -z "$c" ] || dir=$(resolve "$c" "$cwd")

  if [ $is_push = 1 ]; then
    # positional arguments after "push": [remote [refspec...]]
    args=$(sed -E 's/.* push( |$)//' <<<"$seg" | tr ' ' '\n' | grep -v '^-' | grep -v '^$')
    if ! grep -Eq -- '(^| )--force-with-lease' <<<"$seg"; then
      if grep -Eq -- '(^| )(--force|-[[:alpha:]]*f[[:alpha:]]*)( |$)' <<<"$seg" ||
        grep -q '^+' <<<"$args"; then
        deny "Force pushes are blocked. Use git push --force-with-lease instead."
      fi
    fi
    [ -d "$dir" ] || continue
    def=$(default_branch "$dir")
    [ -n "$def" ] || continue
    cur=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || true)
    npos=$(grep -c . <<<"$args" || true)
    if grep -Eq "^(\+?(refs/heads/)?$def|[^:]*:(refs/heads/)?$def)\$" <<<"$args" ||
      { [ $switched = 0 ] && [ "$cur" = "$def" ] && [ "$npos" -le 1 ]; }; then
      deny "Pushing to the default branch ($def) is blocked. Push a branch and open a pull request."
    fi
  fi

  if [ $is_merge = 1 ]; then
    grep -Eq '(^| )(--help|-h)( |$)' <<<"$seg" && continue
    [ $switched = 0 ] || continue
    [ -d "$dir" ] || continue
    cur=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || continue
    def=$(default_branch "$dir")
    if [ -n "$def" ] && [ "$cur" = "$def" ]; then
      deny "git merge on the default branch ($def) is blocked. Merge in a branch, or merge the pull request on the forge."
    fi
  fi
done < <(awk '{ gsub(/&&|\|\||;|\|/, "\n"); print }' <<<"$command")
exit 0

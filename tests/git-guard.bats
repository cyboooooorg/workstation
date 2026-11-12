#!/usr/bin/env bats
# Tests for claude/hooks/git-guard.sh: allowed and denied git commands.
HOOK=$BATS_TEST_DIRNAME/../claude/hooks/git-guard.sh

setup_file() {
  # r: main checkout on main; wt: worktree on feat; other: repository without main
  R=$BATS_FILE_TMPDIR/r
  git init -q -b main "$R"
  git -C "$R" -c user.email=a@b -c user.name=a commit -q --allow-empty -m init
  git -C "$R" worktree add -q "$BATS_FILE_TMPDIR/wt" -b feat
  mkdir "$BATS_FILE_TMPDIR/plain"
}

# decision <command> <cwd relative to the test directory> [tool]
decision() {
  local json out
  json=$(jq -nc --arg k "$1" --arg c "$BATS_FILE_TMPDIR/$2" --arg t "${3:-Bash}" \
    '{tool_name: $t, cwd: $c, tool_input: {command: $k}}')
  out=$("$HOOK" <<<"$json") || { echo "error"; return; }
  if jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 <<<"$out"; then
    echo deny
  else
    echo allow
  fi
}
check() {
  local got
  got=$(decision "$2" "$3" "${4:-}")
  [ "$got" = "$1" ] || { echo "expected $1, got $got for: $2 (in $3)"; return 1; }
}

# Push to the default branch
@test "push on main: denied" { check deny 'git push' r; }
@test "push origin on main: denied" { check deny 'git push origin' r; }
@test "push origin main from a branch: denied" { check deny 'git push origin main' wt; }
@test "push HEAD:main from a branch: denied" { check deny 'git push origin HEAD:main' wt; }
@test "push +main from a branch: denied" { check deny 'git push origin +main' wt; }
@test "push refs/heads/main from a branch: denied" { check deny 'git push origin feat:refs/heads/main' wt; }
@test "git -C main checkout push: denied" { check deny "git -C $BATS_FILE_TMPDIR/r push" wt; }
@test "cd to main checkout then push: denied" { check deny "cd $BATS_FILE_TMPDIR/r && git push" wt; }
@test "push behind env and command prefixes: denied" { check deny 'GIT_TRACE=0 command git push origin main' wt; }
@test "push -u origin feat: allowed" { check allow 'git push -u origin feat' wt; }
@test "push on a branch: allowed" { check allow 'git push' wt; }
@test "push feat:feat from main: allowed" { check allow 'git push origin feat:feat' r; }
@test "cd to a branch worktree then push: allowed" { check allow "cd $BATS_FILE_TMPDIR/wt && git push" r; }
@test "cd ~ then push: allowed" { HOME=$BATS_FILE_TMPDIR/wt check allow 'cd ~ && git push' r; }

# Force pushes
@test "push -f: denied" { check deny 'git push -f origin feat' wt; }
@test "push --force: denied" { check deny 'git push --force origin feat' wt; }
@test "push -uf: denied" { check deny 'git push -uf origin feat' wt; }
@test "push +feat: denied" { check deny 'git push origin +feat' wt; }
@test "push --force-with-lease: allowed" { check allow 'git push --force-with-lease origin feat' wt; }
@test "push -f with --force-with-lease: allowed" { check allow 'git push -f --force-with-lease origin feat' wt; }

# Merges on the default branch
@test "merge on main: denied" { check deny 'git merge feat' r; }
@test "git -C main checkout merge: denied" { check deny "git -C $BATS_FILE_TMPDIR/r merge feat" wt; }
@test "merge after a pipe on main: denied" { check deny 'true | git merge feat' r; }
@test "merge on a branch: allowed" { check allow 'git merge main' wt; }
@test "merge --help on main: allowed" { check allow 'git merge --help' r; }

# The develop cycle of map-generator, started from main
@test "rebuild develop then merge, from main: allowed" {
  check allow 'git fetch origin && git checkout -B develop origin/main && git merge --no-ff origin/feat' r
}
@test "switch then merge, from main: allowed" { check allow 'git switch develop; git merge feat' r; }
@test "reset develop to main: allowed" { check allow 'git push --force-with-lease origin origin/main:develop' r; }
@test "push develop with lease from main: allowed" { check allow 'git push --force-with-lease origin develop' r; }

# Merging a pull request on the forge stays allowed (with the user's approval)
@test "gh pr merge: allowed" { check allow 'gh pr merge 12 --merge --subject "feat: x (#12)"' r; }
@test "glab mr merge: allowed" { check allow 'glab mr merge 12' r; }

# Out of scope
@test "git push quoted in echo: allowed" { check allow 'echo git push -f origin main' r; }
@test "outside git: allowed" { check allow 'git push origin main' plain; }
@test "another tool: allowed" { check allow 'git push -f' r Read; }
@test "empty command: allowed" { check allow '' r; }

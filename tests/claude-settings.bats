#!/usr/bin/env bats
# Tests for tasks/g/claude/settings: merge into an existing ~/.claude/settings.json.
TASK=$BATS_TEST_DIRNAME/../tasks/g/claude/settings
REPO=$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)

setup() {
  export CLAUDE_CONFIG_DIR=$BATS_TEST_TMPDIR/claude
  mkdir -p "$CLAUDE_CONFIG_DIR" "$BATS_TEST_TMPDIR/bin"
  # the task only needs `claude` to be installed
  printf '#!/bin/sh\n' >"$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  PATH=$BATS_TEST_TMPDIR/bin:$PATH
  FILE=$CLAUDE_CONFIG_DIR/settings.json
}
guard() { echo "$REPO/claude/hooks/git-guard.sh"; }
pretool_commands() { jq -c '[.hooks.PreToolUse[].hooks[].command]' "$FILE"; }

@test "creates the settings file" {
  "$TASK"
  [ "$(jq -r .env.CLAUDE_CODE_SUBAGENT_MODEL "$FILE")" = claude-sonnet-5-5 ]
  [ "$(pretool_commands)" = "[\"$(guard)\"]" ]
}

@test "keeps the other settings and hooks" {
  echo '{"theme":"dark","env":{"OTHER":"1"},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"herdr"}]}]}}' >"$FILE"
  "$TASK"
  [ "$(jq -r .theme "$FILE")" = dark ]
  [ "$(jq -r .env.OTHER "$FILE")" = 1 ]
  [ "$(pretool_commands)" = "[\"rtk hook claude\",\"$(guard)\"]" ]
  [ "$(jq -c '[.hooks.SessionStart[].hooks[].command]' "$FILE")" = '["herdr"]' ]
}

@test "a second run changes nothing" {
  echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]}}' >"$FILE"
  "$TASK"
  before=$(cat "$FILE")
  run "$TASK"
  [ "$output" = "up to date: $FILE" ]
  [ "$(cat "$FILE")" = "$before" ]
}

@test "replaces an edited entry of ours in place" {
  echo "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Edit\",\"hooks\":[{\"type\":\"command\",\"command\":\"$(guard)\"}]},{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"rtk hook claude\"}]}]}}" >"$FILE"
  "$TASK"
  [ "$(pretool_commands)" = "[\"$(guard)\",\"rtk hook claude\"]" ]
  [ "$(jq -r '.hooks.PreToolUse[0].matcher' "$FILE")" = Bash ]
}

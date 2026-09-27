#!/bin/bash
# Test harness for install.sh. Every test gets its own temp $HOME so nothing
# ever touches the real ~/.claude/. Run with: bash tests/test_install.sh
set -uo pipefail

SPELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="${SPELL_DIR}/install.sh"
OLD_STOP='{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/save-session-memory.sh","asyncRewake":true}]}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"rtk hook claude"}]}]},"theme":"dark"}'

PASS_COUNT=0
FAIL_COUNT=0

check() {
  local msg="$1"; shift
  if "$@"; then return 0; fi
  echo "    FAIL: ${msg}"
  return 1
}

hook_count() {
  jq --arg event "$2" '[(.hooks[$event] // [])[] | .hooks[]] | length' "$1/.claude/settings.json"
}

run_test() {
  local name="$1" fn="$2"
  if "$fn"; then
    echo "  PASS: ${name}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL: ${name}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

test_fresh_install_creates_settings_and_scripts() {
  local home; home="$(mktemp -d)"
  HOME="$home" bash "$INSTALL_SH" </dev/null >/dev/null || return 1
  check "summarize.py copied" test -f "$home/.claude/hooks/session-recap/summarize.py" &&
  check "recap.py copied" test -f "$home/.claude/hooks/session-recap/recap.py" &&
  check "recap skill copied" test -f "$home/.claude/skills/recap/SKILL.md" &&
  check "one SessionEnd hook" test "$(hook_count "$home" SessionEnd)" = 1 &&
  check "one PreCompact hook" test "$(hook_count "$home" PreCompact)" = 1 &&
  check "one SessionStart hook" test "$(hook_count "$home" SessionStart)" = 1
}

test_merge_keeps_existing_settings_and_is_idempotent() {
  local home; home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  echo "$OLD_STOP" > "$home/.claude/settings.json"
  echo n | HOME="$home" bash "$INSTALL_SH" >/dev/null || return 1
  local second_run; second_run="$(echo n | HOME="$home" bash "$INSTALL_SH")"
  check "theme kept" test "$(jq -r .theme "$home/.claude/settings.json")" = dark &&
  check "PreToolUse kept" test "$(hook_count "$home" PreToolUse)" = 1 &&
  check "old Stop kept when declined" test "$(hook_count "$home" Stop)" = 1 &&
  check "still one SessionStart after rerun" test "$(hook_count "$home" SessionStart)" = 1 &&
  check "rerun reports no changes" test "$second_run" = "Already installed. No changes made."
}

test_accepting_removes_old_stop_hook() {
  local home; home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  echo "$OLD_STOP" > "$home/.claude/settings.json"
  echo y | HOME="$home" bash "$INSTALL_SH" >/dev/null || return 1
  check "Stop key removed" test "$(jq '.hooks | has("Stop")' "$home/.claude/settings.json")" = false &&
  check "PreToolUse kept" test "$(hook_count "$home" PreToolUse)" = 1
}

test_dry_run_changes_nothing() {
  local home; home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  echo "$OLD_STOP" > "$home/.claude/settings.json"
  HOME="$home" bash "$INSTALL_SH" --dry-run >/dev/null || return 1
  check "settings untouched" test "$(cat "$home/.claude/settings.json")" = "$OLD_STOP" &&
  check "no scripts copied" test ! -f "$home/.claude/hooks/session-recap/summarize.py"
}

echo "install.sh tests:"
run_test "fresh install creates settings and scripts" test_fresh_install_creates_settings_and_scripts
run_test "merge keeps existing settings and is idempotent" test_merge_keeps_existing_settings_and_is_idempotent
run_test "accepting removes old Stop hook" test_accepting_removes_old_stop_hook
run_test "dry run changes nothing" test_dry_run_changes_nothing
echo "${PASS_COUNT} passed, ${FAIL_COUNT} failed"
[ "$FAIL_COUNT" -eq 0 ]

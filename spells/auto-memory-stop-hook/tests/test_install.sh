#!/bin/bash
# Test harness for install.sh. Every test gets its own temp $HOME so nothing
# ever touches the real ~/.claude/. Run with: bash tests/test_install.sh
set -uo pipefail

SPELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="${SPELL_DIR}/install.sh"

PASS_COUNT=0
FAIL_COUNT=0

make_fake_home() {
  mktemp -d
}

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$expected" != "$actual" ]; then
    echo "    FAIL: ${msg}"
    echo "      expected: ${expected}"
    echo "      actual:   ${actual}"
    return 1
  fi
}

assert_file_exists() {
  local path="$1" msg="$2"
  if [ ! -f "$path" ]; then
    echo "    FAIL: ${msg} (file does not exist: ${path})"
    return 1
  fi
}

assert_file_absent() {
  local path="$1" msg="$2"
  if [ -f "$path" ]; then
    echo "    FAIL: ${msg} (file unexpectedly exists: ${path})"
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "    FAIL: ${msg}"
    echo "      expected output to contain: ${needle}"
    echo "      actual output: ${haystack}"
    return 1
  fi
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

test_missing_jq_exits_nonzero_with_hint() {
  local fake_home no_jq_path real_jq_path
  fake_home="$(make_fake_home)"
  no_jq_path="$(mktemp -d)"
  for tool in bash mkdir cp chmod cat date mv cmp grep printf rm; do
    real_jq_path="$(command -v "$tool")" || continue
    ln -s "$real_jq_path" "${no_jq_path}/${tool}"
  done
  local output status
  output="$(HOME="$fake_home" PATH="$no_jq_path" "$INSTALL_SH" 2>&1)"
  status=$?
  rm -rf "$fake_home" "$no_jq_path"
  [ "$status" -ne 0 ] || { echo "    FAIL: expected nonzero exit, got 0"; return 1; }
  assert_contains "$output" "jq" "error message should mention jq"
}

test_fresh_install_copies_hook_and_sets_executable() {
  local fake_home
  fake_home="$(make_fake_home)"
  HOME="$fake_home" "$INSTALL_SH" <<< "n" >/dev/null 2>&1
  local dest="${fake_home}/.claude/hooks/save-session-memory.sh"
  assert_file_exists "$dest" "hook should be copied to ~/.claude/hooks/" || { rm -rf "$fake_home"; return 1; }
  local src_content dest_content
  src_content="$(cat "${SPELL_DIR}/hooks/save-session-memory.sh")"
  dest_content="$(cat "$dest")"
  local result=0
  assert_eq "$src_content" "$dest_content" "copied hook content should match source" || result=1
  [ -x "$dest" ] || { echo "    FAIL: copied hook should be executable"; result=1; }
  rm -rf "$fake_home"
  return $result
}

test_dry_run_does_not_copy_hook_and_prints_would_message() {
  local fake_home output
  fake_home="$(make_fake_home)"
  output="$(HOME="$fake_home" "$INSTALL_SH" --dry-run 2>&1)"
  local dest="${fake_home}/.claude/hooks/save-session-memory.sh"
  local result=0
  assert_file_absent "$dest" "dry-run must not copy the hook" || result=1
  assert_contains "$output" "Would copy" "dry-run should print what it would copy" || result=1
  rm -rf "$fake_home"
  return $result
}

test_no_settings_file_creates_from_snippet() {
  local fake_home
  fake_home="$(make_fake_home)"
  HOME="$fake_home" "$INSTALL_SH" <<< "n" >/dev/null 2>&1
  local settings="${fake_home}/.claude/settings.json"
  local result=0
  assert_file_exists "$settings" "settings.json should be created" || result=1
  local has_hook
  has_hook="$(jq --arg cmd "bash ~/.claude/hooks/save-session-memory.sh" \
    '[(.hooks.Stop // [])[] | (.hooks // [])[] | select(.command == $cmd)] | length > 0' "$settings")"
  assert_eq "true" "$has_hook" "new settings.json should contain the hook" || result=1
  rm -rf "$fake_home"
  return $result
}

test_settings_with_hook_already_present_is_noop() {
  local fake_home
  fake_home="$(make_fake_home)"
  mkdir -p "${fake_home}/.claude"
  cp "${SPELL_DIR}/settings.snippet.json" "${fake_home}/.claude/settings.json"
  local before
  before="$(cat "${fake_home}/.claude/settings.json")"
  HOME="$fake_home" "$INSTALL_SH" <<< "n" >/dev/null 2>&1
  local after
  after="$(cat "${fake_home}/.claude/settings.json")"
  local result=0
  assert_eq "$before" "$after" "settings.json should be byte-identical when hook already present" || result=1
  local backup_count
  backup_count="$(find "${fake_home}/.claude" -name 'settings.json.bak.*' | wc -l | tr -d ' ')"
  assert_eq "0" "$backup_count" "no backup should be created when nothing changes" || result=1
  rm -rf "$fake_home"
  return $result
}

test_settings_with_other_stop_hook_appends_not_replaces() {
  local fake_home
  fake_home="$(make_fake_home)"
  mkdir -p "${fake_home}/.claude"
  cat > "${fake_home}/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "echo other-hook" } ] }
    ]
  }
}
EOF
  HOME="$fake_home" "$INSTALL_SH" <<< "n" >/dev/null 2>&1
  local settings="${fake_home}/.claude/settings.json"
  local stop_count has_other has_ours
  stop_count="$(jq '.hooks.Stop | length' "$settings")"
  has_other="$(jq '[.hooks.Stop[] | .hooks[] | select(.command == "echo other-hook")] | length > 0' "$settings")"
  has_ours="$(jq --arg cmd "bash ~/.claude/hooks/save-session-memory.sh" \
    '[.hooks.Stop[] | .hooks[] | select(.command == $cmd)] | length > 0' "$settings")"
  local result=0
  assert_eq "2" "$stop_count" "hooks.Stop should have both entries" || result=1
  assert_eq "true" "$has_other" "original Stop hook should be preserved" || result=1
  assert_eq "true" "$has_ours" "new Stop hook should be appended" || result=1
  rm -rf "$fake_home"
  return $result
}

test_settings_with_no_stop_key_sets_it_and_preserves_other_keys() {
  local fake_home
  fake_home="$(make_fake_home)"
  mkdir -p "${fake_home}/.claude"
  cat > "${fake_home}/.claude/settings.json" <<'EOF'
{
  "theme": "dark",
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "echo pre" } ] }
    ]
  }
}
EOF
  HOME="$fake_home" "$INSTALL_SH" <<< "n" >/dev/null 2>&1
  local settings="${fake_home}/.claude/settings.json"
  local theme pretool_count has_ours
  theme="$(jq -r '.theme' "$settings")"
  pretool_count="$(jq '.hooks.PreToolUse | length' "$settings")"
  has_ours="$(jq --arg cmd "bash ~/.claude/hooks/save-session-memory.sh" \
    '[(.hooks.Stop // [])[] | .hooks[] | select(.command == $cmd)] | length > 0' "$settings")"
  local result=0
  assert_eq "dark" "$theme" "unrelated top-level key should survive" || result=1
  assert_eq "1" "$pretool_count" "unrelated hooks.PreToolUse should survive" || result=1
  assert_eq "true" "$has_ours" "hooks.Stop should now contain the hook" || result=1
  rm -rf "$fake_home"
  return $result
}

test_backup_filename_is_iso8601_not_unix_epoch() {
  local fake_home
  fake_home="$(make_fake_home)"
  mkdir -p "${fake_home}/.claude"
  echo '{"theme": "dark"}' > "${fake_home}/.claude/settings.json"
  HOME="$fake_home" "$INSTALL_SH" <<< "n" >/dev/null 2>&1
  local backup
  backup="$(find "${fake_home}/.claude" -name 'settings.json.bak.*' | head -1)"
  local result=0
  [ -n "$backup" ] || { echo "    FAIL: expected a backup file to exist"; result=1; }
  local suffix
  suffix="$(basename "$backup" | sed 's/^settings\.json\.bak\.//')"
  if [[ ! "$suffix" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z$ ]]; then
    echo "    FAIL: backup suffix '${suffix}' is not ISO 8601 (expected e.g. 2026-06-21T14-32-05Z)"
    result=1
  fi
  if [[ "$suffix" =~ ^[0-9]{10}$ ]]; then
    echo "    FAIL: backup suffix '${suffix}' looks like a bare Unix epoch"
    result=1
  fi
  rm -rf "$fake_home"
  return $result
}

test_dry_run_settings_makes_no_changes() {
  local fake_home output
  fake_home="$(make_fake_home)"
  mkdir -p "${fake_home}/.claude"
  echo '{"theme": "dark"}' > "${fake_home}/.claude/settings.json"
  local before
  before="$(cat "${fake_home}/.claude/settings.json")"
  output="$(HOME="$fake_home" "$INSTALL_SH" --dry-run 2>&1)"
  local after
  after="$(cat "${fake_home}/.claude/settings.json")"
  local backup_count
  backup_count="$(find "${fake_home}/.claude" -name 'settings.json.bak.*' | wc -l | tr -d ' ')"
  local result=0
  assert_eq "$before" "$after" "dry-run must not change settings.json" || result=1
  assert_eq "0" "$backup_count" "dry-run must not create a backup" || result=1
  assert_contains "$output" "Would back up" "dry-run should describe the settings change it would make" || result=1
  rm -rf "$fake_home"
  return $result
}

test_claude_md_absent_and_user_declines_creates_nothing() {
  local fake_home
  fake_home="$(make_fake_home)"
  HOME="$fake_home" "$INSTALL_SH" <<< "n" >/dev/null 2>&1
  assert_file_absent "${fake_home}/.claude/CLAUDE.md" "CLAUDE.md should not be created when declined"
  local result=$?
  rm -rf "$fake_home"
  return $result
}

test_claude_md_absent_and_user_accepts_appends_snippet() {
  local fake_home
  fake_home="$(make_fake_home)"
  HOME="$fake_home" "$INSTALL_SH" <<< "y" >/dev/null 2>&1
  local claude_md="${fake_home}/.claude/CLAUDE.md"
  local result=0
  assert_file_exists "$claude_md" "CLAUDE.md should be created when accepted" || { rm -rf "$fake_home"; return 1; }
  grep -q "## Memory Management" "$claude_md" || { echo "    FAIL: snippet heading not found in CLAUDE.md"; result=1; }
  rm -rf "$fake_home"
  return $result
}

test_claude_md_marker_already_present_skips_without_prompting() {
  local fake_home
  fake_home="$(make_fake_home)"
  mkdir -p "${fake_home}/.claude"
  cat > "${fake_home}/.claude/CLAUDE.md" <<'EOF'
# My existing CLAUDE.md

## Memory Management

Pre-existing sentinel text that must not be duplicated.
EOF
  local before
  before="$(cat "${fake_home}/.claude/CLAUDE.md")"
  HOME="$fake_home" "$INSTALL_SH" < /dev/null >/dev/null 2>&1
  local status=$?
  local after
  after="$(cat "${fake_home}/.claude/CLAUDE.md")"
  local result=0
  [ "$status" -eq 0 ] || { echo "    FAIL: install.sh should not hang/error when marker already present (exit ${status})"; result=1; }
  assert_eq "$before" "$after" "CLAUDE.md should be untouched when marker already present" || result=1
  rm -rf "$fake_home"
  return $result
}

test_dry_run_claude_md_prints_would_prompt_and_writes_nothing() {
  local fake_home output
  fake_home="$(make_fake_home)"
  output="$(HOME="$fake_home" "$INSTALL_SH" --dry-run < /dev/null 2>&1)"
  local result=0
  assert_file_absent "${fake_home}/.claude/CLAUDE.md" "dry-run must not create CLAUDE.md" || result=1
  assert_contains "$output" "claude-md-snippet.md" "dry-run should describe the CLAUDE.md change it would offer" || result=1
  rm -rf "$fake_home"
  return $result
}

run_test "CLAUDE.md absent and user declines creates nothing" test_claude_md_absent_and_user_declines_creates_nothing
run_test "CLAUDE.md absent and user accepts appends snippet" test_claude_md_absent_and_user_accepts_appends_snippet
run_test "CLAUDE.md marker already present skips without prompting" test_claude_md_marker_already_present_skips_without_prompting
run_test "dry-run CLAUDE.md prints would-prompt and writes nothing" test_dry_run_claude_md_prints_would_prompt_and_writes_nothing
run_test "missing jq exits nonzero with hint" test_missing_jq_exits_nonzero_with_hint
run_test "fresh install copies hook and sets executable" test_fresh_install_copies_hook_and_sets_executable
run_test "dry-run does not copy hook and prints would message" test_dry_run_does_not_copy_hook_and_prints_would_message
run_test "no settings file creates from snippet" test_no_settings_file_creates_from_snippet
run_test "settings with hook already present is no-op" test_settings_with_hook_already_present_is_noop
run_test "settings with other Stop hook appends not replaces" test_settings_with_other_stop_hook_appends_not_replaces
run_test "settings with no Stop key sets it and preserves other keys" test_settings_with_no_stop_key_sets_it_and_preserves_other_keys
run_test "backup filename is ISO 8601 not Unix epoch" test_backup_filename_is_iso8601_not_unix_epoch
run_test "dry-run settings makes no changes" test_dry_run_settings_makes_no_changes

echo ""
echo "${PASS_COUNT} passed, ${FAIL_COUNT} failed"
[ "$FAIL_COUNT" -eq 0 ]

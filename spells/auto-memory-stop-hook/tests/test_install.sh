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

run_test "missing jq exits nonzero with hint" test_missing_jq_exits_nonzero_with_hint
run_test "fresh install copies hook and sets executable" test_fresh_install_copies_hook_and_sets_executable
run_test "dry-run does not copy hook and prints would message" test_dry_run_does_not_copy_hook_and_prints_would_message

echo ""
echo "${PASS_COUNT} passed, ${FAIL_COUNT} failed"
[ "$FAIL_COUNT" -eq 0 ]

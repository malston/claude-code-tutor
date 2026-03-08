#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/session-status.sh"

PASS=0
FAIL=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  expected: $(printf '%q' "$expected")"
    echo "  actual:   $(printf '%q' "$actual")"
    FAIL=$((FAIL + 1))
  fi
}

make_temp_home() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.claude-code-tutor"
  echo "$tmp"
}

cleanup() {
  if [[ -n "${TEMP_HOME:-}" && -d "${TEMP_HOME:-}" ]]; then
    rm -rf "$TEMP_HOME"
  fi
}

# ---------- Test 1: No progress file → silent exit ----------
test_no_progress_file() {
  TEMP_HOME="$(mktemp -d)"
  trap cleanup RETURN
  local output
  output="$(HOME="$TEMP_HOME" bash "$HOOK" 2>&1)" || true
  run_test "No progress file → silent exit" "" "$output"
}

# ---------- Test 2: hooks_enabled=false → silent exit ----------
test_hooks_disabled() {
  TEMP_HOME="$(make_temp_home)"
  trap cleanup RETURN
  cat > "$TEMP_HOME/.claude-code-tutor/progress.json" <<'JSON'
{
  "hooks_enabled": false,
  "topics": {
    "guides": {"status": "in_progress", "subtopics_passed": ["effective-prompting"], "subtopics_total": 8}
  }
}
JSON
  local output
  output="$(HOME="$TEMP_HOME" bash "$HOOK" 2>&1)" || true
  run_test "hooks_enabled=false → silent exit" "" "$output"
}

# ---------- Test 3: In-progress topic → status line ----------
test_in_progress() {
  TEMP_HOME="$(make_temp_home)"
  trap cleanup RETURN
  cat > "$TEMP_HOME/.claude-code-tutor/progress.json" <<'JSON'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {"status": "completed", "subtopics_passed": ["system-prompt-anatomy", "context-window-management", "prompt-caching", "token-optimization", "extended-thinking", "tool-execution-context"], "subtopics_total": 6},
    "guides": {"status": "in_progress", "subtopics_passed": ["effective-prompting", "workflow-patterns", "debugging-strategies"], "subtopics_total": 8}
  }
}
JSON
  local output
  output="$(HOME="$TEMP_HOME" bash "$HOOK" 2>&1)" || true
  run_test "In-progress topic → status line" \
    "Tutor: Guides -- 3/8 subtopics complete. /claude-code-tutor:tutor to continue." \
    "$output"
}

# ---------- Test 4: All topics completed → completion message ----------
test_all_completed() {
  TEMP_HOME="$(make_temp_home)"
  trap cleanup RETURN
  cat > "$TEMP_HOME/.claude-code-tutor/progress.json" <<'JSON'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {"status": "completed", "subtopics_passed": ["a","b","c","d","e","f"], "subtopics_total": 6},
    "guides": {"status": "completed", "subtopics_passed": ["a","b","c","d","e","f","g","h"], "subtopics_total": 8},
    "extending": {"status": "completed", "subtopics_passed": ["a","b","c"], "subtopics_total": 3},
    "product": {"status": "completed", "subtopics_passed": ["a","b"], "subtopics_total": 2},
    "enterprise-rollout": {"status": "completed", "subtopics_passed": ["a","b","c","d"], "subtopics_total": 4},
    "training-paths": {"status": "completed", "subtopics_passed": ["a","b","c"], "subtopics_total": 3}
  }
}
JSON
  local output
  output="$(HOME="$TEMP_HOME" bash "$HOOK" 2>&1)" || true
  run_test "All topics completed → completion message" \
    "Tutor: All 6 topics complete! /claude-code-tutor:tutor quiz to review." \
    "$output"
}

# ---------- Test 5: Unlocked topic ready → "Ready for" message ----------
test_unlocked_ready() {
  TEMP_HOME="$(make_temp_home)"
  trap cleanup RETURN
  cat > "$TEMP_HOME/.claude-code-tutor/progress.json" <<'JSON'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {"status": "completed", "subtopics_passed": ["a","b","c","d","e","f"], "subtopics_total": 6},
    "guides": {"status": "unlocked", "subtopics_passed": [], "subtopics_total": 8}
  }
}
JSON
  local output
  output="$(HOME="$TEMP_HOME" bash "$HOOK" 2>&1)" || true
  run_test "Unlocked topic ready → Ready for message" \
    "Tutor: Ready for Guides. /claude-code-tutor:tutor to start." \
    "$output"
}

# ---------- Test 6: Empty topics dict → silent exit ----------
test_empty_topics() {
  TEMP_HOME="$(make_temp_home)"
  trap cleanup RETURN
  cat > "$TEMP_HOME/.claude-code-tutor/progress.json" <<'JSON'
{
  "hooks_enabled": true,
  "topics": {}
}
JSON
  local output
  output="$(HOME="$TEMP_HOME" bash "$HOOK" 2>&1)" || true
  run_test "Empty topics dict → silent exit" "" "$output"
}

# ---------- Test 7: Malformed JSON → silent exit ----------
test_corrupt_json() {
  TEMP_HOME="$(make_temp_home)"
  trap cleanup RETURN
  echo "this is not valid json {{{" > "$TEMP_HOME/.claude-code-tutor/progress.json"
  local output
  output="$(HOME="$TEMP_HOME" bash "$HOOK" 2>&1)" || true
  run_test "Corrupt JSON → silent exit" "" "$output"
}

# ---------- Test 8: In-progress beats unlocked (priority) ----------
test_in_progress_beats_unlocked() {
  TEMP_HOME="$(make_temp_home)"
  trap cleanup RETURN
  cat > "$TEMP_HOME/.claude-code-tutor/progress.json" <<'JSON'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {"status": "in_progress", "subtopics_passed": ["system-prompt-anatomy"], "subtopics_total": 6},
    "guides": {"status": "unlocked", "subtopics_passed": [], "subtopics_total": 8}
  }
}
JSON
  local output
  output="$(HOME="$TEMP_HOME" bash "$HOOK" 2>&1)" || true
  run_test "In-progress beats unlocked → shows in-progress" \
    "Tutor: Internals -- 1/6 subtopics complete. /claude-code-tutor:tutor to continue." \
    "$output"
}

# ---------- Run all tests ----------
echo "=== session-status hook tests ==="
test_no_progress_file
test_hooks_disabled
test_in_progress
test_all_completed
test_unlocked_ready
test_empty_topics
test_corrupt_json
test_in_progress_beats_unlocked

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi

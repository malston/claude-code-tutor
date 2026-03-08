#!/usr/bin/env bash
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/progress-saver.sh"
PASS=0
FAIL=0
TESTS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

cleanup() {
    if [[ -n "${TMPDIR_TEST:-}" && -d "${TMPDIR_TEST:-}" ]]; then
        rm -rf "$TMPDIR_TEST"
    fi
}
trap cleanup EXIT

assert_eq() {
    local description="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS + 1))
        printf "${GREEN}PASS${NC}: %s\n" "$description"
    else
        FAIL=$((FAIL + 1))
        printf "${RED}FAIL${NC}: %s\n  expected: %s\n  actual:   %s\n" "$description" "$expected" "$actual"
    fi
}

setup_temp_home() {
    TMPDIR_TEST=$(mktemp -d)
    export HOME="$TMPDIR_TEST"
}

write_progress() {
    mkdir -p "$HOME/.claude-code-tutor"
    cat > "$HOME/.claude-code-tutor/progress.json"
}

read_progress() {
    cat "$HOME/.claude-code-tutor/progress.json"
}

# Helper: extract a field from progress.json using python3
json_get() {
    local expr="$1"
    python3 -c "import json; data=json.load(open('$HOME/.claude-code-tutor/progress.json')); print($expr)"
}

# --------------------------------------------------------------------------
# Test 1: No progress file -> silent exit
# --------------------------------------------------------------------------
test_no_progress_file() {
    setup_temp_home
    local result
    result=$(echo '{"topic":"internals","subtopic":"prompt-caching","pass":true}' | bash "$HOOK" 2>&1) || true
    assert_eq "No progress file: exits silently" "" "$result"
    assert_eq "No progress file: no file created" "false" "$([ -f "$HOME/.claude-code-tutor/progress.json" ] && echo true || echo false)"
}

# --------------------------------------------------------------------------
# Test 2: hooks_enabled=false -> file unchanged
# --------------------------------------------------------------------------
test_hooks_disabled() {
    setup_temp_home
    write_progress <<'EOF'
{
  "hooks_enabled": false,
  "topics": {
    "internals": {
      "status": "unlocked",
      "subtopics_passed": [],
      "subtopics_total": 6
    }
  }
}
EOF
    local before after
    before=$(read_progress)
    echo '{"topic":"internals","subtopic":"prompt-caching","pass":true}' | bash "$HOOK"
    after=$(read_progress)
    assert_eq "hooks_enabled=false: file unchanged" "$before" "$after"
}

# --------------------------------------------------------------------------
# Test 3: Assessment pass -> subtopic appended to subtopics_passed list
# --------------------------------------------------------------------------
test_pass_appends_subtopic() {
    setup_temp_home
    write_progress <<'EOF'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {
      "status": "in_progress",
      "subtopics_passed": ["system-prompt-anatomy"],
      "subtopics_total": 6
    },
    "guides": {
      "status": "locked",
      "subtopics_passed": [],
      "subtopics_total": 8
    },
    "extending": {
      "status": "locked",
      "subtopics_passed": [],
      "subtopics_total": 5
    }
  }
}
EOF
    echo '{"topic":"internals","subtopic":"prompt-caching","pass":true}' | bash "$HOOK"
    local passed
    passed=$(json_get "json.dumps(sorted(data['topics']['internals']['subtopics_passed']))")
    assert_eq "Pass appends subtopic" '["prompt-caching", "system-prompt-anatomy"]' "$passed"
}

# --------------------------------------------------------------------------
# Test 4: Assessment pass completing topic -> status=completed AND dependents unlocked
# --------------------------------------------------------------------------
test_pass_completes_topic_and_unlocks() {
    setup_temp_home
    write_progress <<'EOF'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {
      "status": "in_progress",
      "subtopics_passed": ["system-prompt-anatomy", "context-window-management", "prompt-caching", "token-optimization", "extended-thinking"],
      "subtopics_total": 6
    },
    "guides": {
      "status": "locked",
      "subtopics_passed": [],
      "subtopics_total": 8
    },
    "extending": {
      "status": "locked",
      "subtopics_passed": [],
      "subtopics_total": 5
    },
    "product": {
      "status": "locked",
      "subtopics_passed": [],
      "subtopics_total": 4
    },
    "enterprise-rollout": {
      "status": "locked",
      "subtopics_passed": [],
      "subtopics_total": 6
    },
    "training-paths": {
      "status": "locked",
      "subtopics_passed": [],
      "subtopics_total": 3
    }
  }
}
EOF
    echo '{"topic":"internals","subtopic":"tool-execution-context","pass":true}' | bash "$HOOK"

    local internals_status guides_status extending_status product_status
    internals_status=$(json_get "data['topics']['internals']['status']")
    guides_status=$(json_get "data['topics']['guides']['status']")
    extending_status=$(json_get "data['topics']['extending']['status']")
    product_status=$(json_get "data['topics']['product']['status']")

    assert_eq "Completing topic: internals status=completed" "completed" "$internals_status"
    assert_eq "Completing topic: guides unlocked" "unlocked" "$guides_status"
    assert_eq "Completing topic: extending unlocked" "unlocked" "$extending_status"
    assert_eq "Completing topic: product stays locked" "locked" "$product_status"
}

# --------------------------------------------------------------------------
# Test 5: Assessment fail -> subtopics_passed unchanged
# --------------------------------------------------------------------------
test_fail_no_change() {
    setup_temp_home
    write_progress <<'EOF'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {
      "status": "in_progress",
      "subtopics_passed": ["system-prompt-anatomy"],
      "subtopics_total": 6
    }
  }
}
EOF
    echo '{"topic":"internals","subtopic":"prompt-caching","pass":false}' | bash "$HOOK"
    local passed
    passed=$(json_get "json.dumps(data['topics']['internals']['subtopics_passed'])")
    assert_eq "Fail: subtopics_passed unchanged" '["system-prompt-anatomy"]' "$passed"
}

# --------------------------------------------------------------------------
# Test 6: Duplicate subtopic pass -> no duplicate in list (idempotent)
# --------------------------------------------------------------------------
test_duplicate_idempotent() {
    setup_temp_home
    write_progress <<'EOF'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {
      "status": "in_progress",
      "subtopics_passed": ["prompt-caching"],
      "subtopics_total": 6
    }
  }
}
EOF
    echo '{"topic":"internals","subtopic":"prompt-caching","pass":true}' | bash "$HOOK"
    local passed
    passed=$(json_get "json.dumps(data['topics']['internals']['subtopics_passed'])")
    assert_eq "Duplicate: no duplicate in list" '["prompt-caching"]' "$passed"
}

# --------------------------------------------------------------------------
# Test 7: training-paths requires BOTH product AND enterprise-rollout
# --------------------------------------------------------------------------
test_training_paths_requires_both() {
    setup_temp_home
    write_progress <<'EOF'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {
      "status": "completed",
      "subtopics_passed": ["a","b","c","d","e","f"],
      "subtopics_total": 6
    },
    "guides": {
      "status": "completed",
      "subtopics_passed": ["a","b","c","d","e","f","g","h"],
      "subtopics_total": 8
    },
    "extending": {
      "status": "completed",
      "subtopics_passed": ["a","b","c","d","e"],
      "subtopics_total": 5
    },
    "product": {
      "status": "in_progress",
      "subtopics_passed": ["product-thinking","user-research","requirements"],
      "subtopics_total": 4
    },
    "enterprise-rollout": {
      "status": "completed",
      "subtopics_passed": ["a","b","c","d","e","f"],
      "subtopics_total": 6
    },
    "training-paths": {
      "status": "locked",
      "subtopics_passed": [],
      "subtopics_total": 3
    }
  }
}
EOF
    echo '{"topic":"product","subtopic":"prototyping","pass":true}' | bash "$HOOK"

    local product_status training_status
    product_status=$(json_get "data['topics']['product']['status']")
    training_status=$(json_get "data['topics']['training-paths']['status']")

    assert_eq "Both prereqs met: product completed" "completed" "$product_status"
    assert_eq "Both prereqs met: training-paths unlocked" "unlocked" "$training_status"
}

# --------------------------------------------------------------------------
# Run all tests
# --------------------------------------------------------------------------
echo "Running progress-saver hook tests..."
echo "======================================"

test_no_progress_file
test_hooks_disabled
test_pass_appends_subtopic
test_pass_completes_topic_and_unlocks
test_fail_no_change
test_duplicate_idempotent
test_training_paths_requires_both

echo "======================================"
echo "Results: $PASS passed, $FAIL failed (of $TESTS tests)"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi

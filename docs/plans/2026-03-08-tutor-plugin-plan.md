# Claude Code Tutor Plugin Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Claude Code plugin that tutors workshop attendees on Claude Code usage via wiki content (WebFetch) and Anki flashcards (AnkiConnect API).

**Architecture:** Skill + 2 agents + 2 commands + 2 hooks. The tutor skill auto-invokes on Claude Code questions and provides the tutoring framework. The content-retriever agent fetches wiki/Anki content. The assessment-evaluator agent scores responses. Commands orchestrate structured sessions. Hooks provide opt-in session status and progress auto-save.

**Tech Stack:** Claude Code plugin system (markdown frontmatter), bash (hooks), jq (JSON parsing in hooks), python3 (JSON manipulation in hooks)

**Design doc:** `docs/plans/2026-03-08-tutor-plugin-design.md`

---

### Task 1: Plugin Scaffold

**Files:**

- Create: `.claude-plugin/plugin.json`
- Create: `.gitignore`

**Step 1: Create plugin.json**

```json
{
  "name": "claude-code-tutor",
  "description": "Interactive tutor for Claude Code workshop attendees. Teaches via wiki content and Anki flashcards with progressive topic unlocking.",
  "version": "0.1.0",
  "author": {
    "name": "Mark Alston"
  },
  "license": "MIT"
}
```

**Step 2: Create .gitignore**

```
.claude/*.local.md
.claude/*.local.json
```

**Step 3: Create directory structure**

```bash
mkdir -p agents skills/tutor commands hooks tests
```

**Step 4: Commit**

```bash
git add .claude-plugin/plugin.json .gitignore
git commit -m "Scaffold plugin structure with plugin.json"
```

---

### Task 2: Tutor Skill

**Files:**

- Create: `skills/tutor/SKILL.md`

**Step 1: Write the skill**

The skill contains:

- Description and trigger conditions (when to auto-invoke)
- Topic map with wiki URL paths (the static registry)
- Progression rules (level order, prerequisites, soft gate behavior)
- Mode routing logic (Q&A vs guided discovery vs quiz)
- Instructions for invoking content-retriever and assessment-evaluator agents
- Progress file path and format reference

Key constraints:

- Target < 2,000 words (skill budget)
- Progressive disclosure: trigger section first (~200 words), then detail layers
- No procedural tool execution in the skill body -- delegate to agents

Content for the topic map comes from the wiki structure documented in the design doc
(`docs/plans/2026-03-08-tutor-plugin-design.md`, lines 59-98).

The wiki base URL is configurable per user (stored in `~/.claude-code-tutor/progress.json`).
The skill instructs Claude to read the progress file to get the base URL before dispatching
the content-retriever agent.

**Step 2: Validate skill size**

```bash
wc -w skills/tutor/SKILL.md
```

Expected: under 2,000 words. If over, trim detail sections.

**Step 3: Commit**

```bash
git add skills/tutor/SKILL.md
git commit -m "Add tutor skill with topic map and progression rules"
```

---

### Task 3: Content Retriever Agent

**Files:**

- Create: `agents/content-retriever.md`

**Step 1: Write the agent definition**

Frontmatter:

```yaml
---
name: content-retriever
description: Fetches Claude Code wiki content via WebFetch and queries AnkiConnect for flashcards. Returns focused excerpts for tutoring.
tools: WebFetch, Read
---
```

Agent prompt must cover:

- **Wiki fetching**: Receives a topic + subtopic, constructs the URL from the base URL +
  path (e.g., `{base_url}/internals/context-window-management/`), fetches via WebFetch,
  extracts the article content, returns a focused excerpt.
- **AnkiConnect querying**: For quiz mode, posts JSON to the AnkiConnect API at the
  configured URL. Uses `findNotes` with deck name and `section::topic` tags, then
  `notesInfo` to get card content. Returns a set of flashcards.
- **Fallback behavior**: If WebFetch fails, return an error message explaining the content
  source is unavailable. Do not fabricate content.
- **Input format**: JSON with `source` (wiki|anki), `topic`, `subtopic`, `base_url`,
  and optional `count` (number of cards for quiz mode).
- **Output format**: JSON with `content` (extracted text), `source_url`, and `status`
  (success|error).

**Step 2: Commit**

```bash
git add agents/content-retriever.md
git commit -m "Add content-retriever agent for wiki and AnkiConnect access"
```

---

### Task 4: Assessment Evaluator Agent

**Files:**

- Create: `agents/assessment-evaluator.md`

**Step 1: Write the agent definition**

Frontmatter:

```yaml
---
name: assessment-evaluator
description: Evaluates teach-back explanations and quiz answers against reference content. Returns structured scoring with feedback.
tools: []
---
```

Agent prompt must cover:

- **Input contract**: Receives JSON with `mode` (teach-back|quiz), `topic`, `subtopic`,
  `reference_content` (wiki excerpt or flashcard), `user_response`.
- **Output contract**: Returns JSON with `accurate` (bool), `score` (0-100), `feedback`
  (string), `key_points_covered` (array), `key_points_missed` (array), `pass` (bool).
- **Evaluation rules**:
  - Compare user response against reference content only, not general knowledge.
  - Teach-back pass: covers >= 60% of key points with no factual errors.
  - Quiz pass: correct answer (binary for factual, scored for scenario).
  - Feedback must be constructive: state what was missed, not just "wrong."
- **No tools**: This agent is pure reasoning -- no file access, no web access. It receives
  all context in the input.

**Step 2: Commit**

```bash
git add agents/assessment-evaluator.md
git commit -m "Add assessment-evaluator agent with scoring contracts"
```

---

### Task 5: `/tutor:setup` Command

**Files:**

- Create: `commands/setup.md`

**Step 1: Write the command definition**

Frontmatter:

```yaml
---
description: First-run setup for the Claude Code tutor. Configures progression mode, content sources, and hooks.
allowed-tools: Bash, Read, Write, WebFetch, AskUserQuestion
---
```

Command body orchestrates:

1. Check if `~/.claude-code-tutor/progress.json` exists.
   - If yes: ask user if they want to reset progress or update settings.
   - If no: proceed with setup.

2. Ask progression mode (use AskUserQuestion):
   - Teach-back (default): explain concepts back for evaluation
   - Self-assessed: self-report readiness

3. Ask content source for wiki:
   - Remote: `https://malston.github.io/claude-code-wiki/` (default)
   - Local: Hugo dev server, ask for port (default 1313)
   - Both: try local first, fall back to remote

4. Verify AnkiConnect connectivity:
   - Use WebFetch to POST `{"action": "version", "version": 6}` to `http://localhost:8765`
   - If it responds, AnkiConnect is available
   - If it fails, warn user that quiz mode requires Anki + AnkiConnect

5. Ask about hooks:
   - "Want automatic session status and progress saving? (yes/no)"
   - Store as `hooks_enabled: true|false`

6. Create `~/.claude-code-tutor/` directory (use Bash: `mkdir -p`)

7. Write `progress.json` with all settings and initial topic state
   (internals = unlocked, all others = locked). Use the subtopic counts from the
   topic map in the tutor skill.

8. Confirm: "Setup complete! Run `/tutor` to start learning, or ask any Claude Code question."

**Step 2: Commit**

```bash
git add commands/setup.md
git commit -m "Add /tutor:setup command for first-run configuration"
```

---

### Task 6: `/tutor` Command

**Files:**

- Create: `commands/tutor.md`

**Step 1: Write the command definition**

Frontmatter:

```yaml
---
description: Start a structured tutoring session. Supports guided discovery, quizzes, and progress tracking.
argument-hint: "[topic] | quiz [topic] | progress | setup"
allowed-tools: Read, Write, Bash, WebFetch, Agent, AskUserQuestion
---
```

Command body handles argument routing:

- **No args** (`/tutor`): Resume guided discovery where user left off.
  1. Read `~/.claude-code-tutor/progress.json`. If missing, tell user to run `/tutor:setup`.
  2. Find the current in-progress topic (or first unlocked topic if none in-progress).
  3. Find the next uncovered subtopic within that topic.
  4. Dispatch content-retriever agent to fetch wiki content for that subtopic.
  5. Present the content as guided discovery (progressive explanation, check understanding).
  6. After covering the subtopic, trigger assessment based on progression_mode.
  7. If teach-back: ask user to explain, dispatch assessment-evaluator, show feedback.
  8. If self-assessed: ask "Ready to move on?"
  9. Update progress.json with results.
  10. Check if topic is now complete; if so, check prerequisite unlocks.

- **`/tutor [topic]`**: Guided discovery for a specific topic.
  1. Read progress.json.
  2. Check if topic is locked. If locked, present soft gate:
     "This builds on [prerequisite]. Cover foundations first, or jump ahead?"
  3. If user jumps ahead, proceed but instruct content-retriever to weave in
     prerequisite context.
  4. Otherwise, same flow as no-args but for the specified topic.

- **`/tutor quiz [topic]`**: Quiz mode.
  1. Read progress.json.
  2. Default to current in-progress topic if no topic specified.
  3. Dispatch content-retriever to query AnkiConnect for flashcards matching the topic.
  4. If AnkiConnect unavailable, fall back to generating questions from wiki content.
  5. Present cards one at a time as questions.
  6. After each answer, dispatch assessment-evaluator for scoring.
  7. Show feedback after each question.
  8. After quiz, update progress.json with results.

- **`/tutor progress`**: Show progress overview.
  1. Read progress.json.
  2. Display table of all topics with status, subtopics passed/total.
  3. Show which topics are locked/unlocked/in-progress/completed.
  4. Suggest next action.

- **`/tutor setup`**: Redirect to `/tutor:setup`.

**Step 2: Commit**

```bash
git add commands/tutor.md
git commit -m "Add /tutor command with guided discovery, quiz, and progress modes"
```

---

### Task 7: SessionStart Hook

**Files:**

- Create: `hooks/session-status.sh`

**Step 1: Write the failing test**

Create a test that verifies the hook script behavior:

```bash
# tests/test-session-status.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../hooks/session-status.sh"

# Test 1: No progress file -- should exit silently with 0
echo "Test 1: No progress file"
PROGRESS_FILE="/tmp/test-tutor-progress-nonexistent.json"
HOME_OVERRIDE="/tmp/test-tutor-no-home"
rm -rf "$HOME_OVERRIDE"
output=$(HOME="$HOME_OVERRIDE" bash "$HOOK_SCRIPT" 2>&1) || true
if [[ -z "$output" ]]; then
  echo "  PASS: silent exit when no progress file"
else
  echo "  FAIL: expected no output, got: $output"
  exit 1
fi

# Test 2: hooks_enabled=false -- should exit silently
echo "Test 2: Hooks disabled"
HOME_OVERRIDE="/tmp/test-tutor-disabled"
mkdir -p "$HOME_OVERRIDE/.claude-code-tutor"
cat > "$HOME_OVERRIDE/.claude-code-tutor/progress.json" <<'PROG'
{
  "hooks_enabled": false,
  "topics": {
    "internals": {"status": "in_progress", "subtopics_passed": 3, "subtopics_total": 6}
  }
}
PROG
output=$(HOME="$HOME_OVERRIDE" bash "$HOOK_SCRIPT" 2>&1) || true
if [[ -z "$output" ]]; then
  echo "  PASS: silent exit when hooks disabled"
else
  echo "  FAIL: expected no output, got: $output"
  exit 1
fi

# Test 3: hooks_enabled=true, in_progress topic -- should print status
echo "Test 3: Active hook with progress"
HOME_OVERRIDE="/tmp/test-tutor-active"
mkdir -p "$HOME_OVERRIDE/.claude-code-tutor"
cat > "$HOME_OVERRIDE/.claude-code-tutor/progress.json" <<'PROG'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {"status": "completed", "subtopics_passed": 6, "subtopics_total": 6},
    "guides": {"status": "in_progress", "subtopics_passed": 3, "subtopics_total": 8},
    "extending": {"status": "locked", "subtopics_passed": 0, "subtopics_total": 5}
  }
}
PROG
output=$(HOME="$HOME_OVERRIDE" bash "$HOOK_SCRIPT" 2>&1)
if echo "$output" | grep -q "Guides"; then
  echo "  PASS: status line mentions current topic"
else
  echo "  FAIL: expected status with 'Guides', got: $output"
  exit 1
fi
if echo "$output" | grep -q "3/8"; then
  echo "  PASS: status line shows subtopic progress"
else
  echo "  FAIL: expected '3/8' in output, got: $output"
  exit 1
fi

# Test 4: All topics completed
echo "Test 4: All topics completed"
HOME_OVERRIDE="/tmp/test-tutor-complete"
mkdir -p "$HOME_OVERRIDE/.claude-code-tutor"
cat > "$HOME_OVERRIDE/.claude-code-tutor/progress.json" <<'PROG'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {"status": "completed", "subtopics_passed": 6, "subtopics_total": 6},
    "guides": {"status": "completed", "subtopics_passed": 8, "subtopics_total": 8}
  }
}
PROG
output=$(HOME="$HOME_OVERRIDE" bash "$HOOK_SCRIPT" 2>&1)
if echo "$output" | grep -qi "complete"; then
  echo "  PASS: status shows completion"
else
  echo "  FAIL: expected completion message, got: $output"
  exit 1
fi

# Cleanup
rm -rf /tmp/test-tutor-*

echo ""
echo "All SessionStart hook tests passed."
```

**Step 2: Run the test to verify it fails**

```bash
chmod +x tests/test-session-status.sh
bash tests/test-session-status.sh
```

Expected: FAIL (hook script doesn't exist yet)

**Step 3: Write the hook script**

```bash
# hooks/session-status.sh
#!/usr/bin/env bash
set -euo pipefail

PROGRESS="$HOME/.claude-code-tutor/progress.json"
if [[ ! -f "$PROGRESS" ]]; then exit 0; fi

HOOKS_ENABLED=$(python3 -c "
import json, sys
try:
    data = json.load(open('$PROGRESS'))
    print(str(data.get('hooks_enabled', False)))
except: print('False')
" 2>/dev/null)

if [[ "$HOOKS_ENABLED" != "True" ]]; then exit 0; fi

# Find current in-progress topic, or report completion
python3 -c "
import json, sys

data = json.load(open('$PROGRESS'))
topics = data.get('topics', {})

# Map topic keys to display names
display_names = {
    'internals': 'Internals',
    'guides': 'Guides',
    'extending': 'Extending',
    'product': 'Product',
    'enterprise-rollout': 'Enterprise Rollout',
    'training-paths': 'Training Paths'
}

# Find in-progress topic
current = None
for key, info in topics.items():
    if info.get('status') == 'in_progress':
        current = key
        break

if current:
    info = topics[current]
    passed = info.get('subtopics_passed', 0)
    total = info.get('subtopics_total', 0)
    name = display_names.get(current, current)
    print(f'Tutor: {name} -- {passed}/{total} subtopics complete. /tutor to continue.')
else:
    completed = sum(1 for t in topics.values() if t.get('status') == 'completed')
    total = len(topics)
    if completed == total and total > 0:
        print(f'Tutor: All {total} topics complete! /tutor quiz to review.')
    else:
        # Find first unlocked topic
        for key, info in topics.items():
            if info.get('status') == 'unlocked':
                name = display_names.get(key, key)
                print(f'Tutor: Ready for {name}. /tutor to start.')
                break
        else:
            print('Tutor: Run /tutor:setup to get started.')
" 2>/dev/null
```

**Step 4: Run the test to verify it passes**

```bash
bash tests/test-session-status.sh
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add hooks/session-status.sh tests/test-session-status.sh
git commit -m "Add SessionStart hook with progress status display"
```

---

### Task 8: PostToolUse Hook (Progress Saver)

**Files:**

- Create: `hooks/progress-saver.sh`

**Step 1: Write the failing test**

```bash
# tests/test-progress-saver.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../hooks/progress-saver.sh"

# Test 1: No progress file -- should exit silently
echo "Test 1: No progress file"
HOME_OVERRIDE="/tmp/test-saver-no-home"
rm -rf "$HOME_OVERRIDE"
echo '{}' | HOME="$HOME_OVERRIDE" bash "$HOOK_SCRIPT" 2>&1 || true
echo "  PASS: silent exit when no progress file"

# Test 2: hooks_enabled=false -- should not modify file
echo "Test 2: Hooks disabled"
HOME_OVERRIDE="/tmp/test-saver-disabled"
mkdir -p "$HOME_OVERRIDE/.claude-code-tutor"
cat > "$HOME_OVERRIDE/.claude-code-tutor/progress.json" <<'PROG'
{
  "hooks_enabled": false,
  "topics": {
    "internals": {"status": "in_progress", "subtopics_passed": 3, "subtopics_total": 6}
  }
}
PROG
BEFORE=$(cat "$HOME_OVERRIDE/.claude-code-tutor/progress.json")
echo '{"tool_input": {"assessment": {"topic": "internals", "subtopic": "prompt-caching", "pass": true}}}' | \
  HOME="$HOME_OVERRIDE" bash "$HOOK_SCRIPT" 2>&1 || true
AFTER=$(cat "$HOME_OVERRIDE/.claude-code-tutor/progress.json")
if [[ "$BEFORE" == "$AFTER" ]]; then
  echo "  PASS: file unchanged when hooks disabled"
else
  echo "  FAIL: file was modified when hooks disabled"
  exit 1
fi

# Test 3: Valid assessment pass -- should increment subtopics_passed
echo "Test 3: Assessment pass increments progress"
HOME_OVERRIDE="/tmp/test-saver-pass"
mkdir -p "$HOME_OVERRIDE/.claude-code-tutor"
cat > "$HOME_OVERRIDE/.claude-code-tutor/progress.json" <<'PROG'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {"status": "in_progress", "subtopics_passed": 3, "subtopics_total": 6},
    "guides": {"status": "locked", "subtopics_passed": 0, "subtopics_total": 8}
  }
}
PROG
echo '{"topic": "internals", "pass": true}' | \
  HOME="$HOME_OVERRIDE" bash "$HOOK_SCRIPT" 2>&1 || true
PASSED=$(python3 -c "import json; print(json.load(open('$HOME_OVERRIDE/.claude-code-tutor/progress.json'))['topics']['internals']['subtopics_passed'])")
if [[ "$PASSED" == "4" ]]; then
  echo "  PASS: subtopics_passed incremented to 4"
else
  echo "  FAIL: expected 4, got: $PASSED"
  exit 1
fi

# Test 4: Assessment pass that completes a topic -- should unlock dependents
echo "Test 4: Topic completion unlocks dependents"
HOME_OVERRIDE="/tmp/test-saver-unlock"
mkdir -p "$HOME_OVERRIDE/.claude-code-tutor"
cat > "$HOME_OVERRIDE/.claude-code-tutor/progress.json" <<'PROG'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {"status": "in_progress", "subtopics_passed": 5, "subtopics_total": 6},
    "guides": {"status": "locked", "subtopics_passed": 0, "subtopics_total": 8},
    "extending": {"status": "locked", "subtopics_passed": 0, "subtopics_total": 5}
  }
}
PROG
echo '{"topic": "internals", "pass": true}' | \
  HOME="$HOME_OVERRIDE" bash "$HOOK_SCRIPT" 2>&1 || true
INTERNALS_STATUS=$(python3 -c "import json; print(json.load(open('$HOME_OVERRIDE/.claude-code-tutor/progress.json'))['topics']['internals']['status'])")
GUIDES_STATUS=$(python3 -c "import json; print(json.load(open('$HOME_OVERRIDE/.claude-code-tutor/progress.json'))['topics']['guides']['status'])")
EXTENDING_STATUS=$(python3 -c "import json; print(json.load(open('$HOME_OVERRIDE/.claude-code-tutor/progress.json'))['topics']['extending']['status'])")
if [[ "$INTERNALS_STATUS" == "completed" ]]; then
  echo "  PASS: internals marked completed"
else
  echo "  FAIL: expected internals=completed, got: $INTERNALS_STATUS"
  exit 1
fi
if [[ "$GUIDES_STATUS" == "unlocked" ]]; then
  echo "  PASS: guides unlocked"
else
  echo "  FAIL: expected guides=unlocked, got: $GUIDES_STATUS"
  exit 1
fi
if [[ "$EXTENDING_STATUS" == "unlocked" ]]; then
  echo "  PASS: extending unlocked"
else
  echo "  FAIL: expected extending=unlocked, got: $EXTENDING_STATUS"
  exit 1
fi

# Test 5: Assessment fail -- should not increment
echo "Test 5: Assessment fail does not increment"
HOME_OVERRIDE="/tmp/test-saver-fail"
mkdir -p "$HOME_OVERRIDE/.claude-code-tutor"
cat > "$HOME_OVERRIDE/.claude-code-tutor/progress.json" <<'PROG'
{
  "hooks_enabled": true,
  "topics": {
    "internals": {"status": "in_progress", "subtopics_passed": 3, "subtopics_total": 6}
  }
}
PROG
echo '{"topic": "internals", "pass": false}' | \
  HOME="$HOME_OVERRIDE" bash "$HOOK_SCRIPT" 2>&1 || true
PASSED=$(python3 -c "import json; print(json.load(open('$HOME_OVERRIDE/.claude-code-tutor/progress.json'))['topics']['internals']['subtopics_passed'])")
if [[ "$PASSED" == "3" ]]; then
  echo "  PASS: subtopics_passed unchanged on fail"
else
  echo "  FAIL: expected 3, got: $PASSED"
  exit 1
fi

# Cleanup
rm -rf /tmp/test-saver-*

echo ""
echo "All PostToolUse hook tests passed."
```

**Step 2: Run the test to verify it fails**

```bash
chmod +x tests/test-progress-saver.sh
bash tests/test-progress-saver.sh
```

Expected: FAIL (script doesn't exist yet)

**Step 3: Write the hook script**

The progress-saver hook reads assessment results from stdin (piped as JSON by Claude Code)
and updates the progress file.

```bash
# hooks/progress-saver.sh
#!/usr/bin/env bash
set -euo pipefail

PROGRESS="$HOME/.claude-code-tutor/progress.json"
if [[ ! -f "$PROGRESS" ]]; then exit 0; fi

# Read input from stdin
INPUT=$(cat)

# Check hooks_enabled
HOOKS_ENABLED=$(python3 -c "
import json
data = json.load(open('$PROGRESS'))
print(str(data.get('hooks_enabled', False)))
" 2>/dev/null)

if [[ "$HOOKS_ENABLED" != "True" ]]; then exit 0; fi

# Parse assessment result and update progress
python3 -c "
import json, sys

input_data = json.loads('''$INPUT''')
topic = input_data.get('topic', '')
passed = input_data.get('pass', False)

if not topic:
    sys.exit(0)

with open('$PROGRESS', 'r') as f:
    data = json.load(f)

topics = data.get('topics', {})
if topic not in topics:
    sys.exit(0)

# Increment subtopics_passed on pass
if passed:
    topics[topic]['subtopics_passed'] = min(
        topics[topic].get('subtopics_passed', 0) + 1,
        topics[topic].get('subtopics_total', 0)
    )

# Check if topic is now complete
info = topics[topic]
if info['subtopics_passed'] >= info['subtopics_total']:
    info['status'] = 'completed'

    # Unlock dependents
    prereqs = {
        'guides': ['internals'],
        'extending': ['internals'],
        'product': ['guides'],
        'enterprise-rollout': ['extending'],
        'training-paths': ['product', 'enterprise-rollout']
    }
    for dep_topic, required in prereqs.items():
        if dep_topic in topics and topics[dep_topic]['status'] == 'locked':
            if all(topics.get(r, {}).get('status') == 'completed' for r in required):
                topics[dep_topic]['status'] = 'unlocked'

with open('$PROGRESS', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
```

**Step 4: Run the test to verify it passes**

```bash
bash tests/test-progress-saver.sh
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add hooks/progress-saver.sh tests/test-progress-saver.sh
git commit -m "Add PostToolUse hook for progress auto-save and topic unlocking"
```

---

### Task 9: Hooks Configuration

**Files:**

- Create: `hooks/hooks.json`

**Step 1: Write hooks.json**

```json
{
  "description": "Opt-in hooks for session status display and progress auto-save. Both no-op unless ~/.claude-code-tutor/progress.json exists with hooks_enabled: true.",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash $CLAUDE_PLUGIN_ROOT/hooks/session-status.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash $CLAUDE_PLUGIN_ROOT/hooks/progress-saver.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Note: The PostToolUse matcher filters to Agent tool calls only. The progress-saver script
further validates that the input contains assessment data before acting.

**Step 2: Commit**

```bash
git add hooks/hooks.json
git commit -m "Add hooks.json registering SessionStart and PostToolUse hooks"
```

---

### Task 10: Plugin Validation

**Step 1: Run all tests**

```bash
bash tests/test-session-status.sh
bash tests/test-progress-saver.sh
```

Expected: All tests pass.

**Step 2: Validate plugin structure**

Verify the final directory layout matches the Claude Code plugin conventions:

```bash
find . -not -path './.git/*' -not -path './.git' | sort
```

Expected:

```
.
./.claude-plugin
./.claude-plugin/plugin.json
./.gitignore
./agents
./agents/assessment-evaluator.md
./agents/content-retriever.md
./commands
./commands/setup.md
./commands/tutor.md
./docs
./docs/plans
./docs/plans/2026-03-08-tutor-plugin-design.md
./docs/plans/2026-03-08-tutor-plugin-plan.md
./hooks
./hooks/hooks.json
./hooks/progress-saver.sh
./hooks/session-status.sh
./skills
./skills/tutor
./skills/tutor/SKILL.md
./tests
./tests/test-progress-saver.sh
./tests/test-session-status.sh
```

**Step 3: Validate plugin.json is valid JSON**

```bash
python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); print('Valid')"
```

**Step 4: Validate hooks.json is valid JSON**

```bash
python3 -c "import json; json.load(open('hooks/hooks.json')); print('Valid')"
```

**Step 5: Run the plugin-validator agent if available**

Use `/plugin-dev:plugin-validator` or manually review against conventions.

**Step 6: Final commit**

```bash
git add docs/plans/2026-03-08-tutor-plugin-plan.md
git commit -m "Add implementation plan"
```

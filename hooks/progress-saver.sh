#!/usr/bin/env bash
set -euo pipefail

PROGRESS="$HOME/.claude-code-tutor/progress.json"
if [[ ! -f "$PROGRESS" ]]; then exit 0; fi

# Capture stdin (assessment JSON from PostToolUse event) before heredoc replaces it
INPUT=$(cat)

python3 - "$PROGRESS" "$INPUT" <<'PYEOF'
import json, sys

progress_path = sys.argv[1]
input_text = sys.argv[2]

try:
    with open(progress_path, 'r') as f:
        data = json.load(f)
except (json.JSONDecodeError, IOError):
    sys.exit(0)

if not data.get('hooks_enabled', False):
    sys.exit(0)

try:
    input_data = json.loads(input_text)
except (json.JSONDecodeError, TypeError, ValueError):
    sys.exit(0)

if not isinstance(input_data, dict):
    sys.exit(0)

topic = input_data.get('topic', '')
subtopic = input_data.get('subtopic', '')
passed = input_data.get('pass', False)

if not topic or not subtopic or passed is not True:
    sys.exit(0)

topics = data.get('topics', {})
if topic not in topics:
    sys.exit(0)

topic_data = topics[topic]
subtopics_passed = topic_data.get('subtopics_passed', [])
subtopics_total = topic_data.get('subtopics_total', 0)

# Append subtopic if not already present
if subtopic not in subtopics_passed:
    subtopics_passed.append(subtopic)
    topic_data['subtopics_passed'] = subtopics_passed

# Check if topic is now complete
if len(subtopics_passed) >= subtopics_total:
    topic_data['status'] = 'completed'

# Prerequisite map: topic -> list of prerequisites (ALL must be completed)
prereqs = {
    'guides': ['internals'],
    'extending': ['internals'],
    'product': ['guides'],
    'enterprise-rollout': ['extending'],
    'training-paths': ['product', 'enterprise-rollout'],
}

# Unlock dependents whose prerequisites are all completed
for dep_topic, required in prereqs.items():
    if dep_topic not in topics:
        continue
    if topics[dep_topic].get('status') != 'locked':
        continue
    if all(topics.get(req, {}).get('status') == 'completed' for req in required):
        topics[dep_topic]['status'] = 'unlocked'

with open(progress_path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

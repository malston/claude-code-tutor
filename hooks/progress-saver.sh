#!/usr/bin/env bash
set -euo pipefail

PROGRESS="$HOME/.claude-code-tutor/progress.json"
if [[ ! -f "$PROGRESS" ]]; then exit 0; fi

HOOKS_ENABLED=$(python3 -c "import json; print(str(json.load(open('$PROGRESS')).get('hooks_enabled', False)).lower())" 2>/dev/null)
if [[ "$HOOKS_ENABLED" != "true" ]]; then exit 0; fi

# Capture stdin before heredoc overrides it
INPUT=$(cat)

python3 -c "
import json, sys, os

progress_path = sys.argv[1]
input_text = sys.argv[2]

input_data = json.loads(input_text)
topic = input_data.get('topic', '')
subtopic = input_data.get('subtopic', '')
passed = input_data.get('pass', False)

if not topic or not subtopic or not passed:
    sys.exit(0)

with open(progress_path, 'r') as f:
    data = json.load(f)

topics = data['topics']
if topic not in topics:
    sys.exit(0)

# Append subtopic if not already present
if subtopic not in topics[topic]['subtopics_passed']:
    topics[topic]['subtopics_passed'].append(subtopic)

# Check if topic is now complete
if len(topics[topic]['subtopics_passed']) >= topics[topic]['subtopics_total']:
    topics[topic]['status'] = 'completed'

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
    if topics[dep_topic]['status'] != 'locked':
        continue
    if all(topics.get(req, {}).get('status') == 'completed' for req in required):
        topics[dep_topic]['status'] = 'unlocked'

with open(progress_path, 'w') as f:
    json.dump(data, f, indent=2)
" "$PROGRESS" "$INPUT"

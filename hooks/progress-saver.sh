#!/usr/bin/env bash
set -euo pipefail

PROGRESS="$HOME/.claude-code-tutor/progress.json"
if [[ ! -f "$PROGRESS" ]]; then exit 0; fi

HOOKS_ENABLED=$(python3 -c "import json; print(json.load(open('$PROGRESS'))['hooks_enabled'])" 2>/dev/null)
if [[ "$HOOKS_ENABLED" != "True" ]]; then exit 0; fi

INPUT=$(cat)

python3 -c "
import json, sys

input_data = json.loads('''$INPUT''')
topic = input_data['topic']
subtopic = input_data['subtopic']
passed = input_data['pass']

if not passed:
    sys.exit(0)

with open('$PROGRESS', 'r') as f:
    data = json.load(f)

topics = data['topics']

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

with open('$PROGRESS', 'w') as f:
    json.dump(data, f, indent=2)
"

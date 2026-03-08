#!/usr/bin/env bash
set -euo pipefail

PROGRESS="$HOME/.claude-code-tutor/progress.json"
if [[ ! -f "$PROGRESS" ]]; then exit 0; fi

python3 - "$PROGRESS" <<'PYEOF'
import json, sys

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except (json.JSONDecodeError, IOError):
    sys.exit(0)

if not data.get('hooks_enabled', False):
    sys.exit(0)

DISPLAY_NAMES = {
    'internals': 'Internals',
    'guides': 'Guides',
    'extending': 'Extending',
    'product': 'Product',
    'enterprise-rollout': 'Enterprise Rollout',
    'training-paths': 'Training Paths',
}

topics = data.get('topics', {})
if not topics:
    sys.exit(0)

# Check for in-progress topic
for key, info in topics.items():
    if info.get('status') == 'in_progress':
        passed = len(info.get('subtopics_passed', []))
        total = info.get('subtopics_total', 0)
        name = DISPLAY_NAMES.get(key, key)
        print(f'Tutor: {name} -- {passed}/{total} subtopics complete. /claude-code-tutor:tutor to continue.')
        sys.exit(0)

# Check if all topics are completed
if all(info.get('status') == 'completed' for info in topics.values()):
    count = len(topics)
    print(f'Tutor: All {count} topics complete! /claude-code-tutor:tutor quiz to review.')
    sys.exit(0)

# Check for unlocked topic ready to start
for key, info in topics.items():
    if info.get('status') == 'unlocked':
        name = DISPLAY_NAMES.get(key, key)
        print(f'Tutor: Ready for {name}. /claude-code-tutor:tutor to start.')
        sys.exit(0)
PYEOF

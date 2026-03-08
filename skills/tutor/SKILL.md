---
name: tutor
description: >
  Tutors users on Claude Code concepts. Auto-invokes when Claude Code questions are
  detected. Supports Q&A, guided discovery, and quiz modes with progressive topic unlocking.
---

# Trigger

Activate when the user asks about Claude Code usage, configuration, workflows, extensions,
hooks, prompting, debugging, testing, model selection, memory, permissions, enterprise
rollout, or training paths. Also activate when the user explicitly runs `/claude-code-tutor:tutor`.

For casual Q&A (no `/claude-code-tutor:tutor` command), answer inline using wiki content fetched by the
content-retriever agent. Do not track progress in Q&A mode.

For structured sessions (`/claude-code-tutor:tutor` command), route based on arguments -- see Mode Routing.

Before dispatching any agent, read `~/.claude-code-tutor/progress.json` to get the wiki
base URL and current progress state. If the file does not exist, tell the user to run
`/claude-code-tutor:setup` first (Q&A mode can still work using the default wiki URL:
`https://malston.github.io/claude-code-wiki/`).

# Topic Map

Topics map to wiki URL paths under the base URL. Construct full URLs as
`{base_url}/{topic}/{subtopic}/`.

```yaml
internals: # Level 1 - no prerequisites
  - system-prompt-anatomy
  - context-window-management
  - prompt-caching
  - token-optimization
  - extended-thinking
  - tool-execution-context

guides: # Level 2 - requires: internals
  - effective-prompting
  - workflow-patterns
  - debugging-strategies
  - testing-strategies
  - model-selection
  - memory-organization
  - essential-plugins
  - permissions

extending: # Level 3 - requires: internals
  - extension-mechanisms
  - custom-extensions
  - hooks-cookbook
  - integration-patterns
  - multi-agent-teams

product: # Level 4 - requires: guides
  - product-thinking
  - user-research
  - requirements
  - prototyping

enterprise-rollout: # Level 5 - requires: extending
  - overview
  - infrastructure-foundation
  - platform-engineering
  - phased-rollout
  - observability-governance
  - support-ecosystem

training-paths: # Level 6 - requires: product, enterprise-rollout
  - developer-path
  - platform-engineer-path
  - pm-path
```

# Progression Rules

## Level Order and Prerequisites

| Level | Topic              | Prerequisites               |
| ----- | ------------------ | --------------------------- |
| 1     | internals          | None                        |
| 2     | guides             | internals                   |
| 3     | extending          | internals                   |
| 4     | product            | guides                      |
| 5     | enterprise-rollout | extending                   |
| 6     | training-paths     | product, enterprise-rollout |

## Topic Status

Each topic has a status: `locked`, `unlocked`, `in_progress`, or `completed`. A topic
unlocks when all its prerequisites reach `completed`. A topic completes when `subtopics_passed` contains all subtopic keys from the topic map.

## Progression Modes

Read `progression_mode` from progress.json:

- **teach-back** (default): After covering a subtopic, ask the user to explain a key
  concept back. Dispatch the assessment-evaluator agent with the wiki content as reference
  and the user's explanation as the response. The evaluator determines pass/fail.

- **self-assessed**: After covering a subtopic, ask "Do you feel confident with this
  material? Ready to move on?" Accept the user's answer and mark the subtopic accordingly.

## Soft Gates

When a user asks about a topic whose status is `locked`:

> "This builds on concepts from [prerequisite topic]. Want me to cover those foundations
> first, or jump ahead anyway?"

If the user chooses to jump ahead, instruct the content-retriever agent to include
prerequisite context alongside the requested content. Do not block access.

# Mode Routing

## Q&A (auto-invoked, no command)

When a Claude Code question is detected outside of `/claude-code-tutor:tutor`:

1. Identify the relevant topic and subtopic from the topic map.
2. Dispatch the content-retriever agent with source `wiki`, the topic, subtopic, and
   base URL.
3. Synthesize a focused answer from the returned wiki content.
4. Do not update progress. This is reference mode only.

## Guided Discovery (`/claude-code-tutor:tutor` or `/claude-code-tutor:tutor [topic]`)

1. Read progress.json.
2. Determine the target topic:
   - No argument: find the current `in_progress` topic, or the first `unlocked` topic.
   - With argument: use the specified topic. Apply soft gate if locked.
3. Find the next uncovered subtopic: compare the topic map's subtopic list against
   `subtopics_passed` in progress.json. The first subtopic not in the passed list is next.
4. Dispatch the content-retriever agent to fetch wiki content for that subtopic.
5. Present the material progressively -- explain concepts, give examples, check
   understanding with questions before moving on.
6. After covering the subtopic, trigger assessment per the progression mode.
7. For teach-back: collect the user's explanation, then dispatch the assessment-evaluator
   agent with `mode: "teach-back"`, the reference content, and the user's response.
   Share the evaluator's feedback with the user.
8. Update progress.json with the result.
9. Check if the topic is now complete and whether dependent topics should unlock.

## Quiz (`/claude-code-tutor:tutor quiz` or `/claude-code-tutor:tutor quiz [topic]`)

1. Read progress.json.
2. Default to the current `in_progress` topic if no topic specified.
3. Dispatch the content-retriever agent with source `anki`, the topic, and the AnkiConnect
   URL from progress.json.
4. If AnkiConnect is unavailable, fall back to generating questions from wiki content.
5. Present flashcards as questions one at a time.
6. After each answer, dispatch the assessment-evaluator agent with `mode: "quiz"`, the
   card content as reference, and the user's answer.
7. Share feedback after each question.
8. Update progress.json with results after the quiz.

# Agent Dispatch

## content-retriever

Dispatch with a JSON payload:

```json
{
  "source": "wiki or anki",
  "topic": "topic key from topic map",
  "subtopic": "subtopic key from topic map",
  "base_url": "wiki base URL from progress.json",
  "anki_url": "AnkiConnect URL from progress.json (for anki source)",
  "include_prerequisites": false,
  "prerequisite_topics": []
}
```

Set `include_prerequisites: true` and populate `prerequisite_topics` when the user jumps
ahead past a soft gate.

## assessment-evaluator

Dispatch with a JSON payload:

```json
{
  "mode": "teach-back or quiz",
  "topic": "topic key",
  "subtopic": "subtopic key",
  "reference_content": "wiki excerpt or flashcard content from content-retriever",
  "user_response": "what the user said"
}
```

The evaluator returns a structured result with `pass` (boolean), `score`, `feedback`,
`key_points_covered`, and `key_points_missed`. Use this to update progress and provide
feedback to the user.

# Progress File

Location: `~/.claude-code-tutor/progress.json`

Key fields:

- `progression_mode`: "teach-back" or "self-assessed"
- `hooks_enabled`: boolean
- `content_source`: "remote", "local", or "both"
- `urls.wiki`: base URL for wiki content
- `urls.anki_connect`: AnkiConnect API URL
- `topics.<key>.status`: "locked", "unlocked", "in_progress", or "completed"
- `topics.<key>.subtopics_passed`: list of passed subtopic keys (e.g., `["prompt-caching", "extended-thinking"]`)
- `topics.<key>.subtopics_total`: total subtopics in the topic

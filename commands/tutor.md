---
description: Start a structured tutoring session. Supports guided discovery, quizzes, and progress tracking.
argument-hint: "[topic] | quiz [topic] | progress | setup"
allowed-tools: Read, Write, Bash, WebFetch, Agent, AskUserQuestion
---

# Tutor Command

Route based on `$ARGUMENTS`:

- If `$ARGUMENTS` is empty or blank: go to **Guided Discovery (Resume)**.
- If `$ARGUMENTS` is `setup`: go to **Setup Redirect**.
- If `$ARGUMENTS` is `progress`: go to **Progress Overview**.
- If `$ARGUMENTS` starts with `quiz`: go to **Quiz Mode** (strip `quiz` prefix, remainder is
  the optional topic).
- Otherwise: treat `$ARGUMENTS` as a topic name and go to **Guided Discovery (Topic)**.

---

## Topic Map

```yaml
internals:
  - system-prompt-anatomy
  - context-window-management
  - prompt-caching
  - token-optimization
  - extended-thinking
  - tool-execution-context

guides:
  - effective-prompting
  - workflow-patterns
  - debugging-strategies
  - testing-strategies
  - model-selection
  - memory-organization
  - essential-plugins
  - permissions

extending:
  - extension-mechanisms
  - custom-extensions
  - hooks-cookbook
  - integration-patterns
  - multi-agent-teams

product:
  - product-thinking
  - user-research
  - requirements
  - prototyping

enterprise-rollout:
  - overview
  - infrastructure-foundation
  - platform-engineering
  - phased-rollout
  - observability-governance
  - support-ecosystem

training-paths:
  - developer-path
  - platform-engineer-path
  - pm-path
```

## Prerequisites

| Topic              | Requires                       |
| ------------------ | ------------------------------ |
| internals          | (none)                         |
| guides             | internals                      |
| extending          | internals                      |
| product            | guides                         |
| enterprise-rollout | extending                      |
| training-paths     | product AND enterprise-rollout |

---

## Setup Redirect

Tell the user:

> Running `/tutor:setup` for you...

Then invoke the `/tutor:setup` command.

---

## Progress Overview

1. Read `~/.claude-code-tutor/progress.json`. If missing, tell the user to run `/tutor setup`
   first and stop.

2. Build a table of all topics with these columns:
   - **Topic**: the topic key
   - **Status**: locked, unlocked, in_progress, or completed
   - **Subtopics Passed**: `{length of subtopics_passed} / {subtopics_total}`
   - **Passed List**: comma-separated list of subtopic keys in `subtopics_passed`, or "--"
     if empty

3. Display the table.

4. Suggest a next action:
   - If there is an `in_progress` topic: "Continue with `/tutor` to pick up where you left
     off."
   - If there are only `unlocked` topics (none in progress): "Start with `/tutor` to begin
     the next unlocked topic."
   - If all topics are `completed`: "All topics complete! Try `/tutor quiz [topic]` to
     review."

---

## Guided Discovery (Resume)

This handles `/tutor` with no arguments.

### Step 1: Load Progress

Read `~/.claude-code-tutor/progress.json`. If missing, tell the user to run `/tutor setup`
first and stop.

### Step 2: Find Target Topic

Look through the topics in progress.json:

1. First, find a topic with status `in_progress`. Use that topic.
2. If no topic is `in_progress`, find the first topic with status `unlocked` (using the
   topic map order: internals, guides, extending, product, enterprise-rollout,
   training-paths). Use that topic and set its status to `in_progress` in the progress data.
3. If no topic is unlocked or in-progress, all are either locked or completed. Tell the user
   and stop.

### Step 3: Find Next Subtopic

Using the topic map above, get the ordered list of subtopics for the target topic. Iterate
through this list and find the first subtopic whose key is NOT in the topic's
`subtopics_passed` list. This is the next subtopic to cover.

If all subtopics are already in `subtopics_passed`, the topic is complete -- update its
status to `completed`, check prerequisite unlocks (see Step 9), and then loop back to Step 2
to find the next topic.

### Step 4: Fetch Content

Dispatch the **content-retriever** agent with this JSON payload:

```json
{
  "source": "wiki",
  "topic": "<target topic key>",
  "subtopic": "<next subtopic key>",
  "base_url": "<urls.wiki from progress.json>",
  "include_prerequisites": false,
  "prerequisite_topics": []
}
```

If the content-retriever returns an error status, inform the user that the content source is
unavailable and suggest trying again later.

### Step 5: Present as Guided Discovery

Present the fetched content as a progressive learning experience:

1. Introduce the subtopic and its relevance.
2. Explain key concepts one at a time, building on each other.
3. Use examples from the wiki content.
4. After covering the material, ask a check-understanding question to confirm the user is
   following before moving to assessment.

### Step 6: Trigger Assessment

Read `progression_mode` from progress.json.

**If teach-back:**

1. Ask the user to explain the key concepts of this subtopic in their own words (via
   AskUserQuestion).
2. Dispatch the **assessment-evaluator** agent with:
   ```json
   {
     "mode": "teach-back",
     "topic": "<topic key>",
     "subtopic": "<subtopic key>",
     "reference_content": "<wiki content from content-retriever>",
     "user_response": "<what the user said>"
   }
   ```
3. Share the evaluator's feedback with the user.
4. If `pass` is true: proceed to Step 7.
5. If `pass` is false: share the feedback, offer to re-explain the material, and let the
   user try again. Do not advance until they pass or choose to skip.

**If self-assessed:**

1. Ask the user (via AskUserQuestion): "Do you feel confident with this material? Ready to
   move on?"
2. If yes: proceed to Step 7.
3. If no: offer to re-explain or go deeper on specific concepts.

### Step 7: Update Progress

Append the subtopic key to the topic's `subtopics_passed` list in progress.json. If the
topic's status was `unlocked`, change it to `in_progress`.

Write the updated progress back to `~/.claude-code-tutor/progress.json`.

### Step 8: Check Topic Completion

Compare the length of `subtopics_passed` against `subtopics_total`.

- If they match: set the topic's status to `completed`.
- If not: the topic remains `in_progress`.

### Step 9: Check Prerequisite Unlocks

When a topic completes, check if any locked topics should now unlock:

- **guides** unlocks when internals is completed.
- **extending** unlocks when internals is completed.
- **product** unlocks when guides is completed.
- **enterprise-rollout** unlocks when extending is completed.
- **training-paths** unlocks when BOTH product AND enterprise-rollout are completed.

For each topic that should unlock, change its status from `locked` to `unlocked` in
progress.json and inform the user.

Write the updated progress to `~/.claude-code-tutor/progress.json`.

### Step 10: Next Steps

Tell the user what was covered and what comes next:

- If the topic has more subtopics: "Next up: [next subtopic]. Run `/tutor` to continue."
- If the topic just completed: "Topic [topic] complete! [Newly unlocked topics] are now
  available."
- If all topics are done: "Congratulations! All topics complete."

---

## Guided Discovery (Topic)

This handles `/tutor [topic]` where a specific topic is provided.

### Step 1: Load Progress

Read `~/.claude-code-tutor/progress.json`. If missing, tell the user to run `/tutor setup`
first and stop.

### Step 2: Validate Topic

Check that the provided topic matches a key in the topic map. If not, list available topics
and stop.

### Step 3: Check Lock Status

Read the topic's status from progress.json.

**If locked:** Present the soft gate:

> "This topic builds on [prerequisite topic(s)]. Want me to cover those foundations first,
> or jump ahead anyway?"

Ask the user via AskUserQuestion.

- If the user wants foundations first: redirect to the prerequisite topic by running the
  Guided Discovery (Resume) flow with that prerequisite as the target.
- If the user wants to jump ahead: proceed, but in Step 4 set
  `include_prerequisites: true` and populate `prerequisite_topics` with the prerequisite
  topic keys.

**If unlocked or in_progress:** Proceed normally.

**If completed:** Tell the user this topic is already completed. Suggest quiz mode for
review (`/tutor quiz [topic]`) or ask if they want to revisit specific subtopics.

### Step 4: Find Next Subtopic

Same as Guided Discovery (Resume) Step 3. Get the ordered subtopic list from the topic map
and find the first one not in `subtopics_passed`.

If the user jumped ahead past a soft gate, dispatch content-retriever with:

```json
{
  "source": "wiki",
  "topic": "<topic key>",
  "subtopic": "<next subtopic key>",
  "base_url": "<urls.wiki from progress.json>",
  "include_prerequisites": true,
  "prerequisite_topics": [
    "<prerequisite topic key 1>",
    "<prerequisite topic key 2>"
  ]
}
```

Otherwise, dispatch with `include_prerequisites: false` and empty `prerequisite_topics`.

### Steps 5-10

Follow the same steps as Guided Discovery (Resume) Steps 5-10.

When presenting content after a soft gate jump, weave the prerequisite summaries from the
content-retriever's response into the explanation naturally before covering the main
subtopic.

---

## Quiz Mode

This handles `/tutor quiz` and `/tutor quiz [topic]`.

### Step 1: Load Progress

Read `~/.claude-code-tutor/progress.json`. If missing, tell the user to run `/tutor setup`
first and stop.

### Step 2: Determine Topic

- If a topic was specified after `quiz`: use that topic. Validate it exists in the topic
  map.
- If no topic specified: use the current `in_progress` topic from progress.json. If no
  topic is in progress, use the most recently completed topic. If no topic qualifies, tell
  the user to start learning with `/tutor` first.

### Step 3: Fetch Quiz Content

Dispatch the **content-retriever** agent to query AnkiConnect:

```json
{
  "source": "anki",
  "topic": "<topic key>",
  "subtopic": "<first subtopic or current subtopic>",
  "base_url": "<urls.wiki from progress.json>",
  "anki_url": "<urls.anki_connect from progress.json>",
  "count": 10
}
```

**If AnkiConnect is unavailable** (content-retriever returns error status): fall back to
wiki-based questions. Dispatch content-retriever with `source: "wiki"` for the topic's
subtopics, then generate questions from the wiki content. Tell the user:

> "AnkiConnect is unavailable (Anki may not be running). Generating questions from wiki
> content instead."

### Step 4: Present Questions

Present flashcards (or generated questions) one at a time:

1. Show the question (the `front` field of each card, or the generated question).
2. Wait for the user's answer via AskUserQuestion.
3. After the user answers, dispatch the **assessment-evaluator** agent:
   ```json
   {
     "mode": "quiz",
     "topic": "<topic key>",
     "subtopic": "<subtopic key>",
     "reference_content": "<card back or wiki content>",
     "user_response": "<user's answer>"
   }
   ```
4. Share the evaluator's feedback immediately after each question.
5. Repeat for the next card.

### Step 5: Quiz Summary

After all questions are answered:

1. Show a summary: total questions, number correct, score percentage.
2. List topics/subtopics where the user struggled (scored below passing).
3. Suggest areas to review.

### Step 6: Update Progress

For each subtopic that the user answered correctly in the quiz: if the subtopic key is not
already in the topic's `subtopics_passed` list, append it.

Write the updated progress to `~/.claude-code-tutor/progress.json`.

Check topic completion and prerequisite unlocks (same as Guided Discovery Steps 8-9).

# Claude Code Tutor Plugin Design

## Purpose

A Claude Code plugin that tutors workshop attendees on how to use and improve their
Claude Code workflow. Pulls content from the Claude Code Wiki (via GitHub Pages or local
Hugo server) and Anki flashcard decks (via AnkiConnect API) to deliver interactive
learning experiences.

## Architecture

### Components

| #   | Type    | Name                   | Purpose                                                                              |
| --- | ------- | ---------------------- | ------------------------------------------------------------------------------------ |
| 1   | Skill   | `tutor`                | Tutoring framework, topic map, mode detection, auto-invokes on Claude Code questions |
| 2   | Agent   | `content-retriever`    | Fetches wiki content via WebFetch, queries AnkiConnect for flashcards                |
| 3   | Agent   | `assessment-evaluator` | Scores teach-back explanations and quiz answers                                      |
| 4   | Command | `/tutor`               | Structured sessions: guided discovery, quiz, progress view                           |
| 5   | Command | `/tutor:setup`         | First-run configuration: progression mode, content sources, hooks                    |
| 6   | Hook    | `SessionStart`         | Injects progress status on session start (opt-in)                                    |
| 7   | Hook    | `PostToolUse`          | Auto-saves progress after assessments (opt-in)                                       |

### Component Relationships

```
User asks Claude Code question
  → tutor skill auto-invokes
  → content-retriever fetches wiki excerpt
  → inline Q&A response

User runs /tutor
  → command checks progress.json
  → content-retriever fetches next subtopic
  → guided discovery or quiz interaction
  → assessment-evaluator scores response
  → progress.json updated

SessionStart hook (opt-in)
  → reads progress.json
  → prints status line

PostToolUse hook (opt-in)
  → triggers after assessment-evaluator
  → updates progress.json, checks unlock conditions
```

## Content Sources

| Source      | Used for                                    | Access method                                |
| ----------- | ------------------------------------------- | -------------------------------------------- |
| Wiki        | Q&A, guided discovery, teach-back reference | WebFetch → GitHub Pages or local Hugo server |
| Study Guide | Quiz cards, teach-back key points           | WebFetch → AnkiConnect API (localhost:8765)  |

### Wiki URL Map

The skill embeds a static topic map (~200 words) mapping topics to wiki URL paths:

```
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
enterprise-rollout:
  - overview
  - infrastructure-foundation
  - platform-engineering
  - phased-rollout
  - observability-governance
  - support-ecosystem
product:
  - product-thinking
  - user-research
  - requirements
  - prototyping
training-paths:
  - developer-path
  - platform-engineer-path
  - pm-path
```

### AnkiConnect Integration

The content-retriever queries AnkiConnect at `localhost:8765` using:

- `findNotes` -- search by deck name and `section::topic` tags
- `notesInfo` -- retrieve card front/back content
- `getDecks` -- list available decks for validation during setup

Cards in the study guide use tab-separated format with tags following the
`section::topic` convention, which maps directly to the topic progression structure.

### Content Source Configuration

Stored in `progress.json`:

```json
{
  "urls": {
    "wiki": "https://malston.github.io/claude-code-wiki/",
    "anki_connect": "http://localhost:8765"
  }
}
```

Users choose their wiki source during `/tutor:setup`:

- **Remote** (default): GitHub Pages
- **Local**: Hugo dev server (user provides port, default 1313)
- **Both**: try local first, fall back to remote

AnkiConnect always runs locally. Setup verifies connectivity by pinging the API.

## Topic Progression

### Level Order

| Level | Topic              | Prerequisites               |
| ----- | ------------------ | --------------------------- |
| 1     | Internals          | None                        |
| 2     | Guides             | Internals                   |
| 3     | Extending          | Internals                   |
| 4     | Product            | Guides                      |
| 5     | Enterprise Rollout | Extending                   |
| 6     | Training Paths     | Product, Enterprise Rollout |

### Progression Modes

Chosen during `/tutor:setup`:

- **Teach-back** (default): After covering a subtopic's key concepts, the plugin asks the
  user to explain a concept back. The assessment-evaluator scores accuracy against wiki
  content. Topic unlocks when the user passes teach-backs for enough subtopics.

- **Self-assessed**: After covering key concepts, the plugin asks "Ready to move on?" and
  trusts the learner's answer.

### Soft Gates

When a user asks about a locked topic:

> "This builds on concepts from [prerequisite]. Want me to cover those foundations first,
> or jump ahead anyway?"

If the user jumps ahead, the content-retriever weaves prerequisite context into the
response naturally.

### Topic Status States

- **locked**: Prerequisites not yet completed
- **unlocked**: Prerequisites met, not yet started
- **in_progress**: User has begun working through subtopics
- **completed**: All subtopics passed (teach-back) or self-assessed

## Interaction Modes

### Q&A (auto-invoked)

- Triggers naturally when Claude detects a Claude Code question
- Skill provides tutoring framework inline
- Content-retriever fetches relevant wiki excerpts
- Responds with focused explanation and examples
- No progress tracking -- reference mode only

### Guided Discovery (via `/tutor`)

- `/tutor` resumes where the user left off
- `/tutor [topic]` starts guided discovery for a specific topic
- Content-retriever fetches the next uncovered subtopic from the wiki
- Presents concepts progressively, checking understanding
- After covering a subtopic, triggers assessment
- Updates progress on completion

### Quiz (via `/tutor quiz`)

- `/tutor quiz` quizzes on the current in-progress topic
- `/tutor quiz [topic]` quizzes on a specific topic
- Content-retriever pulls flashcards from AnkiConnect by deck and tags
- Presents cards as questions (factual recall, scenario diagnosis, config completion, teach-back)
- Assessment-evaluator scores answers
- Updates progress with results

### Progress (via `/tutor progress`)

- Shows current status across all topics
- Subtopics completed vs total for each level
- Which topics are locked/unlocked/in-progress/completed

## Assessment Evaluator Agent

### Input Contract

```json
{
  "mode": "teach-back | quiz",
  "topic": "internals",
  "subtopic": "context-window-management",
  "reference_content": "<wiki excerpt or flashcard content>",
  "user_response": "<what the user said>"
}
```

### Output Contract

```json
{
  "accurate": true,
  "score": 85,
  "feedback": "Good explanation of compaction triggers. You missed that the threshold range is 75-92% depending on context size.",
  "key_points_covered": ["compaction triggers", "context window size"],
  "key_points_missed": ["threshold range specifics"],
  "pass": true
}
```

### Evaluation Criteria

- Checks factual accuracy against the reference content (wiki or flashcard), not general
  Claude knowledge
- **Teach-back pass**: covers at least 60% of key points with no factual errors
- **Quiz pass**: correct answer (binary for factual recall, scored for scenario questions)
- Provides constructive feedback pointing to what was missed

## Hooks

### SessionStart Hook (opt-in)

- Reads `~/.claude-code-tutor/progress.json`
- Quick-exits if file doesn't exist or `hooks_enabled` is false
- Outputs a status line:
  ```
  Tutor: Level 3 (Extending) -- 2/5 subtopics complete. /tutor to continue.
  ```

### PostToolUse Hook (opt-in)

- Triggers after the assessment-evaluator agent completes
- Quick-exits if `hooks_enabled` is false
- Updates `progress.json` with scores
- Checks if new topics should unlock based on prerequisites
- Silent -- no user-visible output

### Hook Gating Pattern

```bash
#!/bin/bash
PROGRESS="$HOME/.claude-code-tutor/progress.json"
if [[ ! -f "$PROGRESS" ]]; then exit 0; fi

HOOKS_ENABLED=$(python3 -c "import json; print(json.load(open('$PROGRESS'))['hooks_enabled'])" 2>/dev/null)
if [[ "$HOOKS_ENABLED" != "True" ]]; then exit 0; fi

# ... hook logic
```

## `/tutor:setup` Command

### Flow

1. Check if `~/.claude-code-tutor/progress.json` exists
   - If yes: offer to reset progress or update settings
   - If no: proceed with first-run setup

2. **Progression mode**: teach-back (default) or self-assessed

3. **Content sources**:
   - Wiki: remote (GitHub Pages), local (Hugo, ask for port), or both with fallback
   - AnkiConnect: verify connectivity at `localhost:8765`

4. **Hooks**: enable session status and auto-save? (yes/no)

5. Create `~/.claude-code-tutor/` directory and write `progress.json`

6. Confirm setup and suggest next step

### Progress File

`~/.claude-code-tutor/progress.json`:

```json
{
  "progression_mode": "teach-back",
  "hooks_enabled": true,
  "content_source": "remote",
  "urls": {
    "wiki": "https://malston.github.io/claude-code-wiki/",
    "anki_connect": "http://localhost:8765"
  },
  "topics": {
    "internals": {
      "status": "unlocked",
      "subtopics_passed": [],
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
```

## Dependencies

- **AnkiConnect**: Anki desktop app with AnkiConnect plugin installed and running
- **Wiki**: GitHub Pages site at `malston.github.io/claude-code-wiki` (or local Hugo server)
- **Study guide decks**: Imported into Anki (6 decks, 417 cards)

## Out of Scope (v1)

- Writing progress back to Anki (marking cards as reviewed)
- MCP server for content access
- Hard gates on topic progression
- Role-based filtering (developer/platform-engineer/PM paths)
- Bundled content (all content fetched at runtime)

# claude-code-tutor

A Claude Code plugin that tutors workshop attendees on how to use and improve their Claude Code workflow. Content is sourced from the [Claude Code Wiki](https://malston.github.io/claude-code-wiki/) and Anki flashcard decks via [AnkiConnect](https://ankiweb.net/shared/info/2055492159).

## Prerequisites

- Claude Code CLI
- [Anki](https://apps.ankiweb.net/) with [AnkiConnect](https://ankiweb.net/shared/info/2055492159) add-on (for quiz mode)
- Study guide flashcard decks imported into Anki

## Installation

```bash
claude plugin marketplace add malston/claude-code-tutor
claude plugin install claude-code-tutor@claude-code-tutor-dev
```

## Setup

Run the setup command to configure your preferences:

```
/tutor:setup
```

This creates `~/.claude-code-tutor/progress.json` with your settings:

- **Progression mode**: teach-back (explain concepts back for evaluation) or self-assessed
- **Content source**: remote (GitHub Pages), local (Hugo dev server), or both
- **Hooks**: opt-in session status display and progress auto-save

## Usage

### Ask questions (auto-invokes)

Just ask any Claude Code question and the tutor skill activates automatically:

> "How does prompt caching work?"
> "What's the best way to set up hooks?"

### Structured learning

```
/tutor              # Resume where you left off
/tutor internals    # Start guided discovery for a specific topic
/tutor quiz         # Quiz on your current topic
/tutor quiz guides  # Quiz on a specific topic
/tutor progress     # See your progress across all topics
```

### Progressive unlocking

Topics unlock as you complete prerequisites:

```
Level 1: Internals (start here)
Level 2: Guides (requires Internals)
Level 3: Extending (requires Internals)
Level 4: Product (requires Guides)
Level 5: Enterprise Rollout (requires Extending)
Level 6: Training Paths (requires Product + Enterprise Rollout)
```

Locked topics use soft gates -- you can jump ahead, but the tutor will offer to cover foundations first.

## Components

| Type    | Name                   | Purpose                                                            |
| ------- | ---------------------- | ------------------------------------------------------------------ |
| Skill   | `tutor`                | Auto-invokes on Claude Code questions, routes to interaction modes |
| Agent   | `content-retriever`    | Fetches wiki content and AnkiConnect flashcards                    |
| Agent   | `assessment-evaluator` | Scores teach-back explanations and quiz answers                    |
| Command | `/tutor`               | Structured learning sessions                                       |
| Command | `/tutor:setup`         | First-run configuration                                            |
| Hook    | `SessionStart`         | Session status display (opt-in)                                    |
| Hook    | `PostToolUse`          | Progress auto-save (opt-in)                                        |

## License

MIT

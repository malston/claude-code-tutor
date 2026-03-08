---
description: First-run setup for the Claude Code tutor. Configures progression mode, content sources, and hooks.
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# Setup

Run the first-time setup for the Claude Code tutor, or update existing settings.

## Step 1: Check for Existing Progress

Read `~/.claude-code-tutor/progress.json`.

- If the file exists: ask the user (via AskUserQuestion) whether they want to reset their
  progress and start fresh, or just update settings. If they choose to update settings,
  preserve their existing topic progress through the remaining steps. If they choose neither,
  stop here.
- If the file does not exist: proceed with fresh setup.

## Step 2: Choose Progression Mode

Ask the user (via AskUserQuestion):

> How would you like to verify understanding?
>
> 1. **Teach-back** (default): Explain concepts back in your own words for evaluation.
> 2. **Self-assessed**: Self-report when you feel ready to move on.

Store the choice as `progression_mode`: either `"teach-back"` or `"self-assessed"`.
Default to `"teach-back"` if the user just presses enter or gives an ambiguous answer.

## Step 3: Choose Content Source

Ask the user (via AskUserQuestion):

> Where should wiki content come from?
>
> 1. **Remote** (default): `https://malston.github.io/claude-code-wiki/`
> 2. **Local**: Hugo dev server (you'll specify the port)
> 3. **Both**: Try local first, fall back to remote

Store the choice as `content_source`: `"remote"`, `"local"`, or `"both"`.

- If `"remote"` or `"both"`: set `urls.wiki` to `https://malston.github.io/claude-code-wiki/`.
- If `"local"`: ask the user for the Hugo dev server port (default 1313) via
  AskUserQuestion. Set `urls.wiki` to `http://localhost:{port}/`.
- If `"both"`: also ask for the local port. Set `urls.wiki` to the remote URL (the skill
  handles fallback logic) and store `urls.local_wiki` as `http://localhost:{port}/`.

## Step 4: Verify AnkiConnect

Use Bash to check AnkiConnect with curl (WebFetch upgrades HTTP to HTTPS, which breaks plain HTTP localhost endpoints):

```bash
curl -s --max-time 3 -X POST http://localhost:8765 -d '{"action":"version","version":6}'
```

- If the response contains `"result": 6` (or any numeric result) and `"error": null`:
  AnkiConnect is available. Set `urls.anki_connect` to `http://localhost:8765`. Tell the
  user AnkiConnect was detected along with the version number.
- If curl fails (connection refused, timeout, non-JSON response, or any error): warn the
  user that quiz mode requires Anki with the AnkiConnect plugin running. Set
  `urls.anki_connect` to `http://localhost:8765` anyway (the user may start Anki later).

## Step 5: Ask About Hooks

Ask the user (via AskUserQuestion):

> Want automatic session status and progress saving? (yes/no)

Store as `hooks_enabled`: `true` if yes, `false` if no. Default to `true`.

## Step 6: Create Config Directory

Run via Bash:

```bash
mkdir -p ~/.claude-code-tutor
```

## Step 7: Write progress.json

Write `~/.claude-code-tutor/progress.json` with all collected settings and the initial
topic state. If the user chose to update settings (Step 1), preserve their existing topic
progress; otherwise use the initial state below.

The file structure:

```json
{
  "progression_mode": "teach-back",
  "content_source": "remote",
  "hooks_enabled": true,
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

If `content_source` is `"both"`, also include `"local_wiki"` under `urls` with the local
URL.

## Step 8: Confirm

Tell the user:

> Setup complete! Run `/claude-code-tutor:tutor` to start learning, or just ask any Claude Code question.

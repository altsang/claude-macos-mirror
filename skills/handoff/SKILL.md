---
name: handoff
description: Hand the current project's workload to the user's other Mac (Madoka / Ji-su). Use when the user says to hand off, move, send, or continue work on their other machine or laptop, or invokes /handoff by name. Writes a self-contained handoff document capturing everything the other machine needs, then transfers ownership of the shared folder. Use this instead of improvising a summary, because a local Cowork project cannot sync its chats and the receiving machine starts with no memory of this conversation.
---

# Hand off a workload to the other Mac

Al works across two Macs, **Madoka** (desktop) and **Ji-su** (laptop). Shared projects live at one
path identical on both:

```
~/Library/Mobile Documents/com~apple~CloudDocs/Claude/Projects/PROJECT
```

Run everything through the `mirror` CLI:

```bash
MIRROR=~/workspace/claude-macos-mirror/bin/mirror
```

If that path does not exist, fall back to the engine in the shared tree:
`bash "$(ls -1 ~/Library/Mobile\ Documents/com~apple~CloudDocs/Claude/_handoff/bin/coworkctl-v5.sh | sort -V | tail -1)"`.

## Why this skill exists

The receiving Mac gets the **files** automatically. It does **not** get this conversation, and it
cannot: **chat is not available for local Cowork projects**, so there is no synced history and no
project memory to fall back on. Everything you know that isn't written down is lost at the handoff.
The document is the deliverable; moving bytes is the easy half.

## Step 1 — Identify project and target

Project = the folder under the shared `Projects/` tree this session is working in. Target =
whichever of Madoka / Ji-su is not this machine (`scutil --get ComputerName`). Ask only if
genuinely ambiguous. `$MIRROR status` shows what is shared and who owns it.

## Step 2 — Write the handoff document

Write `HANDOFF_TOPIC.md` into the project folder. Assume a competent agent with zero context who
will act on it literally.

```markdown
# HANDOFF — one-line subject

Paste this whole document as your first message in Cowork. It is self-contained.

## Your task
What must be accomplished, concretely, with the actual numbers.

## Before you start — check you actually have access
Prerequisites, each independently verifiable. Say what to do if one is missing —
usually "stop, don't improvise."

## Background — what's wrong and why
The reasoning this session paid for. Include corroborating evidence, and name the
wrong theories explicitly so they don't get re-derived.

## Status
What is DONE and verified, with the figures that prove it. Then a table of what remains.

## Gotchas
Failure modes already hit. Silent ones first.
```

What separates a good handoff from a useless one:

- **Put in the numbers.** "Fix the cost basis" is useless; "THW verified exact at $31,461.60" lets
  the next agent check itself.
- **Record dead ends.** "There are NO return-of-capital transactions in 2026 — do not go looking"
  saves an hour.
- **Mark finished work so it isn't redone.** Repeating a completed financial correction is worse
  than never starting.
- **Name prerequisites honestly.** If the work needs Quicken under Parallels and that lives on one
  machine only, say so at the top, and raise it with the user *before* transferring.

## Step 3 — Materialize, then record the handoff

Do both with ordinary file operations inside the project folder. **You do not need a CLI, a
terminal, or computer-use** — a Cowork session is sandboxed to the project folder it was granted,
and everything required lives there.

**3a. Materialize every file.** iCloud keeps evicted files *dataless*: correct name and size in a
listing, contents still in the cloud, and a read returns empty **with no error**. Reading a file is
what pulls it down. So read every file in the project folder (skip `.handoff/`). This is not
optional — it is what guarantees the other Mac receives real bytes rather than empty placeholders.

**3b. Write the ownership event.** Create this file:

```
PROJECT_FOLDER/.handoff/events/TIMESTAMP-THIS_MACHINE-handoff.json
```

`TIMESTAMP` is UTC in the form `20260819T143052Z`; the filename must sort chronologically, because
the newest event is what determines the current owner.

```json
{ "project": "Quicken Reconciliation",
  "verb": "handoff",
  "machine": "Madoka",
  "to": "Ji-su",
  "note": "one line summary",
  "handoff_doc": "HANDOFF_fidelity_big_cost_basis.md",
  "at": "20260819T143052Z" }
```

`machine` is the Mac you are on and `to` is the other one — Al's are **Madoka** (desktop) and
**Ji-su** (laptop). Determine which you are on from device info; if you cannot, ask rather than
guess, because a wrong owner is worse than no event.

Create `.handoff/events/` if it does not exist. Never edit or delete an existing event — the log is
append-only, because iCloud does not reliably propagate in-place modifications.

*(From a terminal outside the sandbox the same thing is available as
`mirror handoff PROJECT --to MACHINE --note "..."`, which is useful for `status` and `log` across
projects. The skill does not need it.)*

## Step 4 — Report honestly

The work is **staged, not delivered**. iCloud takes ~1 minute at best and longer if the other Mac
has been asleep; a zero exit code is not proof of arrival. Delivery is confirmed only when
`/pickup` runs over there.

Tell the user not to edit the project here until it comes back — two Macs editing one synced folder
produces iCloud conflict copies, and the ownership record is what prevents that.

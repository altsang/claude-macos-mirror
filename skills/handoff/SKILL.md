---
name: handoff
description: Hand the current project's workload to the user's other Mac (Madoka <-> Ji-su). Use when the user says to hand off, move, send, or continue work on their other machine or laptop, or invokes /handoff by name. Writes a self-contained handoff document capturing everything the other machine needs, then transfers ownership of the shared folder. Use this instead of improvising a summary, because a local Cowork project cannot sync its chats and the receiving machine starts with no memory of this conversation.
---

# Hand off a workload to the other Mac

Al works across two Macs, **Madoka** (desktop) and **Ji-su** (laptop). Shared projects live at one
path identical on both:

```
~/Library/Mobile Documents/com~apple~CloudDocs/Claude/Projects/<Project>
```

Run everything through the `mirror` CLI:

```bash
MIRROR=~/workspace/claude-macos-mirror/bin/mirror
```

If that path does not exist, fall back to the engine in the shared tree:
`bash "$(ls -1 ~/Library/Mobile\ Documents/com~apple~CloudDocs/Claude/_handoff/bin/coworkctl-v*.sh | sort -V | tail -1)"`.

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

Write `HANDOFF_<topic>.md` into the project folder. Assume a competent agent with zero context who
will act on it literally.

```markdown
# HANDOFF — <one-line subject>

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

## Step 3 — Transfer

```bash
$MIRROR handoff "<Project>" --to <Machine> --note "<one line>" [--wait]
```

This materializes every file first — iCloud keeps files *dataless* (present in `ls`, contents still
remote, reads return empty with no error), so this is not optional — then records the ownership
event.

## Step 4 — Report honestly

The work is **staged, not delivered**. iCloud takes ~1 minute at best and longer if the other Mac
has been asleep; a zero exit code is not proof of arrival. Delivery is confirmed only when
`/pickup` runs over there.

Tell the user not to edit the project here until it comes back — two Macs editing one synced folder
produces iCloud conflict copies, and the ownership record is what prevents that.

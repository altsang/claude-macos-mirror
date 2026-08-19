---
name: handoff
description: Hand the current project's workload to the user's other Mac (Madoka <-> Ji-su). Use when the user says to hand off, move, send, or continue work on their other machine or laptop, or invokes /handoff by name. Writes a self-contained handoff document capturing everything the other machine needs, then transfers the files and ownership. Use this instead of improvising a summary, because the receiving machine starts with no memory of this conversation.
---

# Hand off a workload to the other Mac

Al works across two Macs, **Madoka** (desktop) and **Ji-su** (laptop). Shared projects live at
one path that is identical on both machines:

```
~/Library/Mobile Documents/com~apple~CloudDocs/Claude/Projects/<Project>
```

Always invoke the tool by resolving the newest version — never hardcode a version number:

```bash
COWORKCTL="$(ls -1 ~/Library/Mobile\ Documents/com~apple~CloudDocs/Claude/_handoff/bin/coworkctl-v*.sh | sort -V | tail -1)"
```

The receiving machine gets the **files** automatically. What it does not get is **this
conversation**. Everything you know that isn't written down is lost at the handoff. That is the
entire reason this skill exists — the file transfer is the easy half.

## Step 1 — Identify project and target

Project = the folder under the shared `Projects/` tree this session has been working in.
Target = whichever of Madoka / Ji-su is not this machine (`scutil --get ComputerName`).
Ask only if genuinely ambiguous.

## Step 2 — Write the handoff document

Write `HANDOFF_<topic>.md` into the project folder. **This is the deliverable.** Assume the reader
is a competent agent with zero context who will act on it literally.

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

- **Put in the numbers.** "Fix the cost basis" is useless; "THW verified exact at $31,461.60"
  lets the next agent check itself.
- **Record dead ends.** "There are NO return-of-capital transactions in 2026 — do not go looking"
  saves an hour.
- **Mark finished work so it isn't redone.** Repeating a completed financial correction is worse
  than never starting.
- **Name prerequisites honestly.** If the work needs Quicken under Parallels and that lives on one
  machine only, say so at the top. Raise it with the user *before* transferring, not after.

## Step 3 — Transfer

```bash
bash "$COWORKCTL" handoff <Project> --to <Machine> --note "<one line>" [--wait]
```

**The transport is iCloud, and it is not synchronous.** Measured between these two Macs: ~54s at
best, several minutes if the far Mac has been asleep, and stalled entirely while it naps. The
command materializes the files (so real bytes exist to upload), records the handoff, and returns.

Direct rsync over SSH was built and worked — 0.95s, md5-verified — but writing into an
iCloud-synced folder means two writers for one path, and FileProvider forks them into
`(name) 2.ext` conflict copies rather than reconciling. Real ones appeared on both Macs. One
writer only, so iCloud carries everything now. Do not add a direct push back in.

`--wait` polls for the other machine's claim and reports the ACK when it lands. Use it when the
other Mac is awake and you want confirmation; skip it when it's asleep, since the wait will just
time out at ~6min.

## Step 4 — Report honestly

The work is **staged, not delivered**. Say that plainly — do not describe a handoff as complete
just because the command exited 0. Delivery is proven only when `/pickup` runs on the other Mac.

Tell the user not to edit the project here until it comes back. Two machines editing one synced
folder is precisely what produces conflict copies, and the ownership record is what prevents it.

If they need it *now* and the other Mac is awake, the honest answer is that iCloud will take about
a minute — not that it's already there.

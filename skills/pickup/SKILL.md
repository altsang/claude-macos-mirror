---
name: pickup
description: Resume a workload handed over from the user's other Mac (Madoka / Ji-su). Use when the user says to pick up, resume, or continue work handed off from their other machine, or invokes /pickup by name. Claims the shared project, forces iCloud to download files that are present in name only, and loads the handoff document as working context before doing anything.
---

# Pick up a workload from the other Mac

Counterpart to `/handoff`. Shared projects live at one path identical on both Macs:

```
~/Library/Mobile Documents/com~apple~CloudDocs/Claude/Projects/PROJECT
```

```bash
MIRROR=~/workspace/claude-macos-mirror/bin/mirror
```

## Step 1 — Materialize, verify, claim

All of this is plain file work inside the project folder. **No CLI, terminal, or computer-use
needed** — the session is sandboxed to the project folder, and everything required is there.

**1a. Read every file** in the project folder (skip `.handoff/`). iCloud keeps evicted files
*dataless*: correct name and size in a listing, contents still remote, and a read returns empty or
truncated **with no error**. There are no `.icloud` stub files to warn you. Reading is what pulls
the content down, so do it before trusting anything you see.

If a file still reads as empty after a retry, **stop and tell the user**. Do not proceed on partial
data — in a financial extract that means silently reasoning from nothing.

**1b. Read the ownership log** at `PROJECT_FOLDER/.handoff/events/*.json`. Sort by filename; the
newest event determines the current owner — `to` if its verb is `handoff`, `machine` if it is
`claim`. If the owner is not this machine, say so and check before continuing: two Macs editing one
synced folder is what produces iCloud conflict copies.

**1c. Write a claim event** so the other Mac knows you have it:

```
PROJECT_FOLDER/.handoff/events/TIMESTAMP-THIS_MACHINE-claim.json
```

```json
{ "project": "Quicken Reconciliation",
  "verb": "claim",
  "machine": "Ji-su",
  "to": "Ji-su",
  "note": "carried over from the handoff event",
  "handoff_doc": "HANDOFF_fidelity_big_cost_basis.md",
  "at": "20260819T144500Z" }
```

Append only — never edit or delete existing events.

## Step 2 — Load the context

The command prints `HANDOFF doc`. Read it as your working brief, not as background. It was written
by a session with context you do not have — where it contradicts your assumptions, it wins.

## Step 3 — Verify prerequisites before acting

Check each prerequisite **on this machine**. The common failure is work that needs something only
the other Mac has — Quicken under Parallels, a mounted removable volume, a live web session.

If one is missing, say so and stop. Do not improvise a substitute. Offer to hand the work back.

## Step 4 — Confirm the plan

Before executing, tell the user what the previous machine finished, what remains, and what you will
do first. Cheaper to catch a stale handoff now than after a wrong edit.

## If the folder is not readable

Symptom: the folder appears connected but every read fails with *"is not inside a folder connected
to Cowork on this device"*. Cause: the grant points at a **symlink**. Grant the real shared path
instead — `$MIRROR path "PROJECT"` prints it, and `$MIRROR check` flags projects in this state.
Finder cannot browse to `~/Library/Mobile Documents`; press ⌘⇧G in the picker and paste.

Note also that **cloud** Cowork projects run in a bridged VM and could not reach `~/Library` at all.
Use the `Local`-badged project for file work.

## Ownership

`pickup` transfers ownership to this machine. From here it is the only one that should edit the
project. If the tool warns the project is owned by another machine, take it seriously — editing
anyway is how iCloud produces `(conflicted copy)` files, and reconciling those by hand in a
financial dataset is miserable.

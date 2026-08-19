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

## Step 1 — Claim and download

```bash
$MIRROR pickup "PROJECT"      # omit the name to resolve whichever is addressed to this Mac
```

**Do not skip this and read files directly.** iCloud keeps evicted files *dataless*: correct name,
correct size in `ls`, contents still in the cloud, and reading one returns empty or truncated data
**with no error**. There are no `.icloud` stub files to warn you and `du` cannot see the problem.
In a financial extract that means silently reasoning from nothing. This command forces the download
and verifies before returning.

If it reports files still remote after the timeout, **stop** and tell the user. Retrying in a
minute usually resolves it.

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

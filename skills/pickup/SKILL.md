---
name: pickup
description: Resume a workload handed over from the user's other Mac (Madoka <-> Ji-su). Use when the user says to pick up, resume, or continue work handed off from their other machine, or invokes /pickup by name. Claims the shared project, forces iCloud to download any files that are present in name only, and loads the handoff document as working context before doing anything.
---

# Pick up a workload from the other Mac

The counterpart to `/handoff`. Al's two Macs, **Madoka** and **Ji-su**, share projects at one path
that is identical on both:

```
~/Library/Mobile Documents/com~apple~CloudDocs/Claude/Projects/<Project>
```

Resolve the newest tool version rather than hardcoding one:

```bash
COWORKCTL="$(ls -1 ~/Library/Mobile\ Documents/com~apple~CloudDocs/Claude/_handoff/bin/coworkctl-v*.sh | sort -V | tail -1)"
```

## Step 1 — Claim and download

```bash
bash "$COWORKCTL" pickup [<Project>]
```

With no project named it resolves whichever one is addressed to this machine.

**Do not skip this and read files directly.** On modern macOS, iCloud keeps files *dataless*: they
appear in `ls` with correct names and sizes while the content is still in the cloud. There are no
`.icloud` stub files to warn you, and `du` cannot see the problem either. Reading one before it
materializes returns empty or truncated content **with no error** — and if the file is a financial
extract, you will silently draw conclusions from nothing. This command forces the download and
verifies every file before returning.

If it reports files still remote after the timeout, **stop** and tell the user. Do not proceed on
partial data — iCloud may simply not have finished, and retrying in a minute usually resolves it.

## Step 2 — Load the context

The command prints the `HANDOFF*.md`. Read it as your working brief, not as background. It was
written by a session with context you do not have; where it contradicts your assumptions, it wins.

## Step 3 — Verify prerequisites before acting

Check each prerequisite **on this machine**. The common failure is a workload needing something
only the other Mac has — Quicken under Parallels, a mounted removable volume, a live web session.

If one is missing, say so immediately and stop. Do not improvise a substitute. Offer to hand the
work back with `/handoff`.

## Step 4 — Confirm the plan

Before executing, tell the user in a few lines: what the previous machine finished, what remains,
and what you'll do first. Cheaper to catch a stale handoff now than after a wrong edit.

## Ownership

`pickup` transfers ownership to this machine by writing a claim event. The other Mac sees it once
iCloud carries the event across — around a minute, longer if it has been asleep. From here this
machine is the only one that should edit the project. If the tool warns the project is owned by a different machine, take
it seriously: editing anyway is how iCloud produces `(conflicted copy)` files, and reconciling
those by hand in a financial dataset is miserable.

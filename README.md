# claude-macos-mirror

Move a Claude **Cowork** workload between two Macs — here, `Madoka` (desktop) and `Ji-su` (laptop).

Shared project files live at one path that is byte-identical on both machines, synced by iCloud
Drive. A small tool tracks which Mac currently owns a project, forces iCloud to actually deliver
file contents, and carries a handoff document that lets a session on the other machine pick the
work up cold.

---

## Read this first — what does and does not move

This is the single most important thing in the repo, and getting it wrong wastes hours.

| Thing | Moves between Macs? |
|---|---|
| **Project files** on disk | ✅ yes — that is what this repo does |
| **Custom Cowork skills** | ✅ yes — automatically, at the account level. Never copy them by hand |
| **claude.ai Projects** | ✅ yes — web, and every Mac |
| **Cowork spaces** (a Cowork "project") | ❌ **no — device-local, never syncs** |
| **Folder grants** (which dir a project may read) | ❌ no — set once per machine |

**A Cowork space cannot travel.** Verified by reading `claude.ai/projects` directly: none of the
Cowork spaces on Madoka appear there, and `claude.ai/project/<spaceId>` does not resolve. Cowork
spaces and claude.ai Projects are two different systems that happen to look alike in the UI.

So "moving a workload" does **not** mean the project shows up on the other Mac. It means:

> the **files** are already there, and a **handoff document** brings a fresh session up to speed.

That document is the load-bearing part. The file sync is the easy half.

Related trap: in the local session JSON, `title` is the **chat** name and `spaceId` is the space —
the space's own name is not stored locally at all. Don't infer a project name from a folder name or
a chat title.

---

## Layout

Runtime (in iCloud, identical path on every Mac):

```
~/Library/Mobile Documents/com~apple~CloudDocs/Claude/
    Projects/<Name>/                 shared project files
    _handoff/bin/coworkctl-v4.sh     the tool
    _handoff/events/<Name>/*.json    append-only ownership log
    _handoff/{handoff,pickup}.skill  importable skill bundles
```

Each Mac symlinks its local project path at the shared copy, so an existing Cowork folder grant
keeps resolving:

```
~/Documents/Claude/Projects/<Name> -> ~/Library/Mobile Documents/.../Claude/Projects/<Name>
```

This repo is the source of truth for the tooling. It lives **outside** iCloud on purpose — a `.git`
directory inside a synced folder is precisely the conflict-copy hazard described in
[docs/findings.md](docs/findings.md).

---

## Setting up a new Mac

```bash
git clone <this repo> ~/workspace/claude-macos-mirror
cd ~/workspace/claude-macos-mirror
./install.sh                 # deploys the tool into the iCloud tree
./install.sh --link Finances # symlink one project into ~/Documents/Claude/Projects
```

Then, once per project, in the Claude desktop app:

1. Open (or start) a Cowork session on that Mac.
2. Grant it the folder `~/Documents/Claude/Projects/<Name>`.
   If the sandbox refuses to follow the symlink, grant the iCloud path directly instead — it is the
   same on both machines, so this is still a one-time step.
3. Import `handoff.skill` and `pickup.skill` from `_handoff/` if they are not already present.
   (Custom skills normally sync on their own; check before importing.)

Prerequisite check: iCloud Drive must be signed in to the **same Apple ID** on both Macs. Confirm
with `defaults read MobileMeAccounts Accounts | grep AccountID`.

---

## Daily use

Resolve the newest tool version rather than hardcoding one — releases are new files, never edits:

```bash
COWORKCTL="$(ls -1 ~/Library/Mobile\ Documents/com~apple~CloudDocs/Claude/_handoff/bin/coworkctl-v*.sh | sort -V | tail -1)"
```

**Send work to the other Mac:**

```bash
bash "$COWORKCTL" handoff Finances --to Ji-su --note "6 securities remain" [--wait]
```

Writes an ownership event and materializes every file so real bytes exist to upload. Before running
it, write or refresh `HANDOFF_<topic>.md` in the project folder — the `/handoff` skill does this for
you, and it is the part that actually matters.

**Pick work up on the other Mac:**

```bash
bash "$COWORKCTL" pickup Finances
```

Forces iCloud to deliver file contents, claims ownership, and prints the handoff document. On that
machine, start a **new Cowork session** — the space from the other Mac will not be there — grant it
the shared folder, and give it the document.

**Other commands:**

```bash
bash "$COWORKCTL" status          # who owns what, on this machine
bash "$COWORKCTL" log Finances    # full ownership history
bash "$COWORKCTL" conflicts       # report iCloud conflict copies (reports only, never deletes)
bash "$COWORKCTL" materialize <p> # force-download a path
```

---

## Expectations that will save you confusion

**This is not synchronous.** iCloud carries a handoff in ~30s when the receiving Mac is awake and
enumerating, and minutes when it has been asleep. `handoff` **stages** work; only `pickup` on the
far side proves it arrived. Never read a successful `handoff` as "it's there."

**A sleeping laptop looks exactly like broken sync.** Ji-su defaults to sleeping after one minute
idle. Before diagnosing anything, check `ssh <peer> uptime` and `pmset -g ps`.

**One machine edits at a time.** That is what the ownership log is for. Two Macs editing one synced
folder is how you get `(conflicted copy)` files, and reconciling those by hand in a financial
dataset is miserable.

**Never commit project data.** `.gitignore` blocks the obvious extensions, but the real rule is that
this repo holds tooling and documentation only. The Quicken files contain account numbers and
cost-basis figures.

---

## Why there is no fast path

A direct rsync-over-SSH transport was built and measured at **0.95s with every file md5-verified**,
in both directions. It was then removed on purpose.

Writing into an iCloud-synced folder means two writers for one path — iCloud delivering its copy
while rsync delivers the same bytes. FileProvider forks them rather than reconciling, and real
conflict copies appeared on both Macs (`events 2`, `peers 2.conf`, `coworkctl-v3 2.sh`, and a
duplicated `.qif`). Speed is not worth a financial dataset quietly growing forked copies.

If you want that speed back, the correct shape is to move the shared tree **out** of iCloud
entirely and let rsync be the only writer — not to add rsync back alongside iCloud.

---

## Further reading

- [docs/findings.md](docs/findings.md) — measured iCloud behaviour, and the traps that cost real
  time: dataless files, in-place modifications that never propagate, enumeration latency, openrsync
  quoting, and two destructive commands to avoid.
- [bin/VERSIONING.md](bin/VERSIONING.md) — why the tool filename carries a version number.

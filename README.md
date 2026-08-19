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

## Getting a project onto both Macs

Do this once per project. After that you only ever run `handoff` and `pickup`.

### Step 0 — install the tooling on each Mac (once per machine)

```bash
git clone https://github.com/altsang/claude-macos-mirror.git ~/workspace/claude-macos-mirror
cd ~/workspace/claude-macos-mirror
./bin/mirror deploy
```

Both Macs must be signed in to the **same Apple ID** in iCloud Drive. Check with:

```bash
defaults read MobileMeAccounts Accounts | grep AccountID
```

**On the second Mac this matters less than it looks.** The engine and the skill bundles live
*inside* the shared tree, so iCloud delivers them on its own. Over there you mainly need
`mirror link` — and `mirror deploy` only if you want to bootstrap before iCloud has caught up.

### Step 1 — move the project into the shared tree

Run this **on the Mac that already has the project**:

```bash
./bin/mirror migrate "Finances"
```

That copies `~/Documents/Claude/Projects/Finances` into the iCloud tree, verifies every file by
md5, and only then renames the original aside and leaves a symlink in its place. Your existing
Cowork folder grant keeps working, because the path it points at is unchanged.

The original is preserved as `.Finances.pre-icloud-<timestamp>` and is never deleted. Keep it until
you have confirmed Cowork still reads the project, then remove it yourself.

If verification fails, nothing is moved and the command refuses to continue.

### Step 2 — link it on the other Mac

Wait for iCloud to carry the folder over — a minute or so if the Mac is awake — then:

```bash
./bin/mirror link "Finances"
```

If a real (non-symlink) directory of that name already exists there, the command stops and tells
you to move it aside yourself. It will not clobber project files.

### Step 3 — point Cowork at it (once per machine)

In the Claude desktop app on that Mac:

1. Start a **new Cowork session**. The space from the other Mac will **not** be there — see the
   table at the top. That is expected, not a failure.
2. Grant it the folder `~/Documents/Claude/Projects/Finances`.
   If the sandbox refuses to follow the symlink, grant the iCloud path directly instead; it is
   identical on both machines, so this is still a one-time step.
3. Import `handoff.skill` and `pickup.skill` from `_handoff/` if they are not already in your
   skills list. Custom skills usually sync on their own — check before importing.

Both Macs can now see the same files. From here it is just the loop below.

### If the folder name doesn't match the project name

Cowork project names and folder names drift apart easily — a project called
**Quicken Reconciliation** whose folder is `Finances` will have you typing the wrong one
every time. The folder name is what appears in every `mirror` command, so it is worth aligning:

```bash
./bin/mirror rename "Finances" "Quicken Reconciliation"
```

That renames the shared folder, moves its ownership history, and repoints this Mac's symlink.
Two things it cannot do for you, and it prints both:

1. **Re-grant the folder in Cowork on this Mac** — the old path no longer exists, so the existing
   grant points at nothing.
2. **On the other Mac**, delete the stale symlink and run `mirror link` with the new name.

Do this before you have much handoff history, and ideally while only one Mac is involved.

---

## Going back and forth

This is the part you do repeatedly. **On the Mac you are leaving:**

```bash
mirror handoff Finances --to Ji-su --note "6 securities remain"
```

Before running it, write or refresh `HANDOFF_<topic>.md` in the project folder. The `/handoff`
skill does this for you and it is the part that actually matters — the other machine gets your
files automatically but knows nothing about your conversation.

Then stop editing the project on this Mac.

**On the Mac you are moving to:**

```bash
mirror pickup Finances
```

This forces iCloud to deliver real file contents, claims ownership, and prints the handoff
document. Start a **new Cowork session** there, grant it the shared folder if you have not already,
and give it that document as its first message.

**Coming back** is the same two commands with the machines reversed. The ownership log accumulates,
so `log` shows the whole history:

```bash
mirror status          # who owns what, from this machine
mirror log Finances    # full ownership history
mirror conflicts       # report iCloud conflict copies (reports only, never deletes)
mirror materialize <p> # force-download a path
```

`mirror` is one entry point for everything. Setup verbs (`deploy`, `migrate`, `link`, `rename`,
`check`) run from this repo; runtime verbs (`status`, `handoff`, `pickup`, `log`, `conflicts`,
`materialize`) are passed through to the versioned engine in the iCloud tree, so you never have to
resolve a version yourself. Put `bin/` on your PATH, or call it as `./bin/mirror`.

On a Mac without this repo cloned, call the engine directly:

```bash
bash "$(ls -1 ~/Library/Mobile\ Documents/com~apple~CloudDocs/Claude/_handoff/bin/coworkctl-v*.sh | sort -V | tail -1)" status
```

### What the loop looks like in practice

```
Madoka                                    Ji-su
------                                    -----
/handoff  ──── writes HANDOFF_x.md ───▶
          ──── files + event via iCloud ─▶
                                          /pickup
                                          (new Cowork session, grant folder,
                                           paste the handoff doc, do the work)
          ◀─── files + event via iCloud ── /handoff
/pickup
```

Nothing about the *project* moves. The files and the brief move, and each machine runs its own
Cowork session over the same folder.

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

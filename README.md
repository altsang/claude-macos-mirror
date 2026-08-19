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

## Runbook — mirror a project to another machine, start to finish

Machine **A** is the Mac that already has the project. Machine **B** is the one you want to move
work to. Every command is copy-pasteable; expected output is shown where it matters.

### Part 0 — pick the shared drive (once, ever)

Any folder that syncs between the two Macs works: **iCloud Drive**, **Google Drive**, **Dropbox**.
The tool defaults to iCloud. Trade-offs:

| Drive | Path | Notes |
|---|---|---|
| **iCloud Drive** (default) | `~/Library/Mobile Documents/com~apple~CloudDocs/` | Same path on any Mac regardless of Apple ID. Files go *dataless* when evicted — handled by `pickup` |
| **Google Drive** | `~/Library/CloudStorage/GoogleDrive-<email>/My Drive/` | Path embeds the account email, so it can differ per machine — set it per machine with `use-root`. Check whether it is in "stream" mode, which makes files on-demand |
| **Dropbox** | `~/Library/CloudStorage/Dropbox/` | Same path on both. Watch for selective-sync excluding the folder |

The paths do **not** have to match across machines. The stable path is the symlink at
`~/Documents/Claude/Projects/<Project>`, and the Cowork folder grant is per-machine anyway.

Whatever you choose, confirm it is actually syncing between both Macs **before** you start — put a
file in it on A and watch it appear on B. Every hard-to-debug failure in this system traces back to
a drive that wasn't syncing.

### Part 1 — on machine A (has the project)

**1. Clone and install.**

```bash
git clone https://github.com/altsang/claude-macos-mirror.git ~/workspace/claude-macos-mirror
cd ~/workspace/claude-macos-mirror
```

**2. If you are NOT using iCloud, point it at your drive.**

```bash
./bin/mirror use-root "~/Library/CloudStorage/GoogleDrive-you@gmail.com/My Drive/Claude"
```

Skip this for iCloud. Verify either way:

```bash
./bin/mirror check
#   shared root: …/Claude
#   ✓ shared tree present     ← if this is ✗, the drive is not synced yet. Stop and fix that.
```

**3. Deploy the tooling into the shared tree.**

```bash
./bin/mirror deploy
```

**4. Find the project's folder name.** This is the folder Cowork granted, *not* the project title —
they are often different. In the Claude app, open the project and look at its folder, or:

```bash
ls ~/Documents/Claude/Projects/
```

**5. Move the project into the shared tree.**

```bash
./bin/mirror migrate "Quicken Reconciliation"
#   ✓ copied
#   ✓ verified 17 files identical by md5
#   ✓ linked   ~/Documents/Claude/Projects/… -> …/Claude/Projects/…
#   ✓ original preserved at ~/Documents/Claude/Projects/.<Project>.pre-icloud-<timestamp>
```

It copies first, verifies every file by md5, and only then moves the original aside and leaves a
symlink. **If verification fails nothing is moved.** The original is never deleted.

If the folder name is generic and you would rather it matched the project name, do it now, before
there is any handoff history:

```bash
./bin/mirror rename "Finances" "Quicken Reconciliation"
```

**6. Re-grant the folder in Cowork on A.** Only needed if you renamed, or if the grant broke.
Open the project in the Claude app and point it at `~/Documents/Claude/Projects/<Project>`.

**7. Confirm Cowork can still read the project** — open it and list a file. Once that works, delete
the `.<Project>.pre-icloud-*` backup. Not before.

### Part 2 — on machine B

**8. Wait for the drive to carry the folder over.** A minute or so if B is awake. Check from B:

```bash
ls ~/Library/Mobile\ Documents/com~apple~CloudDocs/Claude/Projects/     # or your drive's path
```

If B has been asleep this can take several minutes. B must be **awake** — a sleeping laptop is
indistinguishable from a broken drive.

**9. Install on B.** Optional but recommended:

```bash
git clone https://github.com/altsang/claude-macos-mirror.git ~/workspace/claude-macos-mirror
cd ~/workspace/claude-macos-mirror
./bin/mirror use-root "<B's path to the shared folder>"   # only if it differs from the default
```

You do **not** need `deploy` on B — the engine and skill bundles live inside the shared tree, so
they arrive on their own.

**10. Link the project on B.**

```bash
./bin/mirror link "Quicken Reconciliation"
#   ✓ linked ~/Documents/Claude/Projects/… -> …/Claude/Projects/…
```

Without the repo on B, the same thing by hand:

```bash
ln -s ~/Library/Mobile\ Documents/com~apple~CloudDocs/Claude/Projects/"Quicken Reconciliation" \
      ~/Documents/Claude/Projects/"Quicken Reconciliation"
```

**11. Pull the file contents down and verify.**

```bash
./bin/mirror materialize ~/Documents/Claude/Projects/"Quicken Reconciliation"
#   all files materialized          ← or "N dataless file(s) — forcing download"
```

This is not optional on iCloud. Files show correct names and sizes in `ls` while their contents are
still in the cloud, and reading one returns empty **with no error**.

**12. Set up Cowork on B.** In the Claude app on B:

- Start a **new Cowork session**. The project from A will **not** appear — Cowork spaces are
  device-local. That is expected; see the table at the top of this README.
- Grant it `~/Documents/Claude/Projects/<Project>`.
- Import `handoff.skill` and `pickup.skill` from the shared `_handoff/` folder if they are not
  already in your skills list.

### Part 3 — verify the mirror

Run on **both** machines and compare:

```bash
./bin/mirror check       # shared root, engine version, projects, symlinks
./bin/mirror status      # who owns what
./bin/mirror conflicts   # must report nothing
```

To prove the files are genuinely identical rather than merely present:

```bash
cd ~/Documents/Claude/Projects/"Quicken Reconciliation" \
  && find . -type f ! -name '.DS_Store' -exec md5 -q {} \; -print | paste - - | sort | md5
```

Same digest on both Macs means the mirror is real. Different means the drive has not finished
syncing — wait, re-run `materialize`, and check `conflicts`.

### Part 4 — from now on

Setup is done and never repeats for this project. Day to day you only use the loop in the next
section: `mirror handoff` when you leave a machine, `mirror pickup` when you arrive at one.

---

## Going back and forth

This is the part you do repeatedly. **On the Mac you are leaving:**

```bash
mirror handoff "Quicken Reconciliation" --to Ji-su --note "6 securities remain"
```

Before running it, write or refresh `HANDOFF_<topic>.md` in the project folder. The `/handoff`
skill does this for you and it is the part that actually matters — the other machine gets your
files automatically but knows nothing about your conversation.

Then stop editing the project on this Mac.

**On the Mac you are moving to:**

```bash
mirror pickup "Quicken Reconciliation"
```

This forces iCloud to deliver real file contents, claims ownership, and prints the handoff
document. Start a **new Cowork session** there, grant it the shared folder if you have not already,
and give it that document as its first message.

**Coming back** is the same two commands with the machines reversed. The ownership log accumulates,
so `log` shows the whole history:

```bash
mirror status          # who owns what, from this machine
mirror log "Quicken Reconciliation"   # full ownership history
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

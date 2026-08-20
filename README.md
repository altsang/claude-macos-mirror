# claude-macos-mirror

Move a Claude **Cowork** workload between two Macs — here `Madoka` (desktop) and `Ji-su` (laptop).

Project files live in one shared-drive folder both machines can reach. Moving work across is two
commands — `mirror send` on one Mac, `mirror receive` on the other — each of which blocks until the
transfer is provable. One Cowork skill, `/handoff`, writes the document that carries the *context* —
the half no CLI can produce, because it lives in the conversation.

---

## The problem

Cowork projects appear on every machine — but the moment you attach a **local folder** to one, it
becomes machine-bound:

- the project is written into *that Mac's* `spaces.json`, gets a `Local` badge, and is invisible on
  the web and on your other Mac
- **chat is not available for local Cowork projects**, so there is no synced conversation history
  and no project memory to fall back on
- the folder itself is only on that machine's disk

So if you're reconciling accounts on the desktop and want to continue on the laptop, three separate
things have to travel: the **files**, the **project definition**, and — hardest — the **context**
of what you were doing and why.

There is no native path for the third one. A cloud project *does* sync chats and memory, but its
Cowork sessions run in a bridged VM that couldn't reach `~/Library` in testing, so it can't touch
your files. **File access and synced context are mutually exclusive today.** That gap is what this
repo fills.

## What actually syncs

Worth internalising before anything else — getting this wrong wastes hours.

| Thing | Crosses machines? |
|---|---|
| Files in a shared-drive folder | ✅ the drive does this — no tooling needed |
| Custom Cowork skills | ✅ automatically, at the account level. Never copy them by hand |
| Cloud projects, their chats, instructions, memory | ✅ server-side |
| **Projects with a local folder** (`Local` badge) | ⚠️ definition is copyable; nothing automatic |
| **Conversations in a local project** | ❌ never — this is why the handoff document exists |
| Folder links (which folder a project reads) | ❌ per-machine — but `mirror` writes them; cloud projects re-grant per session |

## What this repo does — and doesn't

**It does not sync your files.** iCloud (or Google Drive, or Dropbox) does that. What this adds:

- a **migration** that moves a project into the shared tree and md5-verifies every file before
  touching the original
- an **ownership log** so both Macs know which one holds a project, preventing the conflict copies
  that two machines editing one synced folder produce
- **materialization** — forcing the drive to deliver file *contents*, not just names
- a **handoff document** workflow, the only mechanism that carries context to a machine whose
  project cannot sync its chats
- **folder linking without the file picker** — `mirror` writes the project's folder path itself,
  on both Macs
- **upload verification** — proof the bytes actually left this Mac, which "staged" never gave you
- **one verb per side** — `send` and `receive`, each blocking until the transfer is provable,
  instead of a sequence of commands none of which could confirm the others' work
- **diagnostics** for the failure modes that are silent and confusing, chiefly symlinked folder
  links

---

## Install

### 1. Once per machine

```bash
git clone git@github.com:altsang/claude-macos-mirror.git ~/workspace/claude-macos-mirror
cd ~/workspace/claude-macos-mirror
./bin/mirror deploy
```

### Choosing where the shared folder lives

Everything hinges on one folder that **both Macs can see**. Any synced drive works — iCloud Drive,
Google Drive, Dropbox — but the drive has to actually be mounted on *both* machines.

**Check first.** Run this on each Mac; only a path that exists on both is a candidate:

```bash
ls -d ~/Library/Mobile\ Documents/com~apple~CloudDocs \
      ~/Library/CloudStorage/* 2>/dev/null
```

A real example of why this matters — on one setup:

```
~/Library/Mobile Documents/com~apple~CloudDocs                    ✓ both Macs
~/Library/CloudStorage/GoogleDrive-altsang@gmail.com/My Drive     ✓ both Macs
~/Library/CloudStorage/GoogleDrive-agilecto@gmail.com/My Drive    ✗ desktop only
~/Library/CloudStorage/Dropbox                                    ✗ desktop only
```

Dropbox was installed and looked like a fine choice, but it isn't signed in on the laptop — it would
have failed silently at the worst moment.

#### Option A — iCloud Drive (the default)

Nothing to configure. The tool creates and uses:

```
~/Library/Mobile Documents/com~apple~CloudDocs/Claude/
```

The path is identical on every Mac regardless of which Apple ID is signed in, which is why it is the
default. Both Macs must be on the **same Apple ID**:

```bash
defaults read MobileMeAccounts Accounts | grep AccountID
```

#### Option B — Google Drive

The path contains **your account email**, so find yours first:

```bash
ls -d ~/Library/CloudStorage/GoogleDrive-*
# → /Users/you/Library/CloudStorage/GoogleDrive-altsang@gmail.com
```

Then point the tool at a `Claude` folder inside `My Drive` — run this **on each Mac**:

```bash
./bin/mirror use-root "~/Library/CloudStorage/GoogleDrive-altsang@gmail.com/My Drive/Claude"
```

Two Google-specific cautions:

- **If you have more than one Google account signed in**, make sure both Macs use the *same* one.
  The email is in the path, so `GoogleDrive-you@gmail.com` and `GoogleDrive-work@company.com` are
  different roots entirely.
- **Check Drive is mirroring, not streaming.** In Google Drive → Settings → "My Drive syncing
  options", *Mirror files* keeps real files on disk. *Stream files* keeps them on-demand, which
  behaves like iCloud's dataless files — `mirror receive` handles it, but mirroring avoids the
  problem.

#### Either way

The tool creates the same structure under whichever root you choose:

```
CHOSEN_ROOT/
    Projects/PROJECT/       ← your project files; this is the folder the project reads
    _handoff/               ← engine, skill bundles, exported project definitions
```

Roots do **not** have to match across machines — the folder link is per-machine, so each Mac can use
its own path. Matching paths are simply convenient: one copy-pasteable string works on both.

Confirm before going further:

```bash
./bin/mirror check      # ✓ shared tree present   ← if ✗, the drive hasn't synced yet. Fix that first.
```

Both Macs must be signed into the **same account** on the drive:
`defaults read MobileMeAccounts Accounts | grep AccountID`

On the second machine `deploy` is optional — the engine and skill bundles live *inside* the shared
tree, so the drive delivers them.

### 2. Once, for the skills

Claude app → **Settings → Skills → Add**, and upload:

```
skills/handoff/SKILL.md
```

Import on one Mac only; skills sync at the account level.

**`/handoff` is the only skill this setup installs.** The context lives in the Cowork conversation,
so only that session can write the document — and `mirror send` refuses to ship a project without
one.

**`skills/pickup/SKILL.md` is kept in the repo but deliberately not installed.** `mirror receive`
already claims the project and puts the document on your clipboard, leaving the skill nothing
mechanical to do — and a Cowork session cannot force iCloud to deliver, so it can report a folder
as missing when the data is merely un-enumerated (finding 12). Pasting the document after `receive`
is the same brief with one fewer failure mode. Upload it only if you want the prerequisite ritual.

### 3. Once per project

On the Mac that already has the project:

```bash
ls ~/Documents/Claude/Projects/          # find the folder name — often NOT the project name
./bin/mirror migrate "Quicken Reconciliation"
```

It copies into the shared tree, verifies every file by md5, then moves the original aside as
`.PROJECT.pre-icloud-TIMESTAMP`. Nothing is moved if verification fails, and the original is never
deleted. **No symlink is created** — see below.

If the folder name doesn't match the project name, fix it now, before there's any history:

```bash
./bin/mirror rename "Finances" "Quicken Reconciliation"
```

Then link the folder to the project **on each Mac**. `mirror` does this for you — the file picker
is not involved:

- on the Mac you just migrated, `migrate` already repointed it (it does this whenever Claude is
  quit; if it was running, it tells you to run `mirror project-repath`)
- on the other Mac, `mirror receive` writes it as part of the transfer

Confirm either way, then relaunch Claude:

```bash
./bin/mirror check      # granted folders that will fail in Cowork:  none ✓
```

Approve the macOS permission prompt if one appears on first read. That is the OS asking about
`~/Library/Mobile Documents` — once per Mac, not once per project.

### What the link actually is

One field: `folders[].path` on the project's entry in `spaces.json`. There is no token, bookmark or
consent record anywhere else — a UI-attached project and a `mirror`-written one have byte-identical
structure. The app seeds each new session's connected scope from that field, which is why writing
it is a complete grant and not half of one.

Verified 2026-08-20: `Adobe Stock Plan` was linked on both Macs by `mirror` alone, the folder picker
never opened, and Cowork read its files on the receiving Mac.

Two rules follow from it being a plain file:

- **Claude must be quit while it is written.** A running app rewrites `spaces.json` from memory on
  exit and silently discards the change. `project-import` and `project-repath` refuse to run
  otherwise; `migrate` degrades to printing the command for you.
- **Never point it at a symlink** — see the warning below.

### If you ever do need the picker

For a project `mirror` doesn't manage, or to attach a second folder by hand. `./bin/mirror path
"Quicken Reconciliation"` prints the exact path **and copies it to the clipboard**; in the app open
the project → **Add folder** → press **⌘⇧G** → paste → Return → Open.

⌘⇧G is unavoidable there because you cannot browse to the path: Finder hides `~/Library` and
relabels `Mobile Documents/com~apple~CloudDocs` as **"iCloud Drive"**, so the folder named "Mobile
Documents" is not there to click. The sidebar route is **iCloud Drive** → `Claude` → `Projects` →
your project — the same folder under its display name.

> **Link the shared path — never a symlink.** Do not point a project at
> `~/Documents/Claude/Projects/PROJECT` even if it exists and resolves to the right place. Cowork
> registers a symlinked folder as connected — `get_device_info` reports it, the UI shows it
> attached — and then fails **every** read inside it with *"is not inside a folder connected to
> Cowork on this device"*. Because it looks fine, the error points nowhere near the cause. This is
> why `migrate` no longer creates symlinks. `./bin/mirror check` flags any project in this state and
> prints the repair command.

Use the **`Local`**-badged project for file work. Cloud projects run their sessions in a bridged VM
that can't reach these paths.

To put the project on the second Mac, send it — there is no separate export/import step:

```bash
./bin/mirror send "Quicken Reconciliation" --to Ji-su --no-doc   # on A
./bin/mirror receive "Quicken Reconciliation"                    # on B, with Claude QUIT
```

`--no-doc` because a first move usually has no handoff document yet; drop it once there is one.
`send` ships the project definition alongside the files and waits until they have uploaded;
`receive` md5-verifies every file, then writes B's project definition **and its folder link**, so
there is no picker step on the second Mac. Relaunch Claude and the project is ready to read.

It carries name, instructions and id — not the chat history, which is what the handoff document is
for.

Underneath, those two verbs are `project-export` / `project-import --wait` plus `wait`, `handoff`
and `pickup`, all of which still work on their own if you want the pieces:

```bash
./bin/mirror project-export "Quicken Reconciliation"          # on A
./bin/mirror project-import "Quicken Reconciliation" --wait    # on B, with Claude QUIT
```

`--wait` blocks until both halves have crossed: the definition (a few hundred bytes, arrives first)
and then the files, md5-verified against the manifest. That second half matters because iCloud
delivers files *dataless* — listed at full size with no content — and only a read materializes
them. Import without waiting and Cowork opens a project whose files read empty, with nothing on
screen to say why. Nothing is written to `spaces.json` unless every file verifies.

### Verify

```bash
./bin/mirror check        # shared root, engine, broken or symlinked folder links
./bin/mirror status       # who owns what
./bin/mirror conflicts    # must report nothing
```

Same digest on both Macs means the mirror is real, not merely present:

```bash
cd "$(./bin/mirror path 'Quicken Reconciliation')" \
  && find . -type f ! -name '.DS_Store' ! -path './.handoff/*' -exec md5 -q {} \; -print \
  | paste - - | sort | md5
```

---

## Run

Two steps per side: one in Cowork, because only that session knows what you were doing, and one in
a terminal, because only a terminal can prove the transfer.

**Leaving a machine** — in the Cowork session that did the work:

```
/handoff
```

It writes `HANDOFF_TOPIC.md` into the project folder and stops. That document is the whole payload:
a local project cannot sync its chats, so anything you knew and didn't write down is lost here.

Then, in a terminal:

```bash
./bin/mirror send "Quicken Reconciliation" --to Ji-su --note "one line" --wait
```

`send` materializes the folder, exports the project definition, writes an md5 manifest, records the
ownership event naming your document, and then **waits until every file has actually uploaded** —
including `.handoff/`, since the ownership event is what tells the other Mac it owns the project.
With `--wait` it keeps going until the other Mac claims it, which is the only real proof of
delivery.

It refuses to send a project with no `HANDOFF*.md` (`--no-doc` overrides). Shipping files without
the reasoning behind them is the failure this repo exists to prevent.

**Arriving at the other machine** — in a terminal:

```bash
./bin/mirror receive "Quicken Reconciliation"
```

`receive` waits for the handoff event addressed to this Mac, pulls every file and **verifies each
one by md5 against the manifest**, defines the project here if this Mac has never seen it (the only
step that needs Claude quit), claims it, prints the handoff document, and copies it to the
clipboard. It refuses to claim a project that was not handed to this machine.

Then open the project in Cowork and **⌘V**. That document is the receiving session's whole brief;
its own "Before you start" section carries the prerequisites, which is why `/pickup` is no longer
installed here.

### Locking yourself out of a project you handed away

The ownership log records who holds a project; it cannot stop you editing the copy that stays on
this Mac. `--hold` can:

```bash
./bin/mirror send "Quicken Reconciliation" --to Ji-su --note "…" --hold
```

Two `spaces.json` writes, both per-machine and both reversed by `mirror receive` when the project
comes home:

- **a notice in the project's instructions.** A local project's `instructions` land verbatim in the
  Cowork session's `systemPrompt` (verified 2026-08-20), so every session you start here reads
  *"CHECKED OUT TO Ji-su … refuse and say the project is checked out"* before you type a word.
- **`folders[]` emptied**, so a session that ignores the notice still cannot read a byte.

The banner is wrapped in `<!-- mirror:hold -->` markers that `project-export` and `project-import`
always strip, so "checked out to Ji-su" can never travel *to* Ji-su.

Both are `spaces.json` writes, so Claude must be quit — one quit covers both. If it's running,
`send` completes the transfer and prints `mirror hold "PROJECT" --to Ji-su` to run afterwards.
`mirror release "PROJECT"` undoes it by hand; `receive` does it for you.

**What it does not cover:** anything outside Cowork — Finder, Excel, Quicken. Nothing in iCloud
offers a lock, and locking the files themselves would block the sync daemon from writing the other
Mac's changes back, which is worse than the problem.

### Why the split

A Cowork session is sandboxed to its project folder — it cannot see `fileproviderctl`, the shared
`_handoff/` tree, or any CLI. So it can never verify that a transfer completed. The terminal can
never write the document, because the context lives in the session. Each side does only what the
other cannot, and the mechanics have exactly one implementation.

### Expectations

**It is not synchronous.** Measured on a live handoff, 2026-08-20 — 21.6 KB of project across
iCloud between these two Macs:

| Leg | Measured |
|---|---|
| `send` → every file confirmed `isUploaded` | **25s** (5 files, 21.6 KB) · 56s for a 10 MB payload · ~110s for 25 MB |
| `send` → receiving Mac has verified and written its `claim` | **2m12s** · 2m46s in the 10 MB run |
| that `claim` becoming visible back on the sender | **~90s** further |

Upload scales with size and you can watch it. Delivery to an idle peer runs ~2–3 minutes almost
regardless of size — the latency is the drive noticing, not the bytes moving.

**Uploaded ≠ delivered.** `send` proves the bytes left this Mac; only the claim event proves they
landed. `send --wait` waits for it.

**One machine edits at a time.** That's what the ownership log is for.

**The document is the deliverable.** Files arrive on their own. Put the numbers in it.

### Everything else from a terminal

```bash
./bin/mirror status                    # every project, who owns it
./bin/mirror log "Quicken Reconciliation"
./bin/mirror check                     # broken or symlinked folder links
./bin/mirror conflicts                 # iCloud conflict copies
./bin/mirror materialize "$(./bin/mirror path 'PROJECT')"
```

The flags worth knowing on the daily pair:

| Flag | On | Effect |
|---|---|---|
| `--note "…"` | `send` | one line recorded in the ownership log; what `mirror status` shows |
| `--wait` | `send` | after the upload, block until the other Mac claims it |
| `--doc FILE` | `send` | name the document explicitly instead of taking the newest `HANDOFF*.md` |
| `--no-doc` | `send` | ship files with no context — for a first move, or a folder that isn't a project |
| `--hold` | `send` | lock this Mac out of the project until it comes back (below) |
| `--force` | `send` | send a project the log says this Mac doesn't hold. Check `mirror log` first |
| `--timeout N` | both | seconds for the whole wait (default 900) |

`handoff`, `pickup`, `project-export`, `project-import` and `wait` still exist and still work as
separate verbs — `send` and `receive` are those, composed, with the verification that was missing.

---

## Layout

```
~/Library/Mobile Documents/com~apple~CloudDocs/Claude/
    Projects/PROJECT/                     shared files  ← the project reads THIS path
    Projects/PROJECT/.handoff/events/     append-only ownership log
    Projects/PROJECT/HANDOFF_topic.md     the context, written by /handoff
    _handoff/bin/coworkctl-v7.sh          engine (versioned — never edited in place)
    _handoff/projects/PROJECT.TS.json     exported project definitions, one per send
    _handoff/projects/PROJECT.TS.manifest.json   sizes + md5s, what receive verifies against
    _handoff/{handoff,pickup}.skill       importable skill bundles
```

Releases are new files, never edits: the drive does not reliably propagate an in-place modification
of a file the other Mac has already read. Callers resolve `coworkctl-v*.sh | sort -V | tail -1`.
This repo lives **outside** the shared drive — a `.git` directory in a synced folder is the same
two-writer hazard that produces conflict copies.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| *"is not inside a folder connected to Cowork"*, folder looks attached | the link points at a **symlink** | `mirror check`, then `mirror project-repath PROJECT "$(mirror path PROJECT)"` with Claude quit |
| A file reads empty, no error | evicted/dataless — contents still in the cloud | read it again; `mirror materialize`. `du` and `.icloud` checks cannot see this |
| Nothing arrives on the other Mac | it's asleep, or you didn't enumerate | `ssh peer 'uptime; pmset -g ps'`; list the whole parent chain, not just the leaf |
| `(name) 2.ext` files appearing | two writers to one synced path | `mirror conflicts` (reports only), remove by exact path — **never** by glob |
| A Cowork session says the project has no `.handoff` directory | uploaded, but never enumerated on this Mac — and a sandboxed session cannot force the drive to deliver | `mirror receive "P"` — its wait loop lists the whole parent chain, which is what makes iCloud hand it over |
| `/handoff` tries to do the transfer itself | old skill version registered | re-upload `skills/handoff/SKILL.md`; the current one writes the document and stops |
| Skill upload rejected, "cannot have XML tags" | angle-bracket placeholders in `SKILL.md` | use bare words, not `<Project>` |
| Project missing on the other Mac | local projects don't sync | `mirror send "P" --to MACHINE --no-doc`, then `mirror receive "P"` |
| Not sure the files actually reached iCloud | `handoff` only staged them; nothing verified the upload | `mirror send` — it polls `isUploaded` until every file is up |

[docs/findings.md](docs/findings.md) has the measurements behind each of these, and the two commands
that destroyed data during development.

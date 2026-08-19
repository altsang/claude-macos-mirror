# claude-macos-mirror

Move a Claude **Cowork** workload between two Macs — here `Madoka` (desktop) and `Ji-su` (laptop).

Project files live in one shared-drive folder both machines can reach. A small CLI sets that up and
verifies it; two skills (`/handoff`, `/pickup`) do the day-to-day transfer from inside a Cowork
session.

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
| Folder grants | ❌ per-machine, and per-session for cloud projects |

## What this repo does — and doesn't

**It does not sync your files.** iCloud (or Google Drive, or Dropbox) does that. What this adds:

- a **migration** that moves a project into the shared tree and md5-verifies every file before
  touching the original
- an **ownership log** so both Macs know which one holds a project, preventing the conflict copies
  that two machines editing one synced folder produce
- **materialization** — forcing the drive to deliver file *contents*, not just names
- a **handoff document** workflow, the only mechanism that carries context to a machine whose
  project cannot sync its chats
- **diagnostics** for the failure modes that are silent and confusing, chiefly symlinked folder
  grants

---

## Install

### 1. Once per machine

```bash
git clone git@github.com:altsang/claude-macos-mirror.git ~/workspace/claude-macos-mirror
cd ~/workspace/claude-macos-mirror
./bin/mirror deploy
```

Defaults to iCloud Drive. For another drive:

```bash
./bin/mirror use-root "~/Library/CloudStorage/GoogleDrive-you@gmail.com/My Drive/Claude"
```

Roots need not match across machines — grants are per-machine anyway — but matching paths mean one
copy-pasteable string works on both.

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
skills/pickup/SKILL.md
```

Import on one Mac only; skills sync at the account level. `/handoff` and `/pickup` become available
in Cowork.

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

Then, **on each Mac**, grant the folder in the Claude app. This is the fiddliest step, so in full:

**i. Get the exact path.** In a terminal:

```bash
./bin/mirror path "Quicken Reconciliation"
```

It prints one line — the literal string you will paste. For example:

```
/Users/altsang/Library/Mobile Documents/com~apple~CloudDocs/Claude/Projects/Quicken Reconciliation
```

It is also **copied to your clipboard automatically**, so you can go straight to the picker. Same
string on both Macs (only the username differs).

**ii. Open the folder picker.** In the Claude app, open the project → **Add folder**. A standard
macOS file picker appears.

**iii. Press ⌘⇧G.** A small "Go to Folder" box drops down over the picker.

**iv. Paste the path into that box and press Return.** Paste the entire line from step i:

```
/Users/altsang/Library/Mobile Documents/com~apple~CloudDocs/Claude/Projects/Quicken Reconciliation
```

The picker jumps to that folder and shows its contents. Nothing to type by hand — if you find
yourself typing, you are in the wrong box.

**v. Confirm.** With that folder selected, click Open / Add, then approve the macOS permission
prompt if one appears.

**Why ⌘⇧G at all?** Because you cannot browse to it. Finder hides `~/Library`, and it relabels
`Mobile Documents/com~apple~CloudDocs` as **"iCloud Drive"** — so the folder named "Mobile
Documents" simply is not there to click. ⌘⇧G goes straight to a path regardless.

If you would rather click: in the picker's sidebar choose **iCloud Drive**, then `Claude` →
`Projects` → your project. That is the same folder by its display name.

> **Grant this shared path — never a symlink.** Do not grant
> `~/Documents/Claude/Projects/PROJECT` even if it exists and points at the right place. Cowork
> registers a symlinked folder as connected — `get_device_info` reports it, the UI shows it
> attached — and then fails **every** read inside it with *"is not inside a folder connected to
> Cowork on this device"*. Because it looks fine, the error points nowhere near the cause. This is
> why `migrate` no longer creates symlinks. `./bin/mirror check` flags any project in this state and
> prints the repair command.

Use the **`Local`**-badged project for file work. Cloud projects run their sessions in a bridged VM
that can't reach these paths.

To put the project on the second Mac, copy its definition:

```bash
./bin/mirror project-export "Quicken Reconciliation"   # on A — writes into the shared tree
./bin/mirror project-import "Quicken Reconciliation"   # on B, with Claude QUIT
```

Carries name, instructions and id; not the chat history. Editing `spaces.json` while Claude runs is
pointless — the app rewrites it from memory on exit.

### Verify

```bash
./bin/mirror check        # shared root, engine, symlinked grants
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

Day to day you use the skills, in a Cowork session in the `Local` project. No terminal.

**Leaving a machine:**

```
/handoff
```

Refreshes `HANDOFF_TOPIC.md` in the project folder, reads every file to force the drive to deliver
its contents, and records an ownership event at `PROJECT/.handoff/events/`.

**Arriving at the other machine:**

```
/pickup
```

Reads every file (verifying nothing came through empty), checks the ownership log, claims the
project, and loads the handoff document as its working brief.

Then start a **new** Cowork session there and give it that document. The project's conversations do
not travel — that's the whole reason the document exists.

### Expectations

**It is not synchronous.** ~30s at best; minutes if the receiving Mac has been asleep. `/handoff`
**stages**; only `/pickup` proves arrival.

**One machine edits at a time.** That's what the ownership log is for.

**The document is the deliverable.** Files arrive on their own. Everything you knew and didn't write
down is lost at the handoff. Put the numbers in it.

### From a terminal

The CLI covers what a sandboxed session cannot — cross-project ownership, and repair:

```bash
./bin/mirror status                    # every project, who owns it
./bin/mirror log "Quicken Reconciliation"
./bin/mirror handoff "PROJECT" --to MACHINE --note "..."   # terminal equivalent of /handoff
./bin/mirror pickup "PROJECT"
./bin/mirror materialize "$(./bin/mirror path 'PROJECT')"
```

A Cowork session's shell is an isolated Linux VM that sees **only** its granted project folder — not
`~/workspace`, not the shared `_handoff/` tree. That's why the skills use plain file writes and why
per-project state lives in `PROJECT/.handoff/`.

---

## Layout

```
~/Library/Mobile Documents/com~apple~CloudDocs/Claude/
    Projects/PROJECT/                     shared files  ← grant THIS path
    Projects/PROJECT/.handoff/events/     append-only ownership log
    _handoff/bin/coworkctl-v6.sh          engine (versioned — never edited in place)
    _handoff/projects/PROJECT.json        exported project definitions
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
| *"is not inside a folder connected to Cowork"*, folder looks attached | grant points at a **symlink** | `mirror check`, then `mirror project-repath PROJECT "$(mirror path PROJECT)"` with Claude quit |
| A file reads empty, no error | evicted/dataless — contents still in the cloud | read it again; `mirror materialize`. `du` and `.icloud` checks cannot see this |
| Nothing arrives on the other Mac | it's asleep, or you didn't enumerate | `ssh peer 'uptime; pmset -g ps'`; list the whole parent chain, not just the leaf |
| `(name) 2.ext` files appearing | two writers to one synced path | `mirror conflicts` (reports only), remove by exact path — **never** by glob |
| `/handoff` says it can't reach the CLI | old skill version registered | re-upload `skills/*/SKILL.md`; current versions need no CLI |
| Skill upload rejected, "cannot have XML tags" | angle-bracket placeholders in `SKILL.md` | use bare words, not `<Project>` |
| Project missing on the other Mac | local projects don't sync | `mirror project-export` / `project-import` |

[docs/findings.md](docs/findings.md) has the measurements behind each of these, and the two commands
that destroyed data during development.

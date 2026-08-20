# Measured findings

Everything here was verified on macOS 26.6.2 (Ji-su) and Darwin 25.5 (Madoka) on 2026-08-18.
These are not style preferences — each one cost real debugging time, and several look like
"iCloud is broken" until you know the mechanism.

---

## 1. Evicted iCloud files are *dataless*, not `.icloud` stubs

A file evicted from local storage keeps its name and its correct `st_size`, but `st_blocks == 0`
and the content is still in the cloud. **There are no `.icloud` stub files on modern macOS** —
searching for them returns zero even when most of the drive is evicted.

Reading a dataless file returns empty or truncated content **with no error**.

```python
st.st_size > 0 and st.st_blocks == 0   # the only reliable test
```

To materialize: read the file through to EOF, then re-check. `brctl download` does not block until
complete.

Measured: `du -sh` reported **23 MB** for an iCloud Drive holding **~1.03 GB across 397 files**,
75 of them dataless. `du` counts materialized blocks only, so it is blind to exactly the problem
you are looking for.

This is why `pickup` materializes before returning. During the acceptance test it caught a real
dataless `.qif` and downloaded it in 1s — without that, the receiving session would have parsed an
empty financial extract.

## 2. In-place modifications may never propagate

iCloud reliably carries **new** files between Macs. An in-place **modification** of a file the peer
has already cached can stay stale indefinitely — FileProvider pins the cached copy.

Measured: a rewritten `coworkctl.sh` was still the old md5 on the receiving Mac minutes later,
while a brand-new file crossed in ~54s.

Two consequences, both load-bearing:

- **Ownership state is an append-only log.** Every transition writes a NEW event file under
  `_handoff/events/<Project>/`. Nothing is ever rewritten. Current owner = newest event.
- **The tool is versioned, not edited.** Write `coworkctl-v5.sh`; never edit v4 once it has shipped.
  Callers resolve `coworkctl-v*.sh | sort -V | tail -1`.

## 3. Enumeration sets your latency

iCloud does not push to an idle Mac. The directory must be enumerated (`ls`) before a read, and
`test -f` on a missing path does **not** trigger it.

Critically, you must enumerate the **whole parent chain** — `_handoff/`, then `events/`, then
`events/<Project>/` — not just the leaf.

Measured on the same file: enumerating only the leaf, an event was still missing after **220s**.
Enumerating the parent chain, the next one landed in **30s**. Most "iCloud is slow" readings during
development were really "the reader never enumerated properly."

`refresh()` walks the whole chain. Do not trim it.

## 4. Two writers to one iCloud path produce conflict copies

Pushing via rsync into an iCloud-synced folder while iCloud delivers the same bytes makes
FileProvider fork them into `name 2.ext`. Observed on both Macs: `events 2`, `peers 2.conf`,
`coworkctl-v3 2.sh`, and a duplicated `.qif`.

Keep one writer. This is why the direct transport was removed, and why this git repo lives outside
iCloud — a `.git` directory in a synced folder is the same hazard with worse consequences.

## 5. macOS ships openrsync

`rsync --version` reports "openrsync: protocol version 29 / rsync version 2.6.9 compatible".
There is no `--protect-args` and no `-s`.

The shared path contains spaces (`Mobile Documents`), and a remote spec is parsed by the remote
shell, so remote paths must be **single-quoted**:

```bash
rsync -a -e ssh "$SRC/" "user@host:'$DST/'"
```

Without it: `server receiver mode requires two argument`.

(Not used by the tool any more, but needed for any manual administration over SSH.)

## 6. A sleeping laptop is indistinguishable from broken sync

Ji-su defaults to `sleep 1` — one minute of inactivity — and Low Power Mode (battery only) defers
iCloud sync. Several "iCloud is stalled" measurements were really "the laptop napped between SSH
calls."

Before diagnosing sync:

```bash
ssh <peer> 'uptime; pmset -g ps'
ssh <peer> 'nohup caffeinate -dimsu -t 900 >/dev/null 2>&1 &'   # pin awake for a test window
```

## 7. Attaching a folder makes a project machine-bound

A Claude project lives in one of two places, decided by whether a local folder is attached:

- **No folder** → server-side. Appears on claude.ai and on every Mac.
- **Folder attached** → written into *that Mac's* `spaces.json`, shown with a `Local` badge, and
  invisible on the web and on the other Mac.

```
~/Library/Application Support/Claude/local-agent-mode-sessions/<account>/<org>/spaces.json
```

Plain JSON. Each entry is the whole definition: `id`, `name`, `folders[].path`, `instructions`,
`createdAt`, `updatedAt`.

Counted on one setup: 8 cloud projects visible on the web and both Macs; 11 local to Madoka; 2
local to Ji-su. The local counts match each machine's `spaces.json` exactly. The UI shows a folder
name beside the badge only when an entry has exactly one folder — entries with several show a bare
`Local` badge, which is a handy way to sanity-check the UI against the file.

**A local project therefore CAN be copied** — it is a JSON object. `mirror project-export` writes
it into the shared tree, `mirror project-import` splices it into the other Mac's `spaces.json` with
the folder path rewritten. What does **not** travel is the conversation history inside the project;
that is what the handoff document is for.

Edit `spaces.json` only while Claude is quit — a running app rewrites it from memory and silently
discards the change. `project-import` and `project-repath` refuse to run otherwise.

**How this was originally got wrong.** An earlier pass concluded "Cowork spaces are device-local and
cannot travel", from two bad inferences: `claude.ai/projects` did not list them (true, but only
because folder-attached projects are not server-side), and `claude.ai/project/<id>` did not resolve
(true, but the Cowork URL form is `claude.ai/cowork/project/<id>`). Neither was evidence that the
definition was unmovable. `spaces.json` was never opened. The lesson: when concluding that
something is impossible, find the file that stores it first.

Related: in session JSON, `title` is the **chat** name and `spaceId` points at the `spaces.json`
entry. A project's real name is recorded only in `spaces.json`.

## 8. A symlinked folder registers as connected, then fails every read

**Never grant Cowork a symlinked folder.** Grant the real path.

Symptom: `get_device_info` reports the folder as connected and the UI shows it attached, but every
operation inside it fails with:

> `... is not inside a folder connected to Cowork on this device`

Listing fails, staging files fails, and the local shell mount comes up empty. Because the folder
*looks* connected, the error points nowhere near the cause.

Mechanism: the grant is registered against the symlink path. When Cowork resolves an actual file it
gets the real path — here `~/Library/Mobile Documents/…` — compares that against the connected
scope, finds it outside, and denies it.

Verified 2026-08-19 on Ji-su. Same project, same files, same machine:

| Granted path | Result |
|---|---|
| `~/Documents/Claude/Projects/<P>` (symlink) | registered, every read denied |
| `~/Library/Mobile Documents/…/Projects/<P>` (real) | reads correctly |

Confirmed with a random token in a canary file that could not be inferred from context.

Consequences, all now built in:

- `mirror migrate` no longer leaves a symlink behind; it repoints the project at the shared copy.
- `mirror link` is deprecated, creates nothing, and explains this.
- `mirror path <Project>` prints the exact path (and copies it) for the rare hand grant.
- `mirror check` flags any project whose folder is a symlink and prints the repath command.
- `mirror project-repath <Project> <path>` fixes an existing one.

If you ever do open the picker, Finder will not browse to `~/Library/Mobile Documents` — it is
hidden, and Finder relabels `com~apple~CloudDocs` as "iCloud Drive". Press **⌘⇧G** and paste.

## 9. The folder "grant" is one JSON field — no picker required

Attaching a folder in the app writes exactly one thing: `folders[].path` on the project's entry in
`spaces.json`. There is no bookmark blob, permission token or consent record anywhere else in
`~/Library/Application Support/Claude` — a UI-attached project and one written by `mirror` have
identical key sets (`createdAt, folders, id, instructions, links, name, projects, updatedAt`).
`.project-cache/` holds cloud-project content only; the `grantedAt` keys in session files are
computer-use app permissions, unrelated to folders.

The app then **seeds each new session's `userSelectedFolders` from that field** — sessions in a
project all carry its path without the picker ever being reopened. That is why writing the field is
a complete grant rather than half of one, and why a symlinked path fails: the session's connected
scope is that string, and a resolved real path falls outside it (finding 8).

Two observations pinned it down:

- 2026-08-19 20:46 `mirror` wrote the shared path for `Adobe Stock Plan` while Claude was quit;
  the app launched at 20:46:10 and **rewrote `spaces.json` from memory at 20:52 keeping that
  path** — it adopted a link it had never shown a picker for.
- 2026-08-20 `Adobe Stock Plan` was imported onto the second Mac with
  `mirror project-import --wait`, which writes the folder link itself. The picker was never
  opened on that machine and Cowork read the project's files.

So the whole per-machine grant step is `migrate` / `project-import` / `project-repath`, with Claude
quit. What is *not* scriptable: the one-time macOS consent for the location (`TCC` shows
`kTCCServiceFileProviderDomain` allowed for `com.anthropic.claudefordesktop` once granted), and any
write while the app is running — it rewrites `spaces.json` from memory on exit and discards it.

## 10. `isUploaded` is the only way to know the bytes left this Mac

`handoff` could only ever report work as *staged*: the local file is complete, and nothing said
whether iCloud had taken it. The signal that answers it is FileProvider's, via
`fileproviderctl evaluate <file>`, which prints `isUploaded` alongside the download keys.

Verified 2026-08-20 on Darwin 25.5:

| Probe | Result |
|---|---|
| `fileproviderctl evaluate FILE` → `isUploaded` | **works** — 0 immediately after write, 1 when uploaded |
| `fileproviderctl evaluate FILE` → `isUploading` | useless — stayed 0 for an entire 110s upload |
| `brctl status PATH` | fails: *"Client zone not found"* — the legacy CloudDocs path is dead |
| `mdls -name kMDItemIsUbiquitous` | `(null)`, as are the other `kMDItemUbiquitous*` keys |

A 25 MB file written into the shared tree read `isUploaded = 0` at creation and flipped to 1 after
~110s. So poll `isUploaded`, never `isUploading`.

Two consequences now built into `mirror send`:

- It polls every file **including `.handoff/`** — the ownership event is precisely the part that
  tells the other Mac it owns the project, and it uploads like any other file.
- If the probe returns no `isUploaded` key at all (a drive that is not FileProvider-backed), it
  says upload state is unavailable and exits 2 rather than blocking or claiming false proof.

**Uploaded is still not delivered.** Only the receiving Mac's `claim` event proves that, which is
what `send --wait` waits for.

### Why pickup could not have caught a partial transfer

An un-uploaded file is not dataless on the far Mac — it is **absent from the listing entirely**.
`/pickup` read "every file in the folder" with no idea how many there should be, so a partial
transfer looked exactly like a complete one. `project-export`/`import` had solved this with a
manifest and md5s; handoff had no equivalent until `send` started writing the same manifest and
`receive` started verifying against it.

## 11. What a verified transfer actually costs, end to end

First real cross-Mac run of `send`/`receive`, 2026-08-20, Madoka → Ji-su over iCloud.

A plumbing test with a 10 MB payload:

```
20260820T091632Z  Madoka  handoff -> Ji-su    upload verified 4/4 in 56s
20260820T091918Z  Ji-su   claim   -> Ji-su    2m46s after the send
                                              claim visible on Madoka ~90s later
```

Then the live project (21.6 KB — a spreadsheet and an 8.5 KB handoff document):

```
20260820T092533Z  Madoka  handoff -> Ji-su    upload verified 5/5 in 25s
20260820T092745Z  Ji-su   claim   -> Ji-su    2m12s after the send
```

So the shape is: **upload is fast and knowable, delivery is slow and only observable from the far
side.** Uploading is bounded by size (56s for 10 MB, 25s for 21 KB, ~110s for 25 MB) and can be
confirmed locally. Delivery to an idle peer runs ~2–3 minutes regardless of size, and the only
proof is the `claim` event coming back.

The file count polled is larger than the project's: 5 files for a 2-file project, because the
ownership event and the manifest upload too, and they are exactly what the far Mac needs first.

## 12. A sandboxed session cannot make iCloud deliver — so it cannot tell "missing" from "late"

Observed 2026-08-20 on the live handoff. Every file, `.handoff/events/*.json` included, read
`isUploaded = 1` on the sending Mac. On the receiving Mac, `/pickup` in a Cowork session reported
**"no `.handoff` directory"** — and it was right about what it could see.

iCloud does not push to an idle Mac; a parent has to be enumerated before new entries appear
(finding 3). A Cowork session listing its project folder does not prod the drive hard enough to
surface a hidden subdirectory that has never been materialized there. The data was in the cloud the
whole time.

The session therefore cannot distinguish **not sent**, **not yet delivered**, and **delivered but
not enumerated** — three states with three different responses, and it sees one. `mirror receive`
resolves it by listing the whole chain (`_handoff/`, `Projects/`, the project, `.handoff/`,
`.handoff/events/`) every six seconds until the event appears, then verifying by md5.

Practical consequence: **when a skill says something is missing from a shared folder, do not believe
it until a terminal has looked.** Run `mirror receive`, or at minimum `ls` the parent chain.

## 13. Cowork on a cloud project runs in a bridged VM with per-session folder access

A Cowork session started from a **cloud** project runs in a cloud VM (`/home/claude`, Linux) with a
bridge to the Mac — it reports the machine as e.g. `ji-su-local`. Two consequences:

- **Folder access is per session, not per project.** A folder attached to the project does not
  reach a conversation; each session needs its own grant. Its picker offered only Desktop,
  Downloads, or a typed path.
- Grants under `~/Library` did not succeed through the bridge in testing, whereas a **local**
  Cowork session (the `Local`-badged kind) reads the same iCloud path without trouble — ten
  sessions have run against `~/Library/Mobile Documents/…` folders successfully.

So for file-heavy work, use a **local** project. Cloud projects are better when you want chats,
instructions and memory to sync; local projects are what actually reach the disk.

## 14. A Cowork session is sandboxed to its granted folder — put per-project state inside it

The shell a Cowork session gets on the Mac is an isolated Linux VM that sees **only the project
folder it was granted**. It cannot reach `~/workspace`, the shared `_handoff/` tree, or any other
path, and no additional permission grant changes that. Driving Terminal via computer-use is the
only way to run an outside binary, which is a poor way to run a one-line command.

Everything a session *can* do is a file operation, and all of it can live in the project folder:

| Operation | How the session does it |
|---|---|
| write the handoff document | ordinary file write |
| read the ownership log | JSON files in `PROJECT/.handoff/events/` |
| materialize dataless files | **read them** — reading is what pulls content down |

The first design read that as "a skill must not depend on a CLI", and duplicated the mechanics in
both places. That was wrong in one direction: the sandbox also means a session can **never verify a
transfer** — no `fileproviderctl` for upload state, no manifest outside the folder to md5 against,
no view of the other project. Two implementations of the mechanics, neither able to prove anything.

Revised 2026-08-20, each side now does only what the other cannot:

| | Cowork session | terminal (`mirror`) |
|---|---|---|
| write the handoff document | **only it can** — the context is the conversation | no |
| materialize, manifest, ownership event | no | **yes** |
| verify upload / verify arrival by md5 | impossible from the sandbox | **yes** |
| define the project, link its folder | no — `spaces.json` is outside | **yes** |

So `/handoff` writes the document and stops; `mirror send` carries it. `mirror receive` verifies
and claims; `/pickup` reads the result. One implementation of the mechanics, and the session is
still never asked to do something it cannot check.

Ownership events therefore live at `PROJECT/.handoff/events/TIMESTAMP-MACHINE-verb.json`
(engine v6), not in the shared `_handoff/events/` tree where v4/v5 kept them. Verified 2026-08-19:
an event written as a plain file by hand is read back correctly by the CLI, and vice versa.

The original design put them outside the project because it looked like shared infrastructure. It
is per-project state, and putting it outside made the skill unusable from within a session.

## 15. Custom Cowork skills already sync

`skills-plugin/.../manifest.json` lists user-created skills with server-issued `skillId`s,
`creatorType: "user"`, and server timestamps — it is an account-level manifest.

Confirmed empirically: `parallels-windows-apps` was present on Ji-su at the identical path with
matching account UUIDs, without anyone copying it. Do not build skill-syncing machinery.

---

## Two commands that caused damage during development

Both were recovered in full, but neither should be repeated.

**`brctl evict <path>`** executes immediately and takes no confirmation. It was run inside a loop
probing which `brctl` subcommands exist, and evicted the entire iCloud Drive. `brctl --help` lists
only `diagnose` and `log`, but the other verbs exist and *run*.

**`find … -name '* 2*' -delete`** to clean conflict copies. That glob matches real filenames
containing a space followed by `2` — it destroyed `GS Vintage VII 2023 Exchanges.qif` on both Macs
(matched on "2023"). Recovered only because a pre-migration backup existed.

Match `* 2.*` and `* 2`, inspect the list, and remove by exact path. `coworkctl conflicts` therefore
only **reports**; it never deletes.

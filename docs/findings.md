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

## 7. Cowork spaces are not claude.ai Projects

Verified by reading `claude.ai/projects` directly. claude.ai Projects sync across web and both Macs.
Cowork spaces carry a `spaceId` UUID in `local-agent-mode-sessions/*/*/local_*.json`, are
**device-local**, and never sync; `claude.ai/project/<spaceId>` does not resolve.

None of Madoka's Cowork spaces appear in the claude.ai project list. This is why some projects
appear on only one machine and others everywhere.

Also: the session `title` field is the **chat** name, not the project name. The space's own name is
not stored locally at all.

## 8. Custom Cowork skills already sync

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

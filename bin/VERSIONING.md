# Why the filenames are versioned

iCloud does not reliably propagate an in-place MODIFICATION of a file the other Mac
has already read — FileProvider pins the cached copy. Measured 2026-08-18: a rewritten
coworkctl.sh was still the old md5 on the receiving Mac minutes later, while a brand-new
file crossed in ~54s.

So every release is a NEW file: coworkctl-v1.sh, coworkctl-v2.sh, ...
Never edit one in place. Bump the number and write a new file.

Callers should resolve the newest version rather than hardcoding one:

    COWORKCTL="$(ls -1 ~/Library/Mobile\ Documents/com~apple~CloudDocs/Claude/_handoff/bin/coworkctl-v*.sh \
                 | sort -V | tail -1)"
    bash "$COWORKCTL" status

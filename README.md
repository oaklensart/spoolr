# SPOOLR

> **Card memory, multi-session offload & local archival for photographers, with a verdict you can actually trust.**

SPOOLR gives your physical SD cards a permanent identity, offloads each shoot into
its own isolated session folder, archives your keepers to a local vault with
**read-back SHA-256 verification**, and only ever tells you a card is **Safe to
Format** when every keeper has been re-read and byte-matched in that vault.

A moment never comes back. Neither should a frame, so when anything is uncertain,
SPOOLR stops loudly and refuses to call a card safe.

---

## The safety contract

This is the part that matters, so it's stated plainly:

- **SPOOLR never deletes from your card.** Formatting is always your explicit action,
  in-camera, after you've seen a green verdict.
- **Backups are verified by reading them back.** After copying a keeper to your vault,
  SPOOLR re-hashes the file *in the vault* and requires an exact SHA-256 match before
  recording it. A truncated or half-written copy is rejected, not trusted.
- **The verdict re-reads at the moment of truth.** When you run `reconcile` with the
  card inserted, SPOOLR hashes each keeper's **original on the card** and its **copy in
  the vault** and compares them right then, never a remembered value. If the card isn't
  inserted, it verifies against the staged copies and tells you so.
- **Every RAW format is handled everywhere.** The recognised formats live in one list
  used by every stage, so a format can never be offloaded but skipped at verification.
  Supported: `RW2 ARW CR3 CR2 NEF DNG ORF RAF SRW PEF RWL IIQ 3FR GPR`.
- **Read-only stays read-only.** `status`, `where` and `reconcile` never write to your
  card. A card is only ever tagged during a deliberate `spoolr` offload.
- **A card you never formatted is still a backup.** If the drive holding a session's
  originals is lost, stolen or dies, `spoolr restore` pulls that session's keepers
  back off the card. It rebuilds the frame list from the session manifest, or from
  `backups.tsv` when the manifest died with the drive. That index lives on your Mac and
  survives losing both staging and vault. Every candidate is matched by SHA-256, never
  by filename: cameras reuse filenames after a rollover, and a frame that no longer
  hashes correctly is reported, not silently handed back.
- **A restore is never mistaken for an archive.** It lands in a new session marked
  `RESTORED`, never `VERIFIED`, so a recovered card cannot read as safe to format. The
  frames are back, but they are not yet in a vault.

These guarantees are covered by `test/test_spoolr.sh`, including adversarial cases
(corrupted vault copy, missing keeper, filename collisions across sessions, and a
camera that reused a filename between the original pull and the restore).

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/oaklensart/spoolr/main/install.sh | bash
```

Then check your environment:

```bash
spoolr doctor
```

**Recommended:** `brew install exiftool` for reliable embedded-preview extraction and
accurate shoot dates. SPOOLR works without it (it falls back to `sips`), but exiftool is
better.

---

## The workflow

```bash
# 1. Insert the card and offload everything new since your last pull
spoolr

# 2. Open the session folder and color-tag your keeper JPEGs in Finder (Green/Purple)

# 3. Archive the keepers to your vault drive (read-back verified)
spoolr backup

# 4. Ask the question that matters
spoolr reconcile
```

When you see:

```text
✓ SAFE TO FORMAT CARD — every keeper re-read and byte-matched in your vault.
```

every keeper is confirmed in your vault. Format the card in-camera with confidence.

---

## Where are my frames?

Drives get unplugged and `/Volumes/DRIVE` reshuffles on remount, so an absolute path
alone rots quietly. Every session records the **volume UUID** it landed on, plus the
path relative to that volume's mount point, and `spoolr where` resolves them against
what is attached right now:

```bash
spoolr where             # every session
spoolr where SES-018     # one session
spoolr where --json      # for scripts and the dashboard
```

Each session reports as one of five states:

| State | Meaning |
| :--- | :--- |
| `both` | Staged and archived. Nothing to do. |
| `vault` | In the vault only. Staging has been cleared, which is fine. |
| `staging` | Staged but never archived. Do not format that card yet. |
| `offline` | On a volume this Mac knows by UUID but cannot currently see. Reconnect it. |
| `neither` | No copy this tool can find. **This is the only true alarm.** |

`offline` exists so that "unplugged" stops being reported as "lost".

---

## Commands

| Command | Description |
| :--- | :--- |
| `spoolr [slug]` | Rolling offload into a new session folder (`2026-08-24_SES-018_street`) |
| `spoolr --fast [slug]` | Offload without the copy-time card re-read (roughly 2x faster; reconcile is still the gate) |
| `spoolr --today [slug]` | Offload only today's frames without advancing the rolling watermark |
| `spoolr name <NAME>` | Set or rename the inserted card's permanent identity |
| `spoolr status` | Read-only fill gauge, frame headroom, and run history |
| `spoolr where [SES-ID]` | Locate a session: staging / vault / both / offline / neither |
| `spoolr reveal` | Open the latest session folder in Finder, ready for tagging |
| `spoolr backup [path]` | Copy keepers to the vault with read-back SHA-256 verification |
| `spoolr reconcile [folder]` | Pre-wipe verdict (re-reads card + vault; card-wide by default) |
| `spoolr restore [SES-ID] [dir]` | Re-download a past session's keepers off the card when the originals are lost |
| `spoolr restore --dry-run` | Report what is still recoverable from the card; copy nothing |
| `spoolr peel [folder]` | Extract embedded JPEG previews for fast Finder color tagging |
| `spoolr eject` | Safely unmount the active card |
| `spoolr config` | Set staging and vault directories |
| `spoolr doctor` | Environment self-check (tools, paths, cards, active hash backend) |
| `spoolr reset [--all] [--purge-staging]` | Clear tracking data for a clean slate. Photos on cards/vault are never touched; `--purge-staging` also deletes staged folders, `--all` also clears saved paths. |
| `spoolr ui` | Launch the Bento dashboard on `localhost:7331` |

---

## The Bento dashboard, the primary interface

```bash
spoolr ui
```

The dashboard is built to run the **whole workflow from the browser**, leaving the
terminal optional. Dependency-free (Python standard library only), it detects your card
live and walks you through a pipeline that lights up as each stage completes:

1. **Name the card** inline, or rename it. This writes the card's permanent identity.
2. **Pull** offloads new frames and auto-peels previews. On a card's first pull it asks
   what counts as "new" right in the browser. The panel turns **green** with the RAW count.
3. **Peel** turns **green** when every RAW has a preview, **amber** (`X/N`) if some
   couldn't be read. The RAW count always reflects what was pulled, regardless of stray JPEGs.
4. **Tag** opens the session folder in Finder to color-tag your keepers, then reports how
   many survived the cull once they reach the vault.
5. **Backup** shows a **vault picker** the first time, listing your attached drives (click
   to choose, or type a path). After that, keepers are read-back-verified into the vault
   and the panel turns **green**.
6. **Reconcile** turns **green** for SAFE, **red** for not safe.

A live fill gauge with frame headroom, a "last backup" pill that ages green to amber to
red, the session ledger, and **Reset** and **power-off** buttons round it out. The server
binds to loopback only and refuses cross-origin requests.

---

## Where your data lives (`~/.config/spoolr/`)

Durable, and independent of any staging folder or card wipe:

- `cards.tsv`: physical card registry (ID, nickname, capacity, first seen).
- `ledger.tsv`: append-only session history (timestamp, session, card, dates, frames,
  path, status, then any `key=value` fields). Sessions carry `vol_uuid=`, `vol_name=`,
  `rel_path=` and `vol_kind=` so they survive a remount, and a restored session carries
  `restored_from=SES-NNN`.
- `backups.tsv`: per-frame vault index (session, filename, sha256, vault_path, timestamp).
- `watermarks/<CARD_ID>.watermark`: per-card rolling watermark.
- Each session folder also carries a `.spoolr_manifest.tsv` (filename, size, sha256,
  source path).

Sessions are staged under `~/Pictures/Spoolr` by default. Run `spoolr config` to point
staging and the vault somewhere else.

### Advanced / testing overrides

- `SPOOLR_CONFIG_DIR`: use a different config directory.
- `SPOOLR_CARD_GLOB`: override the `/Volumes/*` card-detection root.
- `SPOOLR_ASSUME_YES`: never prompt; fail loudly instead of blocking (for automation).
- `SPOOLR_UI_PORT`: serve the dashboard on a port other than 7331.
- `SPOOLR_BIN`: the binary the dashboard bridge drives (set automatically by `spoolr ui`).
- `SPOOLR_LIB`: set to `1` to source `bin/spoolr` without running the dispatcher, so
  individual functions can be called directly.

---

## Requirements

macOS with `bash`, `rsync` and a SHA-256 tool, all built in. SPOOLR prefers the native
`/sbin/sha256sum` and falls back to `/usr/bin/shasum`, which is a Perl script and roughly
4x slower on a full card. `spoolr doctor` reports which backend is active. Both produce
identical digests, so an archive hashed by either stays valid.

`exiftool` is recommended. Python 3 (built in) is required for the dashboard.

## Tests

```bash
bash test/test_spoolr.sh
```

## License

MIT © [oaklens.art](https://oaklens.art)

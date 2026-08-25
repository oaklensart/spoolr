# INGEST

> **Card memory, multi-session offload & local archival for photographers — with a verdict you can actually trust.**

INGEST gives your physical SD cards a permanent identity, offloads each shoot into
its own isolated session folder, archives your keepers to a local vault with
**read-back SHA-256 verification**, and only ever tells you a card is **Safe to
Format** when every keeper has been re-read and byte-matched in that vault.

A moment never comes back. Neither should a frame — so when anything is uncertain,
INGEST stops loudly and refuses to call a card safe.

---

## The safety contract

This is the part that matters, so it's stated plainly:

- **INGEST never deletes from your card.** Formatting is always your explicit action,
  in-camera, after you've seen a green verdict.
- **Backups are verified by reading them back.** After copying a keeper to your vault,
  INGEST re-hashes the file *in the vault* and requires an exact SHA-256 match before
  recording it. A truncated or half-written copy is rejected, not trusted.
- **The verdict re-reads at the moment of truth.** When you run `reconcile` with the
  card inserted, INGEST hashes each keeper's **original on the card** and its **copy in
  the vault** and compares them right then — not a remembered value. If the card isn't
  inserted, it verifies against the staged copies and tells you so.
- **Every RAW format is handled everywhere.** The recognised formats live in one list
  used by every stage, so a format can never be offloaded but skipped at verification.
  Supported: `RW2 ARW CR3 CR2 NEF DNG ORF RAF SRW PEF RWL IIQ 3FR GPR`.
- **Read-only stays read-only.** `status` and `reconcile` never write to your card.
  A card is only ever tagged during a deliberate `ingest` offload.
- **A card you never formatted is still a backup.** If the drive holding a session's
  originals is lost, stolen or dies, `ingest restore` pulls that session's keepers
  back off the card. It rebuilds the frame list from the session manifest, or — when
  that died with the drive — from `backups.tsv`, which lives on your Mac and survives
  losing both staging and vault. Every candidate is matched by SHA-256, never by
  filename: cameras reuse filenames after a rollover, and a frame that no longer
  hashes correctly is reported, not silently handed back.
- **A restore is never mistaken for an archive.** It lands in a new session marked
  `RESTORED`, never `VERIFIED`, so a recovered card cannot read as safe to format —
  the frames are back, but they are not yet in a vault.

These guarantees are covered by `test/test_ingest.sh`, including adversarial cases
(corrupted vault copy, missing keeper, filename collisions across sessions, and a
camera that reused a filename between the original pull and the restore).

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/oaklens/ingest/main/install.sh | bash
```

Then check your environment:

```bash
ingest doctor
```

**Recommended:** `brew install exiftool` for reliable embedded-preview extraction and
accurate shoot dates. INGEST works without it (falls back to `sips`), but exiftool is
better.

---

## The workflow

```bash
# 1. Insert the card and offload everything new since your last pull
ingest

# 2. Open the session folder and color-tag your keeper JPEGs in Finder (Green/Purple)

# 3. Archive the keepers to your vault drive (read-back verified)
ingest backup

# 4. Ask the question that matters
ingest reconcile
```

When you see:

```text
✓ SAFE TO FORMAT CARD — every keeper re-read and byte-matched in your vault.
```

every keeper is confirmed in your vault. Format the card in-camera with confidence.

---

## Commands

| Command | Description |
| :--- | :--- |
| `ingest [slug]` | Rolling offload into a new session folder (`2026-08-24_SES-018_street`) |
| `ingest --fast [slug]` | Offload without the copy-time card re-read (≈2× faster; reconcile is still the gate) |
| `ingest --today [slug]` | Offload only today's frames without advancing the rolling watermark |
| `ingest name <NAME>` | Set or rename the inserted card's permanent identity |
| `ingest status` | Read-only fill gauge, frame headroom, and run history |
| `ingest backup [path]` | Copy keepers to the vault with read-back SHA-256 verification |
| `ingest reconcile [folder]` | Pre-wipe verdict (re-reads card + vault; card-wide by default) |
| `ingest restore [SES-ID] [dir]` | Re-download a past session's keepers off the card when the originals are lost |
| `ingest restore --dry-run` | Report what is still recoverable from the card; copy nothing |
| `ingest peel [folder]` | Extract embedded JPEG previews for fast Finder color tagging |
| `ingest eject` | Safely unmount the active card |
| `ingest config` | Set staging and vault directories |
| `ingest doctor` | Environment self-check (tools, paths, cards) |
| `ingest reset [--all] [--purge-staging]` | Clear tracking data for a clean slate. Photos on cards/vault are never touched; `--purge-staging` also deletes staged folders, `--all` also clears saved paths. |
| `ingest ui` | Launch the Bento dashboard on `localhost:7331` |

---

## The Bento dashboard — the primary interface

```bash
ingest ui
```

The dashboard is built to run the **whole workflow from the browser** — the terminal is
optional. Dependency-free (Python standard library only), it detects your card live and
walks you through a pipeline that lights up as each stage completes:

1. **Name the card** inline (or rename it) — writes the card's permanent identity.
2. **Pull** → offloads new frames and auto-peels previews. On a card's first pull it asks
   what counts as "new" right in the browser. Panel turns **green** with the RAW count.
3. **Peel** → **green** when every RAW has a preview, **amber** (`X/N`) if some couldn't be
   read — the RAW count always reflects what was pulled, regardless of stray JPEGs.
4. **Tag** → opens the session folder in Finder to color-tag your keepers.
5. **Backup** → the first time, a **vault picker** lists your attached drives (click to choose,
   or type a path); after that, keepers are read-back-verified into the vault and the panel turns **green**.
6. **Reconcile** → **green** SAFE / **red** not safe.

A live fill gauge with frame headroom, a "last backup" pill that ages green→amber→red, the
session ledger, and a **Reset** button round it out. The server binds to loopback only and
refuses cross-origin requests.

---

## Where your data lives (`~/.config/ingest/`)

Durable, and independent of any staging folder or card wipe:

- `cards.tsv` — physical card registry (ID, nickname, capacity, first seen).
- `ledger.tsv` — append-only session history (timestamp, session, card, dates, frames, path, status,
  then any `key=value` fields — a restored session carries `restored_from=SES-NNN`).
- `backups.tsv` — per-frame vault index: `session · filename · sha256 · vault_path · timestamp`.
- `watermarks/<CARD_ID>.watermark` — per-card rolling watermark.
- Each session folder also carries a `.ingest_manifest.tsv` (filename, size, sha256, source path).

### Advanced / testing overrides

- `INGEST_CONFIG_DIR` — use a different config directory.
- `INGEST_CARD_GLOB` — override the `/Volumes/*` card-detection root.
- `INGEST_ASSUME_YES` — never prompt; fail loudly instead of blocking (for automation).

---

## Requirements

macOS with `bash`, `rsync`, `shasum` (all built in). `exiftool` recommended.
Python 3 (built in) for the dashboard.

## Tests

```bash
bash test/test_ingest.sh
```

## License

MIT © [oaklens.art](https://oaklens.art)

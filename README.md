# SPOOLR

> **Card memory, persistent identity & local archival for photographers — with a pre-wipe verdict you can actually trust.**

SPOOLR is a zero-dependency macOS engine and Bento dashboard that gives your physical camera cards a permanent memory, pulls only new frames across multi-day shoots, extracts previews for instant Finder culling, and gives you an uncompromising, byte-verified **Safe to Format** green light before you wipe your card.

No Electron. No subscriptions. No cloud telemetry. Pure Bash, Python 3 standard library, and plain-text UNIX ledgers.

---

## The Dirty Secret of Photography (Why This Exists)

Textbook studio discipline says: *Shoot, offload immediately, wipe the card in-camera, put the card back in its pouch.*

If you shoot street, documentary, travel, or personal work, you know that’s not how real life works:

1. **The card is an accidental air-gapped backup.** You leave photos on your SD cards across multiple weeks and outings because if your laptop drops, an SSD corrupts, or a cloud sync glitches, that physical silicon in your bag is the only place those raw sensor photons still exist.
2. **Cards get formatted when they are *full*, not when a session ends.** You keep shooting until your camera buffer warns you there are only 80 frames of headroom left.
3. **The Pre-Shoot Panic:** You're walking out the door on a Saturday morning, your card is at 94% capacity, and you're staring at the camera's *Format Card* menu wondering:
   > *"Did I actually offload that walk from two weeks ago? Are the keepers from Tuesday actually in my vault, or just sitting in a temporary staging folder? Can I hit format right now without destroying a frame I'll never get back?"*

Commercial DIT tools don't solve this—they are \$150+ heavy utilities built for film sets with daily data runners. Generic sync tools don't understand DCIM folder structures, RAW formats, or embedded previews.

**SPOOLR is built for the photographer whose card is a rolling, multi-session memory.**

---

## Core Superpowers

### 1. The "Safe to Format" Verdict (Psychological Certainty)
The single biggest fear every photographer experiences before hitting `Format` in-camera is: *"Did I actually get everything off this card, and is the backup intact?"*

Most tools give a "Copy Complete" banner (which only means the OS write buffer flushed). SPOOLR’s `reconcile` actively re-reads the card and the vault, hashes both on the fly, and byte-matches them. That explicit verdict is a massive psychological relief. It only ever prints **`✓ SAFE TO FORMAT CARD`** when every keeper is proven identical in your vault.

### 2. The Rolling Multi-Session Watermark
Commercial shooters format after every shoot, but street, documentary, travel, and personal photographers frequently keep shots across multiple days/weeks on a single large card. Standard tools either re-import everything (creating duplicate chaos) or make you manually select date ranges. SPOOLR’s per-card rolling watermark (`.watermark`) makes incremental pulls painless and clean into isolated session folders (`YYYY-MM-DD_SES-018_street`).

### 3. Physical $\leftrightarrow$ Digital Card Identity & Ignition
Photographers color-code their physical gear with tape or colored cases (e.g. *Pink tape = Card Bravo / Lumix*, *Cyan = Card Nomad / Sony*). 

SPOOLR mirrors physical hardware on screen. When you name a card, you assign it an identity color (`cyanotype`, `anthotype`, `aerochrome`, `chlorophyll`). Every time you dock the card, the Bento dashboard runs an **ignition sequence** and re-themes the entire UI in that card's color. If you thought you inserted your spare pink card ("Bravo") and the deck ignites cyan ("Nomad" at 93% full), you get an immediate visual sanity check *before* making any moves.

### 4. Disaster Recovery via Persistent Ledger
If a staging drive dies or an external SSD gets dropped before the card is formatted, `spoolr restore` recovers the session’s keepers by SHA-256 matching from the durable Mac ledger—even if the camera rolled over its filename counter (`DSC0001.ARW` collision). Almost no other tool does this.

### 5. Architecture & Aesthetic: Zero-Bloat Mac Native
- **No Electron:** Built entirely on Bash + Python stdlib + single-file vanilla HTML/CSS. It consumes negligible RAM, launches instantly, and has zero external npm/pip dependencies.
- **Bento Box UI:** The tactile, dark-mode hardware aesthetic (SMD LEDs, ignition sequence, card-specific neon accents, fill gauge) gives you an appliance feel on `localhost:7331`.
- **Finder-Native Culling:** SPOOLR instantly peels embedded JPEGs from your RAWs so you can cull keepers with macOS Finder spacebar and native color tags (Green/Purple) without launching heavy catalog software.

---

## The Safety Contract

This is the non-negotiable core of the tool:

- **SPOOLR never deletes from your card.** Formatting is always your explicit action, in-camera, after you've seen a green verdict.
- **Backups are verified by reading them back.** After copying a keeper to your vault, SPOOLR re-hashes the file *in the vault* and requires an exact SHA-256 match before recording it. A truncated or half-written copy is rejected, not trusted.
- **The verdict re-reads at the moment of truth.** When you run `reconcile` with the card inserted, SPOOLR hashes each keeper's **original on the card** and its **copy in the vault** and compares them right then, never a remembered value. If the card isn't inserted, it verifies against the staged copies and tells you so.
- **Every RAW format is handled everywhere.** The recognised formats live in one list used by every stage:  
  `RW2` `ARW` `CR3` `CR2` `NEF` `DNG` `ORF` `RAF` `SRW` `PEF` `RWL` `IIQ` `3FR` `GPR`.
- **Read-only stays read-only.** `status`, `where` and `reconcile` never write to your card. A card is only ever tagged during a deliberate `spoolr` offload.
- **A card you never formatted is still a backup.** If the drive holding a session's originals is lost, `spoolr restore` pulls that session's keepers back off the card by SHA-256 matching from `backups.tsv`.
- **A restore is never mistaken for an archive.** It lands in a new session marked `RESTORED`, never `VERIFIED`, so a recovered card cannot read as safe to format. The frames are back, but they are not yet in a vault.

---

## The 4-Step Workflow

```bash
# 1. Insert the card and offload everything new since your last pull
spoolr

# 2. Open the session folder and color-tag your keeper JPEGs in Finder (Green/Purple)

# 3. Archive the keepers to your vault drive (read-back verified)
spoolr backup

# 4. Ask the question that matters before formatting
spoolr reconcile
```

When you see:

```text
✓ SAFE TO FORMAT CARD — every keeper re-read and byte-matched in your vault.
```

every keeper is confirmed in your vault. Format the card in-camera with confidence.

---

## Where Are My Frames?

Drives get unplugged and `/Volumes/DRIVE` reshuffles on remount, so an absolute path alone rots quietly. Every session records the **volume UUID** it landed on, plus the path relative to that volume's mount point. `spoolr where` resolves them against what is attached right now:

```bash
spoolr where             # every session
spoolr where SES-018     # one session
spoolr where --json      # for scripts and the dashboard
```

| State | Meaning |
| :--- | :--- |
| `both` | Staged and archived. Nothing to do. |
| `vault` | In the vault only. Staging has been cleared, which is fine. |
| `staging` | Staged but never archived. Do not format that card yet. |
| `offline` | On a volume this Mac knows by UUID but cannot currently see. Reconnect it. |
| `neither` | No copy this tool can find. **This is the only true alarm.** |

`offline` exists so that "unplugged" stops being reported as "lost".

---

## The Bento Dashboard (`spoolr ui`)

```bash
spoolr ui
```

The dashboard runs the **whole workflow from the browser**, leaving the terminal optional. Dependency-free (Python standard library only), it detects your card live and walks you through a pipeline that lights up as each stage completes:

1. **Name & Color the Card** inline — writes the card's permanent identity and color profile.
2. **Pull** offloads new frames and auto-peels previews. On a card's first pull it asks what counts as "new" right in the browser. Panel turns **green** with the RAW count.
3. **Peel** turns **green** when every RAW has a preview, **amber** (`X/N`) if some couldn't be read.
4. **Tag** opens the session folder in Finder to color-tag your keepers.
5. **Backup** shows an attached **vault picker** on first run; after that, keepers are read-back-verified into the vault and the panel turns **green**.
6. **Reconcile** turns **green** for SAFE, **red** for not safe.

---

## Commands

| Command | Description |
| :--- | :--- |
| `spoolr [slug]` | Rolling offload into a new session folder (`2026-08-25_SES-019_street`) |
| `spoolr --fast [slug]` | Offload without the copy-time card re-read (roughly 2× faster; reconcile is still the gate) |
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
| `spoolr reset [--all] [--purge-staging]` | Clear tracking data for a clean slate (`--purge-staging` removes staged sessions) |
| `spoolr ui` | Launch the Bento dashboard on `localhost:7331` |

---

## Installation & Requirements

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/oaklensart/spoolr/main/install.sh | bash
```

Then verify your setup:

```bash
spoolr doctor
```

### Requirements

* macOS with `bash`, `rsync`, and a SHA-256 tool (all built-in). SPOOLR prefers the native `/sbin/sha256sum` and falls back to `/usr/bin/shasum`.
* **Recommended:** `brew install exiftool` for reliable embedded-preview extraction and accurate shoot dates.
* Python 3 (built-in) for the dashboard.

---

## Durable Data Architecture (`~/.config/spoolr/`)

All tracking data lives independently of any staging folder or card wipe:

* `cards.tsv` — Physical card registry (ID, nickname, capacity, color token, first seen).
* `ledger.tsv` — Append-only session history (`timestamp · SES-ID · CARD · dates · frames · path · status · vol_uuid= · vol_name= · rel_path= · vol_kind=`).
* `backups.tsv` — Per-frame vault index (`session · filename · sha256 · vault_path · timestamp`).
* `watermarks/<CARD_ID>.watermark` — Per-card rolling watermark.
* `<session>/.spoolr_manifest.tsv` — Per-session manifest (filename, size, SHA-256, source path, archive state).

### Environment Overrides

* `SPOOLR_CONFIG_DIR` — Custom configuration directory (default: `~/.config/spoolr`).
* `SPOOLR_CARD_GLOB` — Override the `/Volumes/*` card-detection root.
* `SPOOLR_ASSUME_YES` — Never prompt; fail loudly instead of blocking (for automation/cron).
* `SPOOLR_UI_PORT` — Serve the dashboard on a port other than `7331`.

---

## License

MIT © [oaklens.art](https://oaklens.art)

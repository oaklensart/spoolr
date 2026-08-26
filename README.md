# SPOOLR

A Mac app for photographers that offloads camera cards and verifies your backups before you format.

---

## The Dirty Secret of Photography (Why This Exists)

Textbook studio discipline says: *Shoot, offload immediately, format the card in camera, put the card back in its pouch.*

If you shoot street, documentary, travel, or personal work, you know that is not how real life works:

1. **The card is an accidental air gapped backup.** You leave photos on your SD cards across multiple weeks and outings because if your laptop drops, an SSD corrupts, or cloud sync glitches, that physical silicon in your bag is the only place those raw sensor photons still exist.
2. **Cards get formatted when they are full, not when a session ends.** You keep shooting until your camera buffer warns you there are only 80 frames of headroom left.
3. **The Pre Shoot Panic:** You are walking out the door on a Saturday morning, your card is at 94 percent capacity, and you are staring at the camera Format Card menu wondering:
   > *"Did I actually offload that walk from two weeks ago? Are the keepers from Tuesday actually in my vault, or just sitting in a temporary staging folder? Can I format right now without destroying a frame I will never get back?"*

Commercial tools do not solve this. They are expensive utilities built for film sets with daily data runners. Generic sync tools do not understand camera folder structures, RAW formats, or embedded previews.

**SPOOLR is built for the photographer whose card is a rolling memory across multiple shoots.**

---

## Core Superpowers

### 1. The Safe to Format Verdict (Psychological Certainty)
The single biggest fear every photographer experiences before hitting Format in camera is: *"Did I actually get everything off this card, and is the backup intact?"*

Most tools give a Copy Complete banner which only means the drive write buffer flushed. SPOOLR actively re reads the card and the vault, hashes both on the fly, and byte matches them. That explicit verdict is a massive psychological relief. It only ever prints **`✓ SAFE TO FORMAT CARD`** when every keeper is proven identical in your vault.

### 2. The Rolling Multi Session Watermark
Commercial shooters format after every shoot, but street, documentary, travel, and personal photographers frequently keep shots across multiple days or weeks on a single large card. Standard tools either force you to re import everything creating duplicate chaos or make you manually select date ranges. SPOOLR maintains a per card rolling watermark so running `spoolr` pulls only what is new since your last pull into an isolated session folder (`YYYY-MM-DD_SES-018_street`).

### 3. Physical and Digital Card Identity
Photographers color code their physical gear with tape or colored cases (for example Pink tape for Card Bravo, Cyan for Card Nomad). 

SPOOLR mirrors physical hardware on screen. When you name a card, you assign it an identity color (`cyanotype`, `anthotype`, `aerochrome`, `chlorophyll`). Every time you dock the card, the dashboard runs an ignition sequence and re themes the entire interface in that card color. If you thought you inserted your spare pink card and the deck ignites cyan at 93 percent full, you get an immediate visual check before making any moves.

### 4. Disaster Recovery via Persistent Ledger
If a staging drive dies or an external SSD gets dropped before the card is formatted, `spoolr restore` recovers the session keepers by SHA256 matching from the durable Mac ledger, even if the camera rolled over its filename counter (`DSC0001.ARW` collision). Almost no other tool does this.

### 5. Architecture and Aesthetic: Zero Bloat Mac Native
* **No Electron:** Built entirely on Bash, Python standard library, and a single file vanilla HTML and CSS dashboard. It consumes negligible RAM, launches instantly, and has zero external npm or pip dependencies.
* **Bento Box UI:** The tactile dark mode hardware aesthetic with LEDs, ignition sequence, card specific neon accents, and fill gauge gives you an appliance feel on `localhost:7331`.
* **Finder Native Culling:** SPOOLR instantly peels embedded JPEGs from your RAWs so you can cull keepers with macOS Finder spacebar and native color tags (Green or Purple) without launching heavy catalog software.

---

## The Safety Contract

This is the non negotiable core of the tool:

* **SPOOLR never deletes from your card.** Formatting is always your explicit action, in camera, after you have seen a green verdict.
* **Backups are verified by reading them back.** After copying a keeper to your vault, SPOOLR re hashes the file in the vault and requires an exact SHA256 match before recording it. A truncated or half written copy is rejected, not trusted.
* **The verdict re reads at the moment of truth.** When you run `reconcile` with the card inserted, SPOOLR hashes each keeper original on the card and its copy in the vault and compares them right then, never a remembered value. If the card is not inserted, it verifies against the staged copies and tells you so.
* **Every RAW format is handled everywhere.** The recognised formats live in one list used by every stage:  
  `RW2` `ARW` `CR3` `CR2` `NEF` `DNG` `ORF` `RAF` `SRW` `PEF` `RWL` `IIQ` `3FR` `GPR`.
* **Read only stays read only.** `status`, `where` and `reconcile` never write to your card. A card is only ever tagged during a deliberate `spoolr` offload.
* **A card you never formatted is still a backup.** If the drive holding a session originals is lost, `spoolr restore` pulls that session keepers back off the card by SHA256 matching from `backups.tsv`.
* **A restore is never mistaken for an archive.** It lands in a new session marked `RESTORED`, never `VERIFIED`, so a recovered card cannot read as safe to format. The frames are back, but they are not yet in a vault.

---

## The 4 Step Workflow

```bash
# 1. Insert the card and offload everything new since your last pull
spoolr

# 2. Open the session folder and color tag your keeper JPEGs in Finder (Green or Purple)

# 3. Archive the keepers to your vault drive (read back verified)
spoolr backup

# 4. Ask the question that matters before formatting
spoolr reconcile
```

When you see:

```text
✓ SAFE TO FORMAT CARD
```

every keeper is confirmed in your vault. Format the card in camera with confidence.

---

## Where Are My Frames?

Drives get unplugged and `/Volumes/DRIVE` reshuffles on remount, so an absolute path alone rots quietly. Every session records the volume UUID it landed on, plus the path relative to that volume mount point. `spoolr where` resolves them against what is attached right now:

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
| `neither` | No copy this tool can find. This is the only true alarm. |

---

## The Bento Dashboard (`spoolr ui`)

```bash
spoolr ui
```

The dashboard runs the whole workflow from the browser, leaving the terminal optional. Dependency free (Python standard library only), it detects your card live and walks you through a pipeline that lights up as each stage completes:

1. **Name and Color the Card** inline to write the card permanent identity and color profile.
2. **Pull** offloads new frames and auto peels previews. On a card first pull it asks what counts as new right in the browser. Panel turns green with the RAW count.
3. **Peel** turns green when every RAW has a preview, amber if some could not be read.
4. **Tag** opens the session folder in Finder to color tag your keepers.
5. **Backup** shows an attached vault picker on first run; after that, keepers are verified into the vault and the panel turns green.
6. **Reconcile** turns green for SAFE, red for not safe.

---

## Commands

| Command | Description |
| :--- | :--- |
| `spoolr [slug]` | Rolling offload into a new session folder (`2026-08-25_SES-019_street`) |
| `spoolr --fast [slug]` | Offload without the copy time card re read (roughly 2x faster; reconcile is still the gate) |
| `spoolr --today [slug]` | Offload only today frames without advancing the rolling watermark |
| `spoolr name <NAME>` | Set or rename the inserted card permanent identity |
| `spoolr status` | Read only fill gauge, frame headroom, and run history |
| `spoolr where [SES-ID]` | Locate a session: staging, vault, both, offline, neither |
| `spoolr reveal` | Open the latest session folder in Finder, ready for tagging |
| `spoolr backup [path]` | Copy keepers to the vault with read back SHA256 verification |
| `spoolr reconcile [folder]` | Pre wipe verdict (re reads card and vault; card wide by default) |
| `spoolr restore [SES-ID] [dir]` | Re download a past session keepers off the card when originals are lost |
| `spoolr restore --dry-run` | Report what is still recoverable from the card without copying |
| `spoolr peel [folder]` | Extract embedded JPEG previews for fast Finder color tagging |
| `spoolr eject` | Safely unmount the active card |
| `spoolr config` | Set staging and vault directories |
| `spoolr doctor` | Environment self check (tools, paths, cards, active hash backend) |
| `spoolr reset [--all] [--purge-staging]` | Clear tracking data for a clean slate (`--purge-staging` removes staged sessions) |
| `spoolr ui` | Launch the Bento dashboard on `localhost:7331` |

---

## Installation and Requirements

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/oaklensart/spoolr/main/install.sh | bash
```

Then verify your setup:

```bash
spoolr doctor
```

### Requirements

* macOS with `bash`, `rsync`, and a SHA256 tool (all built in). SPOOLR prefers the native `/sbin/sha256sum` and falls back to `/usr/bin/shasum`.
* **Recommended:** `brew install exiftool` for reliable embedded preview extraction and accurate shoot dates.
* Python 3 (built in) for the dashboard.

---

## Durable Data Architecture (`~/.config/spoolr/`)

All tracking data lives independently of any staging folder or card wipe:

* `cards.tsv` (Physical card registry: ID, nickname, capacity, color token, first seen)
* `ledger.tsv` (Append only session history with volume UUID and status)
* `backups.tsv` (Per frame vault index: session, filename, sha256, vault path, timestamp)
* `watermarks/<CARD_ID>.watermark` (Per card rolling watermark)
* `<session>/.spoolr_manifest.tsv` (Per session manifest: filename, size, SHA256, source path, archive state)

### Environment Overrides

* `SPOOLR_CONFIG_DIR` (Custom configuration directory, default: `~/.config/spoolr`)
* `SPOOLR_CARD_GLOB` (Override the `/Volumes/*` card detection root)
* `SPOOLR_ASSUME_YES` (Never prompt; fail loudly instead of blocking)
* `SPOOLR_UI_PORT` (Serve the dashboard on a port other than 7331)

---

## License

MIT © [oaklens.art](https://oaklens.art)


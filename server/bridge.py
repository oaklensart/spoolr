#!/usr/bin/env python3
"""
INGEST — Python UI Bridge Server
Zero external dependencies (Python 3 standard library only).

Serves the Bento dashboard and exposes a small, read-mostly REST surface backed
by the real ledgers in ~/.config/ingest. Binds to loopback only and rejects
cross-origin POSTs so a random web page can't drive your CLI.
"""

import html
import http.server
import json
import os
import re
import shutil
import socketserver
import subprocess
import sys
import webbrowser
from datetime import datetime, timezone
from pathlib import Path

PORT = int(os.environ.get("INGEST_UI_PORT", "7331"))
SERVER_DIR = Path(__file__).resolve().parent
REPO_ROOT = SERVER_DIR.parent

# Web dir works for both the repo layout (server/ ‹sibling› web/) and the
# installed layout (~/.config/ingest/server + ~/.config/ingest/web).
WEB_DIR = REPO_ROOT / "web"

CONFIG_DIR = Path(os.environ.get("INGEST_CONFIG_DIR", Path.home() / ".config" / "ingest"))

# Per-card accent colours. Must stay in step with CARD_PALETTE in bin/ingest and
# the PALETTE table in web/dashboard.html.
CARD_PALETTE = ("cyanotype", "anthotype", "aerochrome", "chlorophyll", "platinum")
MANIFEST_NAME = ".ingest_manifest.tsv"   # must match $MANIFEST_NAME in bin/ingest


def resolve_ingest_bin():
    """Find the ingest executable robustly. Env wins, then PATH, then layout."""
    env_bin = os.environ.get("INGEST_BIN")
    if env_bin and Path(env_bin).exists():
        return env_bin
    on_path = shutil.which("ingest")
    if on_path:
        return on_path
    for cand in (REPO_ROOT / "bin" / "ingest", SERVER_DIR / "ingest"):
        if cand.exists():
            return str(cand)
    return None


BIN_INGEST = resolve_ingest_bin()


def parse_tsv(file_path):
    if not file_path.exists():
        return []
    rows = []
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.rstrip("\n")
            if line and not line.startswith("#"):
                rows.append(line.split("\t"))
    return rows


def session_scan(staging_path):
    """Return (raws, jpgs, backed) for a session folder.
    raws  = frames recorded in the manifest (what was pulled in)
    jpgs  = preview JPEGs present on disk (ignoring macOS ._ sidecars)
    backed = frames marked BACKED in the manifest."""
    p = Path(staging_path)
    rows = parse_tsv(p / MANIFEST_NAME)
    raws = len(rows)
    backed = sum(1 for r in rows if len(r) >= 7 and r[6] == "BACKED")
    jpgs = 0
    if p.is_dir():
        try:
            jpgs = sum(1 for f in p.iterdir()
                       if f.is_file() and not f.name.startswith("._")
                       and f.suffix.lower() in (".jpg", ".jpeg"))
        except OSError:
            pass
    return raws, jpgs, backed


def _run_json(args, default):
    if BIN_INGEST is None:
        return default
    try:
        r = subprocess.run(
            [str(BIN_INGEST), *args], capture_output=True, text=True, timeout=20,
            stdin=subprocess.DEVNULL, env=dict(os.environ, INGEST_CONFIG_DIR=str(CONFIG_DIR)),
        )
        return json.loads((r.stdout or "").strip() or "null") or default
    except Exception:
        return default


def probe_card():
    """Live, side-effect-free card status via `ingest probe`. {} if unavailable."""
    return _run_json(["probe"], {})


def list_volumes():
    """Attached candidate vault drives via `ingest volumes`. [] if unavailable."""
    return _run_json(["volumes"], [])


def fmt_relative(iso_ts):
    """'2 days ago' style label from an ISO-8601 UTC timestamp; passthrough on parse failure."""
    if not iso_ts or iso_ts == "No backups yet":
        return iso_ts or "No backups yet"
    try:
        ts = datetime.strptime(iso_ts.replace("Z", "+0000"), "%Y-%m-%dT%H:%M:%S%z")
    except ValueError:
        return iso_ts
    delta = datetime.now(timezone.utc) - ts
    secs = int(delta.total_seconds())
    if secs < 0:
        secs = 0
    if secs < 60:
        return "just now"
    if secs < 3600:
        return f"{secs // 60}m ago"
    if secs < 86400:
        return f"{secs // 3600}h ago"
    days = secs // 86400
    return "yesterday" if days == 1 else f"{days} days ago"


def card_colors():
    """{card_name: colour} from the registry mirror (cards.tsv col 7).

    Read from the registry rather than the cards themselves, since a ledger
    entry's card is usually not in the reader.
    """
    out = {}
    for r in parse_tsv(CONFIG_DIR / "cards.tsv"):
        if len(r) >= 7 and r[6].strip().lower() in CARD_PALETTE:
            out[r[0]] = r[6].strip().lower()
    return out


def backup_times():
    """{session_id: newest backup timestamp} from the backup index."""
    out = {}
    for r in parse_tsv(CONFIG_DIR / "backups.tsv"):
        if len(r) >= 5 and r[0].startswith("SES-"):
            if r[4] > out.get(r[0], ""):
                out[r[0]] = r[4]
    return out


def tagged_field(cols, key):
    """Value of a key=value field among a ledger row's trailing columns."""
    for c in cols:
        c = c.strip()
        if c.startswith(key + "="):
            return c[len(key) + 1:]
    return ""


def restore_source(session_id, staging_path, backed_at):
    """Where `ingest restore` would get this session's frame list.

    Mirrors restore_wanted() in the CLI, and must keep mirroring it: the two
    records die in different disasters. The manifest lives inside the staging
    folder, so it is gone precisely when that drive is; backups.tsv lives in
    the config dir on this Mac and survives losing both staging and vault.
    '' means neither survives and no honest restore is possible.
    """
    if staging_path and (Path(staging_path) / MANIFEST_NAME).is_file():
        return "session manifest"
    if backed_at.get(session_id):
        return "backup index"
    return ""


def latest_backup(sessions):
    """Newest backup timestamp across the given sessions ('' if never)."""
    stamps = [s.get("backed_at") for s in sessions if s.get("backed_at")]
    return max(stamps) if stamps else ""


def derive_verdict(sessions):
    """Conservative verdict from one card's own sessions.

    Never optimistic: a card with no history is 'idle' (Ready), never 'safe'.
    """
    if not sessions:
        return "idle"
    s = sessions[0]
    if str(s.get("status", "")).upper() == "VERIFIED":
        return "safe"
    try:
        backed = int(s.get("backed") or 0)
    except (TypeError, ValueError):
        backed = 0
    if backed > 0:
        return "backed"
    return "staged"


def get_full_state():
    state = {
        "card_id": "NO CARD",
        "card_present": False,
        "card_unnamed": False,
        "card_name": "",
        "card_color": "",
        "fill_pct": 0,
        "free_space": "—",
        "headroom_frames": 0,
        "verdict": "idle",
        "last_backup": "No backups yet",
        "sessions": [],
        "connected": True,
    }

    # verdict comes from the last CLI action (state.json); last_backup is
    # recomputed per card further down and its value here is discarded.
    state_file = CONFIG_DIR / "state.json"
    if state_file.exists():
        try:
            with open(state_file, "r", encoding="utf-8") as f:
                state.update(json.load(f))
        except Exception:
            pass
    # Which card that snapshot describes — captured BEFORE the live probe below
    # overwrites card_id, so we can tell whether its verdict applies to the card
    # actually in the reader.
    snap_card = str(state.get("card_id", "")).replace("CARD ", "").strip()

    # live card status overrides the snapshot (card may have been inserted/removed)
    p = probe_card()
    if p:
        present = bool(p.get("card_present"))
        state["card_present"] = present
        state["card_unnamed"] = bool(p.get("card_unnamed"))
        state["card_first_run"] = bool(p.get("card_first_run"))
        state["card_name"] = p.get("card_id", "")
        color = str(p.get("card_color", "") or "").lower()
        state["card_color"] = color if color in CARD_PALETTE else ""
        state["num_cards"] = p.get("num_cards", 0)
        if present:
            state["card_id"] = "CARD " + (p.get("card_id") or "?")
            state["fill_pct"] = p.get("fill_pct", 0)
            state["free_space"] = p.get("free_space", "—")
            state["headroom_frames"] = p.get("headroom_frames", 0)
        else:
            state["card_id"] = "NO CARD"
            state["fill_pct"] = 0
            state["free_space"] = "—"
            state["headroom_frames"] = 0
        state["staging_root"] = p.get("staging_root", state.get("staging_root", ""))
        state["vault_root"] = p.get("vault_root", state.get("vault_root", ""))

    state["vault_set"] = bool(state.get("vault_root"))

    # Real session ledger: timestamp, session_id, card_id, dates, frames, staging_path, status
    ledger_rows = parse_tsv(CONFIG_DIR / "ledger.tsv")
    colors = card_colors()
    backed_at = backup_times()
    sessions = []
    for r in reversed(ledger_rows):
        if len(r) >= 6 and r[1].startswith("SES-"):
            staging_path = r[5]
            raws, jpgs, backed = session_scan(staging_path)
            card = r[2]
            sessions.append({
                "id": r[1],
                "card": card,
                # Each ledger entry keeps the colour of the card that made it —
                # a saved state, independent of whatever card is mounted now.
                "color": colors.get(card, ""),
                "date": r[3],
                "frames": r[4],            # frames recorded at pull time
                "raws": raws,              # frames present in manifest now
                "jpgs": jpgs,              # preview JPEGs on disk
                "status": r[6] if len(r) > 6 else "PENDING",
                # Columns 8+ are tagged key=value fields so each can be added
                # independently of the others (see the restore + volume threads).
                "restored_from": tagged_field(r[7:], "restored_from"),
                "keepers": raws,           # keepers default to all RAWs until tagged
                "backed": backed,
                "backed_at": backed_at.get(r[1], ""),
                "path": staging_path,
                "exists": Path(staging_path).is_dir(),
                # Where a re-download would get its frame list, or "" if the
                # session is unrecoverable. Drives the restore affordance.
                "restore_src": restore_source(r[1], staging_path, backed_at),
            })

    # The full history, every card, each wearing its own colour.
    state["ledger"] = sessions[:24]

    # SAFETY: the pipeline and the verdict describe THE MOUNTED CARD ONLY.
    # Without this scoping a freshly inserted card inherits the previous card's
    # session and verdict — i.e. it can read "SAFE / ok to format" for a card
    # that was never backed up. Never show another card's conclusion.
    cur = state.get("card_name") or ""
    mine = [s for s in sessions if s["card"] == cur] if state["card_present"] and cur else []
    state["sessions"] = mine[:12]

    # last_backup is ALWAYS this card's own, never state.json's. That field is
    # the newest backup anywhere on the system, and state.json pairs it with the
    # card of the last CLI action — so merely mounting a virgin card stamps it
    # with some other card's backup time ("18m ago" for a card never backed up).
    # latest_backup(mine) is card-scoped by construction; freshness is not worth
    # a false reassurance on the panel that authorises formatting.
    state["last_backup"] = latest_backup(mine) or "No backups yet"
    state["last_backup_rel"] = fmt_relative(state["last_backup"])

    # The verdict may still come from state.json when the snapshot describes the
    # card in the reader: it is written per CLI action, so it genuinely is that
    # card's conclusion, and it beats the ledger to a just-finished verify. For
    # any other card, derive pessimistically from this card's own history.
    if state["card_present"] and snap_card != cur:
        state["verdict"] = derive_verdict(mine)
    elif not state["card_present"]:
        state["verdict"] = "no_card"

    state["card_id"] = ("CARD " + cur) if state["card_present"] and cur else "NO CARD"
    return state


class IngestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_DIR), **kwargs)

    def log_message(self, fmt, *args):  # quieter console
        pass

    def end_headers(self):
        # This is a local tool UI whose assets are replaced in place by the
        # installer. Without this, a browser happily reuses a heuristically
        # "fresh" cached dashboard.html and keeps showing the old interface
        # after an update. Always revalidate.
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        super().end_headers()

    def _json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _same_origin(self):
        """Reject cross-site POSTs (CSRF): our own fetch omits Origin or sends our host."""
        origin = self.headers.get("Origin")
        if origin is None:
            return True  # same-origin simple requests from our page
        allowed = {f"http://localhost:{PORT}", f"http://127.0.0.1:{PORT}"}
        return origin in allowed

    def do_GET(self):
        if self.path == "/api/state":
            self._json(200, get_full_state())
            return
        if self.path == "/api/volumes":
            self._json(200, {"volumes": list_volumes()})
            return
        if self.path in ("/", "/index.html"):
            self.path = "/dashboard.html"
        return super().do_GET()

    def do_POST(self):
        if not self.path.startswith("/api/action/"):
            self._json(404, {"error": "not found"})
            return
        if not self._same_origin():
            self._json(403, {"error": "cross-origin request refused"})
            return
        if BIN_INGEST is None:
            self._json(200, {"success": False,
                             "output": "ingest executable not found on PATH.",
                             "state": get_full_state()})
            return

        action = self.path.rsplit("/", 1)[-1]
        valid = {
            "status": ["status"],
            "reconcile": ["reconcile"],
            "peel": ["peel"],
            "pull": ["ingest"],
            "pull_fast": ["ingest", "--fast"],
            "backup": ["backup"],
            "eject": ["eject"],
            "reveal": ["reveal"],
            "reset": ["reset", "--yes"],   # tracking data only; never --purge-staging from the web
        }

        # Read an optional JSON body (used by `name`, which carries the new card id).
        body = {}
        try:
            length = int(self.headers.get("Content-Length") or 0)
            if length:
                body = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        except Exception:
            body = {}

        if action == "name":
            new_name = "".join(c for c in str(body.get("name", "")).upper()
                               if c.isalnum() or c in "-_")[:32]
            if not new_name:
                self._json(400, {"error": "a card name is required"})
                return
            argv = ["name", new_name]
            # Optional accent colour, validated against the fixed palette so only
            # known tokens ever reach the CLI.
            color = str(body.get("color", "")).strip().lower()
            if color:
                if color not in CARD_PALETTE:
                    self._json(400, {"error": "unknown card colour"})
                    return
                argv.append(color)
        elif action == "reveal":
            # Optional session id. The path is resolved from OUR ledger, never
            # taken from the request, so the page can't open arbitrary folders.
            sid = str(body.get("session", "")).strip().upper()
            argv = ["reveal"]
            if sid:
                if not re.fullmatch(r"SES-\d{1,6}", sid):
                    self._json(400, {"error": "bad session id"})
                    return
                path = ""
                for r in parse_tsv(CONFIG_DIR / "ledger.tsv"):
                    if len(r) >= 6 and r[1] == sid:
                        path = r[5]
                if not path:
                    self._json(404, {"error": "unknown session"})
                    return
                if not Path(path).is_dir():
                    self._json(410, {"error": "folder moved or deleted", "path": path})
                    return
                argv.append(path)
        elif action in ("restore", "restore_plan"):
            # Re-download a past session off the card. The session id is checked
            # against OUR ledger, so the page can only ask for sessions we know.
            sid = str(body.get("session", "")).strip().upper()
            if not re.fullmatch(r"SES-\d{1,6}", sid):
                self._json(400, {"error": "bad session id"})
                return
            if not any(len(r) >= 6 and r[1] == sid
                       for r in parse_tsv(CONFIG_DIR / "ledger.tsv")):
                self._json(404, {"error": "unknown session"})
                return
            argv = ["restore", sid]
            # An optional destination must already exist: restore writes real
            # files, so the page may pick among drives the user has mounted, not
            # conjure a tree anywhere on the filesystem.
            dest = str(body.get("dest", "")).strip()
            if dest:
                dpath = Path(dest)
                if not dpath.is_absolute() or not dpath.is_dir():
                    self._json(400, {"error": "destination must be an existing folder"})
                    return
                argv.append(str(dpath))
            if action == "restore_plan":
                argv.append("--dry-run")
        elif action == "set-vault":
            path = str(body.get("path", "")).strip()
            if not path:
                self._json(400, {"error": "a vault path is required"})
                return
            argv = ["set-vault", path]
        elif action in ("pull", "pull_fast"):
            argv = list(valid[action])
            baseline = str(body.get("baseline", "")).lower()
            if baseline in ("now", "today", "all"):
                argv.append("--baseline=" + baseline)
        elif action in valid:
            argv = valid[action]
        else:
            self._json(400, {"error": "invalid action"})
            return

        env = dict(os.environ, INGEST_CONFIG_DIR=str(CONFIG_DIR))
        try:
            # Deliberately NOT text=True: universal-newline decoding rewrites
            # every lone \r to \n, which would turn each progress redraw into
            # its own line and leave strip_ansi's \r collapsing with nothing to
            # collapse. Decode ourselves so the carriage returns survive to it.
            result = subprocess.run(
                [str(BIN_INGEST), *argv],
                capture_output=True, timeout=600, check=False,
                stdin=subprocess.DEVNULL, env=env,
            )
            output = (result.stdout or b"").decode("utf-8", "replace") \
                   + (result.stderr or b"").decode("utf-8", "replace")
            success = result.returncode == 0
        except subprocess.TimeoutExpired:
            output, success = "Action timed out after 10 minutes.", False
        except Exception as exc:  # pragma: no cover
            output, success = str(exc), False

        self._json(200, {
            "success": success,
            "action": action,
            "output": strip_ansi(output),
            "state": get_full_state(),
        })


def strip_ansi(text):
    import re
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)          # drop colour codes
    text = re.sub(r"[^\n]*\r", "", text)                # collapse \r progress redraws to their final state
    return text


def run():
    if not WEB_DIR.exists():
        print(f"  ✗ Web assets not found at {WEB_DIR}", file=sys.stderr)
        sys.exit(1)
    socketserver.TCPServer.allow_reuse_address = True
    try:
        httpd = socketserver.TCPServer(("127.0.0.1", PORT), IngestHandler)
    except OSError as exc:
        print(f"  ✗ Could not bind to localhost:{PORT} — {exc}", file=sys.stderr)
        print(f"    Another instance running? Try: INGEST_UI_PORT=7332 ingest ui", file=sys.stderr)
        sys.exit(1)
    with httpd:
        url = f"http://localhost:{PORT}"
        print(f"\n  ⚡ INGEST Bento Dashboard active at {url}")
        print(f"     ingest binary : {BIN_INGEST or 'NOT FOUND'}")
        print(f"     config dir    : {CONFIG_DIR}")
        print("  Press Ctrl+C to stop.\n")
        try:
            webbrowser.open(url)
        except Exception:
            pass
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n  Shutting down dashboard bridge.")
            httpd.server_close()


if __name__ == "__main__":
    run()

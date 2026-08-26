#!/usr/bin/env bash
# ==============================================================================
# SPOOLR — Installer
# Local:   ./install.sh
# Remote:  curl -fsSL https://raw.githubusercontent.com/oaklensart/spoolr/main/install.sh | bash
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

echo ""
echo -e "${BOLD}⚡ SPOOLR INSTALLER${NC} — Card Memory & Archival Engine"
echo ""

# ── Locate sources (local checkout, or download a tarball if piped via curl) ──
# Piped through curl means BASH_SOURCE is an empty array, which is an unbound
# variable under `set -u`. Test it before dereferencing: an empty SCRIPT_DIR is
# the signal to download rather than an accident of where the user happened to
# be standing. (dirname "" returns ".", so guarding with :- alone would silently
# make the current directory look like a checkout.)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
else
  SCRIPT_DIR=""
fi
SRC_ROOT="$SCRIPT_DIR"

if [ -z "$SRC_ROOT" ] || [ ! -f "$SRC_ROOT/bin/spoolr" ]; then
  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TMP_DIR"' EXIT
  echo -e "  ${CYAN}Downloading latest release...${NC}"
  curl -fsSL "https://github.com/oaklensart/spoolr/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMP_DIR"
  SRC_ROOT="$TMP_DIR/spoolr-main"
fi

BIN_SOURCE="$SRC_ROOT/bin/spoolr"
WEB_SOURCE="$SRC_ROOT/web/dashboard.html"
SERVER_SOURCE="$SRC_ROOT/server/bridge.py"

for f in "$BIN_SOURCE" "$WEB_SOURCE" "$SERVER_SOURCE"; do
  [ -f "$f" ] || { echo -e "  ${RED}✗ Missing source file: $f${NC}"; exit 1; }
done

# ── Choose an install dir on PATH ──
INSTALL_DIR="/usr/local/bin"
if [ ! -w "$INSTALL_DIR" ]; then
  mkdir -p "$HOME/.local/bin" 2>/dev/null || true
  INSTALL_DIR="$HOME/.local/bin"
fi

# ── Durable config + UI assets (honors an SPOOLR_CONFIG_DIR override) ──
CFG_DIR="${SPOOLR_CONFIG_DIR:-$HOME/.config/spoolr}"
mkdir -p "$CFG_DIR/watermarks" "$CFG_DIR/server" "$CFG_DIR/web"
touch "$CFG_DIR/cards.tsv" "$CFG_DIR/ledger.tsv" "$CFG_DIR/backups.tsv"

install -m 0755 "$BIN_SOURCE" "$INSTALL_DIR/spoolr"
install -m 0644 "$WEB_SOURCE" "$CFG_DIR/web/dashboard.html"
install -m 0644 "$SERVER_SOURCE" "$CFG_DIR/server/bridge.py"

echo -e "  ${GREEN}✓${NC} Executable installed to ${BOLD}$INSTALL_DIR/spoolr${NC}"
echo -e "  ${GREEN}✓${NC} Dashboard + bridge installed under ${BOLD}$CFG_DIR${NC}"
echo -e "  ${GREEN}✓${NC} Config and ledgers initialized"

# ── PATH ──
# ~/.local/bin is where this lands whenever /usr/local/bin needs root, and it is
# not on the default macOS PATH. Left alone, a successful install is followed by
# "command not found" on the user's very first command. So offer to fix it, and
# take no for an answer with something useful either way.
#
# The prompt has to come from /dev/tty: piping through curl puts the *script* on
# stdin, so a plain `read` would consume the installer's own source. Where there
# is no terminal at all (CI, automation) nothing is written and the line is just
# printed, because an installer that silently edits a shell profile with no one
# watching is worse than one that asks twice.
PATH_LINE="export PATH=\"$INSTALL_DIR:\$PATH\""

shell_profile() {
  case "$(basename "${SHELL:-/bin/zsh}")" in
    zsh)  printf '%s\n' "$HOME/.zshrc" ;;
    bash) if [ -f "$HOME/.bash_profile" ]; then printf '%s\n' "$HOME/.bash_profile"
          else printf '%s\n' "$HOME/.bashrc"; fi ;;
    *)    printf '' ;;   # fish and friends use different syntax; do not guess
  esac
}

case ":$PATH:" in
  *":$INSTALL_DIR:"*) : ;;
  *)
    PROFILE="$(shell_profile)"
    PRETTY="${PROFILE/#$HOME/~}"
    echo ""
    echo -e "  ${YELLOW}One more step.${NC} $INSTALL_DIR is not on your PATH,"
    echo -e "  so your shell cannot find ${BOLD}spoolr${NC} yet."
    echo ""

    if [ -n "$PROFILE" ] && grep -qsF "$INSTALL_DIR" "$PROFILE"; then
      echo -e "  ${GREEN}✓${NC} $PRETTY already adds it. Open a new terminal tab and you are set."
    else
      # Can we actually ask a human?
      ANSWER=""; ASKED=1
      if [ -n "$PROFILE" ] && [ "${SPOOLR_ASSUME_YES:-0}" != "1" ]; then
        if [ -t 0 ]; then
          printf "  Add it to %s for you? [Y/n] " "$PRETTY"
          IFS= read -r ANSWER && ASKED=0
        elif (exec 3</dev/tty) 2>/dev/null; then
          printf "  Add it to %s for you? [Y/n] " "$PRETTY"
          IFS= read -r ANSWER < /dev/tty && ASKED=0
        fi
      fi

      if [ -n "$PROFILE" ] && [ "${SPOOLR_ASSUME_YES:-0}" = "1" ]; then
        printf '\n# Added by the SPOOLR installer\n%s\n' "$PATH_LINE" >> "$PROFILE"
        echo -e "  ${GREEN}✓${NC} Added to $PRETTY."
      elif [ "$ASKED" = "0" ]; then
        case "${ANSWER:-Y}" in
          [Nn]*)
            echo ""
            echo -e "  Left alone. Two ways to run it, whichever you prefer:"
            echo -e "    Add this to $PRETTY:  ${CYAN}$PATH_LINE${NC}"
            echo -e "    Or skip PATH entirely: ${CYAN}$INSTALL_DIR/spoolr ui${NC}" ;;
          *)
            printf '\n# Added by the SPOOLR installer\n%s\n' "$PATH_LINE" >> "$PROFILE"
            echo ""
            echo -e "  ${GREEN}✓${NC} Added to $PRETTY. Open a new terminal tab, or run:"
            echo -e "      ${CYAN}source $PRETTY${NC}" ;;
        esac
      else
        echo -e "  Add this line to your shell profile:"
        echo -e "      ${CYAN}$PATH_LINE${NC}"
        echo -e "  Or skip PATH entirely: ${CYAN}$INSTALL_DIR/spoolr ui${NC}"
      fi
    fi ;;
esac

echo ""
echo -e "  ${BOLD}Getting started:${NC}"
echo -e "    1. Insert your SD card."
echo -e "    2. Open the dashboard:  ${CYAN}spoolr ui${NC}"
echo ""
echo -e "  Everything happens in the browser from there. The terminal is optional:"
echo -e "  ${CYAN}spoolr help${NC} lists every command, ${CYAN}spoolr doctor${NC} checks your setup."
echo ""
echo -e "  ${YELLOW}Recommended:${NC} install exiftool for reliable previews & shoot dates:"
echo -e "      brew install exiftool"
echo ""

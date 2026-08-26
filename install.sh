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

# ── PATH hint ──
case ":$PATH:" in
  *":$INSTALL_DIR:"*) : ;;
  *) echo -e "  ${YELLOW}⚠ $INSTALL_DIR is not on your PATH.${NC} Add to your shell profile:"
     echo -e "      export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
esac

echo ""
echo -e "  ${BOLD}Getting started:${NC}"
echo -e "    1. Check your environment:  ${CYAN}spoolr doctor${NC}"
echo -e "    2. Insert your SD card and: ${CYAN}spoolr${NC}"
echo -e "    3. Launch the dashboard:    ${CYAN}spoolr ui${NC}"
echo ""
echo -e "  ${YELLOW}Recommended:${NC} install exiftool for reliable previews & shoot dates:"
echo -e "      brew install exiftool"
echo ""

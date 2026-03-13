#!/usr/bin/env bash
set -euo pipefail

PLUGIN_NAME="openclaw-agent"
OPENCLAW_JSON="$HOME/.openclaw/openclaw.json"
EXTENSIONS_DIR="$HOME/.openclaw/extensions"
INSTALL_DIR="$EXTENSIONS_DIR/${PLUGIN_NAME}"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BLUE}══${NC} $* ${BLUE}══${NC}"; }

echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  Uninstall openclaw-agent                           ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"

# ── Step 1: Remove plugin files ─────────────────────────────────────────────
step "Removing plugin files"

if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
  success "Removed $INSTALL_DIR"
else
  info "Plugin directory not found, skipping"
fi

# ── Step 2: Clean openclaw.json config ──────────────────────────────────────
step "Cleaning configuration"

if [[ -f "$OPENCLAW_JSON" ]]; then
  node --input-type=module <<'NODEJS'
import { readFileSync, writeFileSync } from 'fs';

const path = process.env.HOME + '/.openclaw/openclaw.json';
let cfg;
try {
  cfg = JSON.parse(readFileSync(path, 'utf8'));
} catch (e) {
  console.error('Failed to parse openclaw.json:', e.message);
  process.exit(1);
}

let changed = false;

// Remove from plugins.allow
if (Array.isArray(cfg.plugins?.allow)) {
  const idx = cfg.plugins.allow.indexOf('openclaw-agent');
  if (idx !== -1) {
    cfg.plugins.allow.splice(idx, 1);
    console.log('Removed "openclaw-agent" from plugins.allow');
    changed = true;
  }
}

// Remove from plugins.entries
if (cfg.plugins?.entries?.['openclaw-agent']) {
  delete cfg.plugins.entries['openclaw-agent'];
  console.log('Removed "openclaw-agent" from plugins.entries');
  changed = true;
}

if (changed) {
  writeFileSync(path, JSON.stringify(cfg, null, 2) + '\n');
  console.log('Config cleaned successfully');
} else {
  console.log('No openclaw-agent config found, nothing to clean');
}
NODEJS
  success "Configuration cleaned"
else
  info "openclaw.json not found, skipping"
fi

# ── Step 3: Restart Gateway ─────────────────────────────────────────────────
step "Restarting Gateway"

if command -v openclaw &>/dev/null; then
  openclaw gateway restart 2>/dev/null || true
  success "Gateway restarted"
else
  warn "OpenClaw not found, skip Gateway restart"
fi

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  openclaw-agent uninstalled successfully!           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "What was removed:"
echo "  ✓ Plugin files (~/.openclaw/extensions/openclaw-agent)"
echo "  ✓ Plugin config from openclaw.json"
echo ""
echo "What was NOT removed (uninstall separately if needed):"
echo "  • Cursor Agent CLI   →  rm ~/.local/bin/agent"
echo "  • Claude Code CLI    →  npm uninstall -g @anthropic-ai/claude-code"
echo "  • Codex CLI          →  brew uninstall codex"
echo ""

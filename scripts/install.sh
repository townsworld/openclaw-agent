#!/usr/bin/env bash
set -euo pipefail

REPO="townsworld/openclaw-agent"
PLUGIN_NAME="openclaw-agent"
OPENCLAW_JSON="$HOME/.openclaw/openclaw.json"

# ── Parse arguments ──────────────────────────────────────────────────────────
UPGRADE_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --upgrade|-u) UPGRADE_ONLY=true ;;
  esac
done

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${BLUE}══${NC} $* ${BLUE}══${NC}"; }

# ── Helpers ──────────────────────────────────────────────────────────────────
command_exists() { command -v "$1" &>/dev/null; }

# Read from /dev/tty so that curl|bash pipe mode still works
HAS_TTY=false
(echo '' >/dev/null </dev/tty) 2>/dev/null && HAS_TTY=true

ask() {
  local prompt="$1" var="$2"
  if [[ "$HAS_TTY" == "true" ]]; then
    read -rp "$prompt" "$var" </dev/tty
  else
    printf '%s' "$prompt"
    read -r "$var" || eval "$var=''"
  fi
}

# ── OS detection ─────────────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  *)
    error "Unsupported platform: $OS (only macOS and Linux are supported)"
    exit 1
    ;;
esac

# ── Desktop/headless detection ────────────────────────────────────────────────
HAS_DESKTOP=false
if [[ "$PLATFORM" == "macos" ]]; then
  HAS_DESKTOP=true
elif [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
  HAS_DESKTOP=true
fi

# ── Step 1: Check OpenClaw ────────────────────────────────────────────────────
step "Checking OpenClaw"
if ! command_exists openclaw; then
  error "OpenClaw not found. Please install it first:"
  echo "  curl -fsSL https://openclaw.dev/install.sh | bash"
  exit 1
fi
success "OpenClaw found: $(which openclaw)"

# ── Shared helpers ────────────────────────────────────────────────────────────
model_menu() {
  local cli_name="$1" var_name="$2"
  echo ""
  echo "  $cli_name model:"
  echo "    [1] Default (CLI decides)"
  echo "    [2] Custom  — specify model name"
  ask "  Select (1/2): " MODEL_CHOICE
  case "$MODEL_CHOICE" in
    2)
      ask "    Model name: " CUSTOM_MODEL
      if [[ -n "$CUSTOM_MODEL" ]]; then
        eval "$var_name='$CUSTOM_MODEL'"
        success "$cli_name model set to: $CUSTOM_MODEL"
      else
        warn "Empty value, using default."
      fi
      ;;
    *) info "$cli_name will use CLI default model." ;;
  esac
}

# ── CLI install/auth functions ────────────────────────────────────────────────
install_cursor() {
  echo ""
  if command_exists agent; then
    success "Cursor CLI already installed: $(which agent)"
    ask "  [1] Re-authenticate  [b] Back : " SUB
    case "$SUB" in
      1)
        if [[ "$HAS_TTY" == "true" ]]; then
          agent login </dev/tty
        else
          warn "No TTY. Run 'agent login' manually."
        fi
        ;;
    esac
  else
    info "Installing Cursor CLI..."
    curl -fsSL https://cursor.com/install | bash
    export PATH="$HOME/.local/bin:$PATH"
    if command_exists agent; then
      success "Cursor CLI installed"
      info "Logging in to Cursor..."
      if [[ "$HAS_TTY" == "true" ]]; then
        agent login </dev/tty
      else
        warn "No TTY. Run 'agent login' manually."
      fi
    else
      warn "Cursor CLI installed but not found in PATH. Run 'agent login' manually."
    fi
  fi
  [[ "$HAS_TTY" == "true" ]] && command_exists agent && model_menu "Cursor Agent" CURSOR_MODEL
  echo ""
}

claude_auth_menu() {
  if [[ -n "${ANTHROPIC_BASE_URL:-}" && -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    success "Proxy mode already active (ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL)"
    echo ""
    echo "  Choose authentication mode:"
    echo "    [1] Normal login  — authenticate via 'claude login' (Anthropic account)"
    echo "    [2] Keep proxy"
    echo "    [3] Re-configure proxy"
    ask "  Select (1/2/3/b): " AUTH
  else
    echo ""
    echo "  Choose authentication mode:"
    echo "    [1] Normal login  — authenticate via 'claude login' (Anthropic account)"
    echo "    [2] Proxy mode   — use a custom API proxy (ANTHROPIC_BASE_URL + AUTH_TOKEN)"
    ask "  Select (1/2/b): " AUTH
  fi

  case "$AUTH" in
    1)
      unset ANTHROPIC_BASE_URL 2>/dev/null || true
      unset ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
      if [[ "$HAS_TTY" == "true" ]]; then
        claude login </dev/tty
      else
        warn "No TTY. Run 'claude login' manually."
      fi
      ;;
    2)
      if [[ -n "${ANTHROPIC_BASE_URL:-}" && -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
        info "Keeping existing proxy config."
      else
        ask "    ANTHROPIC_BASE_URL: " PROXY_URL
        ask "    ANTHROPIC_AUTH_TOKEN: " PROXY_TOKEN
        if [[ -n "$PROXY_URL" && -n "$PROXY_TOKEN" ]]; then
          export ANTHROPIC_BASE_URL="$PROXY_URL"
          export ANTHROPIC_AUTH_TOKEN="$PROXY_TOKEN"
          success "Proxy configured: $PROXY_URL"
        else
          warn "Empty value, proxy not configured."
        fi
      fi
      ;;
    3)
      ask "    ANTHROPIC_BASE_URL: " PROXY_URL
      ask "    ANTHROPIC_AUTH_TOKEN: " PROXY_TOKEN
      if [[ -n "$PROXY_URL" && -n "$PROXY_TOKEN" ]]; then
        export ANTHROPIC_BASE_URL="$PROXY_URL"
        export ANTHROPIC_AUTH_TOKEN="$PROXY_TOKEN"
        success "Proxy configured: $PROXY_URL"
      else
        warn "Empty value, proxy not configured."
      fi
      ;;
    b|B) ;;
    *)
      warn "Invalid choice."
      ;;
  esac
}

install_claude() {
  echo ""
  if command_exists claude; then
    success "Claude Code already installed: $(which claude)"
    claude_auth_menu
  else
    info "Installing Claude Code CLI..."
    if ! command_exists npm; then
      error "npm not found. Install Node.js (https://nodejs.org) first."
      return
    fi
    npm install -g @anthropic-ai/claude-code
    export PATH="$HOME/.local/bin:$(npm bin -g 2>/dev/null || true):$PATH"
    if command_exists claude; then
      success "Claude Code installed"
      if [[ "$HAS_TTY" == "true" ]]; then
        claude_auth_menu
      else
        if [[ -n "${ANTHROPIC_BASE_URL:-}" && -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
          success "Proxy mode detected — no login needed."
        else
          warn "No TTY. Run 'claude login' manually."
        fi
      fi
    else
      warn "Claude Code installed but not found in PATH."
    fi
  fi
  [[ "$HAS_TTY" == "true" ]] && command_exists claude && model_menu "Claude Code" CLAUDE_MODEL
  echo ""
}

codex_auth_menu() {
  local login_hint="authenticate via 'codex login' (OpenAI account)"
  [[ "$HAS_DESKTOP" != "true" ]] && login_hint="device auth (for headless/remote servers)"

  if [[ -n "${CODEX_API_KEY:-}" || -n "${OPENAI_API_KEY:-}" ]]; then
    success "API key mode already active"
    echo ""
    echo "  Choose authentication mode:"
    echo "    [1] Normal login  — $login_hint"
    echo "    [2] Keep API key"
    echo "    [3] Re-configure API key"
    ask "  Select (1/2/3/b): " AUTH
  else
    echo ""
    echo "  Choose authentication mode:"
    echo "    [1] Normal login  — $login_hint"
    echo "    [2] API key mode — use OPENAI_API_KEY environment variable"
    ask "  Select (1/2/b): " AUTH
  fi

  case "$AUTH" in
    1)
      if [[ "$HAS_TTY" != "true" ]]; then
        warn "No TTY. Run 'codex login' manually."
      elif [[ "$HAS_DESKTOP" == "true" ]]; then
        codex login </dev/tty
      else
        info "Headless environment detected, using device auth..."
        codex login --device-auth </dev/tty
      fi
      ;;
    2)
      if [[ -n "${CODEX_API_KEY:-}" || -n "${OPENAI_API_KEY:-}" ]]; then
        info "Keeping existing API key."
      else
        ask "    OPENAI_API_KEY: " API_KEY
        if [[ -n "$API_KEY" ]]; then
          export OPENAI_API_KEY="$API_KEY"
          success "API key configured."
        else
          warn "Empty value, API key not configured."
        fi
      fi
      ;;
    3)
      ask "    OPENAI_API_KEY: " API_KEY
      if [[ -n "$API_KEY" ]]; then
        export OPENAI_API_KEY="$API_KEY"
        success "API key configured."
      else
        warn "Empty value, API key not configured."
      fi
      ;;
    b|B) ;;
    *)
      warn "Invalid choice."
      ;;
  esac
}

install_codex() {
  echo ""
  if command_exists codex; then
    success "Codex CLI already installed: $(which codex)"
    codex_auth_menu
  else
    info "Installing Codex CLI..."
    if command_exists brew; then
      brew install --cask codex
    elif command_exists npm; then
      npm install -g @openai/codex
    else
      error "Neither brew nor npm found. Install manually: npm install -g @openai/codex"
      return
    fi
    export PATH="$HOME/.local/bin:$(npm bin -g 2>/dev/null || true):$PATH"
    if command_exists codex; then
      success "Codex CLI installed"
      if [[ "$HAS_TTY" == "true" ]]; then
        codex_auth_menu
      else
        if [[ -n "${CODEX_API_KEY:-}" || -n "${OPENAI_API_KEY:-}" ]]; then
          success "API key detected — no login needed."
        else
          warn "No TTY. Run 'codex login' manually."
        fi
      fi
    else
      warn "Codex CLI installed but not found in PATH."
    fi
  fi
  [[ "$HAS_TTY" == "true" ]] && command_exists codex && model_menu "Codex" CODEX_MODEL
  echo ""
}

cli_status() {
  # $1=command name, returns status string
  if command_exists "$1"; then
    echo -e "${GREEN}✅ installed${NC}"
  else
    echo -e "${YELLOW}❌ not installed${NC}"
  fi
}

show_cli_menu() {
  echo ""
  echo -e "${BLUE}┌──────────────────────────────────────────┐${NC}"
  echo -e "${BLUE}│${NC}  CLI Tools Setup                         ${BLUE}│${NC}"
  echo -e "${BLUE}├──────────────────────────────────────────┤${NC}"
  echo -e "${BLUE}│${NC}  [1] Cursor Agent   $(cli_status agent)      ${BLUE}│${NC}"
  echo -e "${BLUE}│${NC}  [2] Claude Code    $(cli_status claude)      ${BLUE}│${NC}"
  echo -e "${BLUE}│${NC}  [3] Codex          $(cli_status codex)      ${BLUE}│${NC}"
  echo -e "${BLUE}│${NC}                                          ${BLUE}│${NC}"
  echo -e "${BLUE}│${NC}  [c] Continue to next step               ${BLUE}│${NC}"
  echo -e "${BLUE}└──────────────────────────────────────────┘${NC}"
}

# ── Step 2: Interactive CLI setup menu ───────────────────────────────────────
INSTALL_CURSOR=false; command_exists agent && INSTALL_CURSOR=true
INSTALL_CLAUDE=false; command_exists claude && INSTALL_CLAUDE=true
INSTALL_CODEX=false;  command_exists codex  && INSTALL_CODEX=true

if [[ "$UPGRADE_ONLY" == "true" ]]; then
  info "Upgrade mode: skipping CLI setup."
elif [[ "$HAS_TTY" == "true" ]]; then
  step "CLI Tools Setup"
  while true; do
    show_cli_menu
    ask "  Select (1/2/3/c): " MENU_CHOICE
    case "$MENU_CHOICE" in
      1)
        install_cursor
        command_exists agent && INSTALL_CURSOR=true
        ;;
      2)
        install_claude
        command_exists claude && INSTALL_CLAUDE=true
        ;;
      3)
        install_codex
        command_exists codex && INSTALL_CODEX=true
        ;;
      c|C)
        break
        ;;
      *)
        warn "Invalid choice. Enter 1, 2, 3 or c."
        ;;
    esac
  done
else
  info "Non-interactive mode: auto-installing uninstalled CLIs."

  if ! command_exists agent; then
    info "Installing Cursor CLI..."
    curl -fsSL https://cursor.com/install | bash 2>/dev/null || true
    export PATH="$HOME/.local/bin:$PATH"
    command_exists agent && { success "Cursor CLI installed"; INSTALL_CURSOR=true; } || warn "Cursor CLI install failed. Run manually later."
  fi

  if ! command_exists claude; then
    if command_exists npm; then
      info "Installing Claude Code CLI..."
      npm install -g @anthropic-ai/claude-code 2>/dev/null || true
      export PATH="$HOME/.local/bin:$(npm bin -g 2>/dev/null || true):$PATH"
      command_exists claude && { success "Claude Code installed"; INSTALL_CLAUDE=true; } || warn "Claude Code install failed."
    else
      warn "npm not found, skipping Claude Code install."
    fi
  fi

  if ! command_exists codex; then
    if command_exists brew; then
      info "Installing Codex CLI..."
      brew install --cask codex 2>/dev/null || true
    elif command_exists npm; then
      info "Installing Codex CLI..."
      npm install -g @openai/codex 2>/dev/null || true
    else
      warn "Neither brew nor npm found, skipping Codex install."
    fi
    export PATH="$HOME/.local/bin:$(npm bin -g 2>/dev/null || true):$PATH"
    command_exists codex && { success "Codex CLI installed"; INSTALL_CODEX=true; } || warn "Codex CLI install failed."
  fi

  warn "No TTY available. Run login commands manually if needed:"
  command_exists agent && warn "  agent login"
  command_exists claude && [[ -z "${ANTHROPIC_BASE_URL:-}" ]] && warn "  claude login"
  command_exists codex && [[ -z "${CODEX_API_KEY:-}" && -z "${OPENAI_API_KEY:-}" ]] && warn "  codex login"
fi

if [[ "$UPGRADE_ONLY" != "true" ]]; then
  echo ""
  [[ "$INSTALL_CURSOR" == "true" ]] && success "Cursor Agent  → enabled"
  [[ "$INSTALL_CLAUDE" == "true" ]] && success "Claude Code   → enabled"
  [[ "$INSTALL_CODEX" == "true" ]]  && success "Codex         → enabled"
  if [[ "$INSTALL_CURSOR" == "false" && "$INSTALL_CLAUDE" == "false" && "$INSTALL_CODEX" == "false" ]]; then
    warn "No CLI tools installed. Commands won't be available until you install at least one."
  fi
fi

# ── Model selection variables ──────────────────────────────────────────────
CURSOR_MODEL=""
CLAUDE_MODEL=""
CODEX_MODEL=""

# ── Step 3: Download & install plugin files ───────────────────────────────────
step "Installing openclaw-agent plugin"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

EXTENSIONS_DIR="$HOME/.openclaw/extensions"
INSTALL_DIR="$EXTENSIONS_DIR/${PLUGIN_NAME}"
PLUGIN_TGZ="$TMP_DIR/${PLUGIN_NAME}.tgz"

# Detect existing version for upgrade info
OLD_VERSION=""
if [[ -f "$INSTALL_DIR/package.json" ]]; then
  OLD_VERSION=$(node -e "try{console.log(JSON.parse(require('fs').readFileSync('$INSTALL_DIR/package.json','utf8')).version)}catch{}" 2>/dev/null || true)
fi

# Resolve latest release asset URL via GitHub API (no hardcoded version)
info "Fetching latest release info..."
RELEASE_JSON="$TMP_DIR/release.json"
DOWNLOAD_OK=false

for attempt in 1 2 3; do
  if curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" -o "$RELEASE_JSON" 2>/dev/null; then
    RELEASE_URL=$(node -e "
      const r=JSON.parse(require('fs').readFileSync('$RELEASE_JSON','utf8'));
      const a=r.assets?.find(a=>a.name.endsWith('.tgz'));
      if(a) console.log(a.browser_download_url);
    " 2>/dev/null)
    NEW_VERSION=$(node -e "
      const r=JSON.parse(require('fs').readFileSync('$RELEASE_JSON','utf8'));
      console.log((r.tag_name||'').replace(/^v/,''));
    " 2>/dev/null)

    if [[ -n "$RELEASE_URL" ]]; then
      if [[ -n "$OLD_VERSION" && -n "$NEW_VERSION" ]]; then
        if [[ "$OLD_VERSION" == "$NEW_VERSION" ]]; then
          success "Already on latest version v${NEW_VERSION}"
          if [[ "$HAS_TTY" == "true" ]]; then
            ask "  Re-install anyway? (y/N): " REINSTALL
            if [[ "$REINSTALL" != "y" && "$REINSTALL" != "Y" ]]; then
              info "Skipping plugin update."
              DOWNLOAD_OK="skip"
              break
            fi
          else
            info "Skipping plugin update (same version)."
            DOWNLOAD_OK="skip"
            break
          fi
          info "Re-installing v${NEW_VERSION}"
        else
          info "Upgrading v${OLD_VERSION} → v${NEW_VERSION}"
        fi
      else
        info "Installing v${NEW_VERSION:-latest}"
      fi

      info "Downloading $RELEASE_URL ..."
      if curl -fsSL -L "$RELEASE_URL" -o "$PLUGIN_TGZ"; then
        DOWNLOAD_OK=true
        break
      fi
    fi
  fi
  warn "Attempt $attempt failed, retrying..."
  sleep 2
done

if [[ "$DOWNLOAD_OK" == "skip" ]]; then
  info "Plugin files unchanged."
elif [[ "$DOWNLOAD_OK" == "true" ]]; then
  mkdir -p "$EXTENSIONS_DIR"
  if [[ -d "$INSTALL_DIR" ]]; then
    info "Removing existing installation..."
    rm -rf "$INSTALL_DIR"
  fi

  info "Extracting plugin..."
  mkdir -p "$INSTALL_DIR"
  tar -xzf "$PLUGIN_TGZ" -C "$INSTALL_DIR" --strip-components=1
  success "Plugin files installed to $INSTALL_DIR"
else
  error "Failed to download release after 3 attempts."
  error "Check your network or download manually: https://github.com/${REPO}/releases"
  exit 1
fi

# ── Step 4: Configure openclaw.json ───────────────────────────────────────────
step "Configuring plugin"

PROXY_BASE_URL="${ANTHROPIC_BASE_URL:-}"
PROXY_AUTH_TOKEN="${ANTHROPIC_AUTH_TOKEN:-}"
CODEX_KEY="${CODEX_API_KEY:-${OPENAI_API_KEY:-}}"

if [[ -f "$OPENCLAW_JSON" ]]; then
  PROXY_BASE_URL="$PROXY_BASE_URL" PROXY_AUTH_TOKEN="$PROXY_AUTH_TOKEN" CODEX_KEY="$CODEX_KEY" \
  CURSOR_MODEL="$CURSOR_MODEL" CLAUDE_MODEL="$CLAUDE_MODEL" CODEX_MODEL="$CODEX_MODEL" \
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

cfg.plugins = cfg.plugins ?? {};
cfg.plugins.allow = cfg.plugins.allow ?? [];
cfg.plugins.entries = cfg.plugins.entries ?? {};

if (!cfg.plugins.allow.includes('openclaw-agent')) {
  cfg.plugins.allow.push('openclaw-agent');
}

const entry = cfg.plugins.entries['openclaw-agent'] ?? { enabled: true, config: {} };
entry.config = entry.config ?? {};
entry.config.projects = entry.config.projects ?? {};

const proxyBaseUrl = process.env.PROXY_BASE_URL;
const proxyAuthToken = process.env.PROXY_AUTH_TOKEN;
if (proxyBaseUrl && proxyAuthToken) {
  entry.config.claude = entry.config.claude ?? {};
  entry.config.claude.anthropicBaseUrl = proxyBaseUrl;
  entry.config.claude.anthropicAuthToken = proxyAuthToken;
  console.log('Proxy config saved to plugin settings (ANTHROPIC_BASE_URL=' + proxyBaseUrl + ')');
}

const codexKey = process.env.CODEX_KEY;
if (codexKey) {
  entry.config.codex = entry.config.codex ?? {};
  entry.config.codex.openaiApiKey = codexKey;
  console.log('Codex API key saved to plugin settings');
}

const cursorModel = process.env.CURSOR_MODEL;
if (cursorModel) {
  entry.config.cursor = entry.config.cursor ?? {};
  entry.config.cursor.model = cursorModel;
  console.log('Cursor model: ' + cursorModel);
}

const claudeModel = process.env.CLAUDE_MODEL;
if (claudeModel) {
  entry.config.claude = entry.config.claude ?? {};
  entry.config.claude.model = claudeModel;
  console.log('Claude model: ' + claudeModel);
}

const codexModel = process.env.CODEX_MODEL;
if (codexModel) {
  entry.config.codex = entry.config.codex ?? {};
  entry.config.codex.model = codexModel;
  console.log('Codex model: ' + codexModel);
}

cfg.plugins.entries['openclaw-agent'] = entry;

writeFileSync(path, JSON.stringify(cfg, null, 2) + '\n');
console.log('Config updated: allow-list + plugin entry');
NODEJS
  success "Plugin configured"
else
  warn "openclaw.json not found at $OPENCLAW_JSON, skipping config"
fi

# ── Step 5: Project setup (auto-discover + manual add) ───────────────────────
if [[ "$UPGRADE_ONLY" == "true" ]]; then
  info "Upgrade mode: skipping project setup."
else
step "Project Setup"

PROJ_NAMES=()
PROJ_PATHS=()

# Auto-discover git projects in common directories
SCAN_DIRS=("$HOME/gitlab" "$HOME/github" "$HOME/code" "$HOME/projects" "$HOME/workspace" "$HOME/src" "$HOME/dev" "$HOME/repos")
FOUND_NAMES=()
FOUND_PATHS=()

for scan_dir in "${SCAN_DIRS[@]}"; do
  [[ ! -d "$scan_dir" ]] && continue
  for child in "$scan_dir"/*/; do
    [[ ! -d "$child" ]] && continue
    if [[ -d "$child/.git" ]]; then
      dir_name="$(basename "$child")"
      real_path="$(cd "$child" && pwd)"
      FOUND_NAMES+=("$dir_name")
      FOUND_PATHS+=("$real_path")
    fi
  done
done

# Also check already-configured projects (mark them so user knows)
EXISTING_PROJECTS=""
if [[ -f "$OPENCLAW_JSON" ]]; then
  EXISTING_PROJECTS=$(node -e "
    try {
      const c=JSON.parse(require('fs').readFileSync('$OPENCLAW_JSON','utf8'));
      const p=c?.plugins?.entries?.['openclaw-agent']?.config?.projects;
      if(p) Object.keys(p).forEach(k=>console.log(k));
    } catch{}
  " 2>/dev/null || true)
fi

if [[ ${#FOUND_NAMES[@]} -gt 0 && "$HAS_TTY" == "true" ]]; then
  echo ""
  echo "Found git projects on your machine:"
  echo ""

  # Selection state: 1=selected, 0=deselected
  SELECTED=()
  for i in "${!FOUND_NAMES[@]}"; do
    # Default select all; mark already-configured ones
    SELECTED+=("1")
  done

  while true; do
    # render project list
    for i in "${!FOUND_NAMES[@]}"; do
      num=$((i + 1))
      mark="✅"
      [[ "${SELECTED[$i]}" == "0" ]] && mark="  "
      existing_mark=""
      if echo "$EXISTING_PROJECTS" | grep -qx "${FOUND_NAMES[$i]}" 2>/dev/null; then
        existing_mark=" ${YELLOW}(already configured)${NC}"
      fi
      echo -e "  [${num}] ${mark} ${FOUND_NAMES[$i]}  ${BLUE}${FOUND_PATHS[$i]}${NC}${existing_mark}"
    done
    echo ""
    echo "  [a] Select all   [n] Select none   [m] Add manually   [c] Confirm"
    ask "  Toggle (number) or action (a/n/m/c): " PROJ_CHOICE

    case "$PROJ_CHOICE" in
      a|A)
        for i in "${!SELECTED[@]}"; do SELECTED[$i]="1"; done
        ;;
      n|N)
        for i in "${!SELECTED[@]}"; do SELECTED[$i]="0"; done
        ;;
      m|M)
        echo ""
        echo "  Add projects manually (empty name to stop):"
        while true; do
          ask "    Project name: " MANUAL_NAME
          [[ -z "$MANUAL_NAME" ]] && break
          ask "    Project path: " MANUAL_PATH
          if [[ -z "$MANUAL_PATH" ]]; then
            warn "Empty path, skipping."
            continue
          fi
          [[ ! -d "$MANUAL_PATH" ]] && warn "Directory not found: $MANUAL_PATH (adding anyway)"
          FOUND_NAMES+=("$MANUAL_NAME")
          FOUND_PATHS+=("$MANUAL_PATH")
          SELECTED+=("1")
        done
        ;;
      c|C)
        break
        ;;
      *)
        if [[ "$PROJ_CHOICE" =~ ^[0-9]+$ ]]; then
          idx=$((PROJ_CHOICE - 1))
          if [[ $idx -ge 0 && $idx -lt ${#FOUND_NAMES[@]} ]]; then
            if [[ "${SELECTED[$idx]}" == "1" ]]; then
              SELECTED[$idx]="0"
            else
              SELECTED[$idx]="1"
            fi
          else
            warn "Invalid number."
          fi
        else
          warn "Invalid choice."
        fi
        ;;
    esac
  done

  # Collect selected projects
  for i in "${!FOUND_NAMES[@]}"; do
    if [[ "${SELECTED[$i]}" == "1" ]]; then
      PROJ_NAMES+=("${FOUND_NAMES[$i]}")
      PROJ_PATHS+=("${FOUND_PATHS[$i]}")
    fi
  done

elif [[ "$HAS_TTY" == "true" ]]; then
  # No projects auto-discovered, fall back to manual input
  echo ""
  echo "No git projects found in common directories."
  echo "Add projects manually (empty name to finish):"
  echo ""
  while true; do
    ask "  Project name (e.g. myapp): " PROJ_NAME
    [[ -z "$PROJ_NAME" ]] && break
    ask "  Project path (e.g. /Users/me/code/myapp): " PROJ_PATH
    if [[ -z "$PROJ_PATH" ]]; then
      warn "Empty path, skipping."
      continue
    fi
    [[ ! -d "$PROJ_PATH" ]] && warn "Directory not found: $PROJ_PATH (adding anyway)"
    PROJ_NAMES+=("$PROJ_NAME")
    PROJ_PATHS+=("$PROJ_PATH")
  done
else
  # Non-TTY: auto-add all discovered projects
  if [[ ${#FOUND_NAMES[@]} -gt 0 ]]; then
    info "Auto-discovered ${#FOUND_NAMES[@]} git projects:"
    for i in "${!FOUND_NAMES[@]}"; do
      PROJ_NAMES+=("${FOUND_NAMES[$i]}")
      PROJ_PATHS+=("${FOUND_PATHS[$i]}")
      info "  ${FOUND_NAMES[$i]} → ${FOUND_PATHS[$i]}"
    done
  fi
fi

if [[ ${#PROJ_NAMES[@]} -gt 0 && -f "$OPENCLAW_JSON" ]]; then
  PROJ_NAMES_STR="$(printf '%s\n' "${PROJ_NAMES[@]}")"
  PROJ_PATHS_STR="$(printf '%s\n' "${PROJ_PATHS[@]}")"

  PROJ_NAMES_ENV="$PROJ_NAMES_STR" PROJ_PATHS_ENV="$PROJ_PATHS_STR" \
  node --input-type=module <<NODEJS
import { readFileSync, writeFileSync } from 'fs';

const cfgPath = process.env.HOME + '/.openclaw/openclaw.json';
const names = (process.env.PROJ_NAMES_ENV || '').split('\\n').filter(Boolean);
const paths = (process.env.PROJ_PATHS_ENV || '').split('\\n').filter(Boolean);

let cfg = JSON.parse(readFileSync(cfgPath, 'utf8'));
cfg.plugins = cfg.plugins ?? {};
cfg.plugins.entries = cfg.plugins.entries ?? {};
cfg.plugins.entries['openclaw-agent'] = cfg.plugins.entries['openclaw-agent'] ?? { enabled: true, config: {} };
cfg.plugins.entries['openclaw-agent'].config = cfg.plugins.entries['openclaw-agent'].config ?? {};
const projects = cfg.plugins.entries['openclaw-agent'].config.projects ?? {};

for (let i = 0; i < names.length; i++) {
  projects[names[i]] = paths[i];
}
cfg.plugins.entries['openclaw-agent'].config.projects = projects;

writeFileSync(cfgPath, JSON.stringify(cfg, null, 2) + '\\n');
console.log('Projects saved: ' + names.join(', '));
NODEJS
  success "${#PROJ_NAMES[@]} projects configured"
elif [[ ${#PROJ_NAMES[@]} -eq 0 ]]; then
  info "No projects added. You can configure them later in ~/.openclaw/openclaw.json"
fi
fi  # end of UPGRADE_ONLY check for project setup

# ── Step 6: Restart Gateway ───────────────────────────────────────────────────
if [[ "$DOWNLOAD_OK" != "skip" ]]; then
  step "Restarting Gateway"
  if command_exists openclaw; then
    openclaw gateway restart 2>/dev/null || true
    success "Gateway restarted"
  else
    warn "Run 'openclaw gateway restart' to load the updated plugin."
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
if [[ "$UPGRADE_ONLY" == "true" ]]; then
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  openclaw-agent upgraded successfully!               ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  if [[ -n "${NEW_VERSION:-}" ]]; then
    echo "  Version: v${NEW_VERSION}"
  fi
else
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  openclaw-agent installed successfully!              ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "Usage in Feishu:"
  [[ "$INSTALL_CURSOR" == "true" ]] && echo "  /cursor <project> <prompt>    — invoke Cursor Agent"
  [[ "$INSTALL_CLAUDE" == "true" ]] && echo "  /claude <project> <prompt>    — invoke Claude Code"
  [[ "$INSTALL_CODEX" == "true" ]] && echo "  /codex  <project> <prompt>    — invoke OpenAI Codex"
  echo ""
  echo "Options:"
  echo "  --mode ask|plan|agent         — set execution mode"
  echo "  --continue                    — continue previous session"
  echo "  --resume <chatId>             — resume specific session"
fi
echo ""

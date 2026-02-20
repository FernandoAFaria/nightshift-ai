#!/usr/bin/env bash
#
# tech-team install script
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/FernandoAFaria/ai-org-orchestrator/master/install.sh | bash
#
# What this does:
#   1. Checks/installs Bun (required runtime)
#   2. Detects platform (linux/darwin, x64/arm64)
#   3. Downloads pre-built tarball from GitHub Releases
#   4. Extracts to ~/.ai-org/
#   5. Runs database migrations + seed
#   6. Symlinks bin/ai-org to /usr/local/bin/ai-org
#   7. Prints next steps
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REPO="FernandoAFaria/ai-org-orchestrator"
INSTALL_DIR="${AI_ORG_HOME:-$HOME/.ai-org}"
BIN_LINK="/usr/local/bin/ai-org"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()    { echo -e "${CYAN}$*${RESET}"; }
success() { echo -e "${GREEN}$*${RESET}"; }
warn()    { echo -e "${YELLOW}$*${RESET}"; }
error()   { echo -e "${RED}$*${RESET}" >&2; }
step()    { echo -e "\n${CYAN}▸ $*${RESET}"; }

banner() {
  echo ""
  echo -e "${BOLD}${CYAN}"
  echo "  ┌─────────────────────────────────────┐"
  echo "  │     AI Team Orchestration            │"
  echo "  │     Install Script                   │"
  echo "  └─────────────────────────────────────┘"
  echo -e "${RESET}"
}

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------

detect_platform() {
  local os arch

  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "$os" in
    linux)  ;;
    darwin) ;;
    *)
      error "Unsupported operating system: $os"
      error "ai-org supports Linux and macOS only."
      exit 1
      ;;
  esac

  case "$arch" in
    x86_64|amd64)  arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      error "Unsupported architecture: $arch"
      error "ai-org supports x86_64 and ARM64 only."
      exit 1
      ;;
  esac

  PLATFORM_OS="$os"
  PLATFORM_ARCH="$arch"
  ASSET_NAME="ai-org-${os}-${arch}.tar.gz"
}

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------

ensure_curl() {
  if ! command -v curl &>/dev/null; then
    error "curl is required but not installed."
    error "Install it with your package manager (e.g., apt install curl, brew install curl)."
    exit 1
  fi
}

ensure_bun() {
  if command -v bun &>/dev/null; then
    local bun_version
    bun_version="$(bun --version 2>/dev/null || echo 'unknown')"
    success "  Bun $bun_version found"
    return 0
  fi

  warn "  Bun not found — installing..."
  curl -fsSL https://bun.sh/install | bash

  # Source the updated PATH so we can use bun immediately
  export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
  export PATH="$BUN_INSTALL/bin:$PATH"

  if command -v bun &>/dev/null; then
    local bun_version
    bun_version="$(bun --version 2>/dev/null || echo 'unknown')"
    success "  Bun $bun_version installed"
  else
    error "Failed to install Bun. Install it manually:"
    error "  curl -fsSL https://bun.sh/install | bash"
    exit 1
  fi
}

ensure_node() {
  if command -v node &>/dev/null; then
    local node_version
    node_version="$(node --version 2>/dev/null || echo 'unknown')"
    success "  Node.js $node_version found"
    return 0
  fi

  error "  Node.js is required for the production server."
  error ""
  error "  Install Node.js with one of:"
  error "    curl -fsSL https://fnm.vercel.app/install | bash && fnm install --lts"
  error "    or visit https://nodejs.org"
  exit 1
}

ensure_sqlite3() {
  # sqlite3 CLI is used by the seed-check in start.ts
  # It's pre-installed on macOS; on Linux it may need installing
  if command -v sqlite3 &>/dev/null; then
    return 0
  fi

  warn "  sqlite3 CLI not found (optional, used for seed check)"

  if [ "$PLATFORM_OS" = "linux" ]; then
    if command -v apt-get &>/dev/null; then
      warn "  Install with: sudo apt-get install sqlite3"
    elif command -v dnf &>/dev/null; then
      warn "  Install with: sudo dnf install sqlite"
    elif command -v pacman &>/dev/null; then
      warn "  Install with: sudo pacman -S sqlite"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Download & Install
# ---------------------------------------------------------------------------

get_latest_version() {
  local api_url="https://api.github.com/repos/$REPO/releases/latest"
  local release_json

  release_json="$(curl -fsSL "$api_url" 2>/dev/null)" || {
    error "Failed to fetch latest release from GitHub."
    error "Check your internet connection and that the repo exists."
    exit 1
  }

  # Extract tag_name, strip leading 'v'
  LATEST_VERSION="$(echo "$release_json" | grep '"tag_name"' | sed 's/.*"tag_name": *"v\?\([^"]*\)".*/\1/')"

  if [ -z "$LATEST_VERSION" ]; then
    error "Could not determine latest version from GitHub."
    exit 1
  fi
}

download_and_extract() {
  local download_url="https://github.com/$REPO/releases/download/v${LATEST_VERSION}/${ASSET_NAME}"

  info "  Version:  v$LATEST_VERSION"
  info "  Platform: ${PLATFORM_OS}/${PLATFORM_ARCH}"
  info "  Asset:    $ASSET_NAME"
  echo ""

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  info "  Downloading..."
  curl -fsSL "$download_url" -o "$tmp_dir/$ASSET_NAME" || {
    error "Download failed."
    error "URL: $download_url"
    error ""
    error "This could mean:"
    error "  - The release doesn't have a build for your platform ($PLATFORM_OS/$PLATFORM_ARCH)"
    error "  - The release hasn't been published yet"
    exit 1
  }

  info "  Extracting..."
  tar -xzf "$tmp_dir/$ASSET_NAME" -C "$tmp_dir"

  # The tarball extracts to an ai-org/ directory
  local extracted_dir="$tmp_dir/ai-org"
  if [ ! -d "$extracted_dir" ]; then
    # Fallback: contents may be at top level of tarball
    extracted_dir="$tmp_dir"
  fi

  # If upgrading, preserve existing data
  if [ -d "$INSTALL_DIR" ]; then
    warn "  Existing installation found — preserving data..."

    local backup_dir="$tmp_dir/_backup"
    mkdir -p "$backup_dir/prisma"

    # Preserve database and config
    for item in prisma/dev.db prisma/dev.db-wal prisma/dev.db-shm .env.local; do
      if [ -f "$INSTALL_DIR/$item" ]; then
        cp "$INSTALL_DIR/$item" "$backup_dir/$item"
      fi
    done

    # Remove old installation
    rm -rf "$INSTALL_DIR"
  fi

  # Move to install directory
  mkdir -p "$(dirname "$INSTALL_DIR")"
  mv "$extracted_dir" "$INSTALL_DIR"

  # Restore preserved data if upgrading
  if [ -d "${tmp_dir}/_backup" ]; then
    for item in prisma/dev.db prisma/dev.db-wal prisma/dev.db-shm .env.local; do
      if [ -f "${tmp_dir}/_backup/$item" ]; then
        local item_dir
        item_dir="$(dirname "$INSTALL_DIR/$item")"
        mkdir -p "$item_dir"
        cp "${tmp_dir}/_backup/$item" "$INSTALL_DIR/$item"
      fi
    done
    success "  Preserved existing database and configuration"
  fi

  # Make CLI executable
  chmod +x "$INSTALL_DIR/bin/ai-org"

  success "  Installed to $INSTALL_DIR"
}

# ---------------------------------------------------------------------------
# Post-install setup
# ---------------------------------------------------------------------------

install_dependencies() {
  step "Installing dependencies..."

  cd "$INSTALL_DIR"
  bun install --production 2>/dev/null || bun install

  success "  Dependencies installed"
}

setup_database() {
  step "Setting up database..."

  cd "$INSTALL_DIR"

  # Create .env if it doesn't exist (Prisma needs DATABASE_URL)
  if [ ! -f ".env" ] && [ ! -f ".env.local" ]; then
    echo 'DATABASE_URL="file:./dev.db"' > .env
  fi

  # Run migrations
  bun run prisma migrate deploy 2>&1 | while IFS= read -r line; do
    echo "  $line"
  done

  success "  Database migrations applied"

  # Seed if empty
  if command -v sqlite3 &>/dev/null; then
    local count
    count="$(sqlite3 prisma/dev.db "SELECT COUNT(*) FROM agents;" 2>/dev/null || echo "0")"
    if [ "$count" = "0" ]; then
      info "  Seeding database..."
      bun run db:seed 2>&1 | while IFS= read -r line; do
        echo "  $line"
      done
      success "  Database seeded"
    else
      success "  Database already seeded ($count agents)"
    fi
  else
    # Can't check — try seeding anyway, it's idempotent-ish
    info "  Seeding database..."
    bun run db:seed 2>&1 | while IFS= read -r line; do
      echo "  $line"
    done
  fi
}

create_symlink() {
  step "Creating symlink..."

  local target="$INSTALL_DIR/bin/ai-org"
  local link="$BIN_LINK"

  # Check if we can write to /usr/local/bin
  if [ -w "$(dirname "$link")" ]; then
    ln -sf "$target" "$link"
    success "  Linked $link -> $target"
  elif command -v sudo &>/dev/null; then
    info "  Need sudo to create symlink in $(dirname "$link")"
    sudo ln -sf "$target" "$link"
    success "  Linked $link -> $target"
  else
    warn "  Could not create symlink at $link"
    warn "  Add this to your PATH manually:"
    warn "    export PATH=\"$INSTALL_DIR/bin:\$PATH\""
    MANUAL_PATH=true
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  banner

  # Pre-flight checks
  step "Checking system requirements..."
  ensure_curl
  detect_platform
  ensure_bun
  ensure_node
  ensure_sqlite3

  # Download
  step "Fetching latest release..."
  get_latest_version
  download_and_extract

  # Setup
  install_dependencies
  setup_database
  create_symlink

  # Done
  echo ""
  echo -e "${BOLD}${GREEN}"
  echo "  ┌─────────────────────────────────────┐"
  echo "  │  Installation complete!              │"
  echo "  └─────────────────────────────────────┘"
  echo -e "${RESET}"
  echo ""
  info "  Installed: v$LATEST_VERSION"
  info "  Location:  $INSTALL_DIR"
  echo ""

  if [ "${MANUAL_PATH:-}" = "true" ]; then
    warn "  Add to your PATH first:"
    echo "    export PATH=\"$INSTALL_DIR/bin:\$PATH\""
    echo ""
  fi

  echo "  Get started:"
  echo ""
  echo "    ai-org                 Start the application"
  echo "    ai-org help            Show all commands"
  echo ""
  echo -e "  ${DIM}The setup wizard will open at http://localhost:8989/setup${RESET}"
  echo -e "  ${DIM}to configure your API keys on first run.${RESET}"
  echo ""
}

main "$@"

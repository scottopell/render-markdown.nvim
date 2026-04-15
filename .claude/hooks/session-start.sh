#!/bin/bash
# SessionStart hook for Claude Code on the web.
# Installs neovim + plugin dependencies so tests and linters run in a
# remote session. Idempotent - safe to run multiple times; each step
# checks whether its artefact already exists before doing work.
#
# Validate locally with:
#   CLAUDE_CODE_REMOTE=true .claude/hooks/session-start.sh

set -euo pipefail

# Only run in the remote environment. Locally, users have their own nvim
# install and cloning plugins system-wide would be invasive.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
    exit 0
fi

log() { printf '[session-start] %s\n' "$*"; }

# ---------------------------------------------------------------------
# 1. Neovim
# ---------------------------------------------------------------------
# render-markdown.nvim requires >= 0.9 and recommends >= 0.10. The
# tests/minimal_init.lua uses the nvim-treesitter 1.0+ API which wants
# 0.10+. Ubuntu 24.04's apt neovim is 0.9.5, so pull the portable
# "stable" tarball from the Neovim GitHub release instead.
if ! command -v nvim >/dev/null 2>&1; then
    log "installing neovim (stable) to /opt/nvim"
    sudo mkdir -p /opt/nvim
    curl -fsSL \
        https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz \
        | sudo tar xz -C /opt/nvim --strip-components=1
    sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
else
    log "neovim already installed: $(nvim --version | head -1)"
fi

# ---------------------------------------------------------------------
# 2. Build toolchain for tree-sitter parsers
# ---------------------------------------------------------------------
# nvim-treesitter main branch uses a CLI-driven install flow: it shells
# out to `tree-sitter` to generate parser.c and to `cc` to compile it.
# Ubuntu 24.04 ships tree-sitter 0.20.8 which is too old for current
# nvim-treesitter; pull the latest prebuilt binary instead.
if ! command -v cc >/dev/null 2>&1; then
    log "installing build-essential for tree-sitter parser compile"
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential
else
    log "C compiler already present: $(cc --version | head -1)"
fi

if ! command -v tree-sitter >/dev/null 2>&1; then
    log "installing tree-sitter CLI (prebuilt)"
    curl -fsSL \
        https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-x64.gz \
        | gunzip > /tmp/tree-sitter
    sudo install -m 0755 /tmp/tree-sitter /usr/local/bin/tree-sitter
    rm -f /tmp/tree-sitter
else
    log "tree-sitter CLI already present: $(tree-sitter --version)"
fi

# ---------------------------------------------------------------------
# 3. Plugin dependencies
# ---------------------------------------------------------------------
# tests/minimal_init.lua resolves plugins from stdpath('data'), which is
# $XDG_DATA_HOME/nvim (defaulting to ~/.local/share/nvim). Clone each
# dependency into the standard pack/start location so the runtime finds
# it without any extra rtp tweaks.
DEPS_DIR="$HOME/.local/share/nvim/site/pack/deps/start"
mkdir -p "$DEPS_DIR"

clone_dep() {
    local repo="$1"
    local name="$2"
    local dest="$DEPS_DIR/$name"
    if [ -d "$dest/.git" ]; then
        log "$name already cloned at $dest"
    else
        log "cloning $repo -> $dest"
        git clone --depth 1 --quiet "https://github.com/$repo.git" "$dest"
    fi
}
clone_dep nvim-lua/plenary.nvim plenary.nvim
clone_dep nvim-treesitter/nvim-treesitter nvim-treesitter
clone_dep echasnovski/mini.nvim mini.nvim

# ---------------------------------------------------------------------
# 4. Pre-install tree-sitter parsers
# ---------------------------------------------------------------------
# Running tests/minimal_init.lua headless once triggers
# nvim-treesitter's install({ html, latex, markdown, markdown_inline,
# yaml }):wait() so that subsequent test runs do not pay that cost.
# A parser already installed is a no-op, so this is idempotent too.
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
log "pre-installing tree-sitter parsers via minimal_init.lua"
nvim --headless --noplugin -u tests/minimal_init.lua -c "qa" >/dev/null 2>&1 || {
    log "parser pre-install failed (tests may still run - parsers install on demand)"
}

log "done"

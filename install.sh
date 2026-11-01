#!/bin/sh
# Sets up a new machine (macOS or Linux Debian/Ubuntu) from this repository:
#   curl -fsSL https://raw.githubusercontent.com/cyboooooorg/workstation/main/install.sh | sh
#
# 1. prerequisites (git, curl; Homebrew on macOS)
# 2. mise, through mise.run, into ~/.local/bin
# 3. mise bootstrap: clones the repository into ~/Developer/workstation, links ~/.config/mise
#    to it, then installs packages, tools, dotfiles and services
set -eu

REPO="${WORKSTATION_REPO:-https://github.com/cyboooooorg/workstation.git}"
DIR="${WORKSTATION_DIR:-$HOME/Developer/workstation}"

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# ─── Prerequisites ────────────────────────────────────────────────
case "$(uname)" in
  Darwin)
    if ! xcode-select -p >/dev/null 2>&1; then
      say "Xcode command line tools (git): finish the installation, then run this script again"
      xcode-select --install
      exit 1
    fi
    if ! command -v brew >/dev/null && [ ! -x /opt/homebrew/bin/brew ] && [ ! -x /usr/local/bin/brew ]; then
      say "Homebrew"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    ;;
  Linux)
    if ! command -v git >/dev/null || ! command -v curl >/dev/null; then
      say "git and curl (apt)"
      sudo apt-get update && sudo apt-get install -y git curl
    fi
    ;;
esac

# ─── mise ─────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"
if ! command -v mise >/dev/null; then
  say "mise"
  curl -fsSL https://mise.run | sh
else
  # An mise installed earlier may predate `mise bootstrap --from/--from-dir/--config-dir`
  # (2026.10.21): bring it up to date, through the package manager that installed it
  say "mise (update)"
  if command -v brew >/dev/null && brew list mise >/dev/null 2>&1; then
    brew upgrade mise || true
  else
    mise self-update --yes || true
  fi
fi
if ! mise bootstrap --help 2>/dev/null | grep -q -- '--config-dir'; then
  say "mise $(mise --version) is too old for 'mise bootstrap --from': update it (2026.10.21 or later), then run this script again"
  exit 1
fi

# ─── Global config ────────────────────────────────────────────────
# mise only links ~/.config/mise to the repository if the directory is missing or empty
if [ -d "$HOME/.config/mise" ] && [ ! -L "$HOME/.config/mise" ] && [ -n "$(ls -A "$HOME/.config/mise")" ]; then
  backup="$HOME/.config/mise.bak-$(date +%Y%m%d-%H%M%S)"
  say "~/.config/mise already exists: moved to $backup"
  mv "$HOME/.config/mise" "$backup"
fi

# mise dotfiles refuses to overwrite an existing file: move the files that [dotfiles] links
# (config.toml) aside, unless they already are links
for file in "$HOME/.zshrc"; do
  if [ -e "$file" ] && [ ! -L "$file" ]; then
    backup="$file.bak-$(date +%Y%m%d-%H%M%S)"
    say "${file#"$HOME"/} already exists: moved to $backup"
    mv "$file" "$backup"
  fi
done

# ─── Bootstrap ────────────────────────────────────────────────────
say "mise bootstrap"
mise bootstrap --from "$REPO" --from-dir "$DIR" --config-dir . --yes

say "Done: open a new terminal (zsh)"

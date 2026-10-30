#!/bin/sh
# Installe une machine neuve (macOS ou Linux Debian/Ubuntu) depuis ce dépôt :
#   curl -fsSL https://raw.githubusercontent.com/cyboooooorg/workstation/main/install.sh | sh
#
# 1. prérequis (git, curl ; Homebrew sur macOS)
# 2. mise, via mise.run, dans ~/.local/bin
# 3. mise bootstrap : clone le dépôt dans ~/Developer/workstation, lie ~/.config/mise
#    au dépôt, puis installe paquets, outils, dotfiles et services
set -eu

REPO="${WORKSTATION_REPO:-https://github.com/cyboooooorg/workstation.git}"
DIR="${WORKSTATION_DIR:-$HOME/Developer/workstation}"

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# ─── Prérequis ────────────────────────────────────────────────────
case "$(uname)" in
  Darwin)
    if ! xcode-select -p >/dev/null 2>&1; then
      say "Outils en ligne de commande Xcode (git) : terminer l'installation puis relancer ce script"
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
      say "git et curl (apt)"
      sudo apt-get update && sudo apt-get install -y git curl
    fi
    ;;
esac

# ─── mise ─────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"
if ! command -v mise >/dev/null; then
  say "mise"
  curl -fsSL https://mise.run | sh
fi

# ─── Config globale ───────────────────────────────────────────────
# mise ne lie ~/.config/mise au dépôt que si le dossier est absent ou vide
if [ -d "$HOME/.config/mise" ] && [ ! -L "$HOME/.config/mise" ] && [ -n "$(ls -A "$HOME/.config/mise")" ]; then
  backup="$HOME/.config/mise.bak-$(date +%Y%m%d-%H%M%S)"
  say "~/.config/mise existe déjà : déplacé dans $backup"
  mv "$HOME/.config/mise" "$backup"
fi

# ─── Bootstrap ────────────────────────────────────────────────────
say "mise bootstrap"
mise bootstrap --from "$REPO" --from-dir "$DIR" --config-dir . --yes

say "Terminé : ouvrir un nouveau terminal (zsh)"

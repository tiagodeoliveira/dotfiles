#!/bin/bash

# --- dependency checks
echo "======= Checking dependencies"

if ! command -v zsh &>/dev/null; then
  echo "ERROR: zsh is not installed"
  exit 1
fi

if ! command -v tmux &>/dev/null; then
  echo "ERROR: tmux is not installed"
  exit 1
fi

if ! command -v bash &>/dev/null; then
  echo "ERROR: bash is not installed"
  exit 1
fi

BASH_VERSION_INSTALLED=$(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [[ "$BASH_VERSION_INSTALLED" != "5.3.9" ]]; then
  echo "ERROR: bash 5.3.9 required, found $BASH_VERSION_INSTALLED"
  exit 1
fi

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  echo "ERROR: oh-my-zsh is not installed (expected at ~/.oh-my-zsh)"
  exit 1
fi

echo "All dependencies found"
# ---

# --- nvim
echo "======= Configuring nvim"
mkdir -p $HOME/.config/nvim
cp init.lua $HOME/.config/nvim

if [[ ! -d "$HOME/.config/nvim/autoload" ]]; then
  curl -fLo $HOME/.config/nvim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

nvim +silent +PlugUpgrade +PlugUpdate +PlugInstall +PlugClean +qall
# ---

# --- tmux
echo "======= Configuring tmux"
if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
  mkdir -p $HOME/.tmux/plugins
  git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm
fi

cp tmux.conf $HOME/.tmux.conf
# ---

# --- ghostty
echo "======= Configuring ghostty"
if [[ -d "$HOME/Library/Application Support/com.mitchellh.ghostty" ]]; then
  cp ghostty_config "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
else
  echo "Ghostty config directory not found, skipping"
fi
# ---

# --- git
echo "======= Configuring git"
cp gitconfig $HOME/.gitconfig
cp gitignore_global $HOME/.gitignore_global
# ---

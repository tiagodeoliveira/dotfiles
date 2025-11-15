#!/bin/bash

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

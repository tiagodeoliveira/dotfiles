#!/bin/bash

# --- xcode command line tools
echo "======= Checking Xcode Command Line Tools"
if ! xcode-select -p &>/dev/null; then
  echo "Triggering Xcode CLT installer..."
  xcode-select --install
  echo "Complete the install in the popup, then press Enter to continue..."
  read -r
else
  echo "Xcode CLT already installed"
fi
# ---

# --- homebrew
echo "======= Checking Homebrew"
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  echo "Homebrew already installed"
fi
# load brew into current shell session so brew commands below work
# (shellenv only auto-runs in login shells; this script is non-login)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
# ---

# --- brew packages
# canonical formula names (nvim is an alias for neovim; brew list only matches canonical)
echo "======= Installing Homebrew packages"
BREW_PACKAGES=(bash tmux bat zoxide neovim mise fzf modem-dev/tap/hunk)
for pkg in "${BREW_PACKAGES[@]}"; do
  if brew list --formula "$pkg" &>/dev/null; then
    echo "  [skip] $pkg already installed"
  else
    echo "  [install] $pkg"
    brew install "$pkg"
  fi
done
# ---

# --- claude code
# Use the official installer (self-updating ~/.local/share/claude/versions/*)
# instead of a brew cask, which lags behind upstream.
echo "======= Checking Claude Code"
if command -v claude &>/dev/null; then
  echo "Claude Code already installed at $(command -v claude)"
else
  echo "Installing Claude Code via official installer..."
  curl -fsSL https://claude.ai/install.sh | bash
fi
# ---

# --- claude code skills
# Wire up brew-installed tool skills under ~/.claude/skills/. Symlink against
# /opt/homebrew/opt/<formula>/... (version-stable; survives brew upgrade).
echo "======= Configuring Claude Code skills"
HUNK_SKILL_TARGET="/opt/homebrew/opt/hunk/libexec/skills/hunk-review/SKILL.md"
HUNK_SKILL_LINK="$HOME/.claude/skills/hunk-review/SKILL.md"
if [[ -f "$HUNK_SKILL_TARGET" ]]; then
  mkdir -p "$(dirname "$HUNK_SKILL_LINK")"
  ln -sf "$HUNK_SKILL_TARGET" "$HUNK_SKILL_LINK"
  echo "Linked hunk-review -> $HUNK_SKILL_TARGET"
else
  echo "hunk skill not found at $HUNK_SKILL_TARGET, skipping"
fi
# ---

# --- ssh key
echo "======= Checking SSH key"
SSH_KEY="$HOME/.ssh/id_ed25519"
if [[ -f "$SSH_KEY" ]]; then
  echo "SSH key already exists at $SSH_KEY"
else
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  # source the key comment from the dotfile gitconfig (this script may run before ~/.gitconfig is deployed)
  KEY_COMMENT="$(git config --file gitconfig user.email 2>/dev/null || echo "$(whoami)@$(hostname)")"
  ssh-keygen -t ed25519 -f "$SSH_KEY" -C "$KEY_COMMENT" -N ""
  echo "Generated $SSH_KEY"
fi
# ---

# --- ssh allowed_signers (local git signature verification)
echo "======= Configuring ssh allowed_signers"
ALLOWED_SIGNERS="$HOME/.ssh/allowed_signers"
PUB_KEY="$HOME/.ssh/id_ed25519.pub"
if [[ -f "$ALLOWED_SIGNERS" ]]; then
  echo "$ALLOWED_SIGNERS already exists, skipping"
elif [[ -f "$PUB_KEY" ]]; then
  GIT_EMAIL="$(git config --file gitconfig user.email)"
  # format: <principal> namespaces="<list>" <key_type> <key_data>
  # namespaces="git" restricts trust to commit signing only
  KEY_FIELDS="$(awk '{print $1, $2}' "$PUB_KEY")"
  echo "$GIT_EMAIL namespaces=\"git\" $KEY_FIELDS" > "$ALLOWED_SIGNERS"
  echo "Wrote $ALLOWED_SIGNERS"
else
  echo "$PUB_KEY not found, skipping allowed_signers"
fi
# ---

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
BASH_MAJOR=${BASH_VERSION_INSTALLED%%.*}
BASH_MINOR=$(echo "$BASH_VERSION_INSTALLED" | cut -d. -f2)
if (( BASH_MAJOR < 5 )) || (( BASH_MAJOR == 5 && BASH_MINOR < 3 )); then
  echo "ERROR: bash >= 5.3 required, found $BASH_VERSION_INSTALLED"
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

# --- zsh
# Managed-block model: replace just the marked block in ~/.zshrc; leave the
# rest (machine-specific PATH, dev tool injections, etc.) untouched.
echo "======= Configuring zsh"
ZSHRC="$HOME/.zshrc"
ZSHRC_START="# >>> dotfiles managed >>>"
ZSHRC_END="# <<< dotfiles managed <<<"

if [[ ! -f zshrc ]]; then
  echo "zshrc not found in repo, skipping"
elif [[ -f "$ZSHRC" ]] && grep -qF "$ZSHRC_START" "$ZSHRC"; then
  echo "Updating managed block in $ZSHRC"
  # Replace content between markers in place, preserving block position
  # and everything outside the markers.
  awk -v start="$ZSHRC_START" -v end="$ZSHRC_END" -v file="zshrc" '
    $0 == start {
      print start
      while ((getline line < file) > 0) print line
      close(file)
      print end
      skip = 1
      next
    }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "$ZSHRC" > "$ZSHRC.tmp" && mv "$ZSHRC.tmp" "$ZSHRC"
else
  echo "Appending managed block to $ZSHRC"
  {
    [[ -s "$ZSHRC" ]] && echo ""
    echo "$ZSHRC_START"
    cat zshrc
    echo "$ZSHRC_END"
  } >> "$ZSHRC"
fi
# ---

# --- git
echo "======= Configuring git"
cp gitconfig $HOME/.gitconfig
cp gitignore_global $HOME/.gitignore_global
# ---

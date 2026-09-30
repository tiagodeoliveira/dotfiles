#!/bin/bash

OS="$(uname -s)"   # Darwin | Linux
ARCH="$(uname -m)" # x86_64 | arm64 (macOS) | aarch64 (Linux)
if [[ "$OS" != "Darwin" && "$OS" != "Linux" ]]; then
  echo "ERROR: unsupported OS: $OS"
  exit 1
fi

# --- xcode command line tools
if [[ "$OS" == "Darwin" ]]; then
  echo "======= Checking Xcode Command Line Tools"
  if ! xcode-select -p &>/dev/null; then
    echo "Triggering Xcode CLT installer..."
    xcode-select --install
    echo "Complete the install in the popup, then press Enter to continue..."
    read -r
  else
    echo "Xcode CLT already installed"
  fi
fi
# ---

# --- homebrew
if [[ "$OS" == "Darwin" ]]; then
  # NONINTERACTIVE=1 covers both the installer below and every `brew` call
  # later in this script (formula installs, taps, etc.) - equivalent to apt -y.
  export NONINTERACTIVE=1
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
fi
# ---

# --- linux packages (apt / dnf)
# Native packages first; per-tool fallbacks (next block) cover whatever the
# distro repos lack. A package missing from the repos is not fatal here: the
# final check below fails loudly only if the tool is still absent.
if [[ "$OS" == "Linux" ]]; then
  echo "======= Installing Linux packages"
  export PATH="$HOME/.local/bin:$PATH"
  mkdir -p "$HOME/.local/bin"

  if command -v apt-get &>/dev/null; then
    PKG_MGR=apt
  elif command -v dnf &>/dev/null; then
    PKG_MGR=dnf
  else
    echo "ERROR: need apt-get or dnf"
    exit 1
  fi
  SUDO=""
  [[ $EUID -ne 0 ]] && SUDO="sudo"

  case "$ARCH" in
    x86_64) ARCH_GNU=x86_64; ARCH_ALT=amd64 ;;
    aarch64|arm64) ARCH_GNU=aarch64; ARCH_ALT=arm64 ;;
    *) echo "ERROR: unsupported CPU arch: $ARCH"; exit 1 ;;
  esac

  LINUX_FAILED=()
  linux_gate() {
    if (( ${#LINUX_FAILED[@]} > 0 )); then
      echo "ERROR: could not install: ${LINUX_FAILED[*]}"
      exit 1
    fi
  }
  pkg_installed() {
    case "$PKG_MGR" in
      apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed" ;;
      dnf) rpm -q "$1" &>/dev/null ;;
    esac
  }
  pkg_install() {
    case "$PKG_MGR" in
      apt) $SUDO env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends "$@" ;;
      dnf) $SUDO dnf install -y "$@" ;;
    esac
  }

  if [[ "$PKG_MGR" == apt ]]; then
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 update
    LINUX_PACKAGES=(tar gzip findutils unzip patch file zsh bash tmux bat zoxide neovim fzf ripgrep jq imagemagick ghostscript mediainfo libimage-exiftool-perl sshfs)
  else
    LINUX_PACKAGES=(tar gzip findutils unzip patch file perl zsh bash tmux zoxide neovim fzf ripgrep jq ImageMagick ghostscript mediainfo perl-Image-ExifTool fuse-sshfs)
  fi
  for pkg in "${LINUX_PACKAGES[@]}"; do
    if pkg_installed "$pkg"; then
      echo "  [skip] $pkg already installed"
    else
      echo "  [install] $pkg"
      pkg_install "$pkg" || case "$pkg" in
        sshfs|fuse-sshfs) echo "  [missing] $pkg is not in the $PKG_MGR repos; sshfs is optional and is not installed" ;;
        tar|gzip|findutils|unzip|patch|file|perl|zsh|bash|tmux|jq|ghostscript|imagemagick|ImageMagick) echo "  [missing] $pkg is not in the $PKG_MGR repos and has no fallback; the final check will fail" ;;
        *) echo "  [missing] $pkg is not in the $PKG_MGR repos; a fallback installs it" ;;
      esac
    fi
  done

  # Ubuntu ships bat as batcat and ImageMagick 6 (convert, no magick); zshrc and
  # zoom.yazi call bat and magick. IM6 convert accepts the same arguments.
  if ! command -v bat &>/dev/null && command -v batcat &>/dev/null; then
    ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
  fi
  if ! command -v magick &>/dev/null && command -v convert &>/dev/null; then
    printf '#!/bin/sh\nexec convert "$@"\n' > "$HOME/.local/bin/magick"
    chmod +x "$HOME/.local/bin/magick"
  fi

  github_asset_url() {
    local repo="$1" regex="$2" auth=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    curl -fsSL "${auth[@]}" "https://api.github.com/repos/$repo/releases/latest" \
      | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 \
      | grep -E "/${regex}\$" | head -1
  }

  install_release_bin() {
    local repo="$1" regex="$2" url tmp bin found
    shift 2
    url="$(github_asset_url "$repo" "$regex")"
    if [[ -z "$url" ]]; then
      echo "  ERROR: no asset matching '$regex' in $repo's latest release"
      return 1
    fi
    tmp="$(mktemp -d)"
    if ! curl -fsSL "$url" -o "$tmp/asset"; then rm -rf "$tmp"; return 1; fi
    mkdir "$tmp/x"
    case "$url" in
      *.zip) unzip -q "$tmp/asset" -d "$tmp/x" ;;
      *.tar.gz|*.tgz) tar -xzf "$tmp/asset" -C "$tmp/x" ;;
      *) echo "  ERROR: unsupported archive: $url"; rm -rf "$tmp"; return 1 ;;
    esac
    for bin in "$@"; do
      found="$(find "$tmp/x" -type f -name "$bin" | head -1)"
      if [[ -z "$found" ]]; then
        echo "  ERROR: $bin not found inside $url"
        rm -rf "$tmp"
        return 1
      fi
      install -m 0755 "$found" "$HOME/.local/bin/$bin"
    done
    rm -rf "$tmp"
  }

  ensure_release_bin() {
    local cmd="$1"
    shift
    if command -v "$cmd" &>/dev/null; then
      echo "  [skip] $cmd already installed"
      return 0
    fi
    echo "  [install] $cmd (release binary)"
    install_release_bin "$@" || LINUX_FAILED+=("$cmd")
  }

  echo "======= Installing Linux fallback tools"
  if ! command -v mise &>/dev/null; then
    echo "  [install] mise (official installer)"
    curl -fsSL https://mise.run | sh || LINUX_FAILED+=(mise)
  fi
  ensure_release_bin yazi   sxyazi/yazi           "yazi-${ARCH_GNU}-unknown-linux-musl\.zip" yazi ya
  ensure_release_bin ouch   ouch-org/ouch         "ouch-${ARCH_GNU}-unknown-linux-musl\.tar\.gz" ouch
  ensure_release_bin just   casey/just            "just-[0-9.]+-${ARCH_GNU}-unknown-linux-musl\.tar\.gz" just
  ensure_release_bin kubectx ahmetb/kubectx       "kubectx_v[0-9.]+_linux_${ARCH_GNU/aarch64/arm64}\.tar\.gz" kubectx
  ensure_release_bin kubens  ahmetb/kubectx       "kubens_v[0-9.]+_linux_${ARCH_GNU/aarch64/arm64}\.tar\.gz" kubens
  ensure_release_bin rtk    rtk-ai/rtk            "rtk-${ARCH_GNU}-unknown-linux-(musl|gnu)\.tar\.gz" rtk
  if [[ "$ARCH_GNU" == x86_64 ]]; then
    ensure_release_bin resvg RazrFalcon/resvg     "resvg-linux-x86_64\.tar\.gz" resvg
  else
    echo "  [skip] resvg publishes no linux $ARCH_GNU build"
  fi

  if ! command -v duckdb &>/dev/null; then
    echo "  [install] duckdb (release binary)"
    if curl -fsSL "https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-${ARCH_ALT}.gz" \
        | gunzip > "$HOME/.local/bin/duckdb" && chmod +x "$HOME/.local/bin/duckdb"; then
      :
    else
      rm -f "$HOME/.local/bin/duckdb"
      LINUX_FAILED+=(duckdb)
    fi
  fi

  if ! command -v kustomize &>/dev/null; then
    echo "  [install] kustomize (official installer)"
    (cd "$HOME/.local/bin" && curl -fsSL https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash) \
      || LINUX_FAILED+=(kustomize)
  fi

  # hunk ships a binary plus a skills/ directory the claude-code-skills section links to
  if ! command -v hunk &>/dev/null; then
    echo "  [install] hunk (release tarball)"
    HUNK_URL="$(github_asset_url modem-dev/hunk "hunkdiff-linux-${ARCH_ALT/amd64/x64}\.tar\.gz")"
    HUNK_TMP="$(mktemp -d)"
    if [[ -n "$HUNK_URL" ]] && curl -fsSL "$HUNK_URL" | tar -xz -C "$HUNK_TMP" \
        && HUNK_BIN="$(find "$HUNK_TMP" -type f -name hunk | head -1)" && [[ -n "$HUNK_BIN" ]]; then
      rm -rf "$HOME/.local/share/hunk"
      mkdir -p "$HOME/.local/share/hunk"
      cp -R "$(dirname "$HUNK_BIN")/." "$HOME/.local/share/hunk/"
      chmod +x "$HOME/.local/share/hunk/hunk"
      ln -sf "$HOME/.local/share/hunk/hunk" "$HOME/.local/bin/hunk"
    else
      LINUX_FAILED+=(hunk)
    fi
    rm -rf "$HUNK_TMP"
  fi

  # Not packaged on Amazon Linux 2023 (no-ops where apt/dnf already provided them).
  ensure_release_bin bat    sharkdp/bat           "bat-v[0-9.]+-${ARCH_GNU}-unknown-linux-musl\.tar\.gz" bat
  ensure_release_bin zoxide ajeetdsouza/zoxide    "zoxide-[0-9.]+-${ARCH_GNU}-unknown-linux-musl\.tar\.gz" zoxide
  ensure_release_bin rg     BurntSushi/ripgrep    "ripgrep-[0-9.]+-${ARCH_GNU}-unknown-linux-musl\.tar\.gz" rg
  ensure_release_bin fzf    junegunn/fzf          "fzf-[0-9.]+-linux_${ARCH_ALT}\.tar\.gz" fzf

  # neovim needs its runtime tree next to the binary; nvim-lspconfig needs >= 0.11
  # (Ubuntu 24.04 apt ships 0.9), and ~/.local/bin precedes /usr/bin on PATH
  NVIM_OLD=0
  if command -v nvim &>/dev/null; then
    NVIM_OLD=1 # unrunnable or unparseable counts as too old
    NVIM_VER="$(nvim --version 2>/dev/null | head -1 | sed -E 's/^NVIM v?//')" || true
    if [[ "$NVIM_VER" =~ ^([0-9]+)\.([0-9]+) ]]; then
      if [[ ${BASH_REMATCH[1]} -gt 0 || ${BASH_REMATCH[2]} -ge 11 ]]; then NVIM_OLD=0; fi
    fi
  fi
  if ! command -v nvim &>/dev/null || [[ $NVIM_OLD -eq 1 ]]; then
    echo "  [install] nvim (release tarball)"
    NVIM_URL="$(github_asset_url neovim/neovim "nvim-linux-${ARCH_GNU/aarch64/arm64}\.tar\.gz")"
    NVIM_TMP="$(mktemp -d)"
    if [[ -n "$NVIM_URL" ]] && curl -fsSL "$NVIM_URL" | tar -xz -C "$NVIM_TMP" \
        && NVIM_BIN="$(find "$NVIM_TMP" -type f -path '*/bin/nvim' | head -1)" && [[ -n "$NVIM_BIN" ]]; then
      rm -rf "$HOME/.local/share/nvim-dist"
      mkdir -p "$HOME/.local/share/nvim-dist"
      cp -R "$(dirname "$(dirname "$NVIM_BIN")")/." "$HOME/.local/share/nvim-dist/"
      ln -sf "$HOME/.local/share/nvim-dist/bin/nvim" "$HOME/.local/bin/nvim"
    else
      LINUX_FAILED+=(nvim)
    fi
    rm -rf "$NVIM_TMP"
  fi

  # Perl program with a lib/ tree; run in place through a symlink
  if ! command -v exiftool &>/dev/null; then
    echo "  [install] exiftool (Image-ExifTool from GitHub)"
    EXIF_TMP="$(mktemp -d)"
    EXIF_TAG="$(curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} https://api.github.com/repos/exiftool/exiftool/tags \
      | grep -o '"name": *"[0-9][0-9.]*"' | cut -d'"' -f4 | sort -V | tail -1)"
    [[ -z "$EXIF_TAG" ]] && echo "  ERROR: could not determine latest exiftool tag from the GitHub API"
    if [[ -n "$EXIF_TAG" ]] && curl -fsSL "https://github.com/exiftool/exiftool/archive/refs/tags/$EXIF_TAG.tar.gz" | tar -xz -C "$EXIF_TMP" \
        && EXIF_BIN="$(find "$EXIF_TMP" -maxdepth 2 -type f -name exiftool | head -1)" && [[ -n "$EXIF_BIN" ]]; then
      rm -rf "$HOME/.local/share/exiftool"
      mkdir -p "$HOME/.local/share/exiftool"
      cp -R "$(dirname "$EXIF_BIN")/." "$HOME/.local/share/exiftool/"
      chmod +x "$HOME/.local/share/exiftool/exiftool"
      ln -sf "$HOME/.local/share/exiftool/exiftool" "$HOME/.local/bin/exiftool"
    else
      LINUX_FAILED+=(exiftool)
    fi
    rm -rf "$EXIF_TMP"
  fi

  # MediaArea's Lambda build is a static-enough CLI built for Amazon Linux 2023
  if ! command -v mediainfo &>/dev/null; then
    echo "  [install] mediainfo (MediaArea Lambda build)"
    MI_PATH="$(curl -fsSL https://mediaarea.net/en/MediaInfo/Download/Lambda \
      | grep -o "download/binary/mediainfo/[^\"]*Lambda_${ARCH_GNU/aarch64/arm64}\.zip" | head -1)"
    [[ -z "$MI_PATH" ]] && echo "  ERROR: no Lambda_${ARCH_GNU/aarch64/arm64}.zip link on mediaarea.net Lambda download page"
    MI_TMP="$(mktemp -d)"
    if [[ -n "$MI_PATH" ]] && curl -fsSL "https://mediaarea.net/$MI_PATH" -o "$MI_TMP/mi.zip" \
        && unzip -q "$MI_TMP/mi.zip" -d "$MI_TMP/x" && [[ -f "$MI_TMP/x/bin/mediainfo" ]]; then
      install -m 0755 "$MI_TMP/x/bin/mediainfo" "$HOME/.local/bin/mediainfo"
    else
      LINUX_FAILED+=(mediainfo)
    fi
    rm -rf "$MI_TMP"
  fi

  for cmd in zsh tmux bat zoxide nvim fzf rg jq magick gs mediainfo exiftool patch file unzip mise yazi ya ouch duckdb just kustomize kubectx kubens rtk hunk; do
    command -v "$cmd" &>/dev/null || LINUX_FAILED+=("$cmd")
  done
  [[ "$ARCH_GNU" == x86_64 ]] && { command -v resvg &>/dev/null || LINUX_FAILED+=(resvg); }

  # A downloaded binary can be present yet unrunnable (e.g. built against a newer glibc).
  runs_ok() {
    case "$1" in
      exiftool) "$1" -ver ;;
      mediainfo) "$1" --Version ;;
      kustomize) "$1" version ;;
      kubectx|kubens) "$1" -h ;; # no version flag
      *) "$1" --version ;;
    esac &>/dev/null
  }
  for cmd in bat zoxide nvim fzf rg mediainfo exiftool mise yazi ya ouch duckdb just kustomize kubectx kubens hunk resvg; do
    if command -v "$cmd" &>/dev/null && ! runs_ok "$cmd"; then
      echo "  ERROR: $cmd is installed but does not run"
      LINUX_FAILED+=("$cmd")
    fi
  done

  # rtk is optional when its prebuilt binary cannot run on this host (aarch64 gnu build needs glibc >= 2.39)
  RTK_SKIPPED=""
  if command -v rtk &>/dev/null && ! rtk --version &>/dev/null; then
    RTK_SKIPPED=1
    echo "WARN: rtk is installed but does not run: the prebuilt $ARCH_GNU Linux build needs a newer glibc than this host has."
    echo "WARN: skipping rtk. To build it by hand (needs a Rust toolchain, e.g. 'mise use -g rust'):"
    echo "WARN:   cargo install --git https://github.com/rtk-ai/rtk --locked"
  fi
  linux_gate
fi
# ---

# --- oh-my-zsh
echo "======= Checking oh-my-zsh"
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  echo "Installing oh-my-zsh..."
  # CHSH/RUNZSH=no: skip the shell-change prompt and the "drop into zsh now" step.
  # KEEP_ZSHRC=yes: don't clobber an existing ~/.zshrc; our own managed-block step below handles it.
  CHSH=no RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "oh-my-zsh already installed"
fi
# ---

# --- brew packages
if [[ "$OS" == "Darwin" ]]; then
  # canonical formula names (nvim is an alias for neovim; brew list only matches canonical)
  echo "======= Installing Homebrew packages"
  BREW_PACKAGES=(bash tmux bat zoxide neovim mise fzf rtk modem-dev/tap/hunk ripgrep jq pnpm kustomize kubectx just imagemagick yazi resvg terminal-notifier exiftool mediainfo ghostscript ouch duckdb rich-cli)
  for pkg in "${BREW_PACKAGES[@]}"; do
    if brew list --formula "$pkg" &>/dev/null; then
      echo "  [skip] $pkg already installed"
    else
      echo "  [install] $pkg"
      brew install "$pkg"
    fi
  done
fi
# ---

# --- uv (Python package/project manager)
# Official installer, not brew -- self-updating and matches astral's own docs.
echo "======= Checking uv"
if command -v uv &>/dev/null; then
  echo "uv already installed at $(command -v uv)"
else
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
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
# Wire up installed tool skills under ~/.claude/skills/. On macOS, symlink against
# /opt/homebrew/opt/<formula>/... (version-stable; survives brew upgrade); on Linux,
# against the release tree under ~/.local/share.
echo "======= Configuring Claude Code skills"
if [[ "$OS" == "Darwin" ]]; then
  HUNK_SKILL_TARGET="/opt/homebrew/opt/hunk/libexec/skills/hunk-review/SKILL.md"
else
  HUNK_SKILL_TARGET="$HOME/.local/share/hunk/skills/hunk-review/SKILL.md"
fi
HUNK_SKILL_LINK="$HOME/.claude/skills/hunk-review/SKILL.md"
if [[ -f "$HUNK_SKILL_TARGET" ]]; then
  mkdir -p "$(dirname "$HUNK_SKILL_LINK")"
  ln -sf "$HUNK_SKILL_TARGET" "$HUNK_SKILL_LINK"
  echo "Linked hunk-review -> $HUNK_SKILL_TARGET"
else
  echo "hunk skill not found at $HUNK_SKILL_TARGET, skipping"
fi
# ---

# --- claude code user config
# CLAUDE.md @-imports RTK.md; RTK.md is generated by `rtk init -g` (requires rtk installed above, brew or release binary)
echo "======= Configuring Claude Code user rules"
mkdir -p "$HOME/.claude"
cp CLAUDE.md "$HOME/.claude/CLAUDE.md"
if [[ "$OS" == "Linux" && -n "$RTK_SKIPPED" ]]; then
  echo "rtk does not run on this host, skipping rtk init -g"
else
  rtk init -g
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
if (( BASH_MAJOR < 5 )) || (( BASH_MAJOR == 5 && BASH_MINOR < 2 )); then
  echo "ERROR: bash >= 5.2 required, found $BASH_VERSION_INSTALLED"
  exit 1
fi

echo "All dependencies found"
# ---

# --- mise runtimes
# Editor tooling needs runtimes managed by mise:
#  - stable Python 3: debugpy powers nvim-dap; pudb is the standalone TUI debugger
#  - Node 22 LTS for coc.nvim (Node 25 breaks coc-pyright's Web Storage localStorage)
# Put mise shims on PATH so the headless nvim PlugInstall below resolves python3/node.
echo "======= Installing mise runtimes"
eval "$(mise activate bash --shims)"
mise use -g python@3.13
mise use -g node@22
mise exec python@3.13 -- python -m pip install --upgrade pip debugpy pudb
# ---

# --- linux extras (need uv and node, so they run after the mise section)
# pnpm and rich-cli are brew formulas on macOS; on Linux they come from npm and uv.
if [[ "$OS" == "Linux" ]]; then
  echo "======= Installing Linux extras (pnpm, rich-cli)"
  command -v pnpm &>/dev/null || mise exec node@22 -- npm install -g pnpm || LINUX_FAILED+=(pnpm)
  command -v rich &>/dev/null || uv tool install rich-cli || LINUX_FAILED+=(rich-cli)
  linux_gate
fi
# ---

# --- mnemo (personal AI memory CLI)
# Install from the latest GitHub release tarball, not a plain clone+build:
# release.yml's publish-cli job stamps the real Auth0 domain/audience/client
# id into cli/src/defaults.ts before building. A local build leaves those
# blank (they're only set as GitHub Actions repo Variables), which breaks
# `mnemo login` with a fetch error against an empty https:// URL.
echo "======= Installing mnemo CLI"
if command -v mnemo &>/dev/null; then
  echo "mnemo already installed: $(mnemo --version 2>&1 | head -1)"
else
  gh_auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && gh_auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  MNEMO_TARBALL_URL=$(curl -fsSL "${gh_auth[@]}" https://api.github.com/repos/tiagodeoliveira/mnemo/releases/latest \
    | grep -o '"browser_download_url": *"[^"]*mnemo-cli-[^"]*\.tgz"' \
    | head -1 | cut -d'"' -f4)
  if [[ -z "$MNEMO_TARBALL_URL" ]]; then
    echo "ERROR: no mnemo-cli release tarball found on GitHub; cut a release (tag v*) first"
    exit 1
  fi
  MNEMO_TGZ="$(mktemp -t mnemo-cli.XXXXXX).tgz"
  curl -fsSL "$MNEMO_TARBALL_URL" -o "$MNEMO_TGZ"
  mise exec node@22 -- npm install -g "$MNEMO_TGZ"
  rm -f "$MNEMO_TGZ"
fi
# ---

# --- auris (personal meeting-transcription CLI)
# Same release-tarball approach as mnemo above: release.yml stamps the real
# Auth0 domain/audience/client id into the build before publishing, so a
# local build or plain npm install leaves those blank and breaks `auris login`.
echo "======= Installing auris CLI"
if command -v auris &>/dev/null; then
  echo "auris already installed at $(command -v auris)"
else
  gh_auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && gh_auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  AURIS_TARBALL_URL=$(curl -fsSL "${gh_auth[@]}" https://api.github.com/repos/tiagodeoliveira/auris/releases/latest \
    | grep -o '"browser_download_url": *"[^"]*auris-cli-[^"]*\.tgz"' \
    | head -1 | cut -d'"' -f4)
  if [[ -z "$AURIS_TARBALL_URL" ]]; then
    echo "ERROR: no auris-cli release tarball found on GitHub; cut a release (tag v*) first"
    exit 1
  fi
  AURIS_TGZ="$(mktemp -t auris-cli.XXXXXX).tgz"
  curl -fsSL "$AURIS_TARBALL_URL" -o "$AURIS_TGZ"
  mise exec node@22 -- npm install -g "$AURIS_TGZ"
  rm -f "$AURIS_TGZ"
fi
# ---

# --- claude code mcp registration (mnemo + auris)
# Wire up the personal memory/meeting MCP servers now that both CLIs and
# Claude Code itself are installed. -s user scope makes them available in
# every project, matching how CLAUDE.md documents them as always-on.
echo "======= Registering mnemo and auris MCP servers"
MISE_NODE_BIN="$HOME/.local/share/mise/installs/node/22/bin"
if claude mcp get mnemo &>/dev/null; then
  echo "mnemo MCP already registered"
else
  claude mcp add -s user mnemo -- node "$MISE_NODE_BIN/mnemo-mcp"
fi
if claude mcp get auris &>/dev/null; then
  echo "auris MCP already registered"
else
  claude mcp add -s user auris -- node "$MISE_NODE_BIN/auris-mcp"
fi
# ---

# --- claude code notification channel
# terminal_bell (not the default desktop notification) is what sets tmux's
# window_bell_flag, which is what makes tmux2k flag/bold-color a window --
# desktop notifications never touch that flag.
echo "======= Configuring Claude Code notification channel"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
[[ -f "$CLAUDE_SETTINGS" ]] || echo '{}' > "$CLAUDE_SETTINGS"
if [[ "$(jq -r '.preferredNotifChannel // ""' "$CLAUDE_SETTINGS")" != "terminal_bell" ]]; then
  jq '.preferredNotifChannel = "terminal_bell"' "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp" && mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
  echo "Set preferredNotifChannel = terminal_bell"
else
  echo "preferredNotifChannel already terminal_bell"
fi
# ---

# --- nvim
echo "======= Configuring nvim"
mkdir -p $HOME/.config/nvim
cp init.lua $HOME/.config/nvim
cp coc-settings.json $HOME/.config/nvim  # pins pyright to the mise python (sees our deps)

if [[ ! -d "$HOME/.config/nvim/autoload" ]]; then
  curl -fLo $HOME/.config/nvim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

nvim +silent +PlugUpgrade +PlugUpdate +PlugInstall +PlugClean +qall
# ---

# --- yazi
# package.toml pins the exact plugin set (revs/hashes); `ya pkg install`
# reads it and fetches everything listed, no per-plugin `ya pkg add` needed.
echo "======= Configuring yazi"
mkdir -p "$HOME/.config/yazi"
cp yazi/init.lua yazi/yazi.toml yazi/keymap.toml yazi/package.toml "$HOME/.config/yazi/"
# our duckdb patch below makes ya pkg install abort on re-runs; drop it so it re-fetches clean
[[ -d "$HOME/.config/yazi/plugins/duckdb.yazi" ]] && { chmod -R u+w "$HOME/.config/yazi/plugins/duckdb.yazi"; rm -rf "$HOME/.config/yazi/plugins/duckdb.yazi"; }
(cd "$HOME/.config/yazi" && ya pkg install)

# zoom.yazi is modified heavily enough (crop-based zoom, panning, higher zoom
# ceiling) that it's no longer the upstream plugin -- vendored directly here
# instead of pinned in package.toml, so `ya pkg install` above doesn't touch it.
mkdir -p "$HOME/.config/yazi/plugins/zoom.yazi"
# -f: ya pkg install leaves plugin files read-only, which a plain cp can't
# overwrite on a re-run
cp -f yazi/zoom.yazi/main.lua yazi/zoom.yazi/LICENSE "$HOME/.config/yazi/plugins/zoom.yazi/"

# duckdb.yazi has 3 open, unfixed upstream bugs against our exact yazi/DuckDB
# versions (crash on non-tabular preview, DuckDB >=1.5 lambda-deprecation
# warning leaking into preview, broken H/L scroll on yazi 26.x) -- `ya pkg
# install` re-fetches the plugin fresh from git each run, so re-apply the fix.
DUCKDB_MAIN="$HOME/.config/yazi/plugins/duckdb.yazi/main.lua"
if [[ -f "$DUCKDB_MAIN" ]] && ! grep -qF "lambda_syntax" "$DUCKDB_MAIN"; then
  patch -p1 "$DUCKDB_MAIN" < yazi/duckdb.yazi.patch
fi
if [[ "$OS" == "Darwin" ]]; then
  # sshfs.yazi needs macFUSE, a kernel/system extension -- can't be installed
  # non-interactively (needs a sudo password prompt and System Settings
  # approval). See the manual follow-ups at the end of this script.
  if ! brew list --cask macfuse &>/dev/null; then
    echo "macFUSE not installed -- sshfs.yazi won't work until you run:"
    echo "  brew install --cask macfuse"
  fi
fi
# ---

# --- tmux
echo "======= Configuring tmux"
if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
  mkdir -p $HOME/.tmux/plugins
  git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm
fi

cp tmux.conf $HOME/.tmux.conf

# tpm's install_plugins reads @plugin entries off a running tmux server, so
# drive it from a throwaway detached session instead of a manual prefix + I.
echo "Installing tmux plugins via tpm..."
tmux start-server
tmux new-session -d -s __dotfiles_setup
tmux source-file "$HOME/.tmux.conf"
"$HOME/.tmux/plugins/tpm/bin/install_plugins"
tmux kill-session -t __dotfiles_setup

if [[ "$OS" == "Darwin" ]]; then
  # tmux2k's cpu-temp.sh greps ioreg output case-insensitively for "Temperature",
  # which also matches AverageTemperature/MinimumTemperature/MaximumTemperature
  # substrings inside ioreg's BatteryData blob, plus a separate VirtualTemperature
  # key -- producing garbage on top of the real reading. Tighten it to match only
  # the exact "Temperature" key. tpm's install_plugins only clones what's missing
  # (no re-pull of existing plugins), so this survives a normal setup.sh re-run.
  CPU_TEMP_SCRIPT="$HOME/.tmux/plugins/tmux2k/plugins/cpu-temp.sh"
  if [[ -f "$CPU_TEMP_SCRIPT" ]] && ! grep -qF '"Temperature" =' "$CPU_TEMP_SCRIPT"; then
    sed -i '' "s/grep -i \"Temperature\"/grep -F '\"Temperature\" ='/" "$CPU_TEMP_SCRIPT"
    echo "Patched cpu-temp.sh ioreg grep"
  fi
fi

# tmux2k has no disk-usage widget. Its "custom" plugin ships as a bare
# "Hello Tmux2K" placeholder template -- repurpose it to show disk usage.
CUSTOM_SCRIPT="$HOME/.tmux/plugins/tmux2k/plugins/custom.sh"
if [[ -f "$CUSTOM_SCRIPT" ]] && ! grep -q "disk_percent" "$CUSTOM_SCRIPT"; then
  cat > "$CUSTOM_SCRIPT" <<'EOF'
#!/usr/bin/env bash

current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$current_dir/../lib/utils.sh"

custom_icon=$(get_tmux_option "@tmux2k-custom-icon" "")

main() {
    local disk_percent
    disk_percent=$(df -h / | awk 'NR==2{print $5}')
    echo "$custom_icon $(normalize_padding "$disk_percent" 4)"
}

main
EOF
  echo "Patched custom.sh to show disk usage"
fi
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

# --- manual follow-ups
# Surface the work the script cannot do for the user (interactive auth, etc.)
if [[ "$OS" == "Darwin" ]]; then COPY_KEY="pbcopy < ~/.ssh/id_ed25519.pub"; else COPY_KEY="cat ~/.ssh/id_ed25519.pub"; fi
cat <<EOF

======= Setup done. Manual steps left:

  1. mnemo login          # Auth0 device flow for the memory CLI
  2. auris login          # Auth0 device flow for the meeting CLI
  3. claude               # then /login to authenticate Claude Code
  4. Add SSH key to GitHub: $COPY_KEY
                          # then paste at https://github.com/settings/keys
EOF
if [[ "$OS" == "Darwin" ]]; then
  cat <<'EOF'
  5. brew install --cask macfuse   # then approve it in System Settings ->
                          # Privacy & Security (and likely restart) before
                          # sshfs.yazi (yazi plugin) will work
                          # brew install --cask sshfs-mac   # after macfuse
EOF
fi
if [[ "$OS" == "Linux" ]]; then
  cat <<'EOF'
  5. sudo usermod -s "$(command -v zsh)" "$USER"
                          # login shell is still bash, so ~/.zshrc never loads over SSH;
                          # takes effect on your next login
EOF
  if [[ -n "${RTK_SKIPPED:-}" ]]; then
    cat <<'EOF'
  6. mise use -g rust && cargo install --git https://github.com/rtk-ai/rtk --locked && rtk init -g
                          # the prebuilt rtk needs a newer glibc than this host has
EOF
  fi
fi
echo
# ---

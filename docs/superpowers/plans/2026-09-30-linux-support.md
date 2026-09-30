# Linux Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `setup.sh` provisions the same CLI/TUI environment on macOS, Ubuntu 24.04 (apt) and Amazon Linux 2023 (dnf), proven by a permanent Docker test.

**Architecture:** One `setup.sh` with `OS`-gated sections. macOS-only sections are wrapped in `if [[ "$OS" == "Darwin" ]]`. A new Linux section installs native packages via apt/dnf, then fills gaps with GitHub-release/installer fallbacks through two small helpers. `test/` holds one Dockerfile per distro, a tool-presence checker (`verify-tools.sh`, also runnable on macOS) and a driver (`docker-test.sh`).

**Tech Stack:** bash (must stay bash 3.2-parseable, since macOS `/bin/bash` may run it), apt, dnf, Docker, GitHub release APIs.

**Spec:** `docs/superpowers/specs/2026-09-30-linux-support-design.md`

## Global Constraints

- Single `setup.sh`; no `setup-mac.sh`/`setup-linux.sh` split.
- Linux is SSH-only: no GUI, no desktop notifications, no Ghostty. Homebrew is not installed on Linux.
- Linux package managers: `apt-get` (Ubuntu 24.04) and `dnf` (Amazon Linux 2023), detected by `command -v`, not distro name.
- The macOS path must behave exactly as before.
- Success = on clean `ubuntu:24.04` and `amazonlinux:2023` containers, `setup.sh` exits 0, prints "Setup done", and `test/verify-tools.sh` passes.
- `setup.sh` has no `set -e`: any required Linux tool that fails to install must be recorded and cause a non-zero exit.
- Minimum bash is 5.2 on every platform (was 5.3 on macOS).
- Docker is used only by `test/`; `setup.sh` never depends on it.
- Never `git commit` unless the user asks. Each task ends with a checkpoint that names the commit message to use when they do.
- Out of scope: interactive tmux/yazi/nvim testing, Amazon Linux 2, testing a non-host CPU arch.

## Review Focus

- Re-running `setup.sh` on an already-provisioned Linux box must exit 0 with no duplicate work. Test: `docker-test.sh` runs `setup.sh` twice (Task 1).
- Running as root with no `sudo` installed (the common container/SSH-as-root case). Test: `AS_ROOT=1 test/docker-test.sh ubuntu` (Task 7).
- GitHub API failure or rate limit (401/403/empty asset list) must fail loudly, never skip silently. Test: `GITHUB_TOKEN=invalid` run exits non-zero naming the failed tools (Task 4).
- Ubuntu ships `bat` as `batcat` and ImageMagick 6 (`convert`, no `magick`); `zshrc` and zoom.yazi call `bat` and `magick`. Test: `verify-tools.sh` runs zoom.yazi's exact `magick` argument list and `bat --version` (Task 1, satisfied in Task 3).
- `tmux.conf` must parse on Linux, and the bell hook / `pbcopy` bindings must be inert there. Test: `verify-tools.sh` sources `~/.tmux.conf` in a throwaway server and asserts no `pbcopy` binding exists off macOS (Task 6).

---

### Task 1: Docker test harness and tool checker

**Files:**
- Create: `test/verify-tools.sh`
- Create: `test/Dockerfile.ubuntu`
- Create: `test/Dockerfile.amazonlinux`
- Create: `test/docker-test.sh`
- Create: `.dockerignore`

**Interfaces:**
- Produces: `test/verify-tools.sh` (exit 0 = everything present, non-zero = prints `MISSING: <tool>` lines); `test/docker-test.sh [ubuntu|amazonlinux ...]` with env `PLATFORM` (e.g. `linux/amd64`), `AS_ROOT=1`, `GITHUB_TOKEN` (passed through).

- [ ] **Step 1: Write the checker**

`test/verify-tools.sh`:

```bash
#!/bin/bash
# Asserts everything setup.sh promises is installed and usable. Runs at the end
# of the Docker test and can be run on macOS as a baseline.
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$HOME/.local/share/mise/installs/node/22/bin:$PATH"
OS="$(uname -s)"
ARCH="$(uname -m)"
failed=0

fail() { echo "FAIL: $*"; failed=1; }
require() { command -v "$1" &>/dev/null || { echo "MISSING: $1"; failed=1; }; }

for t in zsh tmux bat zoxide nvim fzf rg jq magick gs mediainfo exiftool patch file unzip \
         yazi ya ouch duckdb rich just kustomize kubectx rtk hunk pnpm mise uv claude mnemo auris; do
  require "$t"
done
# resvg publishes no aarch64 Linux build
if [[ "$OS" == "Darwin" || "$ARCH" == "x86_64" ]]; then require resvg; fi

# yazi config and plugins
[[ -f "$HOME/.config/yazi/plugins/zoom.yazi/main.lua" ]] || fail "zoom.yazi not installed"
grep -qF lambda_syntax "$HOME/.config/yazi/plugins/duckdb.yazi/main.lua" 2>/dev/null || fail "duckdb.yazi patch not applied"

# bat must render (Ubuntu ships it as batcat)
echo hi | bat --paging=never -pp >/dev/null 2>&1 || fail "bat does not run"

# zoom.yazi's exact magick invocation (crop + sample + WEBP output)
tmp="$(mktemp -d)"
if command -v magick &>/dev/null; then
  magick -size 40x40 xc:red "$tmp/in.png" \
    && magick "$tmp/in.png" -auto-orient -strip -crop 20x20+0+0 +repage -sample 10x10 -quality 90 "WEBP:$tmp/out.webp" \
    && [[ -s "$tmp/out.webp" ]] || fail "magick cannot do zoom.yazi's crop+WEBP pipeline"
fi
rm -rf "$tmp"

# tmux config parses; macOS-only bindings absent elsewhere
if command -v tmux &>/dev/null && [[ -f "$HOME/.tmux.conf" ]]; then
  tmux -L verify-tools new-session -d -s verify 2>/dev/null
  tmux -L verify-tools source-file "$HOME/.tmux.conf" || fail "tmux.conf does not parse"
  if [[ "$OS" != "Darwin" ]] && tmux -L verify-tools list-keys -T copy-mode-vi | grep -q pbcopy; then
    fail "pbcopy binding present on $OS"
  fi
  tmux -L verify-tools kill-server 2>/dev/null
fi

[[ $failed -eq 0 ]] && echo "verify-tools: OK"
exit $failed
```

- [ ] **Step 2: Baseline on macOS**

Run: `chmod +x test/verify-tools.sh && test/verify-tools.sh`
Expected: `verify-tools: OK`. If a tool the Mac genuinely has is reported missing, fix the checker (wrong command name), not the Mac.

- [ ] **Step 3: Write the Dockerfiles and `.dockerignore`**

`test/Dockerfile.ubuntu`:

```dockerfile
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends sudo ca-certificates curl git \
 && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash tester \
 && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
USER tester
WORKDIR /home/tester/dotfiles
COPY --chown=tester:tester . .
```

`test/Dockerfile.amazonlinux`:

```dockerfile
FROM amazonlinux:2023
RUN dnf install -y sudo git tar gzip findutils shadow-utils \
 && dnf clean all
RUN useradd -m -s /bin/bash tester \
 && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
USER tester
WORKDIR /home/tester/dotfiles
COPY --chown=tester:tester . .
```

`.dockerignore`:

```
.git
.claude
docs
```

Both images contain only what a fresh host has, plus `git`/`sudo`. `curl` and `ca-certificates` are already in the Amazon Linux base (`curl-minimal`); do not install `curl` there, it conflicts.

- [ ] **Step 4: Write the driver**

`test/docker-test.sh`:

```bash
#!/bin/bash
# Runs setup.sh twice (idempotency) in a clean container per distro, then verify-tools.sh.
# Usage: test/docker-test.sh [ubuntu|amazonlinux ...]   (default: both)
# Env:   PLATFORM=linux/amd64  force CPU arch (default: host arch)
#        AS_ROOT=1             run as root with no sudo in the path
#        GITHUB_TOKEN          forwarded, avoids API rate limits
set -o pipefail
cd "$(dirname "$0")/.."

targets=("$@")
[[ ${#targets[@]} -eq 0 ]] && targets=(ubuntu amazonlinux)

platform_args=()
[[ -n "${PLATFORM:-}" ]] && platform_args=(--platform "$PLATFORM")
user_args=()
[[ -n "${AS_ROOT:-}" ]] && user_args=(--user root -e HOME=/root)

results=()
rc=0
for t in "${targets[@]}"; do
  image="dotfiles-test-$t"
  log="$(mktemp -t "dotfiles-$t.XXXXXX")"
  echo "======= [$t] building"
  if ! docker build "${platform_args[@]}" -f "test/Dockerfile.$t" -t "$image" .; then
    results+=("$t: BUILD FAILED")
    rc=1
    continue
  fi
  echo "======= [$t] running setup.sh x2 + verify (log: $log)"
  docker run --rm "${platform_args[@]}" "${user_args[@]}" ${GITHUB_TOKEN:+-e GITHUB_TOKEN} "$image" \
    bash -c 'bash setup.sh && bash setup.sh && bash test/verify-tools.sh' 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  if [[ $status -eq 0 ]] && grep -q "Setup done" "$log" && grep -q "verify-tools: OK" "$log"; then
    results+=("$t: PASS")
  else
    results+=("$t: FAIL (exit $status, log: $log)")
    rc=1
  fi
done
printf '%s\n' "${results[@]}"
exit $rc
```

- [ ] **Step 5: Confirm the test can fail**

Verify Docker is running: `docker info >/dev/null && echo ok`. Expected: `ok` (start Docker Desktop otherwise).

Run:
```bash
chmod +x test/docker-test.sh
docker build -f test/Dockerfile.ubuntu -t dotfiles-test-ubuntu . && docker run --rm dotfiles-test-ubuntu bash test/verify-tools.sh
```
Expected: FAIL with many `MISSING:` lines and a non-zero exit. That proves the checker fails on a bare box.

- [ ] **Step 6: Checkpoint**

`git status` shows the five new files. Commit message when asked: `test: docker harness for setup.sh on ubuntu and amazon linux`

---

### Task 2: OS detection, macOS gating, portability fixes

**Files:**
- Modify: `setup.sh` (sections: header, xcode, homebrew, brew packages, claude code skills, dependency checks, mnemo, auris, yazi/macFUSE, tmux2k cpu-temp, manual follow-ups)

**Interfaces:**
- Produces: globals `OS` (`Darwin`|`Linux`) and `ARCH` (`uname -m`) available to every later section.

- [ ] **Step 1: Add OS/ARCH detection**

Directly under `#!/bin/bash`, before `# --- xcode command line tools`:

```bash
OS="$(uname -s)"   # Darwin | Linux
ARCH="$(uname -m)" # x86_64 | arm64 (macOS) | aarch64 (Linux)
if [[ "$OS" != "Darwin" && "$OS" != "Linux" ]]; then
  echo "ERROR: unsupported OS: $OS"
  exit 1
fi

```

- [ ] **Step 2: Wrap the xcode and homebrew sections in Darwin guards**

Wrap the whole content between `# --- xcode command line tools` and its closing `# ---` in `if [[ "$OS" == "Darwin" ]]; then` … `fi` (indent the body two spaces), keeping the `# ---` markers outside. Do the same for the `# --- homebrew` section (including `export NONINTERACTIVE=1` and the `shellenv` eval), and for the `# --- brew packages` section (including the `BREW_PACKAGES=(...)` line and loop). Leave the `# --- oh-my-zsh` section between them untouched.

- [ ] **Step 3: Make the hunk skill path OS-aware**

In `# --- claude code skills`, replace the `HUNK_SKILL_TARGET=` line with:

```bash
if [[ "$OS" == "Darwin" ]]; then
  HUNK_SKILL_TARGET="/opt/homebrew/opt/hunk/libexec/skills/hunk-review/SKILL.md"
else
  HUNK_SKILL_TARGET="$HOME/.local/share/hunk/skills/hunk-review/SKILL.md"
fi
```

- [ ] **Step 4: Lower the bash floor to 5.2 on every platform**

In `# --- dependency checks`, change the version comparison and message so the minimum is 5.2 (Ubuntu 24.04 and Amazon Linux 2023 both ship 5.2):

```bash
if (( BASH_MAJOR < 5 )) || (( BASH_MAJOR == 5 && BASH_MINOR < 2 )); then
  echo "ERROR: bash >= 5.2 required, found $BASH_VERSION_INSTALLED"
  exit 1
fi
```

The check stays unguarded and runs on both OSes. Leave the `zsh`/`tmux`/`bash` presence checks as they are.

- [ ] **Step 5: Fix GNU-incompatible commands**

`mktemp -t mnemo-cli` fails on GNU (needs `XXXXXX`). Replace both temp-file lines:

```bash
  MNEMO_TGZ="$(mktemp -t mnemo-cli.XXXXXX).tgz"
```
```bash
  AURIS_TGZ="$(mktemp -t auris-cli.XXXXXX).tgz"
```

Wrap the macFUSE check in the yazi section (`if ! brew list --cask macfuse ...` through its `fi`, plus the two comment lines above it) in `if [[ "$OS" == "Darwin" ]]; then` … `fi`. Wrap the tmux2k `CPU_TEMP_SCRIPT` block (the comment paragraph, the variable, and the `if [[ -f "$CPU_TEMP_SCRIPT" ... fi`, which uses BSD `sed -i ''` and macOS `ioreg`) in the same guard. Leave the tmux2k `custom.sh` disk-usage block unguarded (portable).

- [ ] **Step 6: Split the manual follow-ups**

Replace the single `cat <<'EOF'` block with the common steps, then the macFUSE step on macOS only:

```bash
cat <<'EOF'

======= Setup done. Manual steps left:

  1. mnemo login          # Auth0 device flow for the memory CLI
  2. auris login          # Auth0 device flow for the meeting CLI
  3. claude               # then /login to authenticate Claude Code
  4. Add SSH key to GitHub: pbcopy < ~/.ssh/id_ed25519.pub
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
echo
```

Step 4's `pbcopy` hint is wrong on Linux; change that line to `cat ~/.ssh/id_ed25519.pub` under a Linux branch:

```bash
if [[ "$OS" == "Darwin" ]]; then COPY_KEY="pbcopy < ~/.ssh/id_ed25519.pub"; else COPY_KEY="cat ~/.ssh/id_ed25519.pub"; fi
```
and print it as `  4. Add SSH key to GitHub: $COPY_KEY` (use an unquoted `<<EOF` heredoc for that first block, escaping nothing else since it contains no `$` or backticks besides the variable).

- [ ] **Step 7: Verify only intended changes**

Run: `bash -n setup.sh && git diff -w --stat setup.sh && git diff -w setup.sh | grep '^[+-]' | grep -v '^[+-][+-]' | head -80`
Expected: `bash -n` prints nothing. The whitespace-insensitive diff shows only added `if/fi` lines, the new OS/ARCH header, the hunk path branch, the two `mktemp` templates, and the follow-ups split. No line of the macOS logic is otherwise altered.

- [ ] **Step 8: Checkpoint**

Commit message when asked: `setup.sh: detect OS and gate macOS-only sections`

---

### Task 3: Linux native packages

**Files:**
- Modify: `setup.sh` (new `# --- linux packages` section directly after the `# --- homebrew` section and before `# --- oh-my-zsh`, because oh-my-zsh needs zsh, git and curl installed first)

**Interfaces:**
- Consumes: `OS`, `ARCH` from Task 2.
- Produces (Linux only): `PKG_MGR` (`apt`|`dnf`), `SUDO` (`""`|`sudo`), `ARCH_GNU` (`x86_64`|`aarch64`), `ARCH_ALT` (`amd64`|`arm64`), `LINUX_FAILED` (array of tool names), functions `pkg_installed <pkg>`, `pkg_install <pkg>...`, `linux_gate` (exits 1 with the names if `LINUX_FAILED` is non-empty).

- [ ] **Step 1: Run the Ubuntu test to see it fail**

Run: `test/docker-test.sh ubuntu`
Expected: FAIL. `setup.sh` reaches `oh-my-zsh` with no zsh and exits non-zero, or `verify-tools` lists missing tools.

- [ ] **Step 2: Add the section**

```bash
# --- linux packages (apt / dnf)
# Native packages first; per-tool fallbacks (next block) cover whatever the
# distro repos lack. A package missing from the repos is not fatal here: the
# final check below fails loudly only if the tool is still absent.
if [[ "$OS" == "Linux" ]]; then
  echo "======= Installing Linux packages"
  export DEBIAN_FRONTEND=noninteractive
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
      apt) $SUDO apt-get install -y --no-install-recommends "$@" ;;
      dnf) $SUDO dnf install -y "$@" ;;
    esac
  }

  if [[ "$PKG_MGR" == apt ]]; then
    $SUDO apt-get update
    LINUX_PACKAGES=(tar gzip findutils unzip patch file zsh bash tmux bat zoxide neovim fzf ripgrep jq imagemagick ghostscript mediainfo libimage-exiftool-perl sshfs)
  else
    LINUX_PACKAGES=(tar gzip findutils unzip patch file zsh bash tmux zoxide neovim fzf ripgrep jq ImageMagick ghostscript mediainfo perl-Image-ExifTool fuse-sshfs)
  fi
  for pkg in "${LINUX_PACKAGES[@]}"; do
    if pkg_installed "$pkg"; then
      echo "  [skip] $pkg already installed"
    else
      echo "  [install] $pkg"
      pkg_install "$pkg" || echo "  [missing] $pkg is not in the $PKG_MGR repos; a fallback may cover it"
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

  # @@FALLBACKS@@ (Task 4 replaces this line)

  for cmd in zsh tmux bat zoxide nvim fzf rg jq magick gs mediainfo exiftool patch file unzip; do
    command -v "$cmd" &>/dev/null || LINUX_FAILED+=("$cmd")
  done
  linux_gate
fi
# ---
```

`sshfs`/`fuse-sshfs` is deliberately outside the required-command check: it is optional and Amazon Linux may not carry it.

- [ ] **Step 3: Syntax check and Ubuntu run**

Run: `bash -n setup.sh && test/docker-test.sh ubuntu`
Expected: `bash -n` clean. The container run now gets past the Linux packages section. It still fails at `verify-tools` (or earlier at `linux_gate` if a native package is absent from Ubuntu's repos); list the `MISSING:`/`ERROR: could not install:` names. Anything on that list that Task 4 does not cover gets a fallback entry added in Task 4 (Step 5).

- [ ] **Step 4: Checkpoint**

Commit message when asked: `setup.sh: install native packages on apt/dnf hosts`

---

### Task 4: Linux fallback installers

**Files:**
- Modify: `setup.sh` (replace the `# @@FALLBACKS@@` line from Task 3)

**Interfaces:**
- Consumes: `ARCH_GNU`, `ARCH_ALT`, `LINUX_FAILED` (Task 3).
- Produces: `github_asset_url <repo> <ere-regex>` (prints the download URL of the latest release asset whose whole name matches, empty on failure); `install_release_bin <repo> <ere-regex> <bin>...` (download, extract `.zip`/`.tar.gz`, install named binaries into `~/.local/bin`, non-zero on any failure); `ensure_release_bin <cmd> <repo> <regex> <bin>...` (skips if `<cmd>` exists, records `<cmd>` in `LINUX_FAILED` on failure).

- [ ] **Step 1: Run the Ubuntu test to see it fail**

Run: `test/docker-test.sh ubuntu`
Expected: FAIL with `MISSING:` for `yazi ya ouch duckdb just kustomize kubectx rtk hunk mise` (and `resvg` on x86_64).

- [ ] **Step 2: Replace `# @@FALLBACKS@@` with the helpers**

```bash
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
```

- [ ] **Step 3: Append the per-tool fallbacks after the helpers**

```bash
  echo "======= Installing Linux fallback tools"
  if ! command -v mise &>/dev/null; then
    echo "  [install] mise (official installer)"
    curl -fsSL https://mise.run | sh || LINUX_FAILED+=(mise)
  fi
  ensure_release_bin yazi   sxyazi/yazi           "yazi-${ARCH_GNU}-unknown-linux-musl\.zip" yazi ya
  ensure_release_bin ouch   ouch-org/ouch         "ouch-${ARCH_GNU}-unknown-linux-musl\.tar\.gz" ouch
  ensure_release_bin just   casey/just            "just-[0-9.]+-${ARCH_GNU}-unknown-linux-musl\.tar\.gz" just
  ensure_release_bin kubectx ahmetb/kubectx       "kubectx_v[0-9.]+_linux_${ARCH_GNU/aarch64/arm64}\.tar\.gz" kubectx
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
```

- [ ] **Step 4: Extend the final required-command check**

In the loop added in Task 3, extend the command list to: `zsh tmux bat zoxide nvim fzf rg jq magick gs mediainfo exiftool patch file unzip mise yazi ya ouch duckdb just kustomize kubectx rtk hunk`, and add `resvg` when `$ARCH_GNU == x86_64`:

```bash
  [[ "$ARCH_GNU" == x86_64 ]] && { command -v resvg &>/dev/null || LINUX_FAILED+=(resvg); }
```

- [ ] **Step 5: Run both distros and close gaps**

Run: `test/docker-test.sh`
Expected: setup.sh no longer stops at missing fallback tools. For anything still reported missing (most likely candidates on Amazon Linux: `tmux zoxide neovim fzf ripgrep jq mediainfo bat`), add an `ensure_release_bin <cmd> <repo> <regex> <bin>` line using the same pattern (find the asset name with `gh release view --repo <repo> --json assets --jq '.assets[].name'`), rerun, and repeat until both distros get past the Linux sections. The `pnpm` and `rich` failures are expected until Task 5.

- [ ] **Step 6: Failure-mode check (GitHub API failure fails loudly)**

Run: `GITHUB_TOKEN=invalid test/docker-test.sh ubuntu`
Expected: FAIL, and the log contains `ERROR: no asset matching` lines and `ERROR: could not install:` naming the tools. It must not reach "Setup done".

- [ ] **Step 7: Checkpoint**

Commit message when asked: `setup.sh: fallback installers for tools missing from apt/dnf`

---

### Task 5: Linux extras that need uv and node

**Files:**
- Modify: `setup.sh` (new block after `# --- mise runtimes`)

**Interfaces:**
- Consumes: `LINUX_FAILED`, `linux_gate` (Task 3); `uv` (already installed by the `# --- uv` section), `mise` node@22 (installed by `# --- mise runtimes`).

- [ ] **Step 1: Confirm the failure**

Run: `test/docker-test.sh ubuntu`
Expected: FAIL; `verify-tools` reports `MISSING: pnpm` and `MISSING: rich`.

- [ ] **Step 2: Add the block after the `# --- mise runtimes` section's closing `# ---`**

```bash
# --- linux extras (need uv and node, so they run after the mise section)
# pnpm and rich-cli are brew formulas on macOS; on Linux they come from npm and uv.
if [[ "$OS" == "Linux" ]]; then
  echo "======= Installing Linux extras (pnpm, rich-cli)"
  command -v pnpm &>/dev/null || mise exec node@22 -- npm install -g pnpm || LINUX_FAILED+=(pnpm)
  command -v rich &>/dev/null || uv tool install rich-cli || LINUX_FAILED+=(rich-cli)
  linux_gate
fi
# ---
```

- [ ] **Step 3: Run**

Run: `bash -n setup.sh && test/docker-test.sh`
Expected: on any distro whose earlier tiers pass, `pnpm`/`rich` are installed and the container run reaches the end. Remaining failures are tools from Step 5 of Task 4 or the tmux items in Task 6.

- [ ] **Step 4: Checkpoint**

Commit message when asked: `setup.sh: install pnpm and rich-cli on linux via npm and uv`

---

### Task 6: OS-aware tmux.conf

**Files:**
- Modify: `tmux.conf:4-6` (bell hook), `tmux.conf:49-51` (pbcopy bindings)

- [ ] **Step 1: Confirm the failure**

Run: `test/docker-test.sh ubuntu`
Expected: FAIL with `pbcopy binding present on Linux` from `verify-tools.sh`.

- [ ] **Step 2: Make the bell hook a no-op without terminal-notifier**

Replace the `set-hook -g alert-bell ...` line with:

```
set-hook -g alert-bell 'run-shell "command -v terminal-notifier >/dev/null || exit 0; terminal-notifier -title tmux -subtitle \"#{session_name}: #{window_name}\" -message Bell -sound default"'
```

Update the comment above it to say it is a no-op where terminal-notifier is absent (Linux over SSH).

- [ ] **Step 3: Make the pbcopy bindings macOS-only**

Replace the two `pbcopy` bindings and their comment with:

```
# macOS clipboard integration; elsewhere the plain 'y' copy-selection-and-cancel
# above applies (tmux forwards it to the local terminal via OSC 52 over SSH)
if-shell 'command -v pbcopy' {
  bind-key -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel "pbcopy"
  bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel "pbcopy"
}
```

The `{ }` block form needs tmux ≥ 3.2 (Ubuntu 24.04 ships 3.4). If Amazon Linux's tmux is older, `verify-tools.sh` fails with "tmux.conf does not parse"; then use the single-command form instead, which every tmux version accepts:

```
if-shell 'command -v pbcopy' 'bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel pbcopy ; bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel pbcopy'
```

- [ ] **Step 4: Verify on Linux and macOS**

Run: `test/docker-test.sh` and, on the Mac, `test/verify-tools.sh` after copying the file (`cp tmux.conf ~/.tmux.conf`).
Expected: both containers report `verify-tools: OK`. On macOS, `tmux list-keys -T copy-mode-vi | grep pbcopy` still shows the two bindings.

- [ ] **Step 5: Checkpoint**

Commit message when asked: `tmux.conf: make bell notification and pbcopy bindings macOS-only`

---

### Task 7: Full verification and spec sync

**Files:**
- Modify: `docs/superpowers/specs/2026-09-30-linux-support-design.md`

- [ ] **Step 1: Both distros, clean**

Run: `test/docker-test.sh`
Expected output ends with `ubuntu: PASS` and `amazonlinux: PASS`.

- [ ] **Step 2: Root without sudo**

Run: `AS_ROOT=1 test/docker-test.sh ubuntu`
Expected: `ubuntu: PASS` (exercises `SUDO=""`).

- [ ] **Step 3: Other CPU arch, if the host allows emulation**

On Apple Silicon the default runs are `aarch64`. Run: `PLATFORM=linux/amd64 test/docker-test.sh ubuntu`
Expected: `ubuntu: PASS` (exercises the x86_64 assets, including resvg). Skip and say so in the report if emulation is unavailable.

- [ ] **Step 4: macOS regression**

Ask the user before this step: it runs the real `setup.sh` on their machine (idempotent; it re-copies configs and re-runs installers, as they do routinely). Run: `bash setup.sh && test/verify-tools.sh`
Expected: completes as before, `verify-tools: OK`. Confirm `git status` shows no unintended changes to generated files.

- [ ] **Step 5: Sync the spec with what was built**

Edit the spec so it matches reality: `rtk` and `hunk` install from release tarballs (not `.deb`/`.rpm`); `mise` and `duckdb` need Linux installers (mise.run, release `.gz`) rather than being "already portable"; `pnpm` via `npm -g`; `resvg` skipped on aarch64; the `magick`→`convert` and `bat`→`batcat` shims; the bash minimum drops from 5.3 to 5.2 on all platforms; the tmux bell hook is a runtime `command -v` guard, not `if-shell`; `docker-test.sh` runs `setup.sh` twice.

- [ ] **Step 6: Checkpoint**

`git status` and `git diff --stat`. Commit message when asked: `docs: sync linux support spec with implementation`

---

### Task 8: GitHub Actions workflow for the Docker test

**Files:**
- Create: `.github/workflows/setup-linux.yml`
- Modify: `docs/superpowers/specs/2026-09-30-linux-support-design.md` (add a CI section)

**Interfaces:**
- Consumes: `test/docker-test.sh <ubuntu|amazonlinux>` (Task 1), env `GITHUB_TOKEN` forwarded into the container (Task 1).

- [ ] **Step 1: Write the workflow**

`.github/workflows/setup-linux.yml`:

```yaml
name: setup-linux

on:
  push:
    branches: [main]
    paths: &paths
      - setup.sh
      - tmux.conf
      - zshrc
      - init.lua
      - coc-settings.json
      - yazi/**
      - test/**
      - .github/workflows/setup-linux.yml
  pull_request:
    paths: *paths
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  linux:
    name: setup.sh on ${{ matrix.distro }}
    runs-on: ubuntu-latest
    timeout-minutes: 45
    strategy:
      fail-fast: false
      matrix:
        distro: [ubuntu, amazonlinux]
    steps:
      - uses: actions/checkout@v4
      - name: Run setup.sh twice and verify tools
        env:
          # forwarded into the container; lifts the unauthenticated GitHub API rate limit
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: test/docker-test.sh ${{ matrix.distro }}
```

GitHub-hosted runners are x86_64, so this run exercises the x86_64 release assets (including resvg) that a local Apple-silicon run does not. If the YAML anchor (`&paths` / `*paths`) is rejected by GitHub's parser, repeat the path list under `pull_request` instead.

- [ ] **Step 2: Validate the file locally**

Run: `ruby -ryaml -e 'y = YAML.load_file(".github/workflows/setup-linux.yml", aliases: true); abort("bad") unless y["jobs"]["linux"]["strategy"]["matrix"]["distro"] == %w[ubuntu amazonlinux]; puts "yaml ok"'`
Expected: `yaml ok`. If `actionlint` is installed, also run `actionlint .github/workflows/setup-linux.yml` and expect no output.

- [ ] **Step 3: Document it in the spec**

Add a "CI" section to the spec: the workflow runs `test/docker-test.sh` for `ubuntu` and `amazonlinux` on `ubuntu-latest` (x86_64), on pushes to `main`, pull requests and manual dispatch, restricted to the files that affect the install; macOS is not covered in CI (`setup.sh` mutates the machine and needs Homebrew).

- [ ] **Step 4: Checkpoint**

The first real run happens only after the branch is pushed; note that in the report. Commit message when asked: `ci: run the linux docker test on github actions`

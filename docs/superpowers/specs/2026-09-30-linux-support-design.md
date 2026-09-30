# Linux support for setup.sh

## Goal

`setup.sh` provisions the same CLI/TUI environment on macOS, Ubuntu (apt) and Amazon Linux 2023 (dnf). Linux hosts are only reached over SSH, so anything that exists to serve a local GUI is out of scope there.

Success: on a clean `ubuntu:24.04` and a clean `amazonlinux:2023` container, `setup.sh` runs non-interactively, exits 0 and reaches the "Setup done" banner. The macOS path behaves exactly as before.

## Structure

One `setup.sh`. `OS="$(uname -s)"` near the top; sections that differ branch on it inline. OS-agnostic sections (oh-my-zsh, uv, Claude Code, mise runtimes, mnemo, auris, ssh key, allowed_signers, git, zsh managed block, nvim, yazi config copy) are unchanged.

On Linux the package manager is detected by capability, not distro name: `command -v apt-get`, else `command -v dnf`, else fail loudly. A `SUDO` variable is empty when running as root, `sudo` otherwise. A `pkg_install` helper wraps `apt-get install -y` / `dnf install -y`.

## Package tiers (Linux)

1. **Native packages**, one array per manager because names differ. Candidates: `tmux bash bat zoxide neovim fzf ripgrep jq imagemagick ghostscript mediainfo`, plus exiftool (`libimage-exiftool-perl` on apt, `perl-Image-ExifTool` on dnf). Check-then-install, same shape as `BREW_PACKAGES`.
2. **Per-tool fallback installers**, one commented block each, used when the native package is missing or too old:
   - official install scripts: `pnpm`, `just`, `kustomize`
   - GitHub release binaries: `yazi`, `resvg`, `ouch`, `kubectx`
   - `uv tool install`: `rich-cli`
   - `rtk`: arch-matched `.deb` (apt) or `.rpm` (dnf) from `rtk-ai/rtk` releases
   - `hunk`: Linux tarball from `modem-dev/hunk` releases into `~/.local/bin`
3. **Already portable**: `mise`, `uv`, `duckdb`, Claude Code, mnemo, auris.

Which packages land in tier 1 vs 2 is not known up front, especially on Amazon Linux (thin repos, no EPEL). The Docker run decides; a miss becomes a fallback entry.

Homebrew is not installed on Linux.

## macOS-only pieces

Wrapped in `OS == Darwin`, skipped on Linux: Xcode CLT check, Homebrew install and `BREW_PACKAGES`, terminal-notifier, Ghostty config copy, macFUSE check and its manual follow-up.

`tmux.conf` stays a single shared file. The `alert-bell` `terminal-notifier` hook is wrapped in tmux's `if-shell "uname | grep -q Darwin"`, so `setup.sh` keeps a plain `cp`.

`sshfs.yazi` on Linux needs only the `sshfs` package from apt/dnf, with no approval step.

The hunk skill symlink targets `/opt/homebrew/opt/hunk/...`; on Linux it points at wherever the tarball's `skills/` directory is installed.

## Test harness

```
test/
  Dockerfile.ubuntu        FROM ubuntu:24.04
  Dockerfile.amazonlinux   FROM amazonlinux:2023
  docker-test.sh           build both, run setup.sh in each, report pass/fail
```

Each image contains only what a fresh box has (plus `curl`, `git`, and `sudo` where missing). The repo is copied in and `setup.sh` runs as a non-root user with passwordless sudo, since that matches real usage and exercises the `SUDO` path. `docker-test.sh` accepts an optional target (`ubuntu`, `amazonlinux`) to run one.

Out of scope: interactive verification of tmux, yazi or nvim (needs a pty/expect harness), arm64 vs x86_64 matrix (fallbacks are arch-aware but only the host arch is tested), Amazon Linux 2.

## CI

`.github/workflows/setup-linux.yml` runs `test/docker-test.sh` for `ubuntu` and `amazonlinux` on `ubuntu-latest`. GitHub-hosted runners are x86_64, so CI exercises the x86_64 release assets, including resvg, that local Apple-silicon runs skip. It triggers on pushes to `main`, pull requests and manual dispatch, restricted to the files that affect the install (`setup.sh`, `tmux.conf`, `zshrc`, `init.lua`, `coc-settings.json`, `yazi/`, `test/` and the workflow itself).

`GITHUB_TOKEN` is forwarded into the container to avoid GitHub API rate limits. macOS is not covered in CI: `setup.sh` mutates the machine and needs Homebrew.

## Risks

- Network flakiness in the container run (mise, nvim PlugInstall, tpm all fetch from GitHub).
- Pinned-latest GitHub release URLs can change asset names; fallbacks should resolve the asset by pattern, not a hardcoded version.
- `setup.sh` has no `set -e`, so a failed install would otherwise scroll past. The Linux branch must exit non-zero when a required tool fails to install, or the Docker test can't detect it.

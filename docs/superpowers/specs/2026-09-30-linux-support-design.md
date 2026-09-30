# Linux support for setup.sh

## Goal

`setup.sh` provisions the same CLI/TUI environment on macOS, Ubuntu (apt) and Amazon Linux 2023 (dnf). Linux hosts are only reached over SSH, so anything that exists to serve a local GUI is out of scope there.

Success: on a clean `ubuntu:24.04` and a clean `amazonlinux:2023` container, `setup.sh` runs non-interactively, exits 0 and reaches the "Setup done" banner. The macOS path behaves exactly as before.

## Structure

One `setup.sh`. `OS="$(uname -s)"` near the top; sections that differ branch on it inline. OS-agnostic sections (oh-my-zsh, uv, Claude Code, mise runtimes, mnemo, auris, ssh key, allowed_signers, git, zsh managed block, nvim, yazi config copy) are unchanged.

On Linux the package manager is detected by capability, not distro name: `command -v apt-get`, else `command -v dnf`, else fail loudly. A `SUDO` variable is empty when running as root, `sudo` otherwise. A `pkg_install` helper wraps `apt-get install -y` / `dnf install -y`.

## Package tiers (Linux)

`~/.local/bin` is created and prepended to `PATH` at the start of the Linux section, so installed tools shadow distro ones.

1. **Native packages**, one array per manager because names differ: `tmux bash bat zoxide neovim fzf ripgrep jq imagemagick ghostscript mediainfo`, plus exiftool (`libimage-exiftool-perl` on apt, `perl-Image-ExifTool` on dnf) and `perl` on dnf. Check-then-install, same shape as `BREW_PACKAGES`.
2. **Per-tool fallback installers**, one block each, used when the native package is missing or too old. GitHub assets are resolved by name pattern against the latest release, never a pinned version:
   - official install scripts: `mise` (mise.run), `just`, `kustomize`
   - GitHub release binaries: `yazi`, `resvg` (x86_64 only, no aarch64 build exists so it is skipped there), `ouch`, `kubectx`
   - release tarballs into `~/.local/bin`: `rtk` (`rtk-ai/rtk`) and `hunk` (`modem-dev/hunk`, binary plus its `skills/` directory under `~/.local/share/hunk`). No `.deb`/`.rpm`.
   - `duckdb`: release `duckdb_cli-linux-<arch>.gz`
   - `pnpm`: `npm -g` under the mise-managed node
   - `rich-cli`: `uv tool install`
   - `nvim`: release tarball extracted to `~/.local/share/nvim-dist`, symlinked into `~/.local/bin`. Used when nvim is absent or older than 0.11 (Ubuntu 24.04 apt ships 0.9.5, which breaks nvim-lspconfig). An nvim that does not run counts as too old.
   - Amazon Linux 2023 also lacks `bat`, `zoxide`, `fzf`, `rg`, `mediainfo` and exiftool in dnf, so each has a fallback: release tarballs for bat, zoxide, fzf and rg; the MediaArea Lambda CLI zip for mediainfo (URL scraped from the download page, so fragile); the Image-ExifTool tag tarball for exiftool (verified with `exiftool -ver`).
3. **Shims**: Ubuntu ships `bat` as `batcat` and ImageMagick 6 without `magick`. `~/.local/bin/bat` symlinks to `batcat`, and `~/.local/bin/magick` is a wrapper that execs `convert`.
4. **Already portable**: `uv`, Claude Code, mnemo, auris.

mnemo, auris and exiftool release lookups send `Authorization: Bearer $GITHUB_TOKEN` when it is set.

Which packages land in tier 1 vs 2 was decided by the Docker runs. `setup.sh` ends the Linux section with a gate that exits non-zero listing any required tool that is still missing.

Homebrew is not installed on Linux.

## macOS-only pieces

Wrapped in `OS == Darwin`, skipped on Linux: Xcode CLT check, Homebrew install and `BREW_PACKAGES`, terminal-notifier, Ghostty config copy, macFUSE check and its manual follow-up.

`tmux.conf` stays a single shared file, so `setup.sh` keeps a plain `cp`. The `alert-bell` hook guards at runtime with `command -v terminal-notifier` (a no-op without it); the `pbcopy` copy-mode bindings sit in `if-shell 'command -v pbcopy'`; `extended-keys-format` uses `set -gq` because tmux 3.4 on Ubuntu rejects the option.

`init.lua` only calls `xcrun` for the lldb adapter when `vim.fn.executable('xcrun') == 1`.

The bash minimum is 5.2 on all platforms (was 5.3 on macOS).

`sshfs.yazi` on Linux needs only the `sshfs` package from apt/dnf, with no approval step.

`ya pkg install` aborts if a plugin was modified locally, and `setup.sh` patches `duckdb.yazi`. The yazi section therefore deletes `~/.config/yazi/plugins/duckdb.yazi` before installing, so it is re-fetched and re-patched on every run (this also fixed a second-run failure on macOS).

The hunk skill symlink targets `/opt/homebrew/opt/hunk/...`; on Linux it points at wherever the tarball's `skills/` directory is installed.

## Test harness

```
test/
  Dockerfile.ubuntu        FROM ubuntu:24.04
  Dockerfile.amazonlinux   FROM amazonlinux:2023
  verify-tools.sh          asserts the tools, yazi plugins, duckdb patch and tmux config
  docker-test.sh           build both, run setup.sh twice + verify-tools in each, report pass/fail
```

Each image contains only what a fresh box has (plus `curl`, `git`, and `sudo` where missing). The repo is copied in and `setup.sh` runs as a non-root user with passwordless sudo, since that matches real usage and exercises the `SUDO` path. `setup.sh` runs twice per container to prove idempotency, then `verify-tools.sh` runs. `docker-test.sh` accepts optional targets (`ubuntu`, `amazonlinux`) to run one. Env: `PLATFORM=linux/amd64` forces the CPU arch via emulation, `AS_ROOT=1` runs as root with the `sudo` binary renamed away (exercises `SUDO=""`), `GITHUB_TOKEN` is forwarded.

Out of scope: interactive verification of tmux, yazi or nvim (needs a pty/expect harness), an arm64 vs x86_64 matrix in the default run (fallbacks are arch-aware; `PLATFORM=linux/amd64` exercises x86_64 locally), Amazon Linux 2.

## CI

`.github/workflows/setup-linux.yml` runs `test/docker-test.sh` for `ubuntu` and `amazonlinux` on `ubuntu-latest`. GitHub-hosted runners are x86_64, so CI exercises the x86_64 release assets, including resvg, that local Apple-silicon runs skip. It triggers on pushes to `main`, pull requests and manual dispatch, restricted to the files that affect the install (`setup.sh`, `tmux.conf`, `zshrc`, `init.lua`, `coc-settings.json`, `gitconfig`, `gitignore_global`, `CLAUDE.md`, `ghostty_config`, `yazi/`, `test/` and the workflow itself).

`GITHUB_TOKEN` is forwarded into the container to avoid GitHub API rate limits. macOS is not covered in CI: `setup.sh` mutates the machine and needs Homebrew.

## Risks

- Network flakiness in the container run (mise, nvim PlugInstall, tpm all fetch from GitHub).
- Pinned-latest GitHub release URLs can change asset names; fallbacks should resolve the asset by pattern, not a hardcoded version.
- `setup.sh` has no `set -e`, so a failed install would otherwise scroll past. The Linux branch must exit non-zero when a required tool fails to install, or the Docker test can't detect it.

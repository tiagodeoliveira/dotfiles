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
         yazi ya ouch duckdb rich just kustomize kubectx kubens rtk hunk pnpm mise uv claude mnemo auris; do
  require "$t"
done

# present is not enough: a binary built against a newer glibc is on PATH but dies on start
runs_ok() {
  case "$1" in
    tmux) "$1" -V ;;
    unzip) "$1" -v ;;
    exiftool) "$1" -ver ;;
    mediainfo) "$1" --Version ;;
    kustomize) "$1" version ;;
    kubectx|kubens|auris) "$1" -h ;; # no version flag
    *) "$1" --version ;;
  esac &>/dev/null
}
for t in zsh tmux bat zoxide nvim fzf rg jq magick gs mediainfo exiftool patch file unzip \
         yazi ya ouch duckdb rich just kustomize kubectx kubens hunk pnpm mise uv claude mnemo auris; do
  if command -v "$t" &>/dev/null && ! runs_ok "$t"; then echo "DOES NOT RUN: $t"; failed=1; fi
done
# Prebuilt builds that need a newer glibc than the host has are optional; setup.sh skips them.
# optional_if_old_glibc <tool> <min glibc> <only on this arch, or empty for any>
optional_if_old_glibc() {
  if command -v "$1" &>/dev/null && runs_ok "$1"; then return 0; fi
  local glibc
  glibc="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$')"
  if [[ "$OS" == "Linux" && ( -z "$3" || "$ARCH" == "$3" ) && -n "$glibc" && "$(printf '%s\n%s\n' "$glibc" "$2" | sort -V | head -1)" != "$2" ]]; then
    echo "WARN: $1 does not run (glibc $glibc < $2); optional on this host"
  else
    echo "MISSING or DOES NOT RUN: $1"; failed=1
  fi
}
optional_if_old_glibc rtk 2.39 aarch64   # rtk's prebuilt aarch64 Linux build
# resvg publishes no aarch64 Linux build, and setup.sh removes it when it cannot run
if [[ "$OS" == "Darwin" || "$ARCH" == "x86_64" ]]; then optional_if_old_glibc resvg 2.35 ""; fi

# nvim-lspconfig needs Neovim >= 0.11
if command -v nvim &>/dev/null; then
  nv="$(nvim --version 2>/dev/null | head -1 | sed -E 's/^NVIM v?//')"
  nv_ok=0
  if [[ "$nv" =~ ^([0-9]+)\.([0-9]+) ]]; then
    if [[ ${BASH_REMATCH[1]} -gt 0 || ${BASH_REMATCH[2]} -ge 11 ]]; then nv_ok=1; fi
  fi
  [[ $nv_ok -eq 1 ]] || fail "nvim too old (<0.11) or unrunnable"
fi

# yazi config and plugins
# ya pkg install stops at the first error, so check every plugin, not just the last ones
[[ -f "$HOME/.config/yazi/plugins/zoom.yazi/main.lua" ]] || fail "zoom.yazi not installed"
while IFS= read -r spec; do
  name="${spec##*[/:]}"
  [[ -f "$HOME/.config/yazi/plugins/$name.yazi/main.lua" ]] || fail "yazi plugin $name ($spec) not installed"
done < <(sed -n 's/^use = "\(.*\)"$/\1/p' "$HOME/.config/yazi/package.toml")
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
if command -v tmux &>/dev/null; then
  [[ -f "$HOME/.tmux.conf" ]] || fail "tmux.conf not installed"
fi
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

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

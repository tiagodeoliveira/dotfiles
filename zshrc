export ZSH="$HOME/.oh-my-zsh"
export EDITOR="nvim"

ZSH_THEME="agnoster"
DEFAULT_USER="tiago"

setopt glob_dots null_glob
setopt extendedhistory
setopt extendedglob

plugins=(git brew history aws history-substring-search)

# both completion fpath entries land BEFORE oh-my-zsh sources, so its
# single compinit run picks them up (avoids a second redundant compinit)
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src
fpath+=(~/.docker/completions)
source "$ZSH/oh-my-zsh.sh"

# always hide user@host when on DEFAULT_USER (even over SSH/tmux)
prompt_context() {
  if [[ "$USERNAME" != "$DEFAULT_USER" ]]; then
    prompt_segment "$AGNOSTER_CONTEXT_BG" "$AGNOSTER_CONTEXT_FG" "%(!.%{%F{$AGNOSTER_STATUS_ROOT_FG}%}.)%n@%m"
  fi
}

# arrow-up/down substring-search through history
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

alias vim="nvim"
alias vimdiff="nvim -d"
alias cat="bat --paging=never -pp --style='plain' --theme=TwoDark"
alias la="ls -lAht"
alias psql="docker run -ti --rm alpine/psql"
tailf() { tail -f "$@" | bat --paging=never -l log --style='plain' --theme=TwoDark; }

# Inside tmux, set the pane title to the SSH host while ssh runs so the pane
# border shows the remote host instead of the local cwd basename.
ssh() {
  if [[ -n "$TMUX" ]]; then
    local host="${@: -1}"
    host="${host#*@}"
    tmux select-pane -T "$host"
    command ssh "$@"
    tmux select-pane -T ""
  else
    command ssh "$@"
  fi
}

export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"

# put brew on PATH (Apple Silicon: /opt/homebrew; Intel: /usr/local)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

[[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"
command -v mise   &>/dev/null && eval "$(mise activate zsh)"

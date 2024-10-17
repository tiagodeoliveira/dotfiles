export PATH=$PATH:/Users/tiagode/.toolbox/bin:/Users/tiagode/go/bin:/Users/tiagode/android_sdk/cmdline-tools/latest/bin:/Users/tiagode/android_sdk/platform-tools:/Users/tiagode/miniconda3/bin
export GOPROXY=direct
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="agnoster"
DEFAULT_USER="tiagode"

export AWS_PAGER=""

setopt glob_dots null_glob
setopt extendedhistory
setopt extendedglob

plugins=(
    git
    vscode
    brew
    history
    rust
    aws
    history-substring-search
)

source $ZSH/oh-my-zsh.sh

command_not_found_handler() {
    RED='\033[0;31m'
    NC='\033[0m'
    if [ ${#1} -eq 44 ]; then
      printf "zsh: ${RED}This is a yubikey token!${NC}"
    else
      printf "zsh: ${RED}command not found: $@${NC}"
    fi
    return 127
}

source /Users/tiagode/.brazil_completion/zsh_completion

export GPG_TTY="$(tty)"
export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
gpgconf --launch gpg-agent

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
eval "$(/opt/homebrew/bin/brew shellenv)"
# Set up mise for runtime management
eval "$(mise activate zsh)"

alias vim="nvim"
alias vimdiff='nvim -d'
alias cat="bat --paging=never -pp --style='plain' --theme=TwoDark $*"
alias la="ls -lAht"

. "$HOME/.cargo/env"

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# pnpm
export PNPM_HOME="/Users/tiagode/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

[ -f "/Users/tiagode/.ghcup/env" ] && . "/Users/tiagode/.ghcup/env" # ghcup-env

s3_bucket_delete() {
  aws s3 rb --force s3://$1
}

# Created by `pipx` on 2024-05-28 18:38:33
export PATH="$PATH:/Users/tiagode/.local/bin"





# plugins
plugins=(git ssh-agent asdf kubectl)

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# zsh install directory
export ZSH="$HOME/.oh-my-zsh"

# theme
ZSH_THEME="powerlevel10k/powerlevel10k"

# Ohmyzsh auto update
zstyle ':omz:update' mode auto      # update automatically without asking

# show waiting dots on long running commands
# COMPLETION_WAITING_DOTS="true"

# load ohmyzsh
source $ZSH/oh-my-zsh.sh

# make vim the default editor
export EDITOR='nvim'
alias vim="nvim"
alias n="nvim"
alias nd='NVIM_APPNAME="nvim-kickstart" nvim'
alias vim='NVIM_APPNAME="kvim" nvim'
alias df="yadm"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

. "$HOME/.local/bin/env"

# Powerlevel10k Instant Prompt
[[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]] && source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)
source $ZSH/oh-my-zsh.sh

# Plugin loader (fallback in case Oh My Zsh paths break)
[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Powerlevel10k config
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# Aliases
alias myaliases="grep -E '^alias' ~/.config/zsh/aliases.zsh | cut -d'#' -f1"

# System Info
command -v fastfetch >/dev/null && fastfetch

# Banner
echo -e "\033[1;36mWelcome back, Josh 👨🏽‍💻 | KeepItTechie is live 🚀\033[0m"

# Display the current date and time in prompt
# export PROMPT='%F{green}%D{%a %b %d %I:%M%p}%f %F{blue}%~%f %# '

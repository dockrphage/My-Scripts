#!/usr/bin/env bash
# install-devops-autocomplete.sh
# Adds autocompletion for kubectl, helm, docker, terraform, aws cli, and git to ~/.bashrc, along with useful aliases.   
set -euo pipefail

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
NC="\e[0m"

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

BASHRC="$HOME/.bashrc"
BLOCK_TAG="### --- DevOps Autocompletion Block --- ###"

# Ensure .bashrc exists
if [ ! -f "$BASHRC" ]; then
  warn "~/.bashrc not found. Creating it..."
  touch "$BASHRC"
fi

# Backup
BACKUP="$BASHRC.backup.$(date +%s)"
cp "$BASHRC" "$BACKUP"
log "Backup created at: $BACKUP"

# Check if block already exists
if grep -q "$BLOCK_TAG" "$BASHRC"; then
  warn "DevOps Autocompletion Block already exists in ~/.bashrc. Skipping insertion."
  exit 0
fi

log "Appending DevOps Autocompletion Block to ~/.bashrc..."

cat <<'EOF' >> "$BASHRC"

### --- DevOps Autocompletion Block --- ###

# Bash completion framework
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi

# kubectl + alias k
if command -v kubectl >/dev/null 2>&1; then
    source <(kubectl completion bash)
    alias k=kubectl
    complete -F __start_kubectl k
fi

# helm
if command -v helm >/dev/null 2>&1; then
    source <(helm completion bash)
fi

# docker
if command -v docker >/dev/null 2>&1; then
    source <(docker completion bash)
fi

# terraform + aliases
if command -v terraform >/dev/null 2>&1; then
    complete -C terraform terraform

    alias tfa='terraform apply --auto-approve'
    alias tfd='terraform destroy --auto-approve'
    alias tfp='terraform plan'
    alias tfi='terraform init'
    alias tfv='terraform validate'
    alias tfs='terraform show'
fi

# aws cli
if command -v aws_completer >/dev/null 2>&1; then
    complete -C "$(command -v aws_completer)" aws
fi

# alacritty (system-wide completion)
if [ -f /usr/share/bash-completion/completions/alacritty ]; then
    source /usr/share/bash-completion/completions/alacritty
fi

# cargo / rust
if [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi

# git autocompletion + aliases
if command -v git >/dev/null 2>&1; then
    if [ -f /usr/share/bash-completion/completions/git ]; then
        source /usr/share/bash-completion/completions/git
    fi

    alias ga='git add'
    alias gaa='git add --all'
    alias gb='git branch'
    alias gco='git checkout'
    alias gcb='git checkout -b'
    alias gd='git diff'
    alias gds='git diff --staged'
    alias gl='git pull'
    alias gp='git push'
    alias gpl='git pull --rebase'
    alias gst='git status -sb'
    alias gc='git commit'
    alias gcm='git commit -m'
    alias gca='git commit --amend --no-edit'
    alias gcl='git clone'
    alias glg='git log --oneline --graph --decorate'
fi

### --- End DevOps Autocompletion Block --- ###

EOF

log "DevOps Autocompletion Block added successfully."
log "Reload your shell with:  source ~/.bashrc"

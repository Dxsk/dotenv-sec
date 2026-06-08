# dotenv-sec: Pentest Environment Bootstrap
#
# Source this in ~/.zshrc:
#   export DOTSEC_HOME="$HOME/Documents/github.com/Dxsk/dotenv-sec"
#   export PATH="$DOTSEC_HOME/bin:$PATH"
#   eval "$(dotsec completions zsh 2>/dev/null || true)"
#
# ── Shell integration ────────────────────────────────────
# Auto-load engagement when entering workspace directory
# (uncomment to enable)
#
# chpwd_dotsec() {
#   if [[ "$PWD" =~ ^/workspace/([^/]+) ]]; then
#     dotsec load "${match[1]}" >/dev/null 2>&1
#   fi
# }
# autoload -U add-zsh-hook && add-zsh-hook chpwd chpwd_dotsec

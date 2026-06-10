# dotenv-sec: Pentest Environment Bootstrap
#
# Source this in ~/.zshrc:
#   export DOTSEC_HOME="$HOME/Documents/github.com/Dxsk/dotenv-sec"
#   export PATH="$DOTSEC_HOME/bin:$PATH"
#   eval "$(dotsec completions zsh 2>/dev/null || true)"
#
# ── dotsec shell function ────────────────────────────────
# `load`/`unload` must run in the current shell (a binary can't export into the
# parent shell). Everything else delegates to the dotsec binary.
dotsec() {
  case "$1" in
    load)
      shift
      if source <(command dotsec env "$@" 2>/dev/null); then
        print -P "  %F{green}${TARGET}%f → ${WORKSPACE}  proxy:%F{yellow}${HTTP_PROXY}%f"
      else
        command dotsec env "$@" >/dev/null
      fi
      ;;
    unload)
      unset TARGET DOMAIN IP UA PROGRAM PROXY_PORT WEB_PORT \
            HTTP_PROXY HTTPS_PROXY NO_PROXY WORKSPACE \
            DOTSEC_SESSION_SECRET DOTSEC_API_TOKEN MITMWEB_PASS 2>/dev/null
      print "  engagement vars unset"
      ;;
    *)
      command dotsec "$@"
      ;;
  esac
}

# ── Shell integration ────────────────────────────────────
# Auto-load engagement when entering workspace directory
chpwd_dotsec() {
  if [[ "$PWD" =~ ^${WORKSPACE_ROOT:-/workspace}/([^/]+) ]]; then
    dotsec load "${match[1]}" >/dev/null 2>&1
  fi
}
autoload -U add-zsh-hook && add-zsh-hook chpwd chpwd_dotsec

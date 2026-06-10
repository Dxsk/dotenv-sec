#!/usr/bin/env bash
# ─── lib/ui.sh ─── colors and usage ──
# Colors are consumed across the other sourced libs, so shellcheck (which lints
# each file in isolation) flags them as unused. They are not.
# shellcheck disable=SC2034

# ── Colors ──────────────────────────────────────────────
BOLD=$'\033[1m'; DIM=$'\033[2m'
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
BLUE=$'\033[34m'; MAGENTA=$'\033[35m'; CYAN=$'\033[36m'
RESET=$'\033[0m'

# ── Help ────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}${GREEN}dotsec${RESET} ${DIM}v${VERSION}${RESET} — ${DIM}Pentest environment launcher${RESET}

${BOLD}USAGE${RESET}
  ${GREEN}dotsec${RESET} ${DIM}<command> [args]${RESET}

${BOLD}${CYAN}ENGAGEMENT${RESET}
  ${GREEN}new${RESET}      ${DIM}[-w <path>] <target> [domain]${RESET}    Init workspace + proxy + exegol + tmux
  ${GREEN}load${RESET}     ${DIM}<target>${RESET}             Source .env.engagement
  ${GREEN}unload${RESET}                         Unset engagement vars
  ${GREEN}list${RESET}                           List all engagements

${BOLD}${YELLOW}PROXY & BROWSER${RESET}
  ${GREEN}proxy${RESET}    ${DIM}up|down|status|logs${RESET}  Manage mitmproxy container
  ${GREEN}browser${RESET}  ${DIM}[target]${RESET}             Launch Chromium routed through proxy

${BOLD}${MAGENTA}DASHBOARD${RESET}
  ${GREEN}board${RESET}    ${DIM}up|down|reload|status${RESET}  Homer dashboard ${DIM}(127.0.0.1:9997)${RESET}

${BOLD}${YELLOW}SECRETS${RESET}
  ${GREEN}secrets${RESET}  ${DIM}[target]${RESET}            Show masked secret status
  ${GREEN}rotate${RESET}   ${DIM}[target] [type]${RESET}     Regenerate (all|token|mitmweb|ssh|ca)

${BOLD}${BLUE}WORKSPACE${RESET}
  ${GREEN}spawn${RESET}    ${DIM}[session]${RESET}             Spawn 6-window tmux in Exegol + attach
  ${GREEN}tmux${RESET}     ${DIM}attach|create|kill|ls${RESET}  tmux sessions inside Exegol
  ${GREEN}log${RESET}      ${DIM}<cmd...>${RESET}             Run + log to commands.log
  ${GREEN}archive${RESET}  ${DIM}[target]${RESET}           Archive workspace to tar.gz
  ${GREEN}stop${RESET}     ${DIM}<target>${RESET}             Stop proxy + tmux for engagement
  ${GREEN}restart${RESET}  ${DIM}<target>${RESET}             Restart proxy + exegol + tmux

${BOLD}${MAGENTA}EXEGOL${RESET}
  ${GREEN}exegol${RESET}   ${DIM}exec|shell|setup${RESET}     Run commands inside Exegol

${BOLD}${CYAN}INFO${RESET}
  ${GREEN}status${RESET}   ${DIM}[target]${RESET}            Overview: engagements, proxy/tmux, stats
  ${GREEN}info${RESET}                           Show current engagement
  ${GREEN}help${RESET}                           This message

${BOLD}QUICKSTART${RESET}
  ${GREEN}dotsec${RESET} new mytarget example.com
  ${GREEN}dotsec${RESET} spawn       ${DIM}# or: dotsec tmux attach${RESET}
  ${GREEN}dotsec${RESET} browser

${BOLD}CONFIG${RESET}
  ${DIM}DOTSEC_HOME${RESET} = ${DOTSEC_HOME}
EOF
    exit 0
}

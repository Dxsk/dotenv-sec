# dotenv-sec

[![CI](https://img.shields.io/github/actions/workflow/status/Dxsk/dotenv-sec/ci.yml?branch=main&style=flat-square&label=CI&logo=github)](https://github.com/Dxsk/dotenv-sec/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/Dxsk/dotenv-sec?style=flat-square&color=2EA043)](LICENSE)
[![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com/)
[![Built for Exegol](https://img.shields.io/badge/Built_for-Exegol-FF6B35?style=flat-square)](https://exegol.com/)
[![Security: Trivy](https://img.shields.io/badge/Security-Trivy-1904DA?style=flat-square&logo=aquasec&logoColor=white)](https://trivy.dev/)

**Pentest environment launcher**: one CLI to spawn your entire offensive security workspace:

- tmux sessions
- MITM proxy
- isolated Chromium
- Exegol integration
- a wired recon → scan → audit pipeline

## Architecture

```
dotsec new acme-corp example.com
         │
         ├─► /workspace/acme-corp/   ← full engagement tree
         │       └─ .env              ← per-engagement vars
         │
         ├─► tmux session "acme-corp" ← 6 windows (recon→monitor)
         │
         ├─► mitmproxy container      ← proxy:9999 + webUI:9998
         │       └─► chromium container ← routed through proxy
         │
         └─► homer dashboard          ← all services at a glance (port 9997)
```

## Quickstart

```bash
# Install
make install

# New engagement: workspace + proxy + Exegol + tmux + proxied browser
dotsec new acme-corp example.com

# Source the engagement env into your current shell
dotsec load acme-corp

# Optional: dashboard, then attach the tmux session
dotsec board up
dotsec tmux attach acme-corp
```

## Commands

| Command | Description |
|---------|-------------|
| `dotsec new [-w <path>] <target> [domain]` | Init workspace + proxy + Exegol + tmux |
| `dotsec load <target>` | Source engagement environment variables |
| `dotsec unload` | Unset all engagement vars |
| `dotsec list` | List all engagements under `/workspace/` |
| `dotsec spawn [session]` | Spawn 6-window pentest tmux in Exegol + attach |
| `dotsec proxy up\|down\|status\|logs` | Manage mitmproxy Docker container |
| `dotsec browser [target]` | Launch Chromium routed through proxy |
| `dotsec listener up\|down\|logs\|status` | OOB HTTP callback server + ssh tunnel |
| `dotsec board up\|down\|reload\|status` | Homer dashboard at http://127.0.0.1:9997 |
| `dotsec secrets [target]` | Show masked secret status for an engagement |
| `dotsec rotate [target] [type]` | Regenerate secrets (all\|token\|mitmweb\|ssh\|ca) |
| `dotsec tmux attach\|create\|kill\|ls` | tmux sessions inside Exegol |
| `dotsec log <cmd...>` | Run command and log to `commands.log` |
| `dotsec archive [target]` | Archive workspace to tar.gz |
| `dotsec rm <target> [--archive]` | Remove engagement (containers + workspace) |
| `dotsec stop <target>` | Stop proxy + tmux for the engagement |
| `dotsec restart <target>` | Restart proxy + Exegol + tmux |
| `dotsec exegol exec\|shell\|setup` | Run commands / provision tooling inside Exegol |
| `dotsec status [target]` | Overview: engagements, proxy/tmux, stats |
| `dotsec info` | Show current engagement + global config status |

## Configuration

### Global defaults: `~/.config/dotenvsec/config`

```bash
export EXEGOL_CONTAINER="exegol"  # default Exegol container
export UA="H1-yourhandle"         # default User-Agent
export PROXY_PORT="9999"
export WEB_PORT="9998"
export HOMER_PORT="9997"
export PLATFORM="h1"              # h1 | ywh | inti | custom
```

### Per-engagement: `/workspace/$TARGET/.env`

```bash
export TARGET="acme-corp"
export DOMAIN="acme-corp.com"
export UA="H1-myhandle"
export HTTP_PROXY="http://127.0.0.1:9999"
export EXEGOL_CONTAINER="exegol"
```

## Secrets

Each `dotsec new` generates per-engagement secrets (idempotent, never committed) into the workspace:

- `.env.secrets` (chmod 600): `DOTSEC_SESSION_SECRET`, `DOTSEC_API_TOKEN`, `MITMWEB_PASS`
- `keys/id_ed25519`: ephemeral Ed25519 SSH key (600), `keys/id_ed25519.pub` (644)
- CA certificate: generated on first `proxy up` into `proxy/certs/`

```bash
dotsec secrets acme-corp          # show masked status (never prints values)
dotsec rotate acme-corp           # regenerate all secrets (prompts for ssh/ca/all)
dotsec rotate acme-corp token     # rotate tokens only (no prompt)
dotsec rotate acme-corp mitmweb   # rotate proxy password only (no prompt)
```

## MITM Proxy

```bash
dotsec proxy up          # start mitmproxy container
# → Proxy  : http://127.0.0.1:9999
# → Web UI : http://127.0.0.1:9998
# → CA PEM : /workspace/$TARGET/proxy/certs/mitmproxy-ca-cert.pem

dotsec proxy status      # check container
dotsec proxy logs        # tail container logs
dotsec proxy down        # stop container
```

### Browser integration

Install the CA certificate in your browser once, then:

```bash
dotsec browser           # Chromium auto-routed through proxy
```

Or configure any browser to use `http://127.0.0.1:9999` as HTTP/HTTPS proxy.

## Exegol integration

```bash
dotsec exegol shell                  # open shell in Exegol
dotsec exegol exec nmap -sV target   # run command inside Exegol
dotsec exegol exec "sqlmap -u ..."   # quoted multi-word commands
dotsec exegol setup                  # install uv + pnpm inside Exegol
```

### Exegol tool provisioning

The project ships a `my-resources` bundle deployed (merged) to `~/.exegol/my-resources/`
via `make exegol-setup` (also run by `make install`).

The bundle includes:
- **recon** scripts: `recon-subs`, `recon-alive`, `recon-fingerprint`, `recon-portscan`, `recon-screenshot`, `recon-crawl`, `recon-urls`, `recon-loot`, `recon-extract`, `recon-sourcemaps`, `recon-full`, `dl`
- **scan** scripts: `scan-nuclei` (vuln scan), `scan-takeover` (dangling CNAME; subzy → nuclei fallback)
- **audit** scripts: `audit-code` (trufflehog + gitleaks + semgrep + osv-scanner over the `code/` zone)
- Shell aliases and preloaded history
- `load_user_setup.sh`: idempotent installer for the tools the scripts need that the base image lacks (xnLinkFinder, waymore, sourcemapper, osv-scanner, …)

```bash
make exegol-setup   # deploy/merge bundle to ~/.exegol/my-resources/
```

Scripts run **inside** the Exegol container, driven by engagement env vars (`$DOMAIN`, `$WORKSPACE`).
Typical flow in a loaded engagement window:

```bash
recon-full       # discovery → portscan → screenshots → crawl → loot → JS extract
scan-nuclei      # vulnerability scan of the alive hosts (routed through the proxy)
scan-takeover    # subdomain takeover check
audit-code       # white-box audit of recovered source / sourcemaps
```

On first container start, Exegol auto-runs `/opt/my-resources/setup/load_user_setup.sh`.
To trigger it manually (also installs missing tooling):

```bash
dotsec exegol setup
```

## OOB Listener

Out-of-band HTTP callback server (SSRF/XXE/SSTI blind) in a container, exposed
publicly through an auth-less `ssh -R` tunnel (localhost.run). HTTP only.

```bash
dotsec listener up              # container + public URL (in workspace/oob/url.txt)
dotsec listener up --no-tunnel  # local only (127.0.0.1:9996), expose it yourself
dotsec listener logs            # tail captured hits (workspace/oob/hits.log)
dotsec listener status          # container + public URL
dotsec listener down            # stop container + kill tunnel
```

Every hit is logged with timestamp, source IP, method, path, headers and body.

## Docker Security

- Base images pinned by `@sha256` digest
- Containers run as root today (non-root hardening tracked separately); all service ports are >1024 (rootless-Docker friendly)
- CI pipeline runs Trivy vulnerability scans on every push
- Scheduled scan every Monday + automatic CVE issue creation

## Makefile

| Target | Description |
|--------|-------------|
| `make install` | Full setup: symlinks + config + shell integration + build images |
| `make build` | Build all Docker images |
| `make scan` | Run Trivy vulnerability scanner on all images |
| `make test` | Run bats tests |
| `make lint` | Run shellcheck on all bash |
| `make smoke` | Docker integration smoke (requires `make build`) |
| `make update` | Git pull + rebuild images |
| `make clean` | Stop and remove all mitmproxy containers |
| `make uninstall` | Remove symlinks and config |

## Install

Requires: `zsh`, `docker`, `tmux`, optionally `trivy`.

```bash
git clone git@github.com:Dxsk/dotenv-sec.git
cd dotenv-sec
make install
source ~/.zshrc
```

## Development

```bash
pre-commit install   # runs shellcheck + bats on every commit
make test            # bats test suite
make lint            # shellcheck all bash
make smoke           # Docker integration smoke (requires make build)
```

## Contributing

Issues and pull requests are welcome.

- **Feature / tool request**: [open an issue](https://github.com/Dxsk/dotenv-sec/issues/new?labels=enhancement) describing the tool or stage you'd like wired into the pipeline.
- **Bug report**: [open an issue](https://github.com/Dxsk/dotenv-sec/issues/new?labels=bug) with your Exegol image, the exact command, and the output.
- **Question / anything else**: [open an issue](https://github.com/Dxsk/dotenv-sec/issues/new?labels=question).

For code: fork, branch (`feat/…` or `fix/…`), keep it shellcheck-clean with tests green (see [Development](#development)), then open a PR.

## License

MIT: see [LICENSE](LICENSE).

## Support

If `dotsec` saves you time on engagements, you can support the work:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy_Me_A_Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/dxsk)

# dotenv-sec

**Pentest environment launcher**: one CLI to spawn your entire offensive security workspace: tmux sessions, MITM proxy, isolated Chromium, and Exegol integration.

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

# New engagement
dotsec new acme-corp example.com
dotsec load acme-corp

# Start dashboard + proxy + spawn tmux
dotsec board up
dotsec proxy up
dotsec spawn
```

## Commands

| Command | Description |
|---------|-------------|
| `dotsec new <target> [domain]` | Create engagement workspace, tmux session, .env |
| `dotsec load <target>` | Source engagement environment variables |
| `dotsec unload` | Unset all engagement vars |
| `dotsec list` | List all engagements under `/workspace/` |
| `dotsec spawn [session]` | Instant 6-window pentest tmux session |
| `dotsec proxy up\|down\|status\|logs` | Manage mitmproxy Docker container |
| `dotsec browser [target]` | Launch Chromium routed through proxy |
| `dotsec board up\|down\|reload\|status` | Homer dashboard at http://127.0.0.1:9997 |
| `dotsec exegol exec\|shell` | Execute commands inside Exegol container |
| `dotsec exegol setup` | Install uv + pnpm inside Exegol container |
| `dotsec tmux attach\|create\|kill\|ls` | tmux session management |
| `dotsec log <cmd...>` | Run command and log to `commands.log` |
| `dotsec secrets <target>` | Show masked secret status for an engagement |
| `dotsec rotate <target> [type]` | Regenerate engagement secrets (all\|token\|mitmweb\|ssh\|ca) |
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

Each `dotsec new` generates per-engagement secrets — idempotent, never committed — into the workspace:

- `.env.secrets` (chmod 600): `DOTSEC_SESSION_SECRET`, `DOTSEC_API_TOKEN`, `MITMWEB_PASS`
- `keys/id_ed25519` — ephemeral Ed25519 SSH key (600), `keys/id_ed25519.pub` (644)
- CA certificate — generated on first `proxy up` into `proxy/certs/`

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
- **bin/** scripts: `recon-subs`, `recon-alive`, `recon-crawl`, `recon-loot`, `recon-sourcemaps`, `recon-full`, `dl`
- Shell aliases and preloaded history

```bash
make exegol-setup   # deploy/merge bundle to ~/.exegol/my-resources/
```

Scripts run **inside** the Exegol container, driven by engagement env vars (`$DOMAIN`, `$WORKSPACE`).
Example in a loaded engagement window:

```bash
recon-full
```

On first container start, Exegol auto-runs `/opt/my-resources/setup/load_user_setup.sh`.
To trigger it manually:

```bash
dotsec exegol setup
```

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

## License

MIT: see [LICENSE](LICENSE).

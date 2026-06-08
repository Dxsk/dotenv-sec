# dotenv-sec

**Pentest environment launcher** — one CLI to spawn your entire offensive security workspace: tmux sessions, MITM proxy, isolated Chromium, and Exegol integration.

## Architecture

```
dotsec new acme-corp example.com
         │
         ├─► /workspace/acme-corp/   ← full engagement tree
         │       └─ .env              ← per-engagement vars
         │
         ├─► tmux session "acme-corp" ← 6 windows (recon→monitor)
         │
         └─► mitmproxy container      ← proxy + web UI
                 └─► chromium container ← routed through proxy
```

## Quickstart

```bash
# Install
make install

# New engagement
dotsec new acme-corp example.com
dotsec load acme-corp

# Spawn tmux + start proxy + launch browser
dotsec spawn
dotsec proxy up
dotsec browser
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
| `dotsec exegol exec\|shell` | Execute commands inside Exegol container |
| `dotsec tmux attach\|create\|kill\|ls` | tmux session management |
| `dotsec log <cmd...>` | Run command and log to `commands.log` |
| `dotsec info` | Show current engagement + global config status |

## Configuration

### Global defaults: `~/.config/dotenvsec/config`

```bash
export EXEGOL_CONTAINER="exegol"  # default Exegol container
export UA="H1-yourhandle"         # default User-Agent
export PROXY_PORT="8080"
export WEB_PORT="8081"
export PLATFORM="h1"              # h1 | ywh | inti | custom
```

### Per-engagement: `/workspace/$TARGET/.env`

```bash
export TARGET="acme-corp"
export DOMAIN="acme-corp.com"
export UA="H1-myhandle"
export HTTP_PROXY="http://127.0.0.1:8080"
export EXEGOL_CONTAINER="exegol"
```

## MITM Proxy

```bash
dotsec proxy up          # start mitmproxy container
# → Proxy  : http://127.0.0.1:8080
# → Web UI : http://127.0.0.1:8081
# → CA PEM : /workspace/$TARGET/proxy/certs/mitmproxy-ca.pem

dotsec proxy status      # check container
dotsec proxy logs        # tail container logs
dotsec proxy down        # stop container
```

### Browser integration

Install the CA certificate in your browser once, then:

```bash
dotsec browser           # Chromium auto-routed through proxy
```

Or configure any browser to use `http://127.0.0.1:8080` as HTTP/HTTPS proxy.

## Exegol integration

```bash
dotsec exegol shell                  # open shell in Exegol
dotsec exegol exec nmap -sV target   # run command inside Exegol
dotsec exegol exec "sqlmap -u ..."   # quoted multi-word commands
```

## Docker Security

- Base images pinned with `@sha256` digests
- All packages pinned to exact versions
- Non-root users inside containers
- Ports > 1024 (rootless Docker compatible)
- CI pipeline runs Trivy vulnerability scans on every push
- Scheduled scan every Monday + automatic CVE issue creation

## Makefile

| Target | Description |
|--------|-------------|
| `make install` | Full setup: symlinks + config + shell integration + build images |
| `make build` | Build all Docker images |
| `make scan` | Run Trivy vulnerability scanner on all images |
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

## License

MIT — see [LICENSE](LICENSE).

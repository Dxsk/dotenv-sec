# Code audit suite (`audit-*`) — design

Date: 2026-06-12
Status: design approved (brainstorm), pending implementation plan.

## Goal

Automated, CLI/scriptable white-box source-code audit helpers over the engagement
`code/` zone (recovered sources, leaks, `.git` dumps, repos, white-box assignments
such as the e-voting case). Two consumers:

1. **Operator**: a ranked hotspots report.
2. **AI**: every tool emits structured, machine-readable logs an AI can read to
   accelerate the deep analysis afterward.

Polyglot and language-adaptive: it works on whatever source lands in `code/`,
front-end or back-end, no language assumption.

## Non-goals

- **No magic business-logic bug detection.** Logic flaws require human/AI reasoning.
  The suite only surfaces the *structure* (entry points, sinks, authz candidates)
  to reason over. It accelerates the analysis; it does not find the logic bug.
- **No AI-specific packaging** (no repomix/code2prompt). AI-readability is a
  cross-cutting property: structured `*.json` + a `*.txt`/`*.md` summary per tool.

## Components

Composable bash scripts in `exegol/my-resources/bin/`, run **inside Exegol**,
env-driven (`$WORKSPACE`), writing to `$WORKSPACE/scans/code/`. Each emits
`<name>.json` (machine) + a `<name>.txt`/`.md` summary (human). All best-effort:
a missing engine degrades and is logged, never aborts.

### 1. `audit-sinks` — dangerous functions / sinks
- **semgrep**: `--config p/security-audit --config p/owasp-top-ten` (taint rules
  included), `--json`. The primary, polyglot sink engine.
- **ast-grep**: a bundled polyglot ruleset of high-signal dangerous patterns
  (`eval`/`exec`/deserialize/`innerHTML`/`dangerouslySetInnerHTML`/SQL concat/
  `system`/command exec, ...). **Invoke as `ast-grep`** — `/usr/bin/sg` is the
  unrelated setgid tool, never call `sg`.
- **weggli** (optional, C/C++): semantic patterns (`strcpy`/`memcpy`/`system`/
  `sprintf`/format strings). Text output (weggli has no JSON); folded into the txt.
- Output: `sinks.json` (semgrep + ast-grep merged) + `sinks.txt`.

### 2. `audit-endpoints` — attack surface
- **Backend routes**: ast-grep ruleset per framework (express, flask/fastapi,
  spring, rails, go `http.HandleFunc`, php routers).
- **Frontend**: `xnLinkFinder` on `.js` + URL / `fetch` / `axios` / XHR literals.
- Output: `endpoints.json` (`[{kind, method, path, file, line}]`) + `endpoints.txt`.

### 3. `audit-code` (existing, kept) — secrets + SAST baseline + SCA
trufflehog + gitleaks + semgrep (`auto`) + osv-scanner. Already JSON. Unchanged.

### 4. `audit-hotspots` — aggregator / ranker
- `python3` (stdlib only, type-hinted, docstring'd). Reads every
  `scans/code/*.json`, ranks candidates by signal (semgrep severity, verified
  secrets, endpoint-without-nearby-auth heuristic, sink class), emits
  `hotspots.json` (sorted) + `hotspots.md` (grouped table; operator entry point
  and AI summary in one).
- Excluded from shellcheck (it is python, not bash) via pre-commit `exclude`.

### 5. `audit-full` — orchestrator
Runs 1 → 4 best-effort (trivial glue).

## Data flow

```
code/ ──► audit-sinks      ─┐
      ──► audit-endpoints  ─┤──► scans/code/*.json ──► audit-hotspots ──► scans/code/hotspots.{json,md}
      ──► audit-code       ─┘
```

## Install (`load_user_setup`, idempotent best-effort)

- **ast-grep**: `npm install -g @ast-grep/cli` (binary `ast-grep`).
- **weggli**: `cargo install weggli --locked` (C/C++; slow, best-effort).
- semgrep / trufflehog / gitleaks / osv-scanner / xnLinkFinder / python3 / jq are
  already provisioned (base image or earlier installer work).

## Bundled assets

`exegol/my-resources/audit-rules/` — ast-grep `sgconfig.yml` + rule files
(`sinks/`, `endpoints/`). `deploy.sh` copies the directory to
`~/.exegol/my-resources/audit-rules/` (→ `/opt/my-resources/audit-rules/`).
Scripts reference `${MYRES:-/opt/my-resources}/audit-rules`.

## Integration

- `deploy.sh`: the `audit-*` bin glob (PR #16) already covers the new scripts;
  add a copy step for `audit-rules/`.
- `aliases.dotsec` / `history.dotsec`: add `audit-sinks`, `audit-endpoints`,
  `audit-hotspots`, `audit-full`.
- Engagement tree: `scans/code/` already exists (PR #16).
- Lint: `.pre-commit-config.yaml` + `make lint` exclude `audit-hotspots` from
  shellcheck (python).

## Testing

- **bats**: a fixture dir with a known sink (`eval(userInput)`) and a known route
  (`app.get('/x', ...)`); assert `audit-sinks` flags the `eval` and
  `audit-endpoints` lists `/x`. `bash -n` + shellcheck on all bash scripts.
- **audit-hotspots**: python smoke over sample JSON inputs (deterministic ranking).

## Honest limits

- ast-grep / semgrep custom rules are starter sets, not exhaustive; false negatives
  expected. The covered rule scope is logged, not silently truncated.
- weggli is C/C++ only; skipped elsewhere.
- "authz / IDOR candidate" detection is heuristic (endpoint with no nearby auth
  guard; object access by id with no owner check). These are leads, not findings.

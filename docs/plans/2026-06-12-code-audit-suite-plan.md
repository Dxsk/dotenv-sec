# Code Audit Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a composable white-box code-audit suite (`audit-sinks`, `audit-endpoints`, `audit-hotspots`, `audit-full`) over the engagement `code/` zone, emitting AI-readable structured artifacts plus a ranked hotspots report.

**Architecture:** Bash orchestrator scripts run inside Exegol, env-driven (`$WORKSPACE`), writing `*.json` + summaries to `$WORKSPACE/scans/code/`. semgrep is the confident primary engine; ast-grep / weggli / xnLinkFinder are guarded best-effort enhancers. `audit-hotspots` is a pure-python aggregator (host-unit-testable). Bundled semgrep/ast-grep rules ship in `exegol/my-resources/audit-rules/`.

**Tech Stack:** bash (shellcheck-clean), python3 (stdlib only), semgrep, ast-grep, weggli, xnLinkFinder, bats + stubs.

---

## Conventions (read once)

- New bash scripts go in `exegol/my-resources/bin/`, mode `0755`, `#!/usr/bin/env bash`, `set -euo pipefail`, the standard DOMAIN/dir guards. They must be shellcheck-clean (`shellcheck -x`), now enforced by pre-commit (`exegol/my-resources/bin/[^/]+`).
- `audit-hotspots` is python3 and MUST be excluded from shellcheck.
- Tools live in the Exegol container, not the host. Real-detection tests run in the container (`docker exec exegol-e-voting ...`); host bats tests use stubs in `tests/stubs/`.
- Output dir is always `$WORKSPACE/scans/code/` (created by `dotsec new`, PR #16).
- Commit messages: English, Conventional Commits, no `Co-Authored-By`. Stage explicit paths (`git commit -m "..." -- path`).
- The running container for live checks is `exegol-e-voting`.

## File Structure

| File | Responsibility |
|------|----------------|
| `exegol/my-resources/bin/audit-sinks` (new) | semgrep + ast-grep + weggli sink scan → `sinks.json`/`sinks.txt` |
| `exegol/my-resources/bin/audit-endpoints` (new) | semgrep route rules + xnLinkFinder + grep → `endpoints.json`/`endpoints.txt` |
| `exegol/my-resources/bin/audit-hotspots` (new, python) | aggregate+rank all `scans/code/*.json` → `hotspots.json`/`hotspots.md` |
| `exegol/my-resources/bin/audit-full` (new) | orchestrate audit-code → sinks → endpoints → hotspots |
| `exegol/my-resources/audit-rules/endpoints.yml` (new) | semgrep custom route-definition rules |
| `exegol/my-resources/audit-rules/sgconfig-sinks.yml` + `astgrep-sinks/*.yml` (new) | ast-grep polyglot sink rules |
| `exegol/my-resources/fragments/load_user_setup.dotsec.sh` (modify) | install ast-grep + weggli |
| `exegol/my-resources/deploy.sh` (modify) | copy `audit-rules/` into the volume |
| `exegol/my-resources/fragments/aliases.dotsec` + `history.dotsec` (modify) | shortcuts + history for audit-* |
| `.pre-commit-config.yaml` + `Makefile` (modify) | exclude `audit-hotspots` (python) from shellcheck |
| `tests/audit.bats` (new) | stub-based wiring tests for the bash scripts |
| `tests/test_audit_hotspots.py` (new) | host unit tests for the python ranker |
| `README.md` (modify) | document the audit stage |

---

## Task 1: Install the audit engines

**Files:**
- Modify: `exegol/my-resources/fragments/load_user_setup.dotsec.sh`

- [ ] **Step 1: Add ast-grep + weggli installs**

Insert after the existing `_dotsec_release osv-scanner ...` block, before the final `echo`:

```bash
# ── code audit: structural search engines (audit-sinks/audit-endpoints) ──
# ast-grep installs the `ast-grep` binary (it also ships `sg`, but /usr/bin/sg is
# the unrelated setgid tool — scripts always call `ast-grep`).
_dotsec_have ast-grep || npm install -g @ast-grep/cli >/dev/null 2>&1 || true
# weggli: C/C++ semantic grep (slow cargo build, best-effort).
_dotsec_have weggli || cargo install weggli --locked >/dev/null 2>&1 || true
```

- [ ] **Step 2: shellcheck the fragment**

Run: `shellcheck -x exegol/my-resources/fragments/load_user_setup.dotsec.sh`
Expected: no output (clean).

- [ ] **Step 3: Deploy + install live, verify binaries + pin CLIs**

```bash
DOTSEC_HOME="$PWD" bash exegol/my-resources/deploy.sh
docker exec exegol-e-voting bash -lc 'npm install -g @ast-grep/cli >/dev/null 2>&1; command -v ast-grep; ast-grep --version; ast-grep scan --help 2>&1 | grep -iE "json|config|--rule|-c," | head'
```
Expected: `ast-grep` resolves, version prints. **Record the exact flags** for `scan` (config flag is `-c`/`--config`, JSON flag is `--json` or `--json=stream`) — they are used verbatim in Tasks 3-4. weggli build may take minutes; it is optional, do not block on it.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(audit): install ast-grep + weggli engines" -- exegol/my-resources/fragments/load_user_setup.dotsec.sh
```

---

## Task 2: semgrep endpoint rules

**Files:**
- Create: `exegol/my-resources/audit-rules/endpoints.yml`

- [ ] **Step 1: Write the rules file**

```yaml
# dotsec audit: backend route/handler definitions across common frameworks.
# Used by audit-endpoints (semgrep --config). INFO severity: these are surface,
# not vulns.
rules:
  - id: express-route
    languages: [javascript, typescript]
    severity: INFO
    message: "express/koa route"
    patterns:
      - pattern-either:
          - pattern: $APP.get("$P", ...)
          - pattern: $APP.post("$P", ...)
          - pattern: $APP.put("$P", ...)
          - pattern: $APP.delete("$P", ...)
          - pattern: $APP.patch("$P", ...)
          - pattern: $APP.all("$P", ...)
  - id: flask-fastapi-route
    languages: [python]
    severity: INFO
    message: "flask/fastapi route"
    patterns:
      - pattern-either:
          - pattern: "@$APP.route(\"$P\", ...)"
          - pattern: "@$APP.get(\"$P\", ...)"
          - pattern: "@$APP.post(\"$P\", ...)"
          - pattern: "@$ROUTER.get(\"$P\", ...)"
          - pattern: "@$ROUTER.post(\"$P\", ...)"
  - id: spring-mapping
    languages: [java]
    severity: INFO
    message: "spring request mapping"
    patterns:
      - pattern-either:
          - pattern: "@RequestMapping(...)"
          - pattern: "@GetMapping(...)"
          - pattern: "@PostMapping(...)"
  - id: go-http-handler
    languages: [go]
    severity: INFO
    message: "go http handler"
    patterns:
      - pattern-either:
          - pattern: $MUX.HandleFunc("$P", ...)
          - pattern: http.HandleFunc("$P", ...)
```

- [ ] **Step 2: Validate the rules with semgrep**

Run: `docker exec exegol-e-voting bash -lc 'semgrep --validate --config /opt/my-resources/audit-rules/endpoints.yml 2>&1 | tail -3'`
(Deploy first via `DOTSEC_HOME="$PWD" bash exegol/my-resources/deploy.sh` — but note deploy.sh does not yet copy audit-rules; copy manually for this check: `mkdir -p ~/.exegol/my-resources/audit-rules && cp exegol/my-resources/audit-rules/endpoints.yml ~/.exegol/my-resources/audit-rules/`)
Expected: `Configuration is valid` (or no rule-parse errors). Fix any pattern that fails to parse.

- [ ] **Step 3: Commit**

```bash
git add exegol/my-resources/audit-rules/endpoints.yml
git commit -m "feat(audit): semgrep route-definition rules" -- exegol/my-resources/audit-rules/endpoints.yml
```

---

## Task 3: `audit-hotspots` ranker (python, TDD on host)

This is pure logic — write it test-first on the host (no container needed).

**Files:**
- Create: `tests/test_audit_hotspots.py`
- Create: `exegol/my-resources/bin/audit-hotspots`

- [ ] **Step 1: Write the failing test**

`tests/test_audit_hotspots.py`:

```python
import json, os, subprocess, sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "exegol/my-resources/bin/audit-hotspots"

def _run(ws: Path):
    env = {**os.environ, "WORKSPACE": str(ws)}
    return subprocess.run([sys.executable, str(SCRIPT)], env=env, capture_output=True, text=True)

def test_ranks_error_above_info(tmp_path):
    outd = tmp_path / "scans" / "code"; outd.mkdir(parents=True)
    (outd / "sinks.json").write_text(json.dumps({"results": [
        {"check_id": "eval-injection", "path": "a.js", "start": {"line": 5},
         "extra": {"severity": "ERROR", "message": "eval sink"}},
        {"check_id": "weak-rng", "path": "b.js", "start": {"line": 9},
         "extra": {"severity": "INFO", "message": "weak rng"}},
    ]}))
    r = _run(tmp_path)
    assert r.returncode == 0, r.stderr
    ranked = json.loads((outd / "hotspots.json").read_text())
    assert [f["rule"] for f in ranked] == ["eval-injection", "weak-rng"]
    assert (outd / "hotspots.md").exists()

def test_verified_secret_outranks_sink(tmp_path):
    outd = tmp_path / "scans" / "code"; outd.mkdir(parents=True)
    (outd / "sinks.json").write_text(json.dumps({"results": [
        {"check_id": "eval-injection", "path": "a.js", "start": {"line": 5},
         "extra": {"severity": "ERROR", "message": "eval"}}]}))
    (outd / "secrets_trufflehog.json").write_text(
        json.dumps({"SourceMetadata": {"Data": {"Filesystem": {"file": "c.env"}}},
                    "DetectorName": "AWS", "Verified": True}) + "\n")
    r = _run(tmp_path)
    assert r.returncode == 0, r.stderr
    ranked = json.loads((outd / "hotspots.json").read_text())
    assert ranked[0]["category"] == "secret-verified"

def test_no_inputs_is_clean(tmp_path):
    (tmp_path / "scans" / "code").mkdir(parents=True)
    r = _run(tmp_path)
    assert r.returncode == 0
    assert json.loads((tmp_path / "scans/code/hotspots.json").read_text()) == []
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python3 -m pytest tests/test_audit_hotspots.py -q` (or `pytest`)
Expected: FAIL (script does not exist / no such file).

- [ ] **Step 3: Write `exegol/my-resources/bin/audit-hotspots`**

```python
#!/usr/bin/env python3
"""Aggregate the audit JSON artifacts in scans/code/ into a ranked hotspots
report (hotspots.json + hotspots.md). Pure stdlib; reads whatever is present."""
from __future__ import annotations

import json
import os
from pathlib import Path

SEVERITY_SCORE = {"ERROR": 4, "WARNING": 3, "HIGH": 4, "MEDIUM": 3, "LOW": 2, "INFO": 1}


def load_json(path: Path) -> object | None:
    """Return parsed JSON, or None if missing/unparseable."""
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


def load_jsonl(path: Path) -> list[dict]:
    """Return a list of objects from a JSON-lines file (trufflehog format)."""
    out: list[dict] = []
    try:
        for line in path.read_text().splitlines():
            line = line.strip()
            if line:
                out.append(json.loads(line))
    except Exception:
        pass
    return out


def from_semgrep(data: object, category: str) -> list[dict]:
    """Flatten a semgrep JSON report into scored findings."""
    findings: list[dict] = []
    results = data.get("results", []) if isinstance(data, dict) else []
    for r in results:
        extra = r.get("extra", {})
        sev = str(extra.get("severity", "INFO")).upper()
        findings.append({
            "category": category,
            "rule": r.get("check_id", "?"),
            "file": r.get("path", "?"),
            "line": r.get("start", {}).get("line", 0),
            "message": str(extra.get("message", ""))[:200],
            "score": SEVERITY_SCORE.get(sev, 1),
        })
    return findings


def from_trufflehog(records: list[dict]) -> list[dict]:
    """Verified secrets rank highest; unverified are still surfaced."""
    findings: list[dict] = []
    for rec in records:
        verified = bool(rec.get("Verified"))
        meta = rec.get("SourceMetadata", {}).get("Data", {}).get("Filesystem", {})
        findings.append({
            "category": "secret-verified" if verified else "secret",
            "rule": rec.get("DetectorName", "secret"),
            "file": meta.get("file", "?"),
            "line": meta.get("line", 0),
            "message": "verified live credential" if verified else "potential secret",
            "score": 5 if verified else 2,
        })
    return findings


def main() -> int:
    outd = Path(os.environ.get("WORKSPACE", ".")) / "scans" / "code"
    findings: list[dict] = []
    findings += from_semgrep(load_json(outd / "sinks.json"), "sink")
    findings += from_semgrep(load_json(outd / "endpoints.json"), "endpoint")
    findings += from_trufflehog(load_jsonl(outd / "secrets_trufflehog.json"))

    findings.sort(key=lambda f: (f["score"], f["category"]), reverse=True)

    outd.mkdir(parents=True, exist_ok=True)
    (outd / "hotspots.json").write_text(json.dumps(findings, indent=2))

    lines = ["# Code audit hotspots", "", f"{len(findings)} candidates (ranked).", ""]
    lines += ["| score | category | rule | file:line | note |",
              "|------:|----------|------|-----------|------|"]
    for f in findings:
        lines.append(f"| {f['score']} | {f['category']} | `{f['rule']}` | "
                     f"`{f['file']}:{f['line']}` | {f['message']} |")
    (outd / "hotspots.md").write_text("\n".join(lines) + "\n")
    print(f"[+] {len(findings)} hotspots -> {outd}/hotspots.json (+ hotspots.md)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Make it executable and run the tests**

```bash
chmod +x exegol/my-resources/bin/audit-hotspots
python3 -m pytest tests/test_audit_hotspots.py -q
```
Expected: 3 passed.

- [ ] **Step 5: Exclude it from shellcheck (it is python)**

In `.pre-commit-config.yaml`, the shellcheck hook gains an `exclude`:

```yaml
      - id: shellcheck
        name: shellcheck
        entry: shellcheck -x
        language: system
        files: '^(bin/dotsec|bin/dotsec-build|lib/.*\.sh|tests/integration-smoke\.sh|tests/stubs/.*|\.github/scripts/.*\.sh|exegol/my-resources/bin/[^/]+|exegol/my-resources/deploy\.sh)$'
        exclude: '^exegol/my-resources/bin/audit-hotspots$'
```

In `Makefile`, the `lint` target excludes it from the glob. Replace the `exegol/my-resources/bin/*` argument with an explicit filter:

```make
	@shellcheck -x bin/dotsec bin/dotsec-build lib/*.sh tests/integration-smoke.sh $$(ls exegol/my-resources/bin/* | grep -v '/audit-hotspots$$') exegol/my-resources/deploy.sh && echo "[+] shellcheck clean"
```

- [ ] **Step 6: Verify lint still clean**

Run: `make lint`
Expected: `[+] shellcheck clean` (audit-hotspots not shellcheck'd).

- [ ] **Step 7: Commit**

```bash
git add tests/test_audit_hotspots.py exegol/my-resources/bin/audit-hotspots .pre-commit-config.yaml Makefile
git commit -m "feat(audit): hotspots ranker (python) + lint exclude" -- tests/test_audit_hotspots.py exegol/my-resources/bin/audit-hotspots .pre-commit-config.yaml Makefile
```

---

## Task 4: `audit-sinks` script

**Files:**
- Create: `exegol/my-resources/bin/audit-sinks`
- Create: `tests/stubs/semgrep`
- Modify: `tests/audit.bats` (created here)

- [ ] **Step 1: Write the failing bats test (wiring, stubbed semgrep)**

Create `tests/stubs/semgrep` (mode 0755):

```bash
#!/usr/bin/env bash
# stub: emit a fixed semgrep JSON report to the -o path
out=""
while [[ $# -gt 0 ]]; do case "$1" in -o) out="$2"; shift 2;; *) shift;; esac; done
cat > "$out" <<'JSON'
{"results":[{"check_id":"js-eval","path":"a.js","start":{"line":3},"extra":{"severity":"ERROR","message":"eval sink"}}]}
JSON
```

Create `tests/audit.bats`:

```bash
#!/usr/bin/env bats
setup() {
    BIN="${BATS_TEST_DIRNAME}/../exegol/my-resources/bin"
    export PATH="${BATS_TEST_DIRNAME}/stubs:${PATH}"
    WS="$(mktemp -d)"; export WORKSPACE="$WS"
    mkdir -p "$WS/code"; echo 'eval(x)' > "$WS/code/a.js"
}
teardown() { rm -rf "$WS"; }

@test "audit-sinks writes sinks.json from semgrep" {
    run "$BIN/audit-sinks"
    [ "$status" -eq 0 ]
    [ -f "$WS/scans/code/sinks.json" ]
    grep -q "js-eval" "$WS/scans/code/sinks.json"
}

@test "audit-sinks errors on empty code dir" {
    rm -rf "$WS/code"; mkdir -p "$WS/code"
    run "$BIN/audit-sinks"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/audit.bats`
Expected: FAIL (audit-sinks missing).

- [ ] **Step 3: Write `exegol/my-resources/bin/audit-sinks`**

```bash
#!/usr/bin/env bash
set -euo pipefail
WS="${WORKSPACE:-$PWD}"
CODE="${1:-$WS/code}"
OUTD="$WS/scans/code"
RULES="${MYRES:-/opt/my-resources}/audit-rules"
mkdir -p "$OUTD"

# Dangerous-function / sink scan over the recovered code.
[[ -d "$CODE" ]] || { echo "[!] no dir: $CODE"; exit 1; }
[[ -n "$(find "$CODE" -type f -print -quit 2>/dev/null)" ]] \
    || { echo "[!] $CODE is empty — run recon-sourcemaps / recon-loot first"; exit 1; }
echo "[*] sink scan $CODE"
: > "$OUTD/sinks.txt"

# 1. semgrep security rulesets (primary, polyglot, JSON).
if command -v semgrep >/dev/null 2>&1; then
    semgrep scan --config p/security-audit --config p/owasp-top-ten \
        --json -o "$OUTD/sinks.json" "$CODE" >/dev/null 2>&1 || true
    echo "semgrep: p/security-audit + p/owasp-top-ten -> sinks.json" >> "$OUTD/sinks.txt"
fi

# 2. ast-grep custom polyglot patterns (best-effort). Binary is `ast-grep`,
#    NEVER `sg` (/usr/bin/sg is the unrelated setgid tool).
if command -v ast-grep >/dev/null 2>&1 && [[ -f "$RULES/sgconfig-sinks.yml" ]]; then
    ast-grep scan -c "$RULES/sgconfig-sinks.yml" --json "$CODE" \
        > "$OUTD/sinks_astgrep.json" 2>/dev/null || true
    echo "ast-grep: $RULES/sgconfig-sinks.yml -> sinks_astgrep.json" >> "$OUTD/sinks.txt"
fi

# 3. weggli C/C++ semantic patterns (best-effort, C/C++ only).
if command -v weggli >/dev/null 2>&1; then
    for pat in 'strcpy(_,_);' 'memcpy(_,_,_);' 'system(_);' 'sprintf(_,_);' 'gets(_);'; do
        weggli "{ $pat }" "$CODE" 2>/dev/null >> "$OUTD/sinks.txt" || true
    done
fi
echo "[+] sinks -> $OUTD/sinks.json (+ sinks.txt)"
```

- [ ] **Step 4: Make executable, run bats**

```bash
chmod +x exegol/my-resources/bin/audit-sinks
bats tests/audit.bats
```
Expected: the two audit-sinks tests pass.

- [ ] **Step 5: Verify ast-grep invocation live, fix flags if needed**

Using the flags recorded in Task 1 Step 3, confirm `ast-grep scan -c <cfg> --json <dir>` is valid. If the JSON flag differs (e.g. `--json=stream`), update the script. (ast-grep rules themselves are added in Task 6; this step only confirms the CLI shape so the guard is correct.)

- [ ] **Step 6: shellcheck + commit**

```bash
shellcheck -x exegol/my-resources/bin/audit-sinks tests/stubs/semgrep
git add exegol/my-resources/bin/audit-sinks tests/stubs/semgrep tests/audit.bats
git commit -m "feat(audit): audit-sinks (semgrep + ast-grep + weggli)" -- exegol/my-resources/bin/audit-sinks tests/stubs/semgrep tests/audit.bats
```

---

## Task 5: `audit-endpoints` script

**Files:**
- Create: `exegol/my-resources/bin/audit-endpoints`
- Modify: `tests/audit.bats`

- [ ] **Step 1: Add failing bats test**

Append to `tests/audit.bats`:

```bash
@test "audit-endpoints writes endpoints.json from semgrep" {
    cp "${BATS_TEST_DIRNAME}/../exegol/my-resources/audit-rules/endpoints.yml" /dev/null 2>/dev/null || true
    export MYRES="${BATS_TEST_DIRNAME}/../exegol/my-resources"
    run "$BIN/audit-endpoints"
    [ "$status" -eq 0 ]
    [ -f "$WS/scans/code/endpoints.json" ]
}
```

The semgrep stub already writes a fixed report to `-o`; that satisfies "writes endpoints.json". (The stub ignores `--config`, so the rules path only needs to exist.)

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/audit.bats`
Expected: the new endpoints test FAILS (script missing).

- [ ] **Step 3: Write `exegol/my-resources/bin/audit-endpoints`**

```bash
#!/usr/bin/env bash
set -euo pipefail
WS="${WORKSPACE:-$PWD}"
CODE="${1:-$WS/code}"
OUTD="$WS/scans/code"
RULES="${MYRES:-/opt/my-resources}/audit-rules"
mkdir -p "$OUTD"

# Attack-surface extraction: backend routes + frontend API calls.
[[ -d "$CODE" ]] || { echo "[!] no dir: $CODE"; exit 1; }
[[ -n "$(find "$CODE" -type f -print -quit 2>/dev/null)" ]] \
    || { echo "[!] $CODE is empty"; exit 1; }
echo "[*] endpoint scan $CODE"

# 1. Backend routes via semgrep custom rules.
if command -v semgrep >/dev/null 2>&1 && [[ -f "$RULES/endpoints.yml" ]]; then
    semgrep scan --config "$RULES/endpoints.yml" \
        --json -o "$OUTD/endpoints.json" "$CODE" >/dev/null 2>&1 || true
fi

# 2. Frontend: endpoints referenced from JS + raw URL/fetch/axios literals.
: > "$OUTD/endpoints.txt"
if command -v xnLinkFinder >/dev/null 2>&1; then
    xnLinkFinder -i "$CODE" -sf "${DOMAIN:-}" -o "$OUTD/_xn.txt" >/dev/null 2>&1 || true
    [[ -f "$OUTD/_xn.txt" ]] && cat "$OUTD/_xn.txt" >> "$OUTD/endpoints.txt" && rm -f "$OUTD/_xn.txt"
fi
grep -rhoEi "https?://[^\"'\` )]+|fetch\(|axios\.[a-z]+\(|XMLHttpRequest" "$CODE" 2>/dev/null \
    | sort -u >> "$OUTD/endpoints.txt" || true
sort -u "$OUTD/endpoints.txt" -o "$OUTD/endpoints.txt" 2>/dev/null || true
echo "[+] endpoints -> $OUTD/endpoints.json (+ endpoints.txt)"
```

- [ ] **Step 4: Run bats**

Run: `bats tests/audit.bats`
Expected: all tests pass.

- [ ] **Step 5: Verify xnLinkFinder dir-input flags live**

Run: `docker exec exegol-e-voting bash -lc 'xnLinkFinder --help 2>&1 | grep -iE "\-i |\-o |\-sf|directory" | head'`
Confirm `-i <dir>` accepts a directory and `-o <file>` is the output flag. If xnLinkFinder needs a file list instead of a dir, adjust to iterate `find "$CODE" -name '*.js'`. (xnLinkFinder is guarded by `command -v`, so this only refines behavior, never breaks the script.)

- [ ] **Step 6: shellcheck + commit**

```bash
shellcheck -x exegol/my-resources/bin/audit-endpoints
git add exegol/my-resources/bin/audit-endpoints tests/audit.bats
git commit -m "feat(audit): audit-endpoints (routes + JS surface)" -- exegol/my-resources/bin/audit-endpoints tests/audit.bats
```

---

## Task 6: ast-grep sink rules + `audit-full` + wiring

**Files:**
- Create: `exegol/my-resources/audit-rules/sgconfig-sinks.yml`
- Create: `exegol/my-resources/audit-rules/astgrep-sinks/dangerous.yml`
- Create: `exegol/my-resources/bin/audit-full`
- Modify: `exegol/my-resources/deploy.sh`
- Modify: `exegol/my-resources/fragments/aliases.dotsec`, `history.dotsec`

- [ ] **Step 1: ast-grep sink rules**

`exegol/my-resources/audit-rules/sgconfig-sinks.yml`:

```yaml
ruleDirs:
  - astgrep-sinks
```

`exegol/my-resources/audit-rules/astgrep-sinks/dangerous.yml`:

```yaml
id: js-eval
language: javascript
severity: warning
message: dynamic eval (code-injection sink)
rule:
  pattern: eval($A)
---
id: js-innerhtml
language: javascript
severity: warning
message: innerHTML assignment (DOM XSS sink)
rule:
  pattern: $X.innerHTML = $A
---
id: py-os-system
language: python
severity: warning
message: os.system (command-injection sink)
rule:
  pattern: os.system($A)
```

- [ ] **Step 2: Validate ast-grep rules live**

Run (deploy first): `docker exec exegol-e-voting bash -lc 'ast-grep scan -c /opt/my-resources/audit-rules/sgconfig-sinks.yml --json /opt/my-resources/audit-rules 2>&1 | head -c 200'`
Expected: valid JSON (possibly `[]`). Fix rule syntax to match the version's schema if it errors (record working schema).

- [ ] **Step 3: Write `exegol/my-resources/bin/audit-full`**

```bash
#!/usr/bin/env bash
set -euo pipefail
WS="${WORKSPACE:-$PWD}"
CODE="${1:-$WS/code}"

# Full white-box audit pass over the code/ zone.
echo "[*] full code audit for $CODE"
audit-code "$CODE"       || echo "[i] audit-code step skipped"
audit-sinks "$CODE"      || echo "[i] sinks step skipped"
audit-endpoints "$CODE"  || echo "[i] endpoints step skipped"
audit-hotspots           || echo "[i] hotspots step skipped"
echo "[+] done -> ${WS}/scans/code (see hotspots.md)"
```

- [ ] **Step 4: deploy.sh copies audit-rules/**

In `exegol/my-resources/deploy.sh`, after the bin-copy loop, add:

```bash
if [[ -d "${SRC}/audit-rules" ]]; then
    mkdir -p "${DEST}/audit-rules"
    cp -r "${SRC}/audit-rules/." "${DEST}/audit-rules/"
fi
```

- [ ] **Step 5: aliases + history**

In `exegol/my-resources/fragments/aliases.dotsec`, under the phase shortcuts, append:

```bash
alias sinks='audit-sinks'
alias endpoints='audit-endpoints'
alias hotspots='audit-hotspots'
```

In `exegol/my-resources/fragments/history.dotsec`, append:

```bash
: 0:0;audit-full code/
: 0:0;audit-sinks code/ && audit-hotspots
: 0:0;semgrep scan --config p/security-audit --json code/
```

- [ ] **Step 6: shellcheck + bats + commit**

```bash
shellcheck -x exegol/my-resources/bin/audit-full exegol/my-resources/deploy.sh
bats tests/audit.bats
git add exegol/my-resources/audit-rules exegol/my-resources/bin/audit-full exegol/my-resources/deploy.sh exegol/my-resources/fragments/aliases.dotsec exegol/my-resources/fragments/history.dotsec
git commit -m "feat(audit): ast-grep sink rules, audit-full orchestrator + wiring" -- exegol/my-resources/audit-rules exegol/my-resources/bin/audit-full exegol/my-resources/deploy.sh exegol/my-resources/fragments/aliases.dotsec exegol/my-resources/fragments/history.dotsec
```

---

## Task 7: Live smoke + docs

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Deploy + real-detection smoke in the container**

```bash
DOTSEC_HOME="$PWD" bash exegol/my-resources/deploy.sh
docker exec exegol-e-voting bash -lc '
  export PATH="/opt/my-resources/bin:$PATH" WORKSPACE=/tmp/audit-smoke
  rm -rf "$WORKSPACE"; mkdir -p "$WORKSPACE/code"
  printf "const x=req.query.q; eval(x);\napp.get(\"/admin\", h);\n" > "$WORKSPACE/code/app.js"
  audit-full /tmp/audit-smoke/code
  echo "--- hotspots.md ---"; cat "$WORKSPACE/scans/code/hotspots.md"
  rm -rf "$WORKSPACE"'
```
Expected: `sinks.json`, `endpoints.json`, `hotspots.json`, `hotspots.md` produced; the `eval` appears as a sink and `/admin` as an endpoint in `hotspots.md`. If a tool is missing it degrades, but semgrep findings + hotspots must be present.

- [ ] **Step 2: Document the audit stage in README**

In `README.md`, under the Exegol provisioning "Typical flow", add after `audit-code`:

```markdown
audit-full       # full white-box pass: secrets + SCA + sinks + endpoints + ranked hotspots
```

And in the bundle "audit scripts" bullet, replace the line with:

```markdown
- **audit** scripts: `audit-code` (secrets/SAST/SCA), `audit-sinks` (dangerous functions), `audit-endpoints` (routes + JS surface), `audit-hotspots` (ranked candidates), `audit-full`
```

- [ ] **Step 3: Final full verification**

```bash
make lint
make test
python3 -m pytest tests/test_audit_hotspots.py -q
```
Expected: shellcheck clean; all bats pass; pytest 3 passed.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(audit): document the white-box audit stage" -- README.md
```

---

## Self-Review (completed by author)

- **Spec coverage:** audit-sinks (Task 4 + ast-grep rules Task 6), audit-endpoints (Task 5 + rules Task 2), audit-code (unchanged, referenced in audit-full), audit-hotspots (Task 3), audit-full (Task 6), install (Task 1), bundled rules + deploy (Task 2/6), aliases/history (Task 6), lint exclude (Task 3), tests (Task 3/4/5), honest limits (best-effort guards throughout). All spec sections mapped.
- **Placeholders:** none — every code step shows complete content; the three "verify CLI live" steps (ast-grep/xnLinkFinder/weggli) give the exact verification command and the fallback, because those binaries are not yet installed to hardcode against. They are guarded by `command -v`, so the scripts are correct regardless.
- **Type consistency:** `from_semgrep`/`from_trufflehog`/`load_json`/`load_jsonl` names match between definition and call; finding dict keys (`category`,`rule`,`file`,`line`,`message`,`score`) are identical in the python, the markdown writer, and the tests; output filenames (`sinks.json`,`endpoints.json`,`secrets_trufflehog.json`,`hotspots.json`,`hotspots.md`) are consistent across scripts, tests, and the ranker.

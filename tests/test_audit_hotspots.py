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

def test_astgrep_sink_included(tmp_path):
    outd = tmp_path / "scans" / "code"; outd.mkdir(parents=True)
    (outd / "sinks_astgrep.json").write_text(json.dumps([
        {"ruleId": "js-eval", "severity": "warning", "file": "app.js",
         "range": {"start": {"line": 0, "column": 0}}, "message": "dynamic eval"}
    ]))
    r = _run(tmp_path)
    assert r.returncode == 0, r.stderr
    ranked = json.loads((outd / "hotspots.json").read_text())
    assert ranked[0]["rule"] == "js-eval"
    assert ranked[0]["category"] == "sink"
    assert ranked[0]["line"] == 1  # ast-grep 0-indexed -> 1-indexed

def test_markdown_escapes_pipe_and_newline(tmp_path):
    outd = tmp_path / "scans" / "code"; outd.mkdir(parents=True)
    (outd / "sinks.json").write_text(json.dumps({"results": [
        {"check_id": "r", "path": "a.js", "start": {"line": 1},
         "extra": {"severity": "ERROR", "message": "bad | line\nbreak"}}]}))
    r = _run(tmp_path)
    assert r.returncode == 0, r.stderr
    md = (outd / "hotspots.md").read_text()
    data_rows = [ln for ln in md.splitlines()
                 if ln.startswith("| ") and "score |" not in ln and "---" not in ln]
    assert len(data_rows) == 1  # a newline in a field must not split the row
    assert "\\|" in md          # the literal pipe must be escaped

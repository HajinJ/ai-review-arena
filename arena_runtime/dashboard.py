from __future__ import annotations

import argparse
import html
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Sequence


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def _load_events(runs_dir: Path, limit: int) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for events_path in sorted(runs_dir.glob("*/events.jsonl"), reverse=True):
        with events_path.open("r", encoding="utf-8") as handle:
            for line in handle:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(event, dict):
                    rows.append(event)
        if len(rows) >= limit:
            break
    return rows[:limit]


def _status_counts(events: Sequence[Mapping[str, Any]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for event in events:
        name = str(event.get("event") or "unknown")
        counts[name] = counts.get(name, 0) + 1
    return dict(sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:20])


def _benchmark_cards(benchmarks: Sequence[Any]) -> str:
    cards: list[str] = []
    for payload in benchmarks:
        if not isinstance(payload, dict):
            continue
        title = html.escape(str(payload.get("benchmark") or payload.get("category") or "benchmark"))
        summary = payload.get("summary", {}) if isinstance(payload.get("summary"), dict) else {}
        body = "".join(f"<li><b>{html.escape(str(k))}</b>: {html.escape(str(v))}</li>" for k, v in summary.items())
        runtime = payload.get("runtime", {}) if isinstance(payload.get("runtime"), dict) else {}
        runtime_bits = "".join(f"<li>{html.escape(str(k))}: {html.escape(str(v))}</li>" for k, v in runtime.items())
        cards.append(f"<section class='card'><h2>{title}</h2><ul>{body or runtime_bits or '<li>No summary</li>'}</ul></section>")
    return "\n".join(cards) or "<section class='card'><h2>No benchmark data</h2><p>Run retrieval or harness benchmarks and pass --benchmark-json.</p></section>"


def build_dashboard(*, runs_dir: Path, benchmark_json: Sequence[Path], output: Path) -> dict[str, Any]:
    events = _load_events(runs_dir, 1000) if runs_dir.exists() else []
    benchmarks = [_load_json(path) for path in benchmark_json if path.exists()]
    counts = _status_counts(events)
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    output.parent.mkdir(parents=True, exist_ok=True)
    rows = "".join(f"<tr><td>{html.escape(str(k))}</td><td>{v}</td></tr>" for k, v in counts.items())
    html_doc = f"""<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<title>AI Review Arena Dashboard</title>
<style>
:root {{ --bg:#f4efe6; --ink:#221c16; --card:#fffaf0; --line:#d7c8ad; --accent:#1f6f5b; }}
body {{ margin:0; font-family: ui-serif, Georgia, 'Times New Roman', serif; background: radial-gradient(circle at top left,#fff8d7,transparent 32rem), var(--bg); color:var(--ink); }}
main {{ max-width: 1080px; margin: 0 auto; padding: 48px 20px; }}
h1 {{ font-size: clamp(2.2rem, 6vw, 5rem); line-height: .92; margin: 0 0 16px; letter-spacing: -0.05em; }}
.lede {{ font-size: 1.1rem; max-width: 780px; }}
.grid {{ display:grid; grid-template-columns: repeat(auto-fit,minmax(260px,1fr)); gap:16px; margin-top:32px; }}
.card {{ background: color-mix(in srgb, var(--card) 92%, white); border:1px solid var(--line); border-radius:24px; padding:20px; box-shadow: 0 18px 60px rgba(40,27,10,.08); }}
.card h2 {{ margin-top:0; font-size:1.1rem; text-transform:uppercase; letter-spacing:.08em; color:var(--accent); }}
table {{ width:100%; border-collapse:collapse; }}
td {{ border-bottom:1px solid var(--line); padding:8px 0; }}
code {{ background:#eadfc9; padding:2px 6px; border-radius:8px; }}
</style>
</head>
<body><main>
<h1>AI Review Arena Dashboard</h1>
<p class='lede'>Generated at <code>{generated}</code>. This static dashboard summarizes harness events, benchmark output, provider drift signals, and dogfooding runs.</p>
<div class='grid'>
<section class='card'><h2>Harness events</h2><p>{len(events)} recent events loaded from <code>{html.escape(str(runs_dir))}</code>.</p><table>{rows or '<tr><td>No events</td><td>0</td></tr>'}</table></section>
{_benchmark_cards(benchmarks)}
</div>
</main></body></html>
"""
    output.write_text(html_doc, encoding="utf-8")
    summary = {"status": "built", "output": str(output), "events": len(events), "benchmarks": len(benchmarks), "generated_at": generated}
    (output.parent / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    return summary


def cmd_dashboard_build(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="dashboard-build")
    parser.add_argument("--runs-dir", default=str(_repo_root() / "cache" / "runs"))
    parser.add_argument("--benchmark-json", action="append", default=[])
    parser.add_argument("--output", default=str(_repo_root() / "cache" / "dashboard" / "index.html"))
    args = parser.parse_args(list(argv))
    summary = build_dashboard(runs_dir=Path(args.runs_dir), benchmark_json=[Path(item) for item in args.benchmark_json], output=Path(args.output))
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0

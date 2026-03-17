"""Generate a structured workspace template conformance report.

Compares `template.apply_fdl` output against ASC scenario expected results and
writes a JSON report for mismatch analysis.
"""

from __future__ import annotations

import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from fdl_backend.handlers import template_ops

DEFAULT_ASC_REPO = Path('/Users/dhall/Documents/GitHub/ascmitc/fdl')
DEFAULT_OUTPUT = Path('tests/artifacts/workspace_conformance_report.json')


@dataclass(frozen=True)
class ScenarioCase:
    scenario_name: str
    template_path: Path
    source_path: Path
    expected_path: Path

    @property
    def case_id(self) -> str:
        return f"{self.scenario_name}:{self.expected_path.name}"


def _asc_repo_path() -> Path:
    configured = os.environ.get('ASC_FDL_REPO_PATH', '').strip()
    return Path(configured) if configured else DEFAULT_ASC_REPO


def _scenario_root(repo_path: Path) -> Path:
    return repo_path / 'resources' / 'FDL' / 'Scenarios_For_Implementers'


def _source_root(repo_path: Path) -> Path:
    return repo_path / 'resources' / 'FDL' / 'Original_Source_Files'


def _pick_template_file(scenario_dir: Path) -> Path | None:
    candidates = sorted(p for p in scenario_dir.glob('*.fdl') if p.is_file())
    for c in candidates:
        if c.parent.name == 'Results':
            continue
        try:
            obj = json.loads(c.read_text(encoding='utf-8'))
        except Exception:
            continue
        if obj.get('canvas_templates'):
            return c
    return None


def _resolve_source_path(expected_name: str, source_root: Path) -> Path | None:
    exact = source_root / expected_name
    if exact.exists():
        return exact

    m = re.search(r'([A-Z]_[^/]+\.fdl)$', expected_name)
    if m:
        candidate = source_root / m.group(1)
        if candidate.exists():
            return candidate

    if 'RESULT' in expected_name:
        trimmed = expected_name.split('RESULT', 1)[-1]
        candidate = source_root / trimmed
        if candidate.exists():
            return candidate

    return None


def discover_cases() -> list[ScenarioCase]:
    repo = _asc_repo_path()
    scen_root = _scenario_root(repo)
    src_root = _source_root(repo)
    if not scen_root.exists() or not src_root.exists():
        return []

    cases: list[ScenarioCase] = []
    for scenario_dir in sorted(scen_root.glob('Scen_*')):
        if not scenario_dir.is_dir():
            continue
        template_path = _pick_template_file(scenario_dir)
        if not template_path:
            continue
        results_dir = scenario_dir / 'Results'
        if not results_dir.exists():
            continue

        for expected_path in sorted(results_dir.glob('*.fdl')):
            source_path = _resolve_source_path(expected_path.name, src_root)
            if not source_path:
                continue
            cases.append(
                ScenarioCase(
                    scenario_name=scenario_dir.name,
                    template_path=template_path,
                    source_path=source_path,
                    expected_path=expected_path,
                )
            )

    return cases


def _pick_output_canvas(actual_doc: dict, expected_doc: dict, preferred_id: str | None) -> tuple[dict, dict]:
    actual_canvases = actual_doc['contexts'][0]['canvases']
    expected_canvases = expected_doc['contexts'][0]['canvases']
    expected_out = expected_canvases[-1]

    if preferred_id:
        for canvas in actual_canvases:
            if canvas.get('id') == preferred_id:
                return canvas, expected_out
    return actual_canvases[-1], expected_out


def _first_fd(canvas: dict) -> dict | None:
    fds = canvas.get('framing_decisions') or []
    return fds[0] if fds else None


def _delta_dims(actual: dict | None, expected: dict | None) -> dict[str, Any]:
    if not actual and not expected:
        return {'status': 'match'}
    if not actual or not expected:
        return {'status': 'missing', 'actual': actual, 'expected': expected}
    aw, ah = float(actual.get('width', 0)), float(actual.get('height', 0))
    ew, eh = float(expected.get('width', 0)), float(expected.get('height', 0))
    return {
        'status': 'delta',
        'dw': aw - ew,
        'dh': ah - eh,
        'actual': {'width': aw, 'height': ah},
        'expected': {'width': ew, 'height': eh},
    }


def _delta_point(actual: dict | None, expected: dict | None) -> dict[str, Any]:
    if not actual and not expected:
        return {'status': 'match'}
    if not actual or not expected:
        return {'status': 'missing', 'actual': actual, 'expected': expected}
    ax, ay = float(actual.get('x', 0)), float(actual.get('y', 0))
    ex, ey = float(expected.get('x', 0)), float(expected.get('y', 0))
    return {
        'status': 'delta',
        'dx': ax - ex,
        'dy': ay - ey,
        'actual': {'x': ax, 'y': ay},
        'expected': {'x': ex, 'y': ey},
    }


def _is_close(d: dict[str, Any], tol: float = 1e-3) -> bool:
    if d['status'] == 'match':
        return True
    if d['status'] == 'missing':
        return False
    for k, v in d.items():
        if k.startswith('d') and isinstance(v, (int, float)) and abs(v) > tol:
            return False
    return True


def classify_failure(m: dict[str, dict[str, Any]]) -> str:
    if not _is_close(m['canvas_dims']):
        return 'canvas-dimensions'
    if not _is_close(m['effective_dims']) or not _is_close(m['effective_anchor']):
        return 'effective-geometry'
    if not _is_close(m['fd_dims']) or not _is_close(m['fd_anchor']):
        return 'framing-geometry'
    if not _is_close(m['protection_dims']) or not _is_close(m['protection_anchor']):
        return 'protection-geometry'
    return 'other'


def evaluate_case(case: ScenarioCase) -> dict[str, Any]:
    source_doc = json.loads(case.source_path.read_text(encoding='utf-8'))
    template_doc = json.loads(case.template_path.read_text(encoding='utf-8'))
    expected_doc = json.loads(case.expected_path.read_text(encoding='utf-8'))
    template = (template_doc.get('canvas_templates') or [None])[0]
    if not template:
        return {'case_id': case.case_id, 'status': 'error', 'error': 'missing-template'}

    expected_out = expected_doc['contexts'][0]['canvases'][-1]
    params = {
        'fdl_json': json.dumps(source_doc),
        'template_json': json.dumps(template),
        'context_index': 0,
        'canvas_index': 0,
        'fd_index': 0,
        'new_canvas_id': expected_out.get('id'),
        'new_fd_name': '',
    }

    actual_doc = template_ops.apply_fdl_template(params)['fdl']
    actual_out, expected_out = _pick_output_canvas(actual_doc, expected_doc, expected_out.get('id'))
    actual_fd = _first_fd(actual_out)
    expected_fd = _first_fd(expected_out)

    mismatches = {
        'canvas_dims': _delta_dims(actual_out.get('dimensions'), expected_out.get('dimensions')),
        'effective_dims': _delta_dims(actual_out.get('effective_dimensions'), expected_out.get('effective_dimensions')),
        'effective_anchor': _delta_point(actual_out.get('effective_anchor_point'), expected_out.get('effective_anchor_point')),
        'fd_dims': _delta_dims((actual_fd or {}).get('dimensions'), (expected_fd or {}).get('dimensions')),
        'fd_anchor': _delta_point((actual_fd or {}).get('anchor_point'), (expected_fd or {}).get('anchor_point')),
        'protection_dims': _delta_dims((actual_fd or {}).get('protection_dimensions'), (expected_fd or {}).get('protection_dimensions')),
        'protection_anchor': _delta_point((actual_fd or {}).get('protection_anchor_point'), (expected_fd or {}).get('protection_anchor_point')),
    }

    passed = all(_is_close(v) for v in mismatches.values())
    return {
        'case_id': case.case_id,
        'scenario_name': case.scenario_name,
        'source_file': case.source_path.name,
        'expected_file': case.expected_path.name,
        'template_file': case.template_path.name,
        'status': 'pass' if passed else 'fail',
        'failure_category': None if passed else classify_failure(mismatches),
        'mismatches': mismatches,
    }


def generate_report() -> dict[str, Any]:
    cases = discover_cases()
    results = [evaluate_case(c) for c in cases]
    failed = [r for r in results if r['status'] != 'pass']

    by_category: dict[str, int] = {}
    for f in failed:
        cat = f.get('failure_category') or 'other'
        by_category[cat] = by_category.get(cat, 0) + 1

    return {
        'summary': {
            'cases_total': len(results),
            'cases_passed': len(results) - len(failed),
            'cases_failed': len(failed),
            'failure_categories': dict(sorted(by_category.items(), key=lambda kv: kv[1], reverse=True)),
        },
        'results': results,
    }


def main() -> None:
    report = generate_report()
    out = Path(os.environ.get('WORKSPACE_CONFORMANCE_REPORT_PATH', DEFAULT_OUTPUT))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2), encoding='utf-8')
    s = report['summary']
    print(f"cases={s['cases_total']} passed={s['cases_passed']} failed={s['cases_failed']}")
    print('top_failure_categories=', s['failure_categories'])
    print(out)

    fail_on_mismatch = os.environ.get('WORKSPACE_CONFORMANCE_FAIL_ON_MISMATCH', '').lower() in {
        '1',
        'true',
        'yes',
    }
    if fail_on_mismatch and s['cases_failed'] > 0:
        sys.exit(1)


if __name__ == '__main__':
    main()

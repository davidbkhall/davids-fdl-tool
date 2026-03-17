"""Workspace template-application conformance against ASC scenario outputs.

This suite validates `template.apply_fdl` geometry outcomes against the
official ASC "Scenarios for Implementers" result FDL files.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path

import pytest

from fdl_backend.handlers import template_ops

DEFAULT_ASC_REPO = Path("/Users/dhall/Documents/GitHub/ascmitc/fdl")


@dataclass(frozen=True)
class ScenarioCase:
    scenario_name: str
    template_path: Path
    source_path: Path
    expected_path: Path

    @property
    def name(self) -> str:
        return f"{self.scenario_name}:{self.expected_path.name}"


def _asc_repo_path() -> Path:
    configured = os.environ.get("ASC_FDL_REPO_PATH", "").strip()
    return Path(configured) if configured else DEFAULT_ASC_REPO


def _scenario_root(repo_path: Path) -> Path:
    return repo_path / "resources" / "FDL" / "Scenarios_For_Implementers"


def _source_root(repo_path: Path) -> Path:
    return repo_path / "resources" / "FDL" / "Original_Source_Files"


def _pick_template_file(scenario_dir: Path) -> Path | None:
    candidates = sorted(p for p in scenario_dir.glob("*.fdl") if p.is_file())
    for c in candidates:
        if c.parent.name == "Results":
            continue
        try:
            obj = json.loads(c.read_text(encoding="utf-8"))
        except Exception:
            continue
        if (obj.get("canvas_templates") or []):
            return c
    return None


def _resolve_source_path(expected_name: str, source_root: Path) -> Path | None:
    exact = source_root / expected_name
    if exact.exists():
        return exact

    m = re.search(r"([A-Z]_[^/]+\.fdl)$", expected_name)
    if m:
        candidate = source_root / m.group(1)
        if candidate.exists():
            return candidate

    if "RESULT" in expected_name:
        trimmed = expected_name.split("RESULT", 1)[-1]
        candidate = source_root / trimmed
        if candidate.exists():
            return candidate

    return None


def _discover_cases() -> list[ScenarioCase]:
    repo = _asc_repo_path()
    scen_root = _scenario_root(repo)
    src_root = _source_root(repo)
    if not scen_root.exists() or not src_root.exists():
        return []

    cases: list[ScenarioCase] = []
    for scenario_dir in sorted(scen_root.glob("Scen_*")):
        if not scenario_dir.is_dir():
            continue
        template_path = _pick_template_file(scenario_dir)
        if not template_path:
            continue
        result_dir = scenario_dir / "Results"
        if not result_dir.exists():
            continue
        for expected_path in sorted(result_dir.glob("*.fdl")):
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


def _pick_output_canvas(doc: dict, expected: dict, preferred_id: str | None = None) -> tuple[dict, dict]:
    actual_canvases = doc["contexts"][0]["canvases"]
    expected_canvases = expected["contexts"][0]["canvases"]
    assert expected_canvases, "Expected scenario result to include canvases"
    expected_out = expected_canvases[-1]

    if preferred_id:
        for canvas in actual_canvases:
            if canvas.get("id") == preferred_id:
                return canvas, expected_out

    return actual_canvases[-1], expected_out


def _pick_primary_fd(canvas: dict) -> dict:
    fds = canvas.get("framing_decisions", [])
    assert fds, "Expected at least one framing decision on output canvas"
    return fds[0]


def _assert_dims_close(actual: dict | None, expected: dict | None, tol: float = 1e-3) -> None:
    assert bool(actual) == bool(expected)
    if actual and expected:
        assert abs(float(actual["width"]) - float(expected["width"])) <= tol
        assert abs(float(actual["height"]) - float(expected["height"])) <= tol


def _assert_points_close(actual: dict | None, expected: dict | None, tol: float = 1e-3) -> None:
    assert bool(actual) == bool(expected)
    if actual and expected:
        assert abs(float(actual["x"]) - float(expected["x"])) <= tol
        assert abs(float(actual["y"]) - float(expected["y"])) <= tol


CASES = _discover_cases()
RUN_ASC_CONFORMANCE = os.environ.get('RUN_ASC_CONFORMANCE', '').lower() in {'1', 'true', 'yes'}
if RUN_ASC_CONFORMANCE and not CASES:
    raise RuntimeError(
        "RUN_ASC_CONFORMANCE=1 but no ASC cases were discovered. "
        "Check ASC_FDL_REPO_PATH and scenario resources."
    )


@pytest.mark.skipif(
    (not RUN_ASC_CONFORMANCE) or (not CASES),
    reason="Set RUN_ASC_CONFORMANCE=1 and ASC_FDL_REPO_PATH to enable ASC parity scenarios.",
)
@pytest.mark.parametrize("case", CASES, ids=[c.name for c in CASES])
def test_workspace_template_apply_matches_asc_scenarios(case: ScenarioCase):
    source_doc = json.loads(case.source_path.read_text(encoding="utf-8"))
    template_doc = json.loads(case.template_path.read_text(encoding="utf-8"))
    expected_doc = json.loads(case.expected_path.read_text(encoding="utf-8"))
    template = (template_doc.get("canvas_templates") or [None])[0]
    assert template, f"No canvas template found in {case.template_path}"

    expected_output_canvas = expected_doc["contexts"][0]["canvases"][-1]
    params = {
        "fdl_json": json.dumps(source_doc),
        "template_json": json.dumps(template),
        "context_index": 0,
        "canvas_index": 0,
        "fd_index": 0,
        "new_canvas_id": expected_output_canvas.get("id"),
        "new_fd_name": "",
    }
    actual_doc = template_ops.apply_fdl_template(params)["fdl"]

    actual_canvas, expected_canvas = _pick_output_canvas(actual_doc, expected_doc, preferred_id=expected_output_canvas.get("id"))
    _assert_dims_close(actual_canvas.get("dimensions"), expected_canvas.get("dimensions"))
    _assert_dims_close(
        actual_canvas.get("effective_dimensions"),
        expected_canvas.get("effective_dimensions"),
    )
    _assert_points_close(
        actual_canvas.get("effective_anchor_point"),
        expected_canvas.get("effective_anchor_point"),
    )

    actual_fd = _pick_primary_fd(actual_canvas)
    expected_fd = _pick_primary_fd(expected_canvas)
    _assert_dims_close(actual_fd.get("dimensions"), expected_fd.get("dimensions"))
    _assert_points_close(actual_fd.get("anchor_point"), expected_fd.get("anchor_point"))
    _assert_dims_close(
        actual_fd.get("protection_dimensions"),
        expected_fd.get("protection_dimensions"),
    )
    _assert_points_close(
        actual_fd.get("protection_anchor_point"),
        expected_fd.get("protection_anchor_point"),
    )


@pytest.mark.skipif(
    (not RUN_ASC_CONFORMANCE) or (not template_ops.HAS_FDL) or (not CASES),
    reason="Set RUN_ASC_CONFORMANCE=1 and install fdl for secondary-oracle checks.",
)
@pytest.mark.parametrize("case", CASES, ids=[c.name for c in CASES])
def test_workspace_template_apply_with_library_matches_asc_scenarios(case: ScenarioCase):
    source_doc = json.loads(case.source_path.read_text(encoding="utf-8"))
    template_doc = json.loads(case.template_path.read_text(encoding="utf-8"))
    expected_doc = json.loads(case.expected_path.read_text(encoding="utf-8"))
    template = (template_doc.get("canvas_templates") or [None])[0]
    assert template

    expected_output_canvas = expected_doc["contexts"][0]["canvases"][-1]
    params = {
        "fdl_json": json.dumps(source_doc),
        "template_json": json.dumps(template),
        "context_index": 0,
        "canvas_index": 0,
        "fd_index": 0,
        "new_canvas_id": expected_output_canvas.get("id"),
        "new_fd_name": "",
    }

    actual_doc = template_ops._apply_with_library(params)["fdl"]  # secondary oracle

    actual_canvas, expected_canvas = _pick_output_canvas(actual_doc, expected_doc, preferred_id=expected_output_canvas.get("id"))
    _assert_dims_close(actual_canvas.get("dimensions"), expected_canvas.get("dimensions"))
    _assert_dims_close(
        actual_canvas.get("effective_dimensions"),
        expected_canvas.get("effective_dimensions"),
    )
    _assert_points_close(
        actual_canvas.get("effective_anchor_point"),
        expected_canvas.get("effective_anchor_point"),
    )

    actual_fd = _pick_primary_fd(actual_canvas)
    expected_fd = _pick_primary_fd(expected_canvas)
    _assert_dims_close(actual_fd.get("dimensions"), expected_fd.get("dimensions"))
    _assert_points_close(actual_fd.get("anchor_point"), expected_fd.get("anchor_point"))
    _assert_dims_close(
        actual_fd.get("protection_dimensions"),
        expected_fd.get("protection_dimensions"),
    )
    _assert_points_close(
        actual_fd.get("protection_anchor_point"),
        expected_fd.get("protection_anchor_point"),
    )

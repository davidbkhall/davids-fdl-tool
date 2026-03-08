"""Deterministic ASC scenario parity tests for template.apply_fdl."""

from __future__ import annotations

import json

import pytest

from fdl_backend.handlers import template_ops

# Derived from ASC "Scenarios for Implementers" samples (Scen 10/11).
SCENARIO_CASES = [
    {
        "name": "scen10_fit_width_maintain_aspect",
        "source": {
            "uuid": "source-scen10",
            "version": {"major": 2, "minor": 0},
            "fdl_creator": "ASC FDL Tools",
            "contexts": [
                {
                    "label": "ARRI ALEXA Mini LF",
                    "context_creator": "ASC FDL Tools",
                    "canvases": [
                        {
                            "label": "4.5K LF Open Gate",
                            "id": "1",
                            "source_canvas_id": "1",
                            "dimensions": {"width": 4448, "height": 3096},
                            "anamorphic_squeeze": 1.0,
                            "framing_decisions": [
                                {
                                    "label": "",
                                    "id": "1-1",
                                    "framing_intent_id": "1",
                                    "dimensions": {"width": 4004, "height": 2252},
                                    "anchor_point": {"x": 222, "y": 422},
                                    "protection_dimensions": {"width": 4448, "height": 2502},
                                    "protection_anchor_point": {"x": 0, "y": 297},
                                }
                            ],
                        }
                    ],
                }
            ],
        },
        "template": {
            "label": "VFX Pull - Custom",
            "id": "VX220310",
            "target_dimensions": {"width": 4000, "height": 2500},
            "target_anamorphic_squeeze": 1,
            "fit_source": "framing_decision.dimensions",
            "fit_method": "width",
            "alignment_method_vertical": "center",
            "alignment_method_horizontal": "center",
            "maximum_dimensions": {"width": 6000, "height": 5000},
            "pad_to_maximum": False,
            "round": {"even": "even", "mode": "round"},
        },
        "expected": {
            "canvas_dimensions": {"width": 4000, "height": 2250},
            "effective_dimensions": {"width": 4000, "height": 2250},
            "effective_anchor": {"x": 0, "y": 0},
            "fd_dimensions": {"width": 4000, "height": 2250},
            "fd_anchor": {"x": 0, "y": 0},
        },
    },
    {
        "name": "scen11_fit_height_maintain_aspect",
        "source": {
            "uuid": "source-scen11",
            "version": {"major": 2, "minor": 0},
            "fdl_creator": "ASC FDL Tools",
            "contexts": [
                {
                    "label": "ARRI ALEXA 65",
                    "context_creator": "ASC FDL Tools",
                    "canvases": [
                        {
                            "label": "Open Gate",
                            "id": "1",
                            "source_canvas_id": "1",
                            "dimensions": {"width": 4320, "height": 3456},
                            "anamorphic_squeeze": 2.0,
                            "framing_decisions": [
                                {
                                    "label": "",
                                    "id": "1-1",
                                    "framing_intent_id": "1",
                                    "dimensions": {"width": 3712, "height": 3110},
                                    "anchor_point": {"x": 304, "y": 173},
                                    "protection_dimensions": {"width": 4124, "height": 3456},
                                    "protection_anchor_point": {"x": 98, "y": 0},
                                }
                            ],
                        }
                    ],
                }
            ],
        },
        "template": {
            "label": "VFX Pull - Custom",
            "id": "VX220310",
            "target_dimensions": {"width": 4000, "height": 2160},
            "target_anamorphic_squeeze": 1,
            "fit_source": "framing_decision.dimensions",
            "fit_method": "height",
            "alignment_method_vertical": "center",
            "alignment_method_horizontal": "center",
            "preserve_from_source_canvas": "framing_decision.dimensions",
            "maximum_dimensions": {"width": 6000, "height": 5000},
            "pad_to_maximum": True,
            "round": {"even": "even", "mode": "round"},
        },
        "expected": {
            "canvas_dimensions": {"width": 6000, "height": 5000},
            "effective_dimensions": {"width": 5156, "height": 2160},
            "effective_anchor": {"x": 422, "y": 1420},
            "fd_dimensions": {"width": 5156, "height": 2160},
            "fd_anchor": {"x": 422, "y": 1420},
        },
    },
]


def _pick_output_canvas(doc: dict, preferred_id: str | None = None) -> dict:
    canvases = doc["contexts"][0]["canvases"]
    if preferred_id:
        for canvas in canvases:
            if canvas.get("id") == preferred_id:
                return canvas
    assert canvases, "Expected at least one canvas"
    return canvases[-1]


def _pick_primary_fd(canvas: dict) -> dict:
    fds = canvas.get("framing_decisions", [])
    assert fds, "Expected at least one framing decision"
    return fds[0]


def _rect_tuple(dims: dict) -> tuple[float, float]:
    return (float(dims["width"]), float(dims["height"]))


def _pt_tuple(pt: dict) -> tuple[float, float]:
    return (float(pt["x"]), float(pt["y"]))


def _assert_dims_close(actual: dict, expected: dict, tol: float = 1.0) -> None:
    aw, ah = _rect_tuple(actual)
    ew, eh = _rect_tuple(expected)
    assert abs(aw - ew) <= tol
    assert abs(ah - eh) <= tol


def _assert_points_close(actual: dict, expected: dict, tol: float = 0.5) -> None:
    ax, ay = _pt_tuple(actual)
    ex, ey = _pt_tuple(expected)
    assert abs(ax - ex) <= tol
    assert abs(ay - ey) <= tol


@pytest.mark.parametrize("case", SCENARIO_CASES, ids=[c["name"] for c in SCENARIO_CASES])
def test_apply_fdl_matches_asc_scenario_geometry(case: dict):
    """Validate `template.apply_fdl` output against ASC implementer scenarios."""
    source = case["source"]
    template = case["template"]
    expected = case["expected"]
    new_canvas_id = f"test-{case['name']}"
    params = {
        "fdl_json": json.dumps(source),
        "template_json": json.dumps(template),
        "context_index": 0,
        "canvas_index": 0,
        "fd_index": 0,
        "new_canvas_id": new_canvas_id,
        "new_fd_name": "Template Output",
    }

    actual = template_ops.apply_fdl_template(params)["fdl"]

    actual_canvas = _pick_output_canvas(actual, preferred_id=new_canvas_id)
    _assert_dims_close(actual_canvas["dimensions"], expected["canvas_dimensions"], tol=1.0)

    actual_eff = actual_canvas.get("effective_dimensions")
    expected_eff = expected.get("effective_dimensions")
    assert bool(actual_eff) == bool(expected_eff)
    if actual_eff and expected_eff:
        _assert_dims_close(actual_eff, expected_eff, tol=1.0)

    actual_eff_anchor = actual_canvas.get("effective_anchor_point")
    expected_eff_anchor = expected.get("effective_anchor")
    assert bool(actual_eff_anchor) == bool(expected_eff_anchor)
    if actual_eff_anchor and expected_eff_anchor:
        _assert_points_close(actual_eff_anchor, expected_eff_anchor, tol=0.5)

    actual_fd = _pick_primary_fd(actual_canvas)
    _assert_dims_close(actual_fd["dimensions"], expected["fd_dimensions"], tol=1.0)
    _assert_points_close(actual_fd["anchor_point"], expected["fd_anchor"], tol=0.5)

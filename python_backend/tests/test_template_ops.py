"""Tests for canvas template operations handler."""

import json

import pytest

from fdl_backend.handlers import template_ops


def test_validate_valid_template():
    """Validate a well-formed template."""
    template = json.dumps(
        {
            "name": "Test Template",
            "pipeline": [
                {"type": "normalize"},
                {"type": "scale", "scale_x": 3840, "scale_y": 2160},
                {"type": "round", "strategy": "even"},
            ],
        }
    )
    result = template_ops.validate({"json_string": template})
    assert result["valid"] is True
    assert len(result["errors"]) == 0


def test_validate_empty_pipeline():
    """Validate catches empty pipeline with warning."""
    template = json.dumps({"pipeline": []})
    result = template_ops.validate({"json_string": template})
    assert result["valid"] is True
    assert len(result["warnings"]) > 0


def test_validate_unknown_step_type():
    """Validate catches unknown step type."""
    template = json.dumps({"pipeline": [{"type": "unknown_step"}]})
    result = template_ops.validate({"json_string": template})
    assert result["valid"] is False
    assert any("Unknown step type" in e["message"] for e in result["errors"])


def test_validate_invalid_json():
    """Validate catches malformed JSON."""
    result = template_ops.validate({"json_string": "{not json"})
    assert result["valid"] is False


def test_apply_scale_template():
    """Apply a scale template to an FDL."""
    template = json.dumps(
        {
            "pipeline": [
                {"type": "scale", "scale_x": 0.5, "scale_y": 0.5},
            ],
        }
    )
    fdl = json.dumps(
        {
            "contexts": [
                {
                    "canvases": [
                        {
                            "id": "c1",
                            "source_canvas_id": "c1",
                            "dimensions": {"width": 4096, "height": 2160},
                            "anamorphic_squeeze": 1.0,
                            "framing_decisions": [],
                        }
                    ],
                }
            ],
        }
    )
    result = template_ops.apply_template({"template_json": template, "fdl_json": fdl})
    canvas = result["fdl"]["contexts"][0]["canvases"][0]
    assert canvas["dimensions"]["width"] == 2048.0
    assert canvas["dimensions"]["height"] == 1080.0


def test_apply_round_template():
    """Apply a round template."""
    template = json.dumps(
        {
            "pipeline": [
                {"type": "scale", "scale_x": 1.333, "scale_y": 1.333},
                {"type": "round", "strategy": "even"},
            ],
        }
    )
    fdl = json.dumps(
        {
            "contexts": [
                {
                    "canvases": [
                        {
                            "id": "c1",
                            "source_canvas_id": "c1",
                            "dimensions": {"width": 1920, "height": 1080},
                            "anamorphic_squeeze": 1.0,
                            "framing_decisions": [],
                        }
                    ],
                }
            ],
        }
    )
    result = template_ops.apply_template({"template_json": template, "fdl_json": fdl})
    canvas = result["fdl"]["contexts"][0]["canvases"][0]
    assert canvas["dimensions"]["width"] == 2560
    assert canvas["dimensions"]["height"] == 1440


def test_preview_steps():
    """Preview shows step-by-step results."""
    template = json.dumps(
        {
            "pipeline": [
                {"type": "normalize"},
                {"type": "scale", "scale_x": 3840, "scale_y": 3840},
                {"type": "round", "strategy": "nearest"},
            ],
        }
    )
    fdl = json.dumps(
        {
            "contexts": [
                {
                    "canvases": [
                        {
                            "id": "c1",
                            "source_canvas_id": "c1",
                            "dimensions": {"width": 4096, "height": 2160},
                            "anamorphic_squeeze": 1.0,
                            "framing_decisions": [],
                        }
                    ],
                }
            ],
        }
    )
    result = template_ops.preview({"template_json": template, "fdl_json": fdl})
    steps = result["steps"]
    assert len(steps) == 4
    assert steps[0]["step"] == "input"
    assert steps[0]["width"] == 4096
    assert steps[1]["step"] == "normalize"
    assert steps[2]["step"] == "scale"
    assert steps[3]["step"] == "round"


def test_export_template():
    """Export template as JSON string."""
    data = {"name": "Test", "pipeline": [{"type": "normalize"}]}
    result = template_ops.export_template({"template_data": data})
    assert "json_string" in result
    parsed = json.loads(result["json_string"])
    assert parsed["name"] == "Test"


def test_apply_fdl_template_response_schema_success():
    """apply_fdl_template returns expected top-level schema on success."""
    source = {
        "uuid": "doc-1",
        "version": {"major": 2, "minor": 0},
        "fdl_creator": "FDL Tool Tests",
        "contexts": [
            {
                "label": "ctx",
                "context_creator": "tests",
                "canvases": [
                    {
                        "id": "canvas-1",
                        "label": "canvas",
                        "source_canvas_id": "canvas-1",
                        "dimensions": {"width": 3840, "height": 2160},
                        "anamorphic_squeeze": 1.0,
                        "framing_decisions": [
                            {
                                "id": "fd-1",
                                "label": "fd",
                                "framing_intent_id": "intent-1",
                                "dimensions": {"width": 3840.0, "height": 1608.0},
                                "anchor_point": {"x": 0.0, "y": 276.0},
                            }
                        ],
                    }
                ],
            }
        ],
    }
    template = {
        "id": "tpl-1",
        "label": "UHD",
        "target_dimensions": {"width": 1920, "height": 1080},
        "target_anamorphic_squeeze": 1.0,
        "fit_source": "framing_decision.dimensions",
        "fit_method": "fit_all",
        "alignment_method_horizontal": "center",
        "alignment_method_vertical": "center",
        "round": {"even": "even", "mode": "round"},
        "pad_to_maximum": False,
    }

    result = template_ops.apply_fdl_template(
        {
            "fdl_json": json.dumps(source),
            "template_json": json.dumps(template),
            "context_index": 0,
            "canvas_index": 0,
            "fd_index": 0,
            "new_canvas_id": "new-canvas",
            "new_fd_name": "new-fd",
        }
    )
    assert isinstance(result, dict)
    assert "fdl" in result
    assert isinstance(result["fdl"], dict)

    contexts = result["fdl"].get("contexts")
    assert isinstance(contexts, list)
    assert contexts
    canvases = contexts[0].get("canvases")
    assert isinstance(canvases, list)
    assert canvases
    framing_decisions = canvases[-1].get("framing_decisions")
    assert isinstance(framing_decisions, list)
    assert framing_decisions
    assert "dimensions" in framing_decisions[0]


def test_apply_fdl_template_invalid_index_errors():
    """apply_fdl_template raises when requested selection indexes are invalid."""
    source = {
        "uuid": "doc-2",
        "version": {"major": 2, "minor": 0},
        "fdl_creator": "FDL Tool Tests",
        "contexts": [],
    }
    template = {
        "id": "tpl-2",
        "label": "UHD",
        "target_dimensions": {"width": 1920, "height": 1080},
        "fit_source": "framing_decision.dimensions",
        "fit_method": "fit_all",
        "alignment_method_horizontal": "center",
        "alignment_method_vertical": "center",
        "round": {"even": "even", "mode": "round"},
    }

    with pytest.raises(Exception):
        template_ops.apply_fdl_template(
            {
                "fdl_json": json.dumps(source),
                "template_json": json.dumps(template),
                "context_index": 99,
                "canvas_index": 0,
                "fd_index": 0,
            }
        )

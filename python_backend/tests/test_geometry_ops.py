"""Tests for geometry operations handler.

These tests exercise the geometry handler functions. When the fdl library
is not installed, tests that require it are skipped.
"""

import pytest

from fdl_backend.utils.fdl_convert import HAS_FDL

if HAS_FDL:
    from fdl_backend.handlers import geometry_ops

requires_fdl = pytest.mark.skipif(not HAS_FDL, reason="ASC fdl library not installed")


SAMPLE_FDL = {
    "uuid": "geo_test",
    "version": {"major": 2, "minor": 0},
    "fdl_creator": "test",
    "framing_intents": [
        {"id": "scope", "aspect_ratio": {"width": 239, "height": 100}},
        {"id": "hd", "aspect_ratio": {"width": 16, "height": 9}},
    ],
    "contexts": [
        {
            "label": "Test Context",
            "context_creator": "test",
            "canvases": [
                {
                    "id": "c1",
                    "source_canvas_id": "c1",
                    "label": "4K",
                    "dimensions": {"width": 4096, "height": 2160},
                    "anamorphic_squeeze": 1.0,
                    "framing_decisions": [
                        {
                            "id": "c1-scope",
                            "label": "2.39:1",
                            "framing_intent_id": "scope",
                            "dimensions": {"width": 4096.0, "height": 1716.0},
                            "anchor_point": {"x": 0.0, "y": 222.0},
                        },
                        {
                            "id": "c1-hd",
                            "label": "16:9",
                            "framing_intent_id": "hd",
                            "dimensions": {"width": 3840.0, "height": 2160.0},
                            "anchor_point": {"x": 128.0, "y": 0.0},
                        },
                    ],
                }
            ],
        }
    ],
}

SAMPLE_FDL_WITH_EFFECTIVE = {
    "uuid": "geo_eff_test",
    "version": {"major": 2, "minor": 0},
    "fdl_creator": "test",
    "framing_intents": [
        {"id": "scope", "aspect_ratio": {"width": 239, "height": 100}},
    ],
    "contexts": [
        {
            "label": "Test Context",
            "context_creator": "test",
            "canvases": [
                {
                    "id": "c1",
                    "source_canvas_id": "c1",
                    "label": "4K with effective",
                    "dimensions": {"width": 4096, "height": 2160},
                    "effective_dimensions": {"width": 3840, "height": 2160},
                    "effective_anchor_point": {"x": 128.0, "y": 0.0},
                    "anamorphic_squeeze": 1.0,
                    "framing_decisions": [
                        {
                            "id": "c1-scope",
                            "label": "2.39:1",
                            "framing_intent_id": "scope",
                            "dimensions": {"width": 3840.0, "height": 1608.0},
                            "anchor_point": {"x": 0.0, "y": 276.0},
                        },
                    ],
                }
            ],
        }
    ],
}


@requires_fdl
def test_compute_rects_basic():
    """Compute rects for a basic FDL with two framing decisions."""
    result = geometry_ops.compute_rects({"fdl_data": SAMPLE_FDL})
    assert "contexts" in result
    assert len(result["contexts"]) == 1

    ctx = result["contexts"][0]
    assert len(ctx["canvases"]) == 1

    canvas = ctx["canvases"][0]
    assert canvas["canvas_rect"]["width"] == 4096
    assert canvas["canvas_rect"]["height"] == 2160
    assert canvas["canvas_rect"]["x"] == 0
    assert canvas["canvas_rect"]["y"] == 0
    assert canvas["effective_rect"] is None

    assert len(canvas["framing_decisions"]) == 2
    fd1 = canvas["framing_decisions"][0]
    assert fd1["label"] == "2.39:1"
    assert fd1["framing_rect"]["width"] == 4096
    assert fd1["framing_rect"]["height"] == 1716
    assert fd1["protection_rect"] is None


@requires_fdl
def test_compute_rects_with_effective():
    """Compute rects for an FDL with effective dimensions."""
    result = geometry_ops.compute_rects({"fdl_data": SAMPLE_FDL_WITH_EFFECTIVE})
    canvas = result["contexts"][0]["canvases"][0]
    assert canvas["effective_rect"] is not None
    assert canvas["effective_rect"]["width"] == 3840
    assert canvas["effective_rect"]["height"] == 2160


@requires_fdl
def test_compute_rects_from_json_string():
    """Compute rects from a JSON string instead of dict."""
    import json

    result = geometry_ops.compute_rects({"json_string": json.dumps(SAMPLE_FDL)})
    assert "contexts" in result
    assert len(result["contexts"]) == 1


@requires_fdl
def test_compute_rects_missing_input():
    """compute_rects raises when no input provided."""
    with pytest.raises(ValueError, match="Either fdl_data or json_string"):
        geometry_ops.compute_rects({})


@requires_fdl
def test_apply_alignment_center():
    """Apply center/center alignment to a framing decision."""
    result = geometry_ops.apply_alignment(
        {
            "fdl_data": SAMPLE_FDL,
            "fd_index": 1,
            "h_align": "center",
            "v_align": "center",
        }
    )
    assert "framing_rect" in result
    rect = result["framing_rect"]
    assert rect["width"] == 3840
    assert rect["height"] == 2160

    assert rect["x"] == pytest.approx(128.0, abs=1)
    assert rect["y"] == pytest.approx(0.0, abs=1)


@requires_fdl
def test_apply_alignment_left_top():
    """Apply left/top alignment."""
    result = geometry_ops.apply_alignment(
        {
            "fdl_data": SAMPLE_FDL,
            "fd_index": 1,
            "h_align": "left",
            "v_align": "top",
        }
    )
    rect = result["framing_rect"]
    assert rect["x"] == pytest.approx(0.0, abs=1)
    assert rect["y"] == pytest.approx(0.0, abs=1)


@requires_fdl
def test_apply_alignment_right_bottom():
    """Apply right/bottom alignment."""
    result = geometry_ops.apply_alignment(
        {
            "fdl_data": SAMPLE_FDL,
            "fd_index": 1,
            "h_align": "right",
            "v_align": "bottom",
        }
    )
    rect = result["framing_rect"]
    assert rect["x"] == pytest.approx(256.0, abs=1)
    assert rect["y"] == pytest.approx(0.0, abs=1)


@requires_fdl
def test_apply_alignment_returns_updated_fdl():
    """apply_alignment returns the modified FDL dict."""
    result = geometry_ops.apply_alignment(
        {
            "fdl_data": SAMPLE_FDL,
            "fd_index": 0,
            "h_align": "center",
            "v_align": "center",
        }
    )
    assert "fdl" in result


@requires_fdl
def test_compute_protection_basic():
    """Compute protection dimensions from percentage."""
    result = geometry_ops.compute_protection(
        {
            "framing_width": 3840,
            "framing_height": 2160,
            "protection_percent": 10.0,
        }
    )
    assert result["protection_width"] == pytest.approx(4224.0)
    assert result["protection_height"] == pytest.approx(2376.0)


@requires_fdl
def test_compute_protection_zero_percent():
    """Zero protection percent yields same dimensions as framing."""
    result = geometry_ops.compute_protection(
        {
            "framing_width": 4096,
            "framing_height": 1716,
            "protection_percent": 0.0,
        }
    )
    assert result["protection_width"] == pytest.approx(4096.0)
    assert result["protection_height"] == pytest.approx(1716.0)


def test_compute_protection_no_fdl_library():
    """compute_protection works for basic math without fdl library."""
    from fdl_backend.handlers import geometry_ops as geo

    result = geo.compute_protection(
        {
            "framing_width": 1920,
            "framing_height": 1080,
            "protection_percent": 5.0,
        }
    )
    assert result["protection_width"] == pytest.approx(2016.0)
    assert result["protection_height"] == pytest.approx(1134.0)

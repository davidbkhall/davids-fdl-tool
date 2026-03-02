"""Tests for chart generation handler."""

import json

from fdl_backend.handlers import chart_gen


def test_generate_fdl_basic():
    """Generate an FDL from chart config."""
    result = chart_gen.generate_fdl({
        "canvas_width": 4096,
        "canvas_height": 2160,
        "framelines": [
            {"label": "2.39:1", "width": 4096, "height": 1716},
            {"label": "16:9", "width": 3840, "height": 2160},
        ],
    })
    fdl = result["fdl"]
    assert fdl["header"]["version"] == "2.0.1"
    canvas = fdl["fdl_contexts"][0]["canvases"][0]
    assert canvas["dimensions"]["width"] == 4096
    assert canvas["dimensions"]["height"] == 2160
    assert len(canvas["framing_decisions"]) == 2


def test_generate_svg():
    """Generate SVG chart (requires svgwrite)."""
    try:
        result = chart_gen.generate_svg({
            "canvas_width": 4096,
            "canvas_height": 2160,
            "framelines": [
                {"label": "2.39:1", "width": 4096, "height": 1716},
            ],
            "title": "Test Chart",
        })
        assert "svg" in result
        assert "<svg" in result["svg"]
    except ImportError:
        pass  # svgwrite not installed


def test_generate_png():
    """Generate PNG chart (requires Pillow)."""
    try:
        result = chart_gen.generate_png({
            "canvas_width": 4096,
            "canvas_height": 2160,
            "framelines": [
                {"label": "1.85:1", "width": 3996, "height": 2160},
            ],
            "title": "Test Chart",
        })
        assert "png_base64" in result
        assert len(result["png_base64"]) > 100
    except ImportError:
        pass  # Pillow not installed

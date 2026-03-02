"""Tests for chart generation handler."""

from fdl_backend.handlers import chart_gen


def test_generate_fdl_basic():
    """Generate an FDL from chart config."""
    result = chart_gen.generate_fdl(
        {
            "canvas_width": 4096,
            "canvas_height": 2160,
            "framelines": [
                {"label": "2.39:1", "width": 4096, "height": 1716},
                {"label": "16:9", "width": 3840, "height": 2160},
            ],
        }
    )
    fdl = result["fdl"]
    contexts = fdl["contexts"]
    assert len(contexts) >= 1
    canvas = contexts[0]["canvases"][0]
    dims = canvas["dimensions"]
    assert dims["width"] in (4096, 4096.0)
    assert dims["height"] in (2160, 2160.0)
    fds = canvas["framing_decisions"]
    assert len(fds) == 2


def test_generate_fdl_with_alignment():
    """Generate FDL with explicit alignment."""
    result = chart_gen.generate_fdl(
        {
            "canvas_width": 4096,
            "canvas_height": 2160,
            "framelines": [
                {"label": "Left-Top", "width": 3840, "height": 2160, "h_align": "left", "v_align": "top"},
            ],
        }
    )
    fdl = result["fdl"]
    canvas = fdl["contexts"][0]["canvases"][0]
    fds = canvas["framing_decisions"]
    assert len(fds) == 1


def test_generate_fdl_with_protection():
    """Generate FDL with protection dimensions."""
    result = chart_gen.generate_fdl(
        {
            "canvas_width": 4096,
            "canvas_height": 2160,
            "framelines": [
                {
                    "label": "Protected",
                    "width": 3840,
                    "height": 1608,
                    "protection_width": 4000,
                    "protection_height": 1680,
                },
            ],
        }
    )
    fdl = result["fdl"]
    canvas = fdl["contexts"][0]["canvases"][0]
    fds = canvas["framing_decisions"]
    assert len(fds) == 1


def test_generate_svg():
    """Generate SVG chart (requires svgwrite)."""
    try:
        result = chart_gen.generate_svg(
            {
                "canvas_width": 4096,
                "canvas_height": 2160,
                "framelines": [
                    {"label": "2.39:1", "width": 4096, "height": 1716},
                ],
                "title": "Test Chart",
            }
        )
        assert "svg" in result
        assert "<svg" in result["svg"]
    except ImportError:
        pass


def test_generate_svg_with_layers():
    """Generate SVG with grid, crosshairs, and effective area."""
    try:
        result = chart_gen.generate_svg(
            {
                "canvas_width": 4096,
                "canvas_height": 2160,
                "framelines": [
                    {"label": "2.39:1", "width": 4096, "height": 1716},
                ],
                "title": "Test Chart",
                "effective_width": 3840,
                "effective_height": 2160,
                "show_crosshairs": True,
                "show_grid": True,
                "grid_spacing": 500,
            }
        )
        assert "svg" in result
        assert "<svg" in result["svg"]
    except ImportError:
        pass


def test_generate_png():
    """Generate PNG chart (requires Pillow)."""
    try:
        result = chart_gen.generate_png(
            {
                "canvas_width": 4096,
                "canvas_height": 2160,
                "framelines": [
                    {"label": "1.85:1", "width": 3996, "height": 2160},
                ],
                "title": "Test Chart",
            }
        )
        assert "png_base64" in result
        assert len(result["png_base64"]) > 100
    except ImportError:
        pass

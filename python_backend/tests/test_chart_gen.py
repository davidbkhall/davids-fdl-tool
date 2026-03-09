"""Tests for chart generation handler."""

from fdl_backend.handlers import chart_gen
from fdl_backend.utils.chart_scene import ChartScene


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
    """Generate SVG chart (requires svgwrite); returns a temp file path."""
    import os

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
        assert "file_path" in result
        assert result["format"] == "svg"
        assert os.path.isfile(result["file_path"])
        with open(result["file_path"]) as f:
            svg_content = f.read()
        assert "<svg" in svg_content
    except ImportError:
        pass


def test_generate_svg_with_layers():
    """Generate SVG with grid, crosshairs, and effective area."""
    import os

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
        assert "file_path" in result
        assert result["format"] == "svg"
        assert os.path.isfile(result["file_path"])
    except ImportError:
        pass


def test_generate_png():
    """Generate PNG chart (requires Pillow); returns a temp file path."""
    import os

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
        assert "file_path" in result
        assert result["format"] == "png"
        assert os.path.isfile(result["file_path"])
    except ImportError:
        pass


def test_generate_tiff():
    """Generate TIFF chart (requires Pillow); returns a temp file path."""
    import os

    try:
        result = chart_gen.generate_tiff(
            {
                "canvas_width": 4096,
                "canvas_height": 2160,
                "framelines": [
                    {"label": "2.00:1", "width": 4096, "height": 2048},
                ],
                "title": "Test Chart",
                "dpi": 300,
            }
        )
        assert "file_path" in result
        assert result["format"] == "tiff"
        assert os.path.isfile(result["file_path"])
    except ImportError:
        pass


def test_generate_pdf():
    """Generate PDF chart (requires cairosvg + svgwrite); returns a temp file path."""
    import os

    try:
        result = chart_gen.generate_pdf(
            {
                "canvas_width": 4096,
                "canvas_height": 2160,
                "framelines": [{"label": "2.00:1", "width": 4096, "height": 2048}],
                "title": "Test Chart",
            }
        )
        assert "file_path" in result
        assert result["format"] == "pdf"
        assert os.path.isfile(result["file_path"])
    except ImportError:
        pass


def test_generate_svg_with_phase3_overlays():
    """Generate SVG with markers, burn-ins, and print-safe margin."""
    import os

    try:
        result = chart_gen.generate_svg(
            {
                "canvas_width": 4096,
                "canvas_height": 2160,
                "framelines": [{"label": "2.39:1", "width": 4096, "height": 1716}],
                "show_center_marker": True,
                "show_format_arrows": True,
                "print_safe_margin_percent": 5.0,
                "burn_in": {
                    "title": "Scene 12A",
                    "director": "Director Name",
                    "dop": "DP Name",
                },
            }
        )
        assert "file_path" in result
        assert os.path.isfile(result["file_path"])
        with open(result["file_path"]) as f:
            svg = f.read()
        assert "<svg" in svg
    except ImportError:
        pass


def test_generate_svg_with_white_background_and_siemens_stars():
    """Generate SVG with white chart mode and four Siemens stars."""
    import os

    try:
        result = chart_gen.generate_svg(
            {
                "canvas_width": 4608,
                "canvas_height": 3164,
                "framelines": [{"label": "Main", "width": 4608, "height": 1928}],
                "background_theme": "white",
                "show_siemens_stars": True,
                "show_chart_markers": True,
            }
        )
        assert "file_path" in result
        assert os.path.isfile(result["file_path"])
        with open(result["file_path"]) as f:
            svg = f.read()
        assert "<svg" in svg
        assert 'fill="#FFFFFF"' in svg
        # Siemens stars are now injected from bundled SVG path geometry.
        assert svg.count("<path") >= 16
    except ImportError:
        pass


def test_chart_scene_from_params_normalizes_defaults():
    scene = ChartScene.from_params(
        {
            "canvas_width": 3000,
            "canvas_height": 2000,
            "framelines": [{"label": "Main", "width": 2400, "height": 1350}],
            "layers": {"canvas": True, "effective": False},
        },
        default_colors=chart_gen.FRAMELINE_COLORS,
    )
    assert scene.canvas_width == 3000
    assert scene.canvas_height == 2000
    assert scene.layers["effective"] is False
    assert scene.layers["framing"] is True
    assert len(scene.framelines) == 1
    assert scene.framelines[0].label == "Main"


def test_chart_scene_phase3_fields():
    scene = ChartScene.from_params(
        {
            "canvas_width": 2048,
            "canvas_height": 1152,
            "show_center_marker": True,
            "show_format_arrows": True,
            "print_safe_margin_percent": 7.5,
            "burn_in": {"title": "Burn", "sample_text_1": "S1"},
        },
        default_colors=chart_gen.FRAMELINE_COLORS,
    )
    assert scene.show_center_marker is True
    assert scene.show_format_arrows is True
    assert scene.print_safe_margin_percent == 7.5
    assert scene.burn_in is not None
    assert scene.burn_in.title == "Burn"


def test_chart_scene_style_and_logo_fields():
    scene = ChartScene.from_params(
        {
            "canvas_width": 2048,
            "canvas_height": 1080,
            "framelines": [{"label": "Main", "width": 1920, "height": 1080, "style": "corners", "style_length": 0.12}],
            "logo": {"text": "My Show", "position": "bottom_right"},
        },
        default_colors=chart_gen.FRAMELINE_COLORS,
    )
    assert scene.logo is not None
    assert scene.logo.text == "My Show"
    assert scene.logo.position == "bottom_right"
    assert scene.framelines[0].style == "corners"
    assert scene.framelines[0].style_length == 0.12


def test_chart_scene_phase4_white_theme_and_star_fields():
    scene = ChartScene.from_params(
        {
            "canvas_width": 4608,
            "canvas_height": 3164,
            "background_theme": "white",
            "show_siemens_stars": True,
            "show_chart_markers": True,
            "logo": {
                "text": "Test",
                "position": "top_left",
                "scale": 1.3,
                "offset_x": 12,
                "offset_y": -8,
            },
        },
        default_colors=chart_gen.FRAMELINE_COLORS,
    )
    assert scene.background_theme == "white"
    assert scene.show_siemens_stars is True
    assert scene.show_chart_markers is True
    assert scene.logo is not None
    assert scene.logo.scale == 1.3
    assert scene.logo.offset_x == 12
    assert scene.logo.offset_y == -8


def test_auto_dpi_selection():
    assert chart_gen._auto_dpi(2048, 1152) == 600
    assert chart_gen._auto_dpi(4096, 2160) == 300
    assert chart_gen._auto_dpi(8192, 4320) == 240

"""Export reliability acceptance tests for chart generator outputs."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

from fdl_backend.handlers import chart_gen


def _sample_params() -> dict:
    return {
        "canvas_width": 4608,
        "canvas_height": 3164,
        "title": "",
        "background_theme": "white",
        "preview_desqueeze": True,
        "anamorphic_squeeze": 2.0,
        "show_labels": False,
        "show_boundary_arrows": True,
        "boundary_arrow_scale": 1.0,
        "show_siemens_stars": True,
        "show_center_marker": False,
        "layers": {
            "canvas": True,
            "effective": True,
            "protection": True,
            "framing": True,
        },
        "effective_width": 4320,
        "effective_height": 2430,
        "framelines": [
            {
                "label": "Scope",
                "width": 4096,
                "height": 1716,
                "anchor_x": 256,
                "anchor_y": 724,
                "protection_width": 4320,
                "protection_height": 1810,
                "protection_anchor_x": 144,
                "protection_anchor_y": 677,
                "color": "#FF3B30",
            }
        ],
    }


def _assert_file(path: str, min_bytes: int = 32) -> Path:
    p = Path(path)
    assert p.exists(), f"Expected export file to exist: {p}"
    assert p.stat().st_size >= min_bytes, f"Expected non-trivial export size for {p}"
    return p


def test_export_svg_reliable() -> None:
    out = chart_gen.generate_svg(_sample_params())
    assert out.get("format") == "svg"
    p = _assert_file(out["file_path"], min_bytes=128)
    text = p.read_text(encoding="utf-8")
    assert "<svg" in text
    assert "viewBox=" in text


def test_export_png_reliable() -> None:
    out = chart_gen.generate_png(_sample_params())
    assert out.get("format") == "png"
    p = _assert_file(out["file_path"], min_bytes=256)
    with p.open("rb") as f:
        assert f.read(8) == bytes([137, 80, 78, 71, 13, 10, 26, 10])


def test_export_tiff_reliable() -> None:
    out = chart_gen.generate_tiff(_sample_params())
    assert out.get("format") == "tiff"
    p = _assert_file(out["file_path"], min_bytes=256)
    with p.open("rb") as f:
        hdr = f.read(4)
    assert hdr[:2] in (b"II", b"MM")


def test_export_pdf_reliable() -> None:
    out = chart_gen.generate_pdf(_sample_params())
    assert out.get("format") == "pdf"
    p = _assert_file(out["file_path"], min_bytes=128)
    with p.open("rb") as f:
        assert f.read(5) == b"%PDF-"


def test_export_fdl_reliable() -> None:
    out = chart_gen.generate_fdl(_sample_params())
    fdl = out.get("fdl")
    assert isinstance(fdl, dict)
    contexts = fdl.get("contexts") or []
    assert contexts
    canvases = contexts[0].get("canvases") or []
    assert canvases
    assert canvases[0].get("framing_decisions")


def test_export_fdl_json_roundtrip_file_reliable() -> None:
    params = _sample_params()
    out = chart_gen.generate_fdl(params)
    fdl = out.get("fdl")
    assert isinstance(fdl, dict)

    # Simulate the app writing an `FDL (.fdl)` JSON export.
    with tempfile.TemporaryDirectory() as tmpdir:
        fdl_path = Path(tmpdir) / "chart_export.fdl"
        fdl_path.write_text(json.dumps(fdl, indent=2), encoding="utf-8")
        assert fdl_path.exists()
        assert fdl_path.suffix == ".fdl"

        loaded = json.loads(fdl_path.read_text(encoding="utf-8"))

    contexts = loaded.get("contexts") or []
    assert contexts
    canvases = contexts[0].get("canvases") or []
    assert canvases

    canvas = canvases[0]
    dims = canvas.get("dimensions") or {}
    assert int(dims.get("width", 0)) == params["canvas_width"]
    assert int(dims.get("height", 0)) == params["canvas_height"]

    fds = canvas.get("framing_decisions") or []
    assert fds
    fd = fds[0]
    assert fd.get("dimensions")
    assert fd.get("anchor_point")


def test_multi_format_sequence_reliable() -> None:
    params = _sample_params()
    outputs = [
        chart_gen.generate_svg(params),
        chart_gen.generate_png(params),
        chart_gen.generate_tiff(params),
        chart_gen.generate_pdf(params),
    ]
    paths = []
    for out in outputs:
        assert "file_path" in out
        paths.append(_assert_file(out["file_path"]).as_posix())
    # Ensure each call writes a distinct output path.
    assert len(paths) == len(set(paths))

    # FDL export should also succeed in the same sequence.
    fdl = chart_gen.generate_fdl(params)["fdl"]
    json.dumps(fdl)  # serializable

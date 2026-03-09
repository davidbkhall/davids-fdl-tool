"""Framing chart generation: SVG, PNG, and FDL output.

SVG/PNG rendering uses svgwrite/Pillow directly. FDL generation uses the
ASC fdl library for spec-compliant document construction with anchor
positioning and protection support.
"""

from __future__ import annotations

import base64
import io
import os
import re
import tempfile
import uuid
from pathlib import Path
from typing import Any

from fdl_backend.utils.chart_scene import ChartScene
from fdl_backend.utils.fdl_convert import HAS_FDL

if HAS_FDL:
    from fdl_backend.utils.fdl_convert import (
        add_canvas_to_context,
        add_context_to_fdl,
        add_framing_decision_to_canvas,
        build_fdl,
        fdl_to_dict,
    )

try:
    import svgwrite
except ImportError:
    svgwrite = None

try:
    import cairosvg
except ImportError:
    cairosvg = None

try:
    from PIL import Image, ImageDraw
except ImportError:
    Image = None


FRAMELINE_COLORS = [
    "#FF3B30",
    "#007AFF",
    "#34C759",
    "#FF9500",
    "#AF52DE",
    "#FFD60A",
    "#5AC8FA",
    "#FF2D55",
]

_SIEMENS_SVG_PATH = Path(__file__).resolve().parents[1] / "resources" / "siemens_star.svg"
_SIEMENS_SVG_TEXT = _SIEMENS_SVG_PATH.read_text(encoding="utf-8") if _SIEMENS_SVG_PATH.exists() else ""
_SIEMENS_PATHS = re.findall(r'd="([^"]+)"', _SIEMENS_SVG_TEXT) if _SIEMENS_SVG_TEXT else []
_SIEMENS_PNG_CACHE: dict[tuple[int, int], Any] = {}


def _auto_dpi(canvas_w: int, canvas_h: int) -> int:
    """Pick export DPI automatically based on output size."""
    long_edge = max(canvas_w, canvas_h)
    if long_edge <= 3000:
        return 600
    if long_edge <= 6000:
        return 300
    return 240


def _line_width(base: float, cw: int, ch: int) -> float:
    """Scale line width for clip-safe readability."""
    factor = max(1.0, min(cw, ch) / 1080.0)
    return max(1.0, base * factor)


def _font_size(base: float, cw: int, ch: int) -> float:
    """Scale font size for clip-safe readability."""
    factor = max(1.0, min(cw, ch) / 1080.0)
    return max(9.0, base * factor)


def generate_svg(params: dict) -> dict:
    """Generate a framing chart as SVG.

    Params:
        canvas_width: int — canvas width in pixels
        canvas_height: int — canvas height in pixels
        framelines: list of {label, width, height, color?, h_align?, v_align?}
        title: str — chart title
        show_labels: bool — whether to draw labels
        padding: int — padding around chart
        effective_width: int — effective area width (optional)
        effective_height: int — effective area height (optional)
        show_crosshairs: bool — draw crosshairs at framing centers
        show_grid: bool — draw grid overlay
        grid_spacing: int — grid spacing in canvas pixels
        anamorphic_squeeze: float — squeeze factor (1.0 = spherical)
        show_squeeze_circle: bool — draw anamorphic squeeze reference
        layers: dict — layer visibility overrides
    """
    if svgwrite is None:
        raise ImportError("svgwrite is required for SVG generation. Install with: pip install svgwrite")

    scene = ChartScene.from_params(params, default_colors=FRAMELINE_COLORS)
    canvas_w = scene.canvas_width
    canvas_h = scene.canvas_height
    title = scene.title
    show_labels = scene.show_labels
    padding = scene.padding
    eff_w = scene.effective_width
    eff_h = scene.effective_height
    show_crosshairs = scene.show_crosshairs
    show_grid = scene.show_grid
    grid_spacing = scene.grid_spacing
    squeeze = scene.anamorphic_squeeze
    show_squeeze_circle = scene.show_squeeze_circle
    layers = scene.layers

    show_canvas = layers.get("canvas", True)
    show_effective = layers.get("effective", True)
    show_protection = layers.get("protection", True)
    show_framing = layers.get("framing", True)

    preview_desqueeze = bool(params.get("preview_desqueeze", False))
    display_x = squeeze if preview_desqueeze and squeeze > 1.0 else 1.0
    scale = min(800 / max(1.0, canvas_w * display_x), 600 / canvas_h)
    svg_w = int(canvas_w * scale * display_x) + padding * 2
    svg_h = int(canvas_h * scale) + padding * 2 + (40 if title else 0)

    dwg = svgwrite.Drawing(size=(svg_w, svg_h))
    bg = "#1a1a1a"
    fg = "#2A2A2A" if scene.background_theme == "white" else "white"
    dim_fg = "#666666" if scene.background_theme == "white" else "#999999"
    dwg.add(dwg.rect(insert=(0, 0), size=(svg_w, svg_h), fill=bg))

    title_offset = 0
    if title:
        title_offset = 40
        dwg.add(
            dwg.text(
                title,
                insert=(svg_w / 2, 28),
                fill=fg,
                font_size=f"{_font_size(16.0, canvas_w, canvas_h):.0f}px",
                font_family="sans-serif",
                text_anchor="middle",
            )
        )

    cx, cy = padding, padding + title_offset
    cw, ch = int(canvas_w * scale * display_x), int(canvas_h * scale)
    line_minor = _line_width(1.0, cw, ch)
    line_major = _line_width(2.0, cw, ch)
    font_small = _font_size(10.0, cw, ch)
    label_fg = "#2F2F2F" if scene.background_theme == "white" else "#E4E4E4"

    if show_canvas:
        if scene.background_theme == "white":
            dwg.add(dwg.rect(insert=(cx, cy), size=(cw, ch), fill="#FFFFFF"))
        dwg.add(dwg.rect(insert=(cx, cy), size=(cw, ch), fill="none", stroke="#444", stroke_width=line_minor))
    if show_grid:
        _draw_svg_grid(dwg, cx, cy, cw, ch, canvas_w, canvas_h, grid_spacing, scale)

    if show_effective and eff_w and eff_h:
        ew = int(eff_w * scale * display_x)
        eh = int(eff_h * scale)
        ex = cx + int(((canvas_w - eff_w) / 2.0) * scale * display_x)
        ey = cy + int(((canvas_h - eff_h) / 2.0) * scale)
        exi, eyi, ewi, ehi = _adjusted_rect_for_stroke(ex, ey, ew, eh, _line_width(1.5, cw, ch))
        dwg.add(
            dwg.rect(
                insert=(exi, eyi), size=(ewi, ehi), fill="none", stroke="#5AC8FA", stroke_width=_line_width(1.5, cw, ch)
            )
        )
        if show_labels:
            dwg.add(
                dwg.text(
                    f"Effective: {eff_w}\u00d7{eff_h}",
                    insert=(ex + 4, ey + 14),
                    fill=label_fg,
                    font_size=f"{font_small:.0f}px",
                    font_family="monospace",
                )
            )
            dwg.add(
                dwg.text(
                    f"Anchor: {int((canvas_w - eff_w) / 2)}, {int((canvas_h - eff_h) / 2)}",
                    insert=(ex + 4, min(ey + eh - 4, ey + 28)),
                    fill=label_fg,
                    font_size=f"{max(8.0, font_small - 1):.0f}px",
                    font_family="monospace",
                )
            )

    occupied_rects: list[tuple[float, float, float, float]] = []

    for fl in scene.framelines:
        fw = fl.width
        fh = fl.height
        color = fl.color
        label = fl.label
        h_align = fl.h_align
        v_align = fl.v_align

        sx, sy, sw, sh = _compute_frameline_position(
            cx,
            cy,
            cw,
            ch,
            fw,
            fh,
            canvas_w,
            canvas_h,
            scale,
            scale * display_x,
            scale,
            h_align,
            v_align,
            fl.anchor_x,
            fl.anchor_y,
        )

        prot_w = fl.protection_width
        prot_h = fl.protection_height
        if show_protection and prot_w and prot_h:
            pw = int(prot_w * scale * display_x)
            ph = int(prot_h * scale)
            prot_h_align = h_align
            prot_v_align = v_align
            px, py, _, _ = _compute_frameline_position(
                cx,
                cy,
                cw,
                ch,
                prot_w,
                prot_h,
                canvas_w,
                canvas_h,
                scale,
                scale * display_x,
                scale,
                prot_h_align,
                prot_v_align,
                fl.protection_anchor_x,
                fl.protection_anchor_y,
            )
            pxi, pyi, pwi, phi = _adjusted_rect_for_stroke(px, py, pw, ph, line_minor)
            dwg.add(
                dwg.rect(
                    insert=(pxi, pyi),
                    size=(pwi, phi),
                    fill="none",
                    stroke="#FF9500",
                    stroke_width=line_minor,
                    stroke_dasharray="6,3",
                )
            )
            occupied_rects.append((px, py, px + pw, py + ph))

        if show_framing:
            occupied_rects.append((sx, sy, sx + sw, sy + sh))
            _draw_svg_frameline_style(
                dwg,
                sx,
                sy,
                sw,
                sh,
                color,
                line_major,
                fl.style,
                fl.style_length,
            )

            if show_crosshairs:
                center_x = sx + sw / 2
                center_y = sy + sh / 2
                dwg.add(
                    dwg.line(
                        start=(center_x - 8, center_y),
                        end=(center_x + 8, center_y),
                        stroke=color,
                        stroke_width=line_minor,
                    )
                )
                dwg.add(
                    dwg.line(
                        start=(center_x, center_y - 8),
                        end=(center_x, center_y + 8),
                        stroke=color,
                        stroke_width=line_minor,
                    )
                )

            if show_labels:
                label_size = max(9.0, min(14.0, min(sw, sh) * 0.055))
                label_x = min(max(sx + (sw / 2), cx + 32), cx + cw - 32)
                label_y = min(max(sy + 14, cy + 14), cy + ch - 20)
                dwg.add(
                    dwg.text(
                        label or "",
                        insert=(label_x, label_y),
                        fill=label_fg,
                        font_size=f"{label_size:.0f}px",
                        font_family="monospace",
                        text_anchor="middle",
                    )
                )
                anchor_x = int(
                    fl.anchor_x
                    if fl.anchor_x is not None
                    else ((canvas_w - fw) / 2 if h_align == "center" else (0 if h_align == "left" else canvas_w - fw))
                )
                anchor_y = int(
                    fl.anchor_y
                    if fl.anchor_y is not None
                    else ((canvas_h - fh) / 2 if v_align == "center" else (0 if v_align == "top" else canvas_h - fh))
                )
                dwg.add(
                    dwg.text(
                        f"Anchor: {anchor_x}, {anchor_y}",
                        insert=(min(sx + sw - 4, cx + cw - 4), max(sy + sh - 10, cy + 10)),
                        fill=label_fg,
                        font_size=f"{max(8.0, label_size - 2):.0f}px",
                        font_family="monospace",
                        text_anchor="end",
                    )
                )
                dwg.add(
                    dwg.text(
                        f"Framing Decision: {int(fw)}\u00d7{int(fh)}",
                        insert=(label_x, min(max(sy + sh - 6, cy + 10), cy + ch - 6)),
                        fill=label_fg,
                        font_size=f"{max(8.0, label_size - 1):.0f}px",
                        font_family="monospace",
                        text_anchor="middle",
                    )
                )
                if show_protection and prot_w and prot_h:
                    pa_x = int(
                        fl.protection_anchor_x if fl.protection_anchor_x is not None else (canvas_w - prot_w) / 2
                    )
                    pa_y = int(
                        fl.protection_anchor_y if fl.protection_anchor_y is not None else (canvas_h - prot_h) / 2
                    )
                    dwg.add(
                        dwg.text(
                            f"Protection: {int(prot_w)}\u00d7{int(prot_h)}",
                            insert=(min(max(px + (pw / 2), cx + 32), cx + cw - 32), min(py + ph - 26, cy + ch - 12)),
                            fill=label_fg,
                            font_size=f"{max(8.0, label_size - 1):.0f}px",
                            font_family="monospace",
                            text_anchor="middle",
                        )
                    )
                    dwg.add(
                        dwg.text(
                            f"Anchor: {pa_x}, {pa_y}",
                            insert=(min(px + pw - 4, cx + cw - 4), max(py + ph - 10, cy + 10)),
                            fill=label_fg,
                            font_size=f"{max(8.0, label_size - 2):.0f}px",
                            font_family="monospace",
                            text_anchor="end",
                        )
                    )

    if show_squeeze_circle and squeeze != 1.0:
        center_x = cx + cw / 2
        center_y = cy + ch / 2
        radius = min(cw, ch) * 0.4
        dwg.add(
            dwg.ellipse(
                center=(center_x, center_y),
                r=(radius / squeeze, radius),
                fill="none",
                stroke="#666",
                stroke_width=line_minor,
                stroke_dasharray="4,4",
            )
        )

    _draw_svg_common_overlays(dwg, scene, cx, cy, cw, ch)

    dim_label = f"Canvas: {canvas_w}\u00d7{canvas_h}"
    label_x = cx + cw - 4
    label_y = cy + ch - 6
    bbox_w = max(120.0, len(dim_label) * (font_small * 0.62))
    bbox_h = max(10.0, font_small + 2.0)
    for _ in range(12):
        lx0, ly0 = label_x - bbox_w, label_y - bbox_h
        lx1, ly1 = label_x, label_y
        if any(not (lx1 < rx0 or lx0 > rx1 or ly1 < ry0 or ly0 > ry1) for (rx0, ry0, rx1, ry1) in occupied_rects):
            label_y -= bbox_h + 2
        else:
            break
    dwg.add(
        dwg.text(
            dim_label,
            insert=(label_x, label_y),
            fill=dim_fg,
            font_size=f"{font_small:.0f}px",
            font_family="monospace",
            text_anchor="end",
        )
    )

    tmp = tempfile.NamedTemporaryFile(suffix=".svg", delete=False, mode="w", encoding="utf-8")
    tmp.write(dwg.tostring())
    tmp.close()
    return {"file_path": tmp.name, "format": "svg"}


def generate_png(params: dict) -> dict:
    """Generate a framing chart as PNG (base64-encoded).

    Params: same as generate_svg, plus:
        dpi: int — output DPI (default 150)
    """
    if Image is None:
        raise ImportError("Pillow is required for PNG generation. Install with: pip install Pillow")

    scene = ChartScene.from_params(params, default_colors=FRAMELINE_COLORS)
    canvas_w = scene.canvas_width
    canvas_h = scene.canvas_height
    title = scene.title
    dpi = _auto_dpi(scene.canvas_width, scene.canvas_height)
    padding = scene.padding
    eff_w = scene.effective_width
    eff_h = scene.effective_height
    show_crosshairs = scene.show_crosshairs
    show_grid = scene.show_grid
    grid_spacing = scene.grid_spacing
    squeeze = scene.anamorphic_squeeze
    show_squeeze_circle = scene.show_squeeze_circle
    layers = scene.layers

    show_canvas = layers.get("canvas", True)
    show_effective = layers.get("effective", True)
    show_protection = layers.get("protection", True)
    show_framing = layers.get("framing", True)

    preview_desqueeze = bool(params.get("preview_desqueeze", False))
    display_x = squeeze if preview_desqueeze and squeeze > 1.0 else 1.0
    scale = 1.0
    # Export at exact canvas dimensions; no padding or title border.
    img_w = int(canvas_w * display_x)
    img_h = canvas_h

    bg = "#1a1a1a" if scene.background_theme != "white" else "#FFFFFF"
    img = Image.new("RGB", (img_w, img_h), bg)
    draw = ImageDraw.Draw(img)

    cx, cy = 0, 0
    cw, ch = img_w, img_h

    if show_canvas:
        if scene.background_theme == "white":
            draw.rectangle([cx, cy, cx + cw, cy + ch], fill="#FFFFFF")
        draw.rectangle([cx, cy, cx + cw, cy + ch], outline="#444444", width=int(_line_width(1.0, cw, ch)))
    if show_grid:
        _draw_png_grid(draw, cx, cy, cw, ch, canvas_w, canvas_h, grid_spacing, scale)

    if show_effective and eff_w and eff_h:
        ew = int(eff_w * scale * display_x)
        eh = int(eff_h * scale)
        ex = cx + int(((canvas_w - eff_w) / 2.0) * scale * display_x)
        ey = cy + int(((canvas_h - eff_h) / 2.0) * scale)
        exi, eyi, ewi, ehi = _adjusted_rect_for_stroke(ex, ey, ew, eh, _line_width(1.5, cw, ch))
        draw.rectangle([exi, eyi, exi + ewi, eyi + ehi], outline="#5AC8FA", width=int(_line_width(1.5, cw, ch)))

    for fl in scene.framelines:
        fw = fl.width
        fh = fl.height
        color = fl.color
        h_align = fl.h_align
        v_align = fl.v_align

        sx, sy, sw, sh = _compute_frameline_position(
            cx,
            cy,
            cw,
            ch,
            fw,
            fh,
            canvas_w,
            canvas_h,
            scale,
            scale * display_x,
            scale,
            h_align,
            v_align,
            fl.anchor_x,
            fl.anchor_y,
        )

        prot_w = fl.protection_width
        prot_h = fl.protection_height
        if show_protection and prot_w and prot_h:
            pw = int(prot_w * scale * display_x)
            ph = int(prot_h * scale)
            prot_h_align = h_align
            prot_v_align = v_align
            px, py, _, _ = _compute_frameline_position(
                cx,
                cy,
                cw,
                ch,
                prot_w,
                prot_h,
                canvas_w,
                canvas_h,
                scale,
                scale * display_x,
                scale,
                prot_h_align,
                prot_v_align,
                fl.protection_anchor_x,
                fl.protection_anchor_y,
            )
            pxi, pyi, pwi, phi = _adjusted_rect_for_stroke(px, py, pw, ph, _line_width(1.0, cw, ch))
            draw.rectangle([pxi, pyi, pxi + pwi, pyi + phi], outline="#FF9500", width=int(_line_width(1.0, cw, ch)))

        if show_framing:
            _draw_png_frameline_style(
                draw,
                sx,
                sy,
                sw,
                sh,
                color,
                int(_line_width(2.0, cw, ch)),
                fl.style,
                fl.style_length,
            )

            if show_crosshairs:
                center_x = sx + sw // 2
                center_y = sy + sh // 2
                draw.line(
                    [(center_x - 8, center_y), (center_x + 8, center_y)],
                    fill=color,
                    width=int(_line_width(1.0, cw, ch)),
                )
                draw.line(
                    [(center_x, center_y - 8), (center_x, center_y + 8)],
                    fill=color,
                    width=int(_line_width(1.0, cw, ch)),
                )

            label = fl.label
            if label:
                label_x = min(max(sx + 4, cx + 2), cx + cw - 120)
                label_y = min(max(sy + 2, cy + 2), cy + ch - 14)
                draw.text((label_x, label_y), label, fill=color)
                draw.text(
                    (min(max(sx + sw - 68, cx + 2), cx + cw - 68), min(max(sy + sh - 12, cy + 2), cy + ch - 12)),
                    f"{int(fw)}x{int(fh)}",
                    fill=color,
                )

    if show_squeeze_circle and squeeze != 1.0:
        center_x = cx + cw // 2
        center_y = cy + ch // 2
        radius = min(cw, ch) * 0.4
        rx = radius / squeeze
        ry = radius
        bbox = [center_x - rx, center_y - ry, center_x + rx, center_y + ry]
        draw.ellipse(bbox, outline="#666666", width=int(_line_width(1.0, cw, ch)))

    _draw_png_common_overlays(draw, scene, cx, cy, cw, ch)

    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    img.save(tmp.name, format="PNG", dpi=(dpi, dpi))
    tmp.close()
    return {"file_path": tmp.name, "format": "png"}


def generate_tiff(params: dict) -> dict:
    """Generate a framing chart as TIFF (base64-encoded)."""
    if Image is None:
        raise ImportError("Pillow is required for TIFF generation. Install with: pip install Pillow")

    scene = ChartScene.from_params(params, default_colors=FRAMELINE_COLORS)
    canvas_w = scene.canvas_width
    canvas_h = scene.canvas_height
    title = scene.title
    dpi = _auto_dpi(scene.canvas_width, scene.canvas_height)
    padding = scene.padding
    eff_w = scene.effective_width
    eff_h = scene.effective_height
    show_crosshairs = scene.show_crosshairs
    show_grid = scene.show_grid
    grid_spacing = scene.grid_spacing
    squeeze = scene.anamorphic_squeeze
    show_squeeze_circle = scene.show_squeeze_circle
    layers = scene.layers

    show_canvas = layers.get("canvas", True)
    show_effective = layers.get("effective", True)
    show_protection = layers.get("protection", True)
    show_framing = layers.get("framing", True)

    preview_desqueeze = bool(params.get("preview_desqueeze", False))
    display_x = squeeze if preview_desqueeze and squeeze > 1.0 else 1.0
    scale = 1.0
    # Export at exact canvas dimensions; no padding or title border.
    img_w = int(canvas_w * display_x)
    img_h = canvas_h

    bg = "#1a1a1a" if scene.background_theme != "white" else "#FFFFFF"
    img = Image.new("RGB", (img_w, img_h), bg)
    draw = ImageDraw.Draw(img)

    cx, cy = 0, 0
    cw, ch = img_w, img_h

    if show_canvas:
        if scene.background_theme == "white":
            draw.rectangle([cx, cy, cx + cw, cy + ch], fill="#FFFFFF")
        draw.rectangle([cx, cy, cx + cw, cy + ch], outline="#444444", width=int(_line_width(1.0, cw, ch)))
    if show_grid:
        _draw_png_grid(draw, cx, cy, cw, ch, canvas_w, canvas_h, grid_spacing, scale)

    if show_effective and eff_w and eff_h:
        ew = int(eff_w * scale * display_x)
        eh = int(eff_h * scale)
        ex = cx + int(((canvas_w - eff_w) / 2.0) * scale * display_x)
        ey = cy + int(((canvas_h - eff_h) / 2.0) * scale)
        exi, eyi, ewi, ehi = _adjusted_rect_for_stroke(ex, ey, ew, eh, _line_width(1.5, cw, ch))
        draw.rectangle([exi, eyi, exi + ewi, eyi + ehi], outline="#5AC8FA", width=int(_line_width(1.5, cw, ch)))

    for fl in scene.framelines:
        fw = fl.width
        fh = fl.height
        color = fl.color
        h_align = fl.h_align
        v_align = fl.v_align

        sx, sy, sw, sh = _compute_frameline_position(
            cx,
            cy,
            cw,
            ch,
            fw,
            fh,
            canvas_w,
            canvas_h,
            scale,
            scale * display_x,
            scale,
            h_align,
            v_align,
            fl.anchor_x,
            fl.anchor_y,
        )

        prot_w = fl.protection_width
        prot_h = fl.protection_height
        if show_protection and prot_w and prot_h:
            pw = int(prot_w * scale * display_x)
            ph = int(prot_h * scale)
            px, py, _, _ = _compute_frameline_position(
                cx,
                cy,
                cw,
                ch,
                prot_w,
                prot_h,
                canvas_w,
                canvas_h,
                scale,
                scale * display_x,
                scale,
                h_align,
                v_align,
                fl.protection_anchor_x,
                fl.protection_anchor_y,
            )
            pxi, pyi, pwi, phi = _adjusted_rect_for_stroke(px, py, pw, ph, _line_width(1.0, cw, ch))
            draw.rectangle([pxi, pyi, pxi + pwi, pyi + phi], outline="#FF9500", width=int(_line_width(1.0, cw, ch)))

        if show_framing:
            _draw_png_frameline_style(
                draw,
                sx,
                sy,
                sw,
                sh,
                color,
                int(_line_width(2.0, cw, ch)),
                fl.style,
                fl.style_length,
            )

            if show_crosshairs:
                center_x = sx + sw // 2
                center_y = sy + sh // 2
                draw.line(
                    [(center_x - 8, center_y), (center_x + 8, center_y)],
                    fill=color,
                    width=int(_line_width(1.0, cw, ch)),
                )
                draw.line(
                    [(center_x, center_y - 8), (center_x, center_y + 8)],
                    fill=color,
                    width=int(_line_width(1.0, cw, ch)),
                )

            label = fl.label
            if label:
                label_x = min(max(sx + 4, cx + 2), cx + cw - 120)
                label_y = min(max(sy + 2, cy + 2), cy + ch - 14)
                draw.text((label_x, label_y), label, fill=color)
                draw.text(
                    (min(max(sx + sw - 68, cx + 2), cx + cw - 68), min(max(sy + sh - 12, cy + 2), cy + ch - 12)),
                    f"{int(fw)}x{int(fh)}",
                    fill=color,
                )

    if show_squeeze_circle and squeeze != 1.0:
        center_x = cx + cw // 2
        center_y = cy + ch // 2
        radius = min(cw, ch) * 0.4
        rx = radius / squeeze
        ry = radius
        bbox = [center_x - rx, center_y - ry, center_x + rx, center_y + ry]
        draw.ellipse(bbox, outline="#666666", width=int(_line_width(1.0, cw, ch)))

    _draw_png_common_overlays(draw, scene, cx, cy, cw, ch)

    tmp = tempfile.NamedTemporaryFile(suffix=".tiff", delete=False)
    img.save(tmp.name, format="TIFF", compression="tiff_lzw", dpi=(dpi, dpi))
    tmp.close()
    return {"file_path": tmp.name, "format": "tiff"}


def generate_pdf(params: dict) -> dict:
    """Generate a framing chart as PDF (base64-encoded)."""
    if cairosvg is None:
        raise ImportError("cairosvg is required for PDF generation. Install with: pip install cairosvg")
    svg = generate_svg(params)["svg"]
    pdf_bytes = cairosvg.svg2pdf(bytestring=svg.encode("utf-8"))
    tmp = tempfile.NamedTemporaryFile(suffix=".pdf", delete=False)
    tmp.write(pdf_bytes)
    tmp.close()
    return {"file_path": tmp.name, "format": "pdf"}


def generate_fdl(params: dict) -> dict:
    """Generate an FDL JSON document from chart configuration.

    Uses the ASC fdl library when available for spec-compliant output
    with proper anchor positioning and protection dimensions.

    Params:
        canvas_width: int
        canvas_height: int
        framelines: list of {label, width, height, h_align?, v_align?,
                    anchor_x?, anchor_y?, protection_width?, protection_height?,
                    framing_intent?}
        effective_width: int (optional)
        effective_height: int (optional)
        description: str (optional)
        anamorphic_squeeze: float (optional, default 1.0)
    """
    scene = ChartScene.from_params(params, default_colors=FRAMELINE_COLORS)
    canvas_w = scene.canvas_width
    canvas_h = scene.canvas_height
    description = scene.description
    eff_w = scene.effective_width
    eff_h = scene.effective_height
    squeeze = scene.anamorphic_squeeze

    if HAS_FDL:
        return _generate_fdl_with_library(canvas_w, canvas_h, scene.framelines, description, eff_w, eff_h, squeeze)

    return _generate_fdl_fallback(canvas_w, canvas_h, scene.framelines, description)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _print_safe_rect(cx: int, cy: int, cw: int, ch: int, percent: float) -> tuple[int, int, int, int] | None:
    if percent <= 0:
        return None
    margin_x = int(cw * (percent / 100.0))
    margin_y = int(ch * (percent / 100.0))
    return (cx + margin_x, cy + margin_y, max(1, cw - margin_x * 2), max(1, ch - margin_y * 2))


def _draw_svg_common_overlays(dwg: Any, scene: ChartScene, cx: int, cy: int, cw: int, ch: int) -> None:
    line_minor = _line_width(1.0, cw, ch)
    font_small = _font_size(10.0, cw, ch)
    overlay_color = "#4D4D4D" if scene.background_theme == "white" else "#CCCCCC"
    safe = _print_safe_rect(cx, cy, cw, ch, scene.print_safe_margin_percent)
    if safe is not None:
        sx, sy, sw, sh = safe
        dwg.add(
            dwg.rect(
                insert=(sx, sy),
                size=(sw, sh),
                fill="none",
                stroke="#808080",
                stroke_width=line_minor,
                stroke_dasharray="5,4",
            )
        )

    if scene.show_chart_markers:
        mx = 14
        my = 14
        center_x = cx + cw / 2
        center_y = cy + ch / 2
        dwg.add(dwg.line(start=(center_x, cy), end=(center_x, cy + my), stroke=overlay_color, stroke_width=line_minor))
        dwg.add(
            dwg.line(
                start=(center_x, cy + ch), end=(center_x, cy + ch - my), stroke=overlay_color, stroke_width=line_minor
            )
        )
        dwg.add(dwg.line(start=(cx, center_y), end=(cx + mx, center_y), stroke=overlay_color, stroke_width=line_minor))
        dwg.add(
            dwg.line(
                start=(cx + cw, center_y), end=(cx + cw - mx, center_y), stroke=overlay_color, stroke_width=line_minor
            )
        )

    if getattr(scene, "show_boundary_arrows", False) and scene.framelines:
        _draw_svg_boundary_arrows(dwg, scene, cx, cy, cw, ch)

    if scene.show_siemens_stars:
        stars = _siemens_star_centers(scene, cx, cy, cw, ch)
        star_size = _siemens_star_size(scene, cw, ch, small=34.0, large=68.0)
        # Respect source anamorphic squeeze in normal view; de-squeeze flow expands cw
        # so dividing by source squeeze naturally morphs stars back to 1:1.
        star_width = star_size * (
            max(1.0, (cw / max(1, scene.canvas_width)) / max(0.0001, ch / max(1, scene.canvas_height)))
            / max(1.0, scene.anamorphic_squeeze)
        )
        for sx, sy in stars:
            _draw_svg_siemens_star(dwg=dwg, center_x=sx, center_y=sy, width=star_width, height=star_size)

    if scene.show_center_marker:
        center_x = cx + cw / 2
        center_y = cy + ch / 2
        dwg.add(
            dwg.line(
                start=(center_x - 12, center_y),
                end=(center_x + 12, center_y),
                stroke=overlay_color,
                stroke_width=line_minor,
            )
        )
        dwg.add(
            dwg.line(
                start=(center_x, center_y - 12),
                end=(center_x, center_y + 12),
                stroke=overlay_color,
                stroke_width=line_minor,
            )
        )

    metadata = scene.metadata
    burn = scene.burn_in
    lines: list[str] = []
    if metadata is not None:
        lines.append(metadata.show_name or scene.title)
        if burn is not None and burn.director:
            lines.append(f"Dir: {burn.director}")
        lines.append(f"DP: {metadata.dop or '—'}")
        lines.append(f"Camera: {metadata.camera_model or 'Custom Canvas'}")
        lines.append(f"Mode: {metadata.recording_mode or 'Custom Mode'}")
        lines.append(f"Framing Decision: {metadata.framing_dimensions or 'N/A'}")
        lines.append(f"Aspect Ratio: {metadata.framing_aspect_ratio or 'N/A'}")
    if burn is not None:
        lines.extend([burn.sample_text_1, burn.sample_text_2])
    lines = [line for line in lines if line]
    if lines:
        auto_meta_font_scale = 0.88 if scene.logo is not None else 1.0
        auto_meta_offset_y = max(18.0, 28.0 * scene.logo.scale) if scene.logo is not None else 0.0
        center_x = cx + cw / 2 + (metadata.offset_x if metadata else 0.0)
        center_y = cy + ch / 2 + (metadata.offset_y if metadata else 0.0) + auto_meta_offset_y
        base_font = (
            max((metadata.font_size if metadata else 12.0), (burn.font_size if burn else 12.0)) * auto_meta_font_scale
        )
        line_gap = max(8, int(_font_size(base_font, cw, ch)))
        y = center_y - ((len(lines) - 1) * line_gap) / 2
        for line in lines:
            dwg.add(
                dwg.text(
                    line,
                    insert=(center_x, y),
                    fill=overlay_color,
                    font_size=f"{line_gap:.0f}px",
                    font_family="sans-serif",
                    text_anchor="middle",
                )
            )
            y += line_gap

    logo = scene.logo
    if logo is not None:
        logo_scale_x = max(
            1.0, (cw / max(1, scene.canvas_width)) / max(0.0001, ch / max(1, scene.canvas_height))
        ) / max(1.0, scene.anamorphic_squeeze)
        x = cx + cw / 2 + logo.offset_x
        y = cy + ch / 2 - 64 + logo.offset_y
        anchor = "middle"
        if logo.image_base64:
            width = 140 * max(0.1, logo.scale) * logo_scale_x
            height = 52 * max(0.1, logo.scale)
            ix = x - (width / 2)
            iy = y - height + 6
            href = f"data:image/png;base64,{logo.image_base64}"
            dwg.add(dwg.image(href=href, insert=(ix, iy), size=(width, height), opacity=0.95))
        elif logo.text:
            text_group = dwg.g(transform=f"translate({x},{y}) scale({logo_scale_x},1) translate({-x},{-y})")
            text_group.add(
                dwg.text(
                    logo.text,
                    insert=(x, y),
                    fill=overlay_color,
                    font_size=f"{max(8, font_small * logo.scale):.0f}px",
                    font_family="sans-serif",
                    text_anchor=anchor,
                )
            )
            dwg.add(text_group)


def _draw_png_common_overlays(draw: Any, scene: ChartScene, cx: int, cy: int, cw: int, ch: int) -> None:
    line_minor = int(_line_width(1.0, cw, ch))
    overlay_color = "#4D4D4D" if scene.background_theme == "white" else "#CCCCCC"
    safe = _print_safe_rect(cx, cy, cw, ch, scene.print_safe_margin_percent)
    if safe is not None:
        sx, sy, sw, sh = safe
        draw.rectangle([sx, sy, sx + sw, sy + sh], outline="#808080", width=line_minor)

    if scene.show_chart_markers:
        center_x = cx + cw // 2
        center_y = cy + ch // 2
        draw.line([(center_x, cy), (center_x, cy + 14)], fill=overlay_color, width=line_minor)
        draw.line([(center_x, cy + ch), (center_x, cy + ch - 14)], fill=overlay_color, width=line_minor)
        draw.line([(cx, center_y), (cx + 14, center_y)], fill=overlay_color, width=line_minor)
        draw.line([(cx + cw, center_y), (cx + cw - 14, center_y)], fill=overlay_color, width=line_minor)

    # Boundary arrows: point from canvas edges toward the first frameline's edges
    if getattr(scene, "show_boundary_arrows", False) and scene.framelines:
        _draw_png_boundary_arrows(draw, scene, cx, cy, cw, ch)

    if scene.show_siemens_stars:
        stars = _siemens_star_centers(scene, cx, cy, cw, ch)
        star_size = _siemens_star_size(scene, cw, ch, small=50.0, large=112.0)
        # Keep stars squeezed with source anamorphic unless preview/export path de-squeezes.
        star_width = star_size * (
            max(1.0, (cw / max(1, scene.canvas_width)) / max(0.0001, ch / max(1, scene.canvas_height)))
            / max(1.0, scene.anamorphic_squeeze)
        )
        for sx, sy in stars:
            _draw_png_siemens_star(draw=draw, center_x=sx, center_y=sy, width=star_width, height=star_size)

    if scene.show_center_marker:
        center_x = cx + cw // 2
        center_y = cy + ch // 2
        draw.line([(center_x - 12, center_y), (center_x + 12, center_y)], fill=overlay_color, width=line_minor)
        draw.line([(center_x, center_y - 12), (center_x, center_y + 12)], fill=overlay_color, width=line_minor)

    metadata = scene.metadata
    burn = scene.burn_in
    lines: list[str] = []
    if metadata is not None:
        lines.append(metadata.show_name or scene.title)
        if burn is not None and burn.director:
            lines.append(f"Dir: {burn.director}")
        lines.append(f"DP: {metadata.dop or '—'}")
        lines.append(f"Camera: {metadata.camera_model or 'Custom Canvas'}")
        lines.append(f"Mode: {metadata.recording_mode or 'Custom Mode'}")
        lines.append(f"Framing Decision: {metadata.framing_dimensions or 'N/A'}")
        lines.append(f"Aspect Ratio: {metadata.framing_aspect_ratio or 'N/A'}")
    if burn is not None:
        lines.extend([burn.sample_text_1, burn.sample_text_2])
    lines = [line for line in lines if line]
    if lines:
        auto_meta_font_scale = 0.88 if scene.logo is not None else 1.0
        auto_meta_offset_y = max(18.0, 28.0 * scene.logo.scale) if scene.logo is not None else 0.0
        line_gap = max(
            8,
            int(
                max((metadata.font_size if metadata else 12.0), (burn.font_size if burn else 12.0))
                * auto_meta_font_scale
            ),
        )
        center_x = int(cx + cw / 2 + (metadata.offset_x if metadata else 0.0))
        y = int(
            cy
            + ch / 2
            + (metadata.offset_y if metadata else 0.0)
            + auto_meta_offset_y
            - ((len(lines) - 1) * line_gap) / 2
        )
        for line in lines:
            text_w = len(line) * max(5, int(line_gap * 0.55))
            draw.text((int(center_x - text_w / 2), y), line, fill=overlay_color)
            y += line_gap

    logo = scene.logo
    if logo is not None:
        logo_scale_x = max(
            1.0, (cw / max(1, scene.canvas_width)) / max(0.0001, ch / max(1, scene.canvas_height))
        ) / max(1.0, scene.anamorphic_squeeze)
        x = int(cx + cw / 2 + logo.offset_x)
        y = int(cy + ch / 2 - 64 + logo.offset_y)
        if logo.image_base64:
            try:
                blob = base64.b64decode(logo.image_base64)
                logo_img = Image.open(io.BytesIO(blob)).convert("RGBA")
                target_w = max(8, int(logo_img.width * logo.scale * logo_scale_x))
                target_h = max(8, int(logo_img.height * logo.scale))
                logo_img = logo_img.resize((target_w, target_h))
                img_ref = draw._image  # Pillow internal backing image
                img_ref.paste(logo_img, (x - target_w // 2, y - target_h), logo_img)
            except Exception:
                if logo.text:
                    draw.text((x - 40, y), logo.text, fill=overlay_color)
        elif logo.text:
            draw.text((x - 40, y), logo.text, fill=overlay_color)


def _draw_svg_boundary_arrows(
    dwg: Any, scene: ChartScene, cx: int, cy: int, cw: int, ch: int
) -> None:
    """Draw boundary arrows in SVG pointing from canvas edges toward first frameline."""
    import math as _math
    if not scene.framelines:
        return
    fl = scene.framelines[0]
    fw = fl.width
    fh = fl.height
    if fw <= 0 or fh <= 0:
        return

    ax = fl.anchor_x if fl.anchor_x is not None else (scene.canvas_width - fw) / 2.0
    ay = fl.anchor_y if fl.anchor_y is not None else (scene.canvas_height - fh) / 2.0
    sx = cx + ax
    sy = cy + ay

    arrow_color = fl.color
    scale = getattr(scene, "boundary_arrow_scale", 1.0) or 1.0
    ah = max(8.0, min(cw, ch) * 0.008 * scale)
    sw2 = max(2.0, ah * 0.35)
    canvas_cx = cx + cw / 2
    canvas_cy = cy + ch / 2

    def _svg_arrow(x1: float, y1: float, x2: float, y2: float) -> None:
        dwg.add(dwg.line(start=(x1, y1), end=(x2, y2), stroke=arrow_color, stroke_width=sw2))
        angle = _math.atan2(y2 - y1, x2 - x1)
        for da in (0.45, -0.45):
            bx = x2 - ah * _math.cos(angle + da)
            by = y2 - ah * _math.sin(angle + da)
            dwg.add(dwg.line(start=(x2, y2), end=(bx, by), stroke=arrow_color, stroke_width=sw2))

    gap = max(4.0, ah)
    if sy > cy + gap * 2:
        _svg_arrow(canvas_cx, cy + gap, canvas_cx, sy - gap)
    if sy + fh < cy + ch - gap * 2:
        _svg_arrow(canvas_cx, cy + ch - gap, canvas_cx, sy + fh + gap)
    if sx > cx + gap * 2:
        _svg_arrow(cx + gap, canvas_cy, sx - gap, canvas_cy)
    if sx + fw < cx + cw - gap * 2:
        _svg_arrow(cx + cw - gap, canvas_cy, sx + fw + gap, canvas_cy)


def _draw_png_boundary_arrows(
    draw: Any, scene: ChartScene, cx: int, cy: int, cw: int, ch: int
) -> None:
    """Draw boundary arrows pointing from canvas edges toward the first frameline."""
    import math as _math
    if not scene.framelines:
        return
    fl = scene.framelines[0]
    fw = fl.width
    fh = fl.height
    if fw <= 0 or fh <= 0:
        return

    # Anchor of first frameline (centered on canvas by default)
    ax = fl.anchor_x if fl.anchor_x is not None else (scene.canvas_width - fw) / 2.0
    ay = fl.anchor_y if fl.anchor_y is not None else (scene.canvas_height - fh) / 2.0

    # Scale to image coordinates
    sx = cx + int(ax)
    sy = cy + int(ay)
    sw = int(fw)
    sh = int(fh)

    arrow_color = fl.color
    scale = getattr(scene, "boundary_arrow_scale", 1.0) or 1.0
    arrow_head = max(8, int(min(cw, ch) * 0.008 * scale))
    shaft_w = max(2, int(arrow_head * 0.35))

    canvas_cx = cx + cw // 2
    canvas_cy = cy + ch // 2

    def _arrow(x1: float, y1: float, x2: float, y2: float) -> None:
        draw.line([(int(x1), int(y1)), (int(x2), int(y2))], fill=arrow_color, width=shaft_w)
        # arrowhead at (x2, y2) pointing in direction from (x1,y1)
        angle = _math.atan2(y2 - y1, x2 - x1)
        for da in (0.45, -0.45):
            bx = x2 - arrow_head * _math.cos(angle + da)
            by = y2 - arrow_head * _math.sin(angle + da)
            draw.line([(int(x2), int(y2)), (int(bx), int(by))], fill=arrow_color, width=shaft_w)

    gap = max(4, arrow_head)
    # Top arrow: from top canvas edge down to top frameline edge
    if sy > cy + gap * 2:
        _arrow(canvas_cx, cy + gap, canvas_cx, sy - gap)
    # Bottom arrow
    if sy + sh < cy + ch - gap * 2:
        _arrow(canvas_cx, cy + ch - gap, canvas_cx, sy + sh + gap)
    # Left arrow
    if sx > cx + gap * 2:
        _arrow(cx + gap, canvas_cy, sx - gap, canvas_cy)
    # Right arrow
    if sx + sw < cx + cw - gap * 2:
        _arrow(cx + cw - gap, canvas_cy, sx + sw + gap, canvas_cy)


def _siemens_star_centers(scene: ChartScene, cx: int, cy: int, cw: int, ch: int) -> list[tuple[float, float]]:
    target_x, target_y, target_w, target_h = float(cx), float(cy), float(cw), float(ch)
    if scene.framelines:
        fl = scene.framelines[0]
        fw = (float(fl.width) / max(1.0, float(scene.canvas_width))) * target_w
        fh = (float(fl.height) / max(1.0, float(scene.canvas_height))) * target_h
        if fl.anchor_x is not None and fl.anchor_y is not None:
            fx = target_x + (float(fl.anchor_x) / max(1.0, float(scene.canvas_width))) * target_w
            fy = target_y + (float(fl.anchor_y) / max(1.0, float(scene.canvas_height))) * target_h
        else:
            fx = (
                target_x
                if fl.h_align == "left"
                else (target_x + target_w - fw if fl.h_align == "right" else target_x + (target_w - fw) / 2.0)
            )
            fy = (
                target_y
                if fl.v_align == "top"
                else (target_y + target_h - fh if fl.v_align == "bottom" else target_y + (target_h - fh) / 2.0)
            )
        target_x, target_y, target_w, target_h = float(fx), float(fy), float(fw), float(fh)
    radius = max(14.0, min(28.0, min(target_w, target_h) * 0.09))
    inset = radius + max(14.0, min(target_w, target_h) * 0.08)
    return [
        (target_x + inset, target_y + inset),
        (target_x + target_w - inset, target_y + inset),
        (target_x + inset, target_y + target_h - inset),
        (target_x + target_w - inset, target_y + target_h - inset),
    ]


def _siemens_star_size(scene: ChartScene, cw: int, ch: int, small: float, large: float) -> float:
    base = max(small, min(large, min(cw, ch) * 0.125))
    size = (scene.siemens_star_size or "small").lower()
    if size == "large":
        return base * 2.05
    if size == "medium":
        return base * 1.60
    return base * 1.15


def _draw_svg_siemens_star(
    dwg: Any,
    center_x: float,
    center_y: float,
    width: float,
    height: float,
) -> None:
    if not _SIEMENS_PATHS:
        return
    scale_x = width / 20000.0
    scale_y = height / 20000.0
    group = dwg.g(transform=f"translate({center_x - (width / 2)},{center_y - (height / 2)}) scale({scale_x},{scale_y})")
    for d in _SIEMENS_PATHS:
        group.add(dwg.path(d=d, fill="#000000", stroke="none"))
    dwg.add(group)


def _draw_png_siemens_star(
    draw: Any,
    center_x: float,
    center_y: float,
    width: float,
    height: float,
) -> None:
    if Image is None or cairosvg is None or not _SIEMENS_SVG_TEXT:
        return
    key = (max(12, int(width)), max(12, int(height)))
    sprite = _SIEMENS_PNG_CACHE.get(key)
    if sprite is None:
        png_bytes = cairosvg.svg2png(
            bytestring=_SIEMENS_SVG_TEXT.encode("utf-8"), output_width=key[0], output_height=key[1]
        )
        sprite = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
        _SIEMENS_PNG_CACHE[key] = sprite
    img_ref = draw._image
    img_ref.paste(sprite, (int(center_x - key[0] / 2), int(center_y - key[1] / 2)), sprite)


def _draw_svg_frameline_style(
    dwg: Any,
    sx: int,
    sy: int,
    sw: int,
    sh: int,
    color: str,
    line_major: float,
    style: str,
    style_length: float,
) -> None:
    sx, sy, sw, sh = _adjusted_rect_for_stroke(sx, sy, sw, sh, line_major)
    if style == "corners":
        c = max(6, int(min(sw, sh) * style_length))
        # top-left
        dwg.add(dwg.line(start=(sx, sy), end=(sx + c, sy), stroke=color, stroke_width=line_major))
        dwg.add(dwg.line(start=(sx, sy), end=(sx, sy + c), stroke=color, stroke_width=line_major))
        # top-right
        dwg.add(dwg.line(start=(sx + sw, sy), end=(sx + sw - c, sy), stroke=color, stroke_width=line_major))
        dwg.add(dwg.line(start=(sx + sw, sy), end=(sx + sw, sy + c), stroke=color, stroke_width=line_major))
        # bottom-left
        dwg.add(dwg.line(start=(sx, sy + sh), end=(sx + c, sy + sh), stroke=color, stroke_width=line_major))
        dwg.add(dwg.line(start=(sx, sy + sh), end=(sx, sy + sh - c), stroke=color, stroke_width=line_major))
        # bottom-right
        dwg.add(dwg.line(start=(sx + sw, sy + sh), end=(sx + sw - c, sy + sh), stroke=color, stroke_width=line_major))
        dwg.add(dwg.line(start=(sx + sw, sy + sh), end=(sx + sw, sy + sh - c), stroke=color, stroke_width=line_major))
    else:
        dwg.add(dwg.rect(insert=(sx, sy), size=(sw, sh), fill="none", stroke=color, stroke_width=line_major))


def _draw_png_frameline_style(
    draw: Any,
    sx: int,
    sy: int,
    sw: int,
    sh: int,
    color: str,
    line_major: int,
    style: str,
    style_length: float,
) -> None:
    sx, sy, sw, sh = _adjusted_rect_for_stroke(sx, sy, sw, sh, line_major)
    if style == "corners":
        c = max(6, int(min(sw, sh) * style_length))
        draw.line([(sx, sy), (sx + c, sy)], fill=color, width=line_major)
        draw.line([(sx, sy), (sx, sy + c)], fill=color, width=line_major)
        draw.line([(sx + sw, sy), (sx + sw - c, sy)], fill=color, width=line_major)
        draw.line([(sx + sw, sy), (sx + sw, sy + c)], fill=color, width=line_major)
        draw.line([(sx, sy + sh), (sx + c, sy + sh)], fill=color, width=line_major)
        draw.line([(sx, sy + sh), (sx, sy + sh - c)], fill=color, width=line_major)
        draw.line([(sx + sw, sy + sh), (sx + sw - c, sy + sh)], fill=color, width=line_major)
        draw.line([(sx + sw, sy + sh), (sx + sw, sy + sh - c)], fill=color, width=line_major)
    else:
        draw.rectangle([sx, sy, sx + sw, sy + sh], outline=color, width=line_major)


def _adjusted_rect_for_stroke(sx: int, sy: int, sw: int, sh: int, line_width: float) -> tuple[int, int, int, int]:
    half = max(1, int(round(line_width / 2.0)))
    # Always draw inside defined dimensions.
    return sx + half, sy + half, max(1, sw - (half * 2)), max(1, sh - (half * 2))


def _compute_frameline_position(
    cx: int,
    cy: int,
    cw: int,
    ch: int,
    fw: float,
    fh: float,
    canvas_w: int,
    canvas_h: int,
    scale: float,
    scale_x: float,
    scale_y: float,
    h_align: str,
    v_align: str,
    anchor_x: float | None = None,
    anchor_y: float | None = None,
) -> tuple[int, int, int, int]:
    """Compute the screen position of a frameline within the canvas area.

    Returns (x, y, width, height) in screen coordinates.
    """
    sw = int(fw * scale_x)
    sh = int(fh * scale_y)

    if anchor_x is not None and anchor_y is not None:
        sx = cx + int(anchor_x * scale_x)
        sy = cy + int(anchor_y * scale_y)
    else:
        if h_align == "left":
            sx = cx
        elif h_align == "right":
            sx = cx + cw - sw
        else:
            sx = cx + (cw - sw) // 2

        if v_align == "top":
            sy = cy
        elif v_align == "bottom":
            sy = cy + ch - sh
        else:
            sy = cy + (ch - sh) // 2

    return sx, sy, sw, sh


def _draw_svg_grid(
    dwg: Any,
    cx: int,
    cy: int,
    cw: int,
    ch: int,
    canvas_w: int,
    canvas_h: int,
    grid_spacing: int,
    scale: float,
) -> None:
    """Draw a grid overlay on the SVG canvas."""
    for gx in range(0, canvas_w + 1, grid_spacing):
        x = cx + int(gx * scale)
        if x <= cx + cw:
            dwg.add(dwg.line(start=(x, cy), end=(x, cy + ch), stroke="#333", stroke_width=0.5))
    for gy in range(0, canvas_h + 1, grid_spacing):
        y = cy + int(gy * scale)
        if y <= cy + ch:
            dwg.add(dwg.line(start=(cx, y), end=(cx + cw, y), stroke="#333", stroke_width=0.5))


def _draw_png_grid(
    draw: Any,
    cx: int,
    cy: int,
    cw: int,
    ch: int,
    canvas_w: int,
    canvas_h: int,
    grid_spacing: int,
    scale: float,
) -> None:
    """Draw a grid overlay on the PNG canvas."""
    for gx in range(0, canvas_w + 1, grid_spacing):
        x = cx + int(gx * scale)
        if x <= cx + cw:
            draw.line([(x, cy), (x, cy + ch)], fill="#333333", width=1)
    for gy in range(0, canvas_h + 1, grid_spacing):
        y = cy + int(gy * scale)
        if y <= cy + ch:
            draw.line([(cx, y), (cx + cw, y)], fill="#333333", width=1)


def _generate_fdl_with_library(
    canvas_w: int,
    canvas_h: int,
    framelines: list[Any],
    description: str,
    eff_w: int | None,
    eff_h: int | None,
    squeeze: float,
) -> dict:
    """Generate FDL using the ASC fdl library with full anchor/protection support."""
    doc = build_fdl(fdl_creator="FDL Tool", description=description)

    ctx = add_context_to_fdl(doc, label="Chart Generated", context_creator="FDL Tool Chart Generator")

    canvas = add_canvas_to_context(
        ctx,
        label=f"{canvas_w}x{canvas_h}",
        width=canvas_w,
        height=canvas_h,
        effective_width=eff_w,
        effective_height=eff_h,
        anamorphic_squeeze=squeeze,
    )

    for fl in framelines:
        fd = add_framing_decision_to_canvas(
            canvas,
            label=fl.label,
            width=float(fl.width),
            height=float(fl.height),
            framing_intent_id=fl.framing_intent,
            anchor_x=fl.anchor_x,
            anchor_y=fl.anchor_y,
            protection_width=fl.protection_width,
            protection_height=fl.protection_height,
            protection_anchor_x=fl.protection_anchor_x or 0.0,
            protection_anchor_y=fl.protection_anchor_y or 0.0,
        )

        h_align = fl.h_align
        v_align = fl.v_align
        if h_align and v_align and fl.anchor_x is None:
            fd.adjust_anchor_point(canvas, h_align, v_align)

    return {"fdl": fdl_to_dict(doc)}


def _generate_fdl_fallback(
    canvas_w: int,
    canvas_h: int,
    framelines: list[Any],
    description: str,
) -> dict:
    """Generate FDL in v2.0.1 format using raw dicts (no fdl library)."""
    framing_decisions = []
    for fl in framelines:
        fw = float(fl.width)
        fh = float(fl.height)

        if fl.anchor_x is not None and fl.anchor_y is not None:
            ax, ay = float(fl.anchor_x), float(fl.anchor_y)
        elif fl.h_align or fl.v_align:
            ax, ay = _compute_anchor_from_alignment(
                canvas_w,
                canvas_h,
                fw,
                fh,
                fl.h_align or "center",
                fl.v_align or "center",
            )
        else:
            ax, ay = _compute_anchor_from_alignment(canvas_w, canvas_h, fw, fh, "center", "center")

        fd: dict = {
            "id": str(uuid.uuid4()),
            "label": fl.label,
            "framing_intent_id": fl.framing_intent,
            "dimensions": {"width": fw, "height": fh},
            "anchor_point": {"x": ax, "y": ay},
        }

        if fl.protection_width and fl.protection_height:
            fd["protection_dimensions"] = {
                "width": float(fl.protection_width),
                "height": float(fl.protection_height),
            }
            fd["protection_anchor_point"] = {
                "x": float(fl.protection_anchor_x or 0),
                "y": float(fl.protection_anchor_y or 0),
            }

        framing_decisions.append(fd)

    doc = {
        "uuid": str(uuid.uuid4()),
        "version": {"major": 2, "minor": 0},
        "fdl_creator": "FDL Tool",
        "framing_intents": [],
        "contexts": [
            {
                "label": "Chart Generated",
                "context_creator": "FDL Tool Chart Generator",
                "canvases": [
                    {
                        "id": str(uuid.uuid4()),
                        "label": f"{canvas_w}x{canvas_h}",
                        "source_canvas_id": "",
                        "dimensions": {"width": canvas_w, "height": canvas_h},
                        "anamorphic_squeeze": 1.0,
                        "framing_decisions": framing_decisions,
                    }
                ],
            }
        ],
        "canvas_templates": [],
    }

    return {"fdl": doc}


def _compute_anchor_from_alignment(
    canvas_w: int, canvas_h: int, fw: float, fh: float, h_align: str, v_align: str
) -> tuple[float, float]:
    """Compute anchor point from alignment enums."""
    if h_align == "left":
        ax = 0.0
    elif h_align == "right":
        ax = float(canvas_w - fw)
    else:
        ax = float(canvas_w - fw) / 2.0

    if v_align == "top":
        ay = 0.0
    elif v_align == "bottom":
        ay = float(canvas_h - fh)
    else:
        ay = float(canvas_h - fh) / 2.0

    return ax, ay

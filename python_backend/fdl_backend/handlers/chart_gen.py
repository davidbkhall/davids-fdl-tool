"""Framing chart generation: SVG, PNG, and FDL output.

SVG/PNG rendering uses svgwrite/Pillow directly. FDL generation uses the
ASC fdl library for spec-compliant document construction with anchor
positioning and protection support.
"""

from __future__ import annotations

import base64
import io
import uuid
from typing import Any

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

    canvas_w = params.get("canvas_width", 4096)
    canvas_h = params.get("canvas_height", 2160)
    framelines = params.get("framelines", [])
    title = params.get("title", "Framing Chart")
    show_labels = params.get("show_labels", True)
    padding = params.get("padding", 60)
    eff_w = params.get("effective_width")
    eff_h = params.get("effective_height")
    show_crosshairs = params.get("show_crosshairs", False)
    show_grid = params.get("show_grid", False)
    grid_spacing = params.get("grid_spacing", 100)
    squeeze = params.get("anamorphic_squeeze", 1.0)
    show_squeeze_circle = params.get("show_squeeze_circle", False)
    layers = params.get("layers", {})

    show_canvas = layers.get("canvas", True)
    show_effective = layers.get("effective", True)
    show_protection = layers.get("protection", True)
    show_framing = layers.get("framing", True)

    scale = min(800 / canvas_w, 600 / canvas_h)
    svg_w = int(canvas_w * scale) + padding * 2
    svg_h = int(canvas_h * scale) + padding * 2 + (40 if title else 0)

    dwg = svgwrite.Drawing(size=(svg_w, svg_h))
    dwg.add(dwg.rect(insert=(0, 0), size=(svg_w, svg_h), fill="#1a1a1a"))

    title_offset = 0
    if title:
        title_offset = 40
        dwg.add(
            dwg.text(
                title,
                insert=(svg_w / 2, 28),
                fill="white",
                font_size="16px",
                font_family="sans-serif",
                text_anchor="middle",
            )
        )

    cx, cy = padding, padding + title_offset
    cw, ch = int(canvas_w * scale), int(canvas_h * scale)

    if show_grid:
        _draw_svg_grid(dwg, cx, cy, cw, ch, canvas_w, canvas_h, grid_spacing, scale)

    if show_canvas:
        dwg.add(dwg.rect(insert=(cx, cy), size=(cw, ch), fill="none", stroke="#444", stroke_width=1))

    if show_effective and eff_w and eff_h:
        ew = int(eff_w * scale)
        eh = int(eff_h * scale)
        ex = cx + (cw - ew) // 2
        ey = cy + (ch - eh) // 2
        dwg.add(dwg.rect(insert=(ex, ey), size=(ew, eh), fill="none", stroke="#5AC8FA", stroke_width=1.5))
        if show_labels:
            dwg.add(
                dwg.text(
                    f"Effective {eff_w}\u00d7{eff_h}",
                    insert=(ex + 4, ey + 14),
                    fill="#5AC8FA",
                    font_size="10px",
                    font_family="sans-serif",
                )
            )

    for i, fl in enumerate(framelines):
        fw = fl.get("width", canvas_w)
        fh = fl.get("height", canvas_h)
        color = fl.get("color", FRAMELINE_COLORS[i % len(FRAMELINE_COLORS)])
        label = fl.get("label", "")
        h_align = fl.get("h_align", "center")
        v_align = fl.get("v_align", "center")

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
            h_align,
            v_align,
            fl.get("anchor_x"),
            fl.get("anchor_y"),
        )

        prot_w = fl.get("protection_width")
        prot_h = fl.get("protection_height")
        if show_protection and prot_w and prot_h:
            pw = int(prot_w * scale)
            ph = int(prot_h * scale)
            prot_h_align = fl.get("protection_h_align", h_align)
            prot_v_align = fl.get("protection_v_align", v_align)
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
                prot_h_align,
                prot_v_align,
                fl.get("protection_anchor_x"),
                fl.get("protection_anchor_y"),
            )
            dwg.add(
                dwg.rect(
                    insert=(px, py),
                    size=(pw, ph),
                    fill="none",
                    stroke="#FF9500",
                    stroke_width=1,
                    stroke_dasharray="6,3",
                )
            )

        if show_framing:
            dwg.add(dwg.rect(insert=(sx, sy), size=(sw, sh), fill="none", stroke=color, stroke_width=2))

            if show_crosshairs:
                center_x = sx + sw / 2
                center_y = sy + sh / 2
                dwg.add(
                    dwg.line(start=(center_x - 8, center_y), end=(center_x + 8, center_y), stroke=color, stroke_width=1)
                )
                dwg.add(
                    dwg.line(start=(center_x, center_y - 8), end=(center_x, center_y + 8), stroke=color, stroke_width=1)
                )

            if show_labels and label:
                dwg.add(
                    dwg.text(label, insert=(sx + 4, sy + 14), fill=color, font_size="11px", font_family="sans-serif")
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
                stroke_width=1,
                stroke_dasharray="4,4",
            )
        )

    dim_label = f"{canvas_w} \u00d7 {canvas_h}"
    dwg.add(
        dwg.text(
            dim_label,
            insert=(cx + cw - 4, cy + ch - 6),
            fill="#666",
            font_size="10px",
            font_family="monospace",
            text_anchor="end",
        )
    )

    metadata = params.get("metadata")
    if metadata:
        meta_y = cy + ch + 16
        show_name = metadata.get("show_name", "")
        dop = metadata.get("dop", "")
        if show_name:
            dwg.add(dwg.text(show_name, insert=(cx, meta_y), fill="#999", font_size="11px", font_family="sans-serif"))
            meta_y += 16
        if dop:
            dwg.add(
                dwg.text(f"DP: {dop}", insert=(cx, meta_y), fill="#999", font_size="11px", font_family="sans-serif")
            )

    return {"svg": dwg.tostring()}


def generate_png(params: dict) -> dict:
    """Generate a framing chart as PNG (base64-encoded).

    Params: same as generate_svg, plus:
        dpi: int — output DPI (default 150)
    """
    if Image is None:
        raise ImportError("Pillow is required for PNG generation. Install with: pip install Pillow")

    canvas_w = params.get("canvas_width", 4096)
    canvas_h = params.get("canvas_height", 2160)
    framelines = params.get("framelines", [])
    title = params.get("title", "Framing Chart")
    dpi = params.get("dpi", 150)
    padding = params.get("padding", 60)
    eff_w = params.get("effective_width")
    eff_h = params.get("effective_height")
    show_crosshairs = params.get("show_crosshairs", False)
    show_grid = params.get("show_grid", False)
    grid_spacing = params.get("grid_spacing", 100)
    squeeze = params.get("anamorphic_squeeze", 1.0)
    show_squeeze_circle = params.get("show_squeeze_circle", False)
    layers = params.get("layers", {})

    show_canvas = layers.get("canvas", True)
    show_effective = layers.get("effective", True)
    show_protection = layers.get("protection", True)
    show_framing = layers.get("framing", True)

    scale = min(800 / canvas_w, 600 / canvas_h)
    img_w = int(canvas_w * scale) + padding * 2
    img_h = int(canvas_h * scale) + padding * 2 + (40 if title else 0)

    img = Image.new("RGB", (img_w, img_h), "#1a1a1a")
    draw = ImageDraw.Draw(img)

    title_offset = 0
    if title:
        title_offset = 40
        draw.text((img_w // 2, 10), title, fill="white", anchor="mt")

    cx, cy = padding, padding + title_offset
    cw, ch = int(canvas_w * scale), int(canvas_h * scale)

    if show_grid:
        _draw_png_grid(draw, cx, cy, cw, ch, canvas_w, canvas_h, grid_spacing, scale)

    if show_canvas:
        draw.rectangle([cx, cy, cx + cw, cy + ch], outline="#444444")

    if show_effective and eff_w and eff_h:
        ew = int(eff_w * scale)
        eh = int(eff_h * scale)
        ex = cx + (cw - ew) // 2
        ey = cy + (ch - eh) // 2
        draw.rectangle([ex, ey, ex + ew, ey + eh], outline="#5AC8FA")

    for i, fl in enumerate(framelines):
        fw = fl.get("width", canvas_w)
        fh = fl.get("height", canvas_h)
        color = fl.get("color", FRAMELINE_COLORS[i % len(FRAMELINE_COLORS)])
        h_align = fl.get("h_align", "center")
        v_align = fl.get("v_align", "center")

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
            h_align,
            v_align,
            fl.get("anchor_x"),
            fl.get("anchor_y"),
        )

        prot_w = fl.get("protection_width")
        prot_h = fl.get("protection_height")
        if show_protection and prot_w and prot_h:
            pw = int(prot_w * scale)
            ph = int(prot_h * scale)
            prot_h_align = fl.get("protection_h_align", h_align)
            prot_v_align = fl.get("protection_v_align", v_align)
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
                prot_h_align,
                prot_v_align,
                fl.get("protection_anchor_x"),
                fl.get("protection_anchor_y"),
            )
            draw.rectangle([px, py, px + pw, py + ph], outline="#FF9500")

        if show_framing:
            draw.rectangle([sx, sy, sx + sw, sy + sh], outline=color, width=2)

            if show_crosshairs:
                center_x = sx + sw // 2
                center_y = sy + sh // 2
                draw.line([(center_x - 8, center_y), (center_x + 8, center_y)], fill=color, width=1)
                draw.line([(center_x, center_y - 8), (center_x, center_y + 8)], fill=color, width=1)

            label = fl.get("label", "")
            if label:
                draw.text((sx + 4, sy + 2), label, fill=color)

    if show_squeeze_circle and squeeze != 1.0:
        center_x = cx + cw // 2
        center_y = cy + ch // 2
        radius = min(cw, ch) * 0.4
        rx = radius / squeeze
        ry = radius
        bbox = [center_x - rx, center_y - ry, center_x + rx, center_y + ry]
        draw.ellipse(bbox, outline="#666666", width=1)

    metadata = params.get("metadata")
    if metadata:
        meta_y = cy + ch + 4
        show_name = metadata.get("show_name", "")
        dop = metadata.get("dop", "")
        if show_name:
            draw.text((cx, meta_y), show_name, fill="#999999")
            meta_y += 16
        if dop:
            draw.text((cx, meta_y), f"DP: {dop}", fill="#999999")

    buf = io.BytesIO()
    img.save(buf, format="PNG", dpi=(dpi, dpi))
    png_b64 = base64.b64encode(buf.getvalue()).decode("ascii")

    return {"png_base64": png_b64}


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
    canvas_w = params.get("canvas_width", 4096)
    canvas_h = params.get("canvas_height", 2160)
    framelines = params.get("framelines", [])
    description = params.get("description", "Generated by FDL Tool Chart Generator")
    eff_w = params.get("effective_width")
    eff_h = params.get("effective_height")
    squeeze = params.get("anamorphic_squeeze", 1.0)

    if HAS_FDL:
        return _generate_fdl_with_library(canvas_w, canvas_h, framelines, description, eff_w, eff_h, squeeze)

    return _generate_fdl_fallback(canvas_w, canvas_h, framelines, description)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


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
    h_align: str,
    v_align: str,
    anchor_x: float | None = None,
    anchor_y: float | None = None,
) -> tuple[int, int, int, int]:
    """Compute the screen position of a frameline within the canvas area.

    Returns (x, y, width, height) in screen coordinates.
    """
    sw = int(fw * scale)
    sh = int(fh * scale)

    if anchor_x is not None and anchor_y is not None:
        sx = cx + int(anchor_x * scale)
        sy = cy + int(anchor_y * scale)
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
    framelines: list[dict],
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
            label=fl.get("label", ""),
            width=float(fl.get("width", canvas_w)),
            height=float(fl.get("height", canvas_h)),
            framing_intent_id=fl.get("framing_intent"),
            anchor_x=fl.get("anchor_x"),
            anchor_y=fl.get("anchor_y"),
            protection_width=fl.get("protection_width"),
            protection_height=fl.get("protection_height"),
            protection_anchor_x=fl.get("protection_anchor_x", 0.0),
            protection_anchor_y=fl.get("protection_anchor_y", 0.0),
        )

        h_align = fl.get("h_align")
        v_align = fl.get("v_align")
        if h_align and v_align and fl.get("anchor_x") is None:
            fd.adjust_anchor_point(canvas, h_align, v_align)

    return {"fdl": fdl_to_dict(doc)}


def _generate_fdl_fallback(
    canvas_w: int,
    canvas_h: int,
    framelines: list[dict],
    description: str,
) -> dict:
    """Generate FDL in v2.0.1 format using raw dicts (no fdl library)."""
    framing_decisions = []
    for fl in framelines:
        fw = float(fl.get("width", canvas_w))
        fh = float(fl.get("height", canvas_h))

        if fl.get("anchor_x") is not None and fl.get("anchor_y") is not None:
            ax, ay = float(fl["anchor_x"]), float(fl["anchor_y"])
        elif fl.get("h_align") or fl.get("v_align"):
            ax, ay = _compute_anchor_from_alignment(
                canvas_w,
                canvas_h,
                fw,
                fh,
                fl.get("h_align", "center"),
                fl.get("v_align", "center"),
            )
        else:
            ax, ay = _compute_anchor_from_alignment(canvas_w, canvas_h, fw, fh, "center", "center")

        fd: dict = {
            "id": str(uuid.uuid4()),
            "label": fl.get("label", ""),
            "framing_intent_id": fl.get("framing_intent", ""),
            "dimensions": {"width": fw, "height": fh},
            "anchor_point": {"x": ax, "y": ay},
        }

        if fl.get("protection_width") and fl.get("protection_height"):
            fd["protection_dimensions"] = {
                "width": float(fl["protection_width"]),
                "height": float(fl["protection_height"]),
            }
            fd["protection_anchor_point"] = {
                "x": float(fl.get("protection_anchor_x", 0)),
                "y": float(fl.get("protection_anchor_y", 0)),
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

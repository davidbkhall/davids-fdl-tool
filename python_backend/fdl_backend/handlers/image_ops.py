"""Image operations: load with overlay, get info.

Uses the ASC fdl library for geometry computations when available,
ensuring correct rect positions for all layers (canvas, effective,
protection, framing decisions).
"""

from __future__ import annotations

import base64
import io
from typing import Any

from fdl_backend.utils.fdl_convert import HAS_FDL

if HAS_FDL:
    from fdl_backend.utils.fdl_convert import dict_to_fdl

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


def load_and_overlay(params: dict) -> dict:
    """Load an image and draw FDL geometry layers as overlay.

    Params:
        image_path: str — path to image file
        fdl_data: dict — FDL document with contexts/canvases/framing decisions
        layers: dict — layer visibility overrides (canvas, effective, protection, framing, labels, crosshairs)
    """
    if Image is None:
        raise ImportError("Pillow is required for image operations")

    image_path = params["image_path"]
    fdl_data = params.get("fdl_data", {})
    layers = params.get("layers", {})

    show_canvas = layers.get("canvas", False)
    show_effective = layers.get("effective", True)
    show_protection = layers.get("protection", True)
    show_framing = layers.get("framing", True)
    show_labels = layers.get("labels", True)
    show_crosshairs = layers.get("crosshairs", False)

    img = Image.open(image_path).convert("RGB")
    draw = ImageDraw.Draw(img)
    img_w, img_h = img.size

    if HAS_FDL:
        _draw_overlay_with_library(draw, img_w, img_h, fdl_data, show_canvas, show_effective, show_protection, show_framing, show_labels, show_crosshairs)
    else:
        _draw_overlay_fallback(draw, img_w, img_h, fdl_data, show_labels)

    buf = io.BytesIO()
    img.save(buf, format="PNG")
    png_b64 = base64.b64encode(buf.getvalue()).decode("ascii")

    return {"png_base64": png_b64, "width": img_w, "height": img_h}


def get_info(params: dict) -> dict:
    """Get image dimensions and metadata.

    Params:
        image_path: str — path to image file
    """
    if Image is None:
        raise ImportError("Pillow is required for image operations")

    image_path = params["image_path"]
    img = Image.open(image_path)

    info: dict[str, Any] = {
        "width": img.width,
        "height": img.height,
        "mode": img.mode,
        "format": img.format or "unknown",
    }

    if hasattr(img, "info"):
        dpi = img.info.get("dpi")
        if dpi:
            info["dpi"] = list(dpi)

    return info


# ---------------------------------------------------------------------------
# Internal overlay drawing
# ---------------------------------------------------------------------------


def _draw_overlay_with_library(
    draw: Any,
    img_w: int,
    img_h: int,
    fdl_data: dict,
    show_canvas: bool,
    show_effective: bool,
    show_protection: bool,
    show_framing: bool,
    show_labels: bool,
    show_crosshairs: bool,
) -> None:
    """Draw all geometry layers using fdl library rect computations."""
    try:
        fdl_obj = dict_to_fdl(fdl_data)
    except Exception:
        _draw_overlay_fallback(draw, img_w, img_h, fdl_data, show_labels)
        return

    color_idx = 0
    for ctx in fdl_obj.contexts:
        for canvas in ctx.canvases:
            canvas_rect = canvas.get_rect()
            cw, ch = canvas_rect.width, canvas_rect.height
            scale_x = img_w / cw if cw > 0 else 1
            scale_y = img_h / ch if ch > 0 else 1

            if show_canvas:
                _draw_scaled_rect(draw, canvas_rect, scale_x, scale_y, outline="#888888", width=1)
                if show_labels:
                    draw.text(
                        (4, 2),
                        f"Canvas {int(cw)}\u00d7{int(ch)}",
                        fill="#888888",
                    )

            eff_rect = canvas.get_effective_rect()
            if show_effective and eff_rect:
                _draw_scaled_rect(draw, eff_rect, scale_x, scale_y, outline="#5AC8FA", width=1)
                if show_labels:
                    ex = int(eff_rect.x * scale_x)
                    ey = int(eff_rect.y * scale_y)
                    draw.text(
                        (ex + 4, ey + 2),
                        f"Effective {int(eff_rect.width)}\u00d7{int(eff_rect.height)}",
                        fill="#5AC8FA",
                    )

            for fd in canvas.framing_decisions:
                color = FRAMELINE_COLORS[color_idx % len(FRAMELINE_COLORS)]

                prot_rect = fd.get_protection_rect()
                if show_protection and prot_rect:
                    _draw_dashed_rect(draw, prot_rect, scale_x, scale_y, outline="#FF9500", width=1)

                fd_rect = fd.get_rect()
                if show_framing:
                    _draw_scaled_rect(draw, fd_rect, scale_x, scale_y, outline=color, width=2)

                    if show_crosshairs:
                        cx = int((fd_rect.x + fd_rect.width / 2) * scale_x)
                        cy = int((fd_rect.y + fd_rect.height / 2) * scale_y)
                        draw.line([(cx - 10, cy), (cx + 10, cy)], fill=color, width=1)
                        draw.line([(cx, cy - 10), (cx, cy + 10)], fill=color, width=1)

                    if show_labels and fd.label:
                        fx = int(fd_rect.x * scale_x)
                        fy = int(fd_rect.y * scale_y)
                        draw.text((fx + 4, fy + 2), fd.label, fill=color)

                color_idx += 1


def _draw_scaled_rect(
    draw: Any,
    rect: Any,
    scale_x: float,
    scale_y: float,
    outline: str,
    width: int,
) -> None:
    """Draw a rect scaled to image coordinates."""
    x1 = int(rect.x * scale_x)
    y1 = int(rect.y * scale_y)
    x2 = int((rect.x + rect.width) * scale_x)
    y2 = int((rect.y + rect.height) * scale_y)
    draw.rectangle([x1, y1, x2, y2], outline=outline, width=width)


def _draw_dashed_rect(
    draw: Any,
    rect: Any,
    scale_x: float,
    scale_y: float,
    outline: str,
    width: int = 1,
    dash_length: int = 8,
    gap_length: int = 5,
) -> None:
    """Draw a dashed rect (for protection boundaries)."""
    x1 = int(rect.x * scale_x)
    y1 = int(rect.y * scale_y)
    x2 = int((rect.x + rect.width) * scale_x)
    y2 = int((rect.y + rect.height) * scale_y)
    for start, end in [(x1, x2), (x1, x2)]:
        for edge_y in [y1, y2]:
            x = start
            while x < end:
                seg_end = min(x + dash_length, end)
                draw.line([(x, edge_y), (seg_end, edge_y)], fill=outline, width=width)
                x += dash_length + gap_length
    for start, end in [(y1, y2), (y1, y2)]:
        for edge_x in [x1, x2]:
            y = start
            while y < end:
                seg_end = min(y + dash_length, end)
                draw.line([(edge_x, y), (edge_x, seg_end)], fill=outline, width=width)
                y += dash_length + gap_length


def _draw_overlay_fallback(
    draw: Any,
    img_w: int,
    img_h: int,
    fdl_data: dict,
    show_labels: bool,
) -> None:
    """Draw frameline overlay using raw dict geometry (no fdl library)."""
    color_idx = 0
    for ctx in fdl_data.get("contexts", fdl_data.get("fdl_contexts", [])):
        for canvas in ctx.get("canvases", []):
            canvas_dims = canvas.get("dimensions", {})
            cw = canvas_dims.get("width", img_w)
            ch = canvas_dims.get("height", img_h)
            scale_x = img_w / cw if cw > 0 else 1
            scale_y = img_h / ch if ch > 0 else 1

            for fd in canvas.get("framing_decisions", []):
                fd_dims = fd.get("dimensions", {})
                fw = fd_dims.get("width", 0)
                fh = fd_dims.get("height", 0)

                anchor = fd.get("anchor_point", fd.get("anchor", {}))
                ax = anchor.get("x", (cw - fw) / 2)
                ay = anchor.get("y", (ch - fh) / 2)

                x1 = int(ax * scale_x)
                y1 = int(ay * scale_y)
                x2 = int((ax + fw) * scale_x)
                y2 = int((ay + fh) * scale_y)

                color = FRAMELINE_COLORS[color_idx % len(FRAMELINE_COLORS)]
                draw.rectangle([x1, y1, x2, y2], outline=color, width=2)

                label = fd.get("label", "")
                if show_labels and label:
                    draw.text((x1 + 4, y1 + 2), label, fill=color)

                color_idx += 1

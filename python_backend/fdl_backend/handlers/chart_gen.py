"""Framing chart generation: SVG, PNG, and FDL output."""

import base64
import io
import json
import uuid
from typing import Any

try:
    import svgwrite
except ImportError:
    svgwrite = None

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    Image = None


# Default colors for framelines
FRAMELINE_COLORS = [
    "#FF3B30",  # Red
    "#007AFF",  # Blue
    "#34C759",  # Green
    "#FF9500",  # Orange
    "#AF52DE",  # Purple
    "#FFD60A",  # Yellow
    "#5AC8FA",  # Cyan
    "#FF2D55",  # Pink
]


def generate_svg(params: dict) -> dict:
    """Generate a framing chart as SVG.

    Params:
        canvas_width: int — canvas width in pixels
        canvas_height: int — canvas height in pixels
        framelines: list of {label, width, height, color?}
        title: str — chart title
        show_labels: bool — whether to draw labels
        padding: int — padding around chart
    """
    if svgwrite is None:
        raise ImportError("svgwrite is required for SVG generation. Install with: pip install svgwrite")

    canvas_w = params.get("canvas_width", 4096)
    canvas_h = params.get("canvas_height", 2160)
    framelines = params.get("framelines", [])
    title = params.get("title", "Framing Chart")
    show_labels = params.get("show_labels", True)
    padding = params.get("padding", 60)

    # SVG dimensions (scaled to reasonable display size)
    scale = min(800 / canvas_w, 600 / canvas_h)
    svg_w = int(canvas_w * scale) + padding * 2
    svg_h = int(canvas_h * scale) + padding * 2 + (40 if title else 0)

    dwg = svgwrite.Drawing(size=(svg_w, svg_h))

    # Background
    dwg.add(dwg.rect(insert=(0, 0), size=(svg_w, svg_h), fill="#1a1a1a"))

    # Title
    title_offset = 0
    if title:
        title_offset = 40
        dwg.add(dwg.text(title, insert=(svg_w / 2, 28), fill="white",
                         font_size="16px", font_family="sans-serif",
                         text_anchor="middle"))

    # Canvas outline
    cx, cy = padding, padding + title_offset
    cw, ch = int(canvas_w * scale), int(canvas_h * scale)
    dwg.add(dwg.rect(insert=(cx, cy), size=(cw, ch),
                      fill="none", stroke="#444", stroke_width=1))

    # Draw framelines (centered within canvas)
    for i, fl in enumerate(framelines):
        fw = fl.get("width", canvas_w)
        fh = fl.get("height", canvas_h)
        color = fl.get("color", FRAMELINE_COLORS[i % len(FRAMELINE_COLORS)])
        label = fl.get("label", "")

        # Scale and center
        sw = int(fw * scale)
        sh = int(fh * scale)
        sx = cx + (cw - sw) // 2
        sy = cy + (ch - sh) // 2

        dwg.add(dwg.rect(insert=(sx, sy), size=(sw, sh),
                          fill="none", stroke=color, stroke_width=2))

        if show_labels and label:
            dwg.add(dwg.text(label, insert=(sx + 4, sy + 14), fill=color,
                             font_size="11px", font_family="sans-serif"))

    # Canvas dimensions label
    dim_label = f"{canvas_w} \u00d7 {canvas_h}"
    dwg.add(dwg.text(dim_label, insert=(cx + cw - 4, cy + ch - 6), fill="#666",
                     font_size="10px", font_family="monospace", text_anchor="end"))

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
    draw.rectangle([cx, cy, cx + cw, cy + ch], outline="#444444")

    for i, fl in enumerate(framelines):
        fw = fl.get("width", canvas_w)
        fh = fl.get("height", canvas_h)
        color = fl.get("color", FRAMELINE_COLORS[i % len(FRAMELINE_COLORS)])

        sw = int(fw * scale)
        sh = int(fh * scale)
        sx = cx + (cw - sw) // 2
        sy = cy + (ch - sh) // 2

        draw.rectangle([sx, sy, sx + sw, sy + sh], outline=color, width=2)

        label = fl.get("label", "")
        if label:
            draw.text((sx + 4, sy + 2), label, fill=color)

    buf = io.BytesIO()
    img.save(buf, format="PNG", dpi=(dpi, dpi))
    png_b64 = base64.b64encode(buf.getvalue()).decode("ascii")

    return {"png_base64": png_b64}


def generate_fdl(params: dict) -> dict:
    """Generate an FDL JSON document from chart configuration.

    Params:
        canvas_width: int
        canvas_height: int
        framelines: list of {label, width, height}
        camera_model: str (optional)
        description: str (optional)
    """
    canvas_w = params.get("canvas_width", 4096)
    canvas_h = params.get("canvas_height", 2160)
    framelines = params.get("framelines", [])
    description = params.get("description", "Generated by FDL Tool Chart Generator")

    fdl_uuid = str(uuid.uuid4())
    context_uuid = str(uuid.uuid4())
    canvas_uuid = str(uuid.uuid4())

    framing_decisions = []
    for fl in framelines:
        fd_uuid = str(uuid.uuid4())
        fd = {
            "fd_uuid": fd_uuid,
            "label": fl.get("label", ""),
            "dimensions": {
                "width": fl.get("width", canvas_w),
                "height": fl.get("height", canvas_h),
            },
        }
        if "framing_intent" in fl:
            fd["framing_intent"] = fl["framing_intent"]
        framing_decisions.append(fd)

    doc = {
        "uuid": fdl_uuid,
        "header": {
            "uuid": fdl_uuid,
            "version": "2.0.1",
            "fdl_creator": "FDL Tool",
            "description": description,
        },
        "fdl_contexts": [
            {
                "context_uuid": context_uuid,
                "label": "Chart Generated",
                "context_creator": "FDL Tool Chart Generator",
                "canvases": [
                    {
                        "canvas_uuid": canvas_uuid,
                        "label": f"{canvas_w}x{canvas_h}",
                        "dimensions": {"width": canvas_w, "height": canvas_h},
                        "framing_decisions": framing_decisions,
                    }
                ],
            }
        ],
    }

    return {"fdl": doc}

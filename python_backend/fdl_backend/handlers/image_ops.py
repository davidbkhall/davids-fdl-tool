"""Image operations: load with overlay, get info."""

import base64
import io

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
    """Load an image and draw FDL framelines as overlay.

    Params:
        image_path: str — path to image file
        fdl_data: dict — FDL document with contexts/canvases/framing decisions
    """
    if Image is None:
        raise ImportError("Pillow is required for image operations")

    image_path = params["image_path"]
    fdl_data = params.get("fdl_data", {})

    img = Image.open(image_path).convert("RGB")
    draw = ImageDraw.Draw(img)
    img_w, img_h = img.size

    # Draw framelines from FDL
    color_idx = 0
    for ctx in fdl_data.get("fdl_contexts", []):
        for canvas in ctx.get("canvases", []):
            canvas_dims = canvas.get("dimensions", {})
            cw = canvas_dims.get("width", img_w)
            ch = canvas_dims.get("height", img_h)

            # Scale factor from canvas to image
            scale_x = img_w / cw if cw > 0 else 1
            scale_y = img_h / ch if ch > 0 else 1

            for fd in canvas.get("framing_decisions", []):
                fd_dims = fd.get("dimensions", {})
                fw = fd_dims.get("width", 0)
                fh = fd_dims.get("height", 0)

                anchor = fd.get("anchor", {})
                ax = anchor.get("x", (cw - fw) / 2)
                ay = anchor.get("y", (ch - fh) / 2)

                # Map to image coordinates
                x1 = int(ax * scale_x)
                y1 = int(ay * scale_y)
                x2 = int((ax + fw) * scale_x)
                y2 = int((ay + fh) * scale_y)

                color = FRAMELINE_COLORS[color_idx % len(FRAMELINE_COLORS)]
                draw.rectangle([x1, y1, x2, y2], outline=color, width=2)

                label = fd.get("label", "")
                if label:
                    draw.text((x1 + 4, y1 + 2), label, fill=color)

                color_idx += 1

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

    info = {
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

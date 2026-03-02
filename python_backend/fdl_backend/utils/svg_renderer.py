"""SVG chart rendering utilities."""

from typing import Any

try:
    import svgwrite
except ImportError:
    svgwrite = None


def create_chart_svg(
    canvas_width: int,
    canvas_height: int,
    framelines: list[dict],
    title: str = "",
    padding: int = 60,
    scale: float | None = None,
) -> str:
    """Create a framing chart SVG string.

    Args:
        canvas_width: Canvas width in pixels
        canvas_height: Canvas height in pixels
        framelines: List of dicts with 'label', 'width', 'height', 'color'
        title: Chart title
        padding: Padding around chart
        scale: Display scale factor (auto-calculated if None)

    Returns:
        SVG string
    """
    if svgwrite is None:
        raise ImportError("svgwrite is required")

    if scale is None:
        scale = min(800 / canvas_width, 600 / canvas_height)

    svg_w = int(canvas_width * scale) + padding * 2
    svg_h = int(canvas_height * scale) + padding * 2

    dwg = svgwrite.Drawing(size=(svg_w, svg_h))
    dwg.add(dwg.rect(insert=(0, 0), size=(svg_w, svg_h), fill="#1a1a1a"))

    # Canvas outline
    cx, cy = padding, padding
    cw = int(canvas_width * scale)
    ch = int(canvas_height * scale)
    dwg.add(dwg.rect(insert=(cx, cy), size=(cw, ch),
                      fill="none", stroke="#444", stroke_width=1))

    colors = ["#FF3B30", "#007AFF", "#34C759", "#FF9500",
              "#AF52DE", "#FFD60A", "#5AC8FA", "#FF2D55"]

    for i, fl in enumerate(framelines):
        fw = int(fl["width"] * scale)
        fh = int(fl["height"] * scale)
        color = fl.get("color", colors[i % len(colors)])

        sx = cx + (cw - fw) // 2
        sy = cy + (ch - fh) // 2

        dwg.add(dwg.rect(insert=(sx, sy), size=(fw, fh),
                          fill="none", stroke=color, stroke_width=2))

    return dwg.tostring()

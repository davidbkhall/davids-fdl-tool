"""Bidirectional converter between FDL and ARRI frameline XML.

FDL -> ARRI
    Reads an FDL, extracts the canvas and framing decision geometry,
    and maps each geometry layer to a ``FramelineBox`` (four ``<line>``
    elements) inside an ARRI FLT XML file.

ARRI -> FDL
    Parses an ARRI FLT XML, converts the normalised line coordinates
    back to pixel dimensions, and builds a valid FDL with context,
    canvas, framing intent, and framing decision(s).
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from pathlib import Path

from fdl import (
    FDL,
    Canvas,
    Context,
    DimensionsFloat,
    DimensionsInt,
    FramingDecision,
    FramingIntent,
    PointFloat,
    read_from_file,
    write_to_file,
)

from fdl_arri_frameline.cameras import get_camera
from fdl_arri_frameline.models import (
    ArriFrameline,
    CameraInfo,
    CenterMarker,
    FramelineBox,
    Surround,
    read_xml,
    write_xml,
)

logger = logging.getLogger(__name__)

FDL_CREATOR = "fdl-arri-frameline"

FORMAT_IDS = ("formatA", "formatB", "formatC")


# ---------------------------------------------------------------------------
# Result types
# ---------------------------------------------------------------------------


@dataclass
class ConversionResult:
    """Result of an FDL -> ARRI frameline conversion."""

    frameline: ArriFrameline
    source_fdl_path: str | None = None
    camera_type: str = ""
    sensor_mode: str = ""
    boxes_generated: int = 0


@dataclass
class FDLConversionResult:
    """Result of an ARRI frameline -> FDL conversion."""

    fdl: FDL
    source_xml_path: str | None = None
    framing_decisions_created: int = 0


# ---------------------------------------------------------------------------
# FDL -> ARRI frameline
# ---------------------------------------------------------------------------


def _normalise_rect(
    anchor_x: float,
    anchor_y: float,
    width: float,
    height: float,
    canvas_width: float,
    canvas_height: float,
) -> tuple[float, float, float, float]:
    """Convert pixel-space geometry to ARRI normalised edge insets.

    Returns (left, right, top, bottom) where each value is the
    fractional distance from the corresponding edge.
    """
    left = anchor_x / canvas_width if canvas_width else 0.0
    top = anchor_y / canvas_height if canvas_height else 0.0
    right = 1.0 - (anchor_x + width) / canvas_width if canvas_width else 0.0
    bottom = 1.0 - (anchor_y + height) / canvas_height if canvas_height else 0.0

    left = max(0.0, min(1.0, left))
    right = max(0.0, min(1.0, right))
    top = max(0.0, min(1.0, top))
    bottom = max(0.0, min(1.0, bottom))

    return left, right, top, bottom


def fdl_to_arri_frameline(
    fdl_path: str | Path,
    camera_type: str,
    sensor_mode: str,
    *,
    include_protection: bool = True,
    include_effective: bool = False,
    surround_opacity: float = 0.5,
    line_width: int = 4,
    context_label: str | None = None,
    canvas_id: str | None = None,
) -> ConversionResult:
    """Convert an FDL file to an ARRI frameline XML model.

    Parameters
    ----------
    fdl_path:
        Path to the source FDL file.
    camera_type:
        ARRI camera model string (e.g. "ALEXA 35").
    sensor_mode:
        Sensor mode name (e.g. "4.6K 3:2 Open Gate").
    include_protection:
        Generate a box for the protection area if present.
    include_effective:
        Generate a box for the effective area if present.
    surround_opacity:
        Unused in v2.2 format but kept for API compat.
    line_width:
        Line width in pixels for the frameline borders.
    context_label:
        Select a specific context by label. Defaults to first.
    canvas_id:
        Select a specific canvas by id. Defaults to first.
    """
    fdl = read_from_file(Path(fdl_path))
    camera = get_camera(camera_type)
    mode = camera.get_mode(sensor_mode)

    context = _resolve_context(fdl, context_label)
    canvas = _resolve_canvas(context, canvas_id)
    if not canvas.framing_decisions:
        raise ValueError(f"Canvas {canvas.id!r} has no framing decisions")
    framing = canvas.framing_decisions[0]

    canvas_w = float(canvas.dimensions.width)
    canvas_h = float(canvas.dimensions.height)

    boxes: list[FramelineBox] = []
    fmt_idx = 0

    # Framing decision box
    fd_left, fd_right, fd_top, fd_bottom = _normalise_rect(
        framing.anchor_point.x,
        framing.anchor_point.y,
        framing.dimensions.width,
        framing.dimensions.height,
        canvas_w,
        canvas_h,
    )

    fd_aspect = framing.dimensions.width / framing.dimensions.height if framing.dimensions.height else 0
    boxes.append(
        FramelineBox(
            format_id=FORMAT_IDS[fmt_idx],
            name=f"FDL Framing {fd_aspect:.2f}:1",
            scaling=100.0,
            left=fd_left,
            right=fd_right,
            top=fd_top,
            bottom=fd_bottom,
            line_width=line_width,
        )
    )
    fmt_idx += 1

    # Protection box
    if include_protection and framing.protection_dimensions and framing.protection_anchor_point:
        p_left, p_right, p_top, p_bottom = _normalise_rect(
            framing.protection_anchor_point.x,
            framing.protection_anchor_point.y,
            framing.protection_dimensions.width,
            framing.protection_dimensions.height,
            canvas_w,
            canvas_h,
        )
        boxes.append(
            FramelineBox(
                format_id=FORMAT_IDS[fmt_idx],
                name="FDL Protection",
                scaling=100.0,
                left=p_left,
                right=p_right,
                top=p_top,
                bottom=p_bottom,
                line_width=max(1, line_width // 2),
            )
        )
        fmt_idx += 1

    # Effective dimensions box
    if include_effective and canvas.effective_dimensions and canvas.effective_anchor_point:
        e_left, e_right, e_top, e_bottom = _normalise_rect(
            canvas.effective_anchor_point.x,
            canvas.effective_anchor_point.y,
            float(canvas.effective_dimensions.width),
            float(canvas.effective_dimensions.height),
            canvas_w,
            canvas_h,
        )
        boxes.append(
            FramelineBox(
                format_id=FORMAT_IDS[min(fmt_idx, len(FORMAT_IDS) - 1)],
                name="FDL Effective",
                scaling=100.0,
                left=e_left,
                right=e_right,
                top=e_top,
                bottom=e_bottom,
                line_width=max(1, line_width // 2),
            )
        )

    squeeze = getattr(canvas, "anamorphic_squeeze", 1.0) or 1.0
    xml_version = camera.xml_version
    is_old = not xml_version

    # Old-format cameras get a default line color per box
    if is_old:
        _OLD_COLORS = ("user", "user", "user")
        for i, box in enumerate(boxes):
            if not box.line_color:
                box.line_color = _OLD_COLORS[min(i, len(_OLD_COLORS) - 1)]

    frameline = ArriFrameline(
        version=xml_version,
        camera=CameraInfo(
            aspect=mode.aspect,
            camera_type=camera.camera_type,
            sensor_mode=mode.name,
            hres=mode.hres,
            vres=mode.vres,
            lens_squeeze=float(squeeze),
        ),
        boxes=boxes,
        center_marker=CenterMarker() if not is_old else None,
        surround=Surround(opacity=surround_opacity) if is_old else None,
    )

    return ConversionResult(
        frameline=frameline,
        source_fdl_path=str(fdl_path),
        camera_type=camera.camera_type,
        sensor_mode=mode.name,
        boxes_generated=len(boxes),
    )


def convert_and_write(
    fdl_path: str | Path,
    output_path: str | Path,
    camera_type: str,
    sensor_mode: str,
    **kwargs,
) -> ConversionResult:
    """Convert an FDL to ARRI frameline XML and write to disk."""
    result = fdl_to_arri_frameline(fdl_path, camera_type, sensor_mode, **kwargs)
    write_xml(result.frameline, output_path)
    logger.info("Wrote ARRI frameline XML to %s (%d boxes)", output_path, result.boxes_generated)
    return result


# ---------------------------------------------------------------------------
# ARRI frameline -> FDL
# ---------------------------------------------------------------------------


def arri_frameline_to_fdl(
    xml_path: str | Path,
    *,
    context_label: str = "ARRI Frameline",
    canvas_label: str | None = None,
    hres: int | None = None,
    vres: int | None = None,
) -> FDLConversionResult:
    """Convert an ARRI frameline XML file to an FDL.

    Each ``FramelineBox`` becomes a framing decision on the canvas.
    The camera resolution is extracted from the XML comment metadata,
    or can be supplied explicitly via *hres* / *vres*.

    Parameters
    ----------
    xml_path:
        Path to the ARRI frameline XML file.
    context_label:
        Label for the created FDL context.
    canvas_label:
        Optional label for the canvas. Defaults to camera type + sensor.
    hres:
        Explicit horizontal resolution. Overrides value from XML metadata.
    vres:
        Explicit vertical resolution. Overrides value from XML metadata.
    """
    frameline = read_xml(Path(xml_path))
    cam = frameline.camera

    if hres is not None:
        cam.hres = hres
    if vres is not None:
        cam.vres = vres

    if not cam.hres or not cam.vres:
        raise ValueError(
            "Frameline XML has no camera resolution. "
            "Supply hres/vres explicitly or ensure the file was exported "
            "from the ARRI FLT tool (which includes resolution in a comment block)."
        )

    fdl_obj = _build_fdl_from_frameline(frameline, context_label, canvas_label)

    fd_count = sum(len(c.framing_decisions) for ctx in fdl_obj.contexts for c in ctx.canvases)

    return FDLConversionResult(
        fdl=fdl_obj,
        source_xml_path=str(xml_path),
        framing_decisions_created=fd_count,
    )


def convert_xml_to_fdl_file(
    xml_path: str | Path,
    output_path: str | Path,
    **kwargs,
) -> FDLConversionResult:
    """Convert an ARRI frameline XML to FDL and write to disk."""
    result = arri_frameline_to_fdl(xml_path, **kwargs)
    write_to_file(result.fdl, Path(output_path))
    logger.info("Wrote FDL to %s (%d framing decisions)", output_path, result.framing_decisions_created)
    return result


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _resolve_context(fdl: FDL, label: str | None) -> Context:
    if label:
        for ctx in fdl.contexts:
            if ctx.label == label:
                return ctx
        raise ValueError(f"Context with label {label!r} not found")
    if not fdl.contexts:
        raise ValueError("FDL has no contexts")
    return fdl.contexts[0]


def _resolve_canvas(context: Context, canvas_id: str | None) -> Canvas:
    if canvas_id:
        for c in context.canvases:
            if c.id == canvas_id:
                return c
        raise ValueError(f"Canvas with id {canvas_id!r} not found")
    if not context.canvases:
        raise ValueError("Context has no canvases")
    return context.canvases[0]


def _denormalise_rect(
    left: float,
    right: float,
    top: float,
    bottom: float,
    hres: int,
    vres: int,
) -> tuple[float, float, float, float]:
    """Convert ARRI normalised edge insets to pixel-space geometry.

    Returns (anchor_x, anchor_y, width, height).
    """
    anchor_x = left * hres
    anchor_y = top * vres
    width = (1.0 - left - right) * hres
    height = (1.0 - top - bottom) * vres
    return anchor_x, anchor_y, max(0.0, width), max(0.0, height)


def _build_fdl_from_frameline(
    frameline: ArriFrameline,
    context_label: str,
    canvas_label: str | None,
) -> FDL:
    """Construct an FDL from parsed ARRI frameline data."""
    cam = frameline.camera
    hres = cam.hres
    vres = cam.vres

    canvas_id = _fdl_id()
    canvas_lbl = canvas_label or f"{cam.camera_type} {cam.sensor_mode}".strip()

    canvas = Canvas(
        label=canvas_lbl,
        id=canvas_id,
        source_canvas_id=canvas_id,
        dimensions=DimensionsInt(width=hres, height=vres),
    )
    if cam.lens_squeeze != 1.0:
        canvas.anamorphic_squeeze = cam.lens_squeeze

    fdl_obj = FDL(fdl_creator=FDL_CREATOR)

    for i, box in enumerate(frameline.boxes):
        ax, ay, w, h = _denormalise_rect(box.left, box.right, box.top, box.bottom, hres, vres)

        box_label = box.name or f"format_{i}"
        aspect_w = round(w) if w else hres
        aspect_h = round(h) if h else vres

        intent_id = _fdl_id()
        intent = FramingIntent(
            label=box_label,
            id=intent_id,
            aspect_ratio=DimensionsInt(width=aspect_w, height=aspect_h),
        )
        fdl_obj.framing_intents.append(intent)

        fd = FramingDecision(
            label=box_label,
            id=f"{canvas_id}-{intent_id}",
            framing_intent_id=intent_id,
            dimensions=DimensionsFloat(width=w, height=h),
            anchor_point=PointFloat(x=ax, y=ay),
        )
        canvas.framing_decisions.append(fd)

    context = Context(label=context_label)
    context.canvases.append(canvas)
    fdl_obj.contexts.append(context)

    if fdl_obj.framing_intents:
        fdl_obj.default_framing_intent = fdl_obj.framing_intents[0].id

    return fdl_obj


def _fdl_id() -> str:
    """Generate an ID matching ``fdl_id`` pattern: ``^[A-Za-z0-9_]+$``."""
    return uuid.uuid4().hex[:16]

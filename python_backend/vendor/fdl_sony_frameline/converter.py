"""Bidirectional converter between FDL and Sony VENICE frameline XML.

FDL -> Sony
    Reads an FDL, extracts the canvas and framing decision geometry,
    and produces one or two ``SonyFrameline`` objects (one per geometry
    layer).  Each is written to a separate XML file because the camera
    loads one file per frame line slot (L1 / L2).

Sony -> FDL
    Parses a Sony frameline XML, converts the normalised corner-point
    coordinates back to pixel dimensions, and builds a valid FDL
    with context, canvas, framing intent, and framing decision.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass, field
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

from fdl_sony_frameline.cameras import get_camera, get_camera_by_model_code
from fdl_sony_frameline.models import (
    CameraSettings,
    FrameLineRect,
    SonyFrameline,
    frameline_rect_from_insets,
    read_xml,
    write_xml,
)

logger = logging.getLogger(__name__)

FDL_CREATOR = "fdl-sony-frameline"

MAX_FRAME_LINES = 2


# ---------------------------------------------------------------------------
# Result types
# ---------------------------------------------------------------------------


@dataclass
class ConversionResult:
    """Result of an FDL -> Sony frameline conversion.

    Contains up to 2 SonyFrameline objects (one per camera slot).
    """

    framelines: list[SonyFrameline] = field(default_factory=list)
    source_fdl_path: str | None = None
    camera_type: str = ""
    imager_mode: str = ""

    @property
    def frame_lines_generated(self) -> int:
        return len(self.framelines)


@dataclass
class FDLConversionResult:
    """Result of a Sony frameline -> FDL conversion."""

    fdl: FDL
    source_xml_path: str | None = None
    framing_decisions_created: int = 0


# ---------------------------------------------------------------------------
# FDL -> Sony frameline
# ---------------------------------------------------------------------------


def _normalise_to_insets(
    anchor_x: float,
    anchor_y: float,
    width: float,
    height: float,
    canvas_width: float,
    canvas_height: float,
) -> tuple[float, float, float, float]:
    """Convert pixel-space geometry to normalised edge insets.

    Returns (left, right, top, bottom) where each value is the
    fractional distance from the corresponding edge, clamped to [0, 1].
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


def fdl_to_sony_frameline(
    fdl_path: str | Path,
    camera_type: str,
    imager_mode: str,
    *,
    include_protection: bool = False,
    framing_color: str = "White",
    protection_color: str = "Yellow",
    context_label: str | None = None,
    canvas_id: str | None = None,
) -> ConversionResult:
    """Convert an FDL file to Sony frameline XML model(s).

    Produces one ``SonyFrameline`` for the framing decision, and
    optionally a second one for the protection area.  The camera
    has two frame line slots (L1 / L2), each loaded from a separate
    XML file, so at most 2 can be generated.

    Parameters
    ----------
    fdl_path:
        Path to the source FDL file.
    camera_type:
        Sony camera model string (e.g. "VENICE 2 8K") or model code
        (e.g. "MPC-3628").
    imager_mode:
        Imager mode name (e.g. "6K 2.39:1").
    include_protection:
        Generate a second frame line for the protection area if present.
    framing_color:
        Colour for the framing decision frame line.
    protection_color:
        Colour for the protection frame line.
    context_label:
        Select a specific context by label. Defaults to first.
    canvas_id:
        Select a specific canvas by id. Defaults to first.
    """
    fdl = read_from_file(Path(fdl_path))
    camera = get_camera(camera_type)
    mode = camera.get_mode(imager_mode)

    context = _resolve_context(fdl, context_label)
    canvas = _resolve_canvas(context, canvas_id)
    if not canvas.framing_decisions:
        raise ValueError(f"Canvas {canvas.id!r} has no framing decisions")
    framing = canvas.framing_decisions[0]

    canvas_w = float(canvas.dimensions.width)
    canvas_h = float(canvas.dimensions.height)

    cam_settings = CameraSettings(model_code=camera.model_code, imager_mode=mode.name)
    framelines: list[SonyFrameline] = []

    fd_left, fd_right, fd_top, fd_bottom = _normalise_to_insets(
        framing.anchor_point.x,
        framing.anchor_point.y,
        framing.dimensions.width,
        framing.dimensions.height,
        canvas_w,
        canvas_h,
    )
    framelines.append(
        SonyFrameline(
            camera=CameraSettings(model_code=cam_settings.model_code, imager_mode=cam_settings.imager_mode),
            frame_line=frameline_rect_from_insets(fd_left, fd_right, fd_top, fd_bottom, color=framing_color),
        )
    )

    if include_protection and framing.protection_dimensions and framing.protection_anchor_point:
        p_left, p_right, p_top, p_bottom = _normalise_to_insets(
            framing.protection_anchor_point.x,
            framing.protection_anchor_point.y,
            framing.protection_dimensions.width,
            framing.protection_dimensions.height,
            canvas_w,
            canvas_h,
        )
        framelines.append(
            SonyFrameline(
                camera=CameraSettings(model_code=cam_settings.model_code, imager_mode=cam_settings.imager_mode),
                frame_line=frameline_rect_from_insets(p_left, p_right, p_top, p_bottom, color=protection_color),
            )
        )

    return ConversionResult(
        framelines=framelines[:MAX_FRAME_LINES],
        source_fdl_path=str(fdl_path),
        camera_type=camera.camera_type,
        imager_mode=mode.name,
    )


def convert_and_write(
    fdl_path: str | Path,
    output_path: str | Path,
    camera_type: str,
    imager_mode: str,
    **kwargs,
) -> ConversionResult:
    """Convert an FDL to Sony frameline XML(s) and write to disk.

    When a single frame line is generated, writes to ``output_path``
    directly.  When two are generated (framing + protection), writes
    ``<stem>_L1.xml`` and ``<stem>_L2.xml`` next to ``output_path``.
    """
    result = fdl_to_sony_frameline(fdl_path, camera_type, imager_mode, **kwargs)
    out = Path(output_path)

    if len(result.framelines) == 1:
        write_xml(result.framelines[0], out)
        logger.info("Wrote Sony frameline XML to %s", out)
    else:
        for i, fl in enumerate(result.framelines, start=1):
            slot_path = out.parent / f"{out.stem}_L{i}{out.suffix}"
            write_xml(fl, slot_path)
            logger.info("Wrote Sony frameline XML (L%d) to %s", i, slot_path)

    return result


# ---------------------------------------------------------------------------
# Sony frameline -> FDL
# ---------------------------------------------------------------------------


def _insets_from_rect(rect: FrameLineRect) -> tuple[float, float, float, float]:
    """Extract normalised edge insets from a Sony FrameLineRect.

    Returns (left, right, top, bottom).
    """
    return rect.left_inset, rect.right_inset, rect.top_inset, rect.bottom_inset


def _denormalise_insets(
    left: float,
    right: float,
    top: float,
    bottom: float,
    hres: int,
    vres: int,
) -> tuple[float, float, float, float]:
    """Convert normalised edge insets to pixel-space geometry.

    Returns (anchor_x, anchor_y, width, height).
    """
    anchor_x = left * hres
    anchor_y = top * vres
    width = (1.0 - left - right) * hres
    height = (1.0 - top - bottom) * vres
    return anchor_x, anchor_y, max(0.0, width), max(0.0, height)


def sony_frameline_to_fdl(
    xml_path: str | Path,
    *,
    context_label: str = "Sony Frameline",
    canvas_label: str | None = None,
) -> FDLConversionResult:
    """Convert a Sony frameline XML file to an FDL.

    The frame line becomes a framing decision on the canvas. The
    camera's imager mode resolution defines the canvas dimensions.

    Parameters
    ----------
    xml_path:
        Path to the Sony frameline XML file.
    context_label:
        Label for the created FDL context.
    canvas_label:
        Optional label for the canvas. Defaults to camera type + imager mode.
    """
    frameline = read_xml(Path(xml_path))
    cam = frameline.camera

    if not cam.model_code or not cam.imager_mode:
        raise ValueError("Frameline XML has no camera settings (model code / imager mode)")

    camera = get_camera_by_model_code(cam.model_code)
    mode = camera.get_mode(cam.imager_mode)

    fdl_obj = _build_fdl_from_frameline(frameline, mode.hres, mode.vres, camera.camera_type, context_label, canvas_label)

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
    """Convert a Sony frameline XML to FDL and write to disk."""
    result = sony_frameline_to_fdl(xml_path, **kwargs)
    write_to_file(result.fdl, Path(output_path))
    logger.info(
        "Wrote FDL to %s (%d framing decisions)",
        output_path,
        result.framing_decisions_created,
    )
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


def _build_fdl_from_frameline(
    frameline: SonyFrameline,
    hres: int,
    vres: int,
    camera_type: str,
    context_label: str,
    canvas_label: str | None,
) -> FDL:
    """Construct an FDL from parsed Sony frameline data."""
    canvas_id = _fdl_id()
    canvas_lbl = canvas_label or f"{camera_type} {frameline.camera.imager_mode}"

    canvas = Canvas(
        label=canvas_lbl,
        id=canvas_id,
        source_canvas_id=canvas_id,
        dimensions=DimensionsInt(width=hres, height=vres),
    )

    fdl_obj = FDL(fdl_creator=FDL_CREATOR)

    rect = frameline.frame_line
    left, right, top, bottom = _insets_from_rect(rect)
    ax, ay, w, h = _denormalise_insets(left, right, top, bottom, hres, vres)

    aspect_w = round(w) if w else hres
    aspect_h = round(h) if h else vres

    intent_id = _fdl_id()
    intent = FramingIntent(
        label="frameline intent",
        id=intent_id,
        aspect_ratio=DimensionsInt(width=aspect_w, height=aspect_h),
    )
    fdl_obj.framing_intents.append(intent)

    fd = FramingDecision(
        label="frameline",
        id=f"{canvas_id}-{intent_id}",
        framing_intent_id=intent_id,
        dimensions=DimensionsFloat(width=w, height=h),
        anchor_point=PointFloat(x=ax, y=ay),
    )
    canvas.framing_decisions.append(fd)

    context = Context(label=context_label)
    context.canvases.append(canvas)
    fdl_obj.contexts.append(context)

    fdl_obj.default_framing_intent = intent_id

    return fdl_obj


def _fdl_id() -> str:
    """Generate an ID matching ``fdl_id`` pattern: ``^[A-Za-z0-9_]+$``."""
    return uuid.uuid4().hex[:16]

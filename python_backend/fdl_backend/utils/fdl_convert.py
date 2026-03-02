"""Bridge utilities between raw dicts and ASC fdl library objects.

Provides conversion in both directions so handlers can accept dict params
from JSON-RPC and return dict results, while using fdl library objects
for geometry, validation, and template operations internally.

The Swift frontend uses the v1 FDL JSON schema (with "header", "fdl_contexts",
"canvas_uuid", "fd_uuid", "anchor"). The fdl library's programmatic API produces
v2 format (with "version" object, "contexts", "id", "anchor_point"). This module
handles the translation between both.
"""

from __future__ import annotations

import json
import uuid as _uuid
from typing import Any

try:
    import fdl as fdl_lib
    from fdl import (
        FDL,
        Canvas,
        Context,
        FramingDecision,
        read_from_file,
        read_from_string,
        write_to_string,
    )
    from fdl.fdl_types import DimensionsFloat, DimensionsInt, PointFloat, Rect

    HAS_FDL = True
except ImportError:
    HAS_FDL = False


def require_fdl() -> None:
    """Raise a clear error if the fdl library is not available."""
    if not HAS_FDL:
        raise ImportError(
            "The ASC fdl library is required but not installed. "
            "Build and install from https://github.com/ascmitc/fdl/tree/dev"
        )


# ---------------------------------------------------------------------------
# Low-level type conversions
# ---------------------------------------------------------------------------


def rect_to_dict(rect: Any) -> dict[str, float]:
    """Convert an fdl Rect to a plain dict."""
    return {"x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height}


def dims_to_dict(dims: Any) -> dict[str, Any]:
    """Convert DimensionsInt or DimensionsFloat to a plain dict."""
    return {"width": dims.width, "height": dims.height}


def point_to_dict(point: Any) -> dict[str, float]:
    """Convert a PointFloat to a plain dict."""
    return {"x": point.x, "y": point.y}


# ---------------------------------------------------------------------------
# Parsing / I/O
# ---------------------------------------------------------------------------


def fdl_from_string(json_string: str, validate: bool = True) -> Any:
    """Parse an FDL JSON string into an fdl library object."""
    require_fdl()
    return read_from_string(json_string, validate=validate)


def fdl_from_path(path: str, validate: bool = True) -> Any:
    """Read an FDL file into an fdl library object."""
    require_fdl()
    return read_from_file(path, validate=validate)


def dict_to_fdl(data: dict) -> Any:
    """Convert a plain dict (from JSON-RPC params) into an fdl library FDL object.

    Detects v1 format (fdl_contexts, header) and converts to v2 before parsing,
    because the library only populates its object model (contexts, canvases,
    framing_decisions) from v2 format input.
    """
    require_fdl()
    if "fdl_contexts" in data or "header" in data:
        data = _v1_to_v2(data)
    json_str = json.dumps(data)
    return read_from_string(json_str, validate=False)


# ---------------------------------------------------------------------------
# Serialization (library object → dict)
# ---------------------------------------------------------------------------


def fdl_to_dict(fdl_obj: Any) -> dict:
    """Convert an fdl library FDL object to the v2.0.1 schema format.

    If the object was parsed from a legacy (pre-v2) format, converts to v2.
    """
    d = fdl_obj.as_dict()
    if "fdl_contexts" in d:
        return _v1_to_v2(d)
    return d


def fdl_to_json(fdl_obj: Any, indent: int = 2) -> str:
    """Serialize an fdl library object to a v2.0.1 JSON string."""
    return json.dumps(fdl_to_dict(fdl_obj), indent=indent, ensure_ascii=False)


# ---------------------------------------------------------------------------
# Programmatic FDL construction
# ---------------------------------------------------------------------------


def build_fdl(
    *,
    fdl_creator: str = "FDL Tool",
    description: str = "",
    default_framing_intent: str | None = None,
    fdl_uuid: str | None = None,
) -> Any:
    """Create a new empty FDL document using the fdl library."""
    require_fdl()
    return FDL(
        uuid=fdl_uuid or str(_uuid.uuid4()),
        fdl_creator=fdl_creator,
        default_framing_intent=default_framing_intent,
    )


def add_context_to_fdl(fdl_obj: Any, *, label: str = "", context_creator: str = "FDL Tool") -> Any:
    """Add a context to an FDL object and return it."""
    return fdl_obj.add_context(label=label, context_creator=context_creator)


def add_canvas_to_context(
    ctx: Any,
    *,
    label: str = "",
    width: int = 0,
    height: int = 0,
    canvas_id: str | None = None,
    source_canvas_id: str = "",
    effective_width: int | None = None,
    effective_height: int | None = None,
    effective_anchor_x: float = 0.0,
    effective_anchor_y: float = 0.0,
    anamorphic_squeeze: float = 1.0,
) -> Any:
    """Add a canvas to a context and return it."""
    require_fdl()
    canvas = ctx.add_canvas(
        canvas_id or str(_uuid.uuid4()),
        label,
        source_canvas_id,
        DimensionsInt(width=width, height=height),
        anamorphic_squeeze,
    )
    if effective_width is not None and effective_height is not None:
        canvas.set_effective(
            DimensionsInt(width=effective_width, height=effective_height),
            PointFloat(x=effective_anchor_x, y=effective_anchor_y),
        )
    return canvas


def add_framing_decision_to_canvas(
    canvas: Any,
    *,
    label: str = "",
    width: float = 0.0,
    height: float = 0.0,
    fd_id: str | None = None,
    framing_intent_id: str = "",
    anchor_x: float | None = None,
    anchor_y: float | None = None,
    protection_width: float | None = None,
    protection_height: float | None = None,
    protection_anchor_x: float = 0.0,
    protection_anchor_y: float = 0.0,
) -> Any:
    """Add a framing decision to a canvas and return it."""
    require_fdl()

    anchor = PointFloat(x=anchor_x or 0.0, y=anchor_y or 0.0)

    fd = canvas.add_framing_decision(
        fd_id or str(_uuid.uuid4()),
        label,
        framing_intent_id or "",
        DimensionsFloat(width=width, height=height),
        anchor,
    )

    if protection_width is not None and protection_height is not None:
        fd.set_protection(
            DimensionsFloat(width=protection_width, height=protection_height),
            PointFloat(x=protection_anchor_x, y=protection_anchor_y),
        )

    return fd


# ---------------------------------------------------------------------------
# Geometry extraction
# ---------------------------------------------------------------------------


def extract_all_rects(fdl_obj: Any) -> list[dict]:
    """Extract geometry rects for every context/canvas/fd in an FDL object.

    Returns a list of context dicts, each containing canvases with their
    geometry rectangles and framing decision rectangles.
    """
    require_fdl()
    contexts_out = []

    for ctx in fdl_obj.contexts:
        canvases_out = []
        for canvas in ctx.canvases:
            canvas_rect = rect_to_dict(canvas.get_rect())
            eff_rect_obj = canvas.get_effective_rect()
            effective_rect = rect_to_dict(eff_rect_obj) if eff_rect_obj else None

            fds_out = []
            for fd in canvas.framing_decisions:
                fd_rect = rect_to_dict(fd.get_rect())
                prot_rect_obj = fd.get_protection_rect()
                protection_rect = rect_to_dict(prot_rect_obj) if prot_rect_obj else None

                fds_out.append({
                    "label": fd.label or "",
                    "framing_intent": fd.framing_intent_id or "",
                    "framing_rect": fd_rect,
                    "protection_rect": protection_rect,
                    "anchor_point": point_to_dict(fd.anchor_point) if fd.anchor_point else None,
                })

            canvases_out.append({
                "label": canvas.label,
                "canvas_rect": canvas_rect,
                "effective_rect": effective_rect,
                "framing_decisions": fds_out,
            })

        contexts_out.append({
            "label": ctx.label,
            "canvases": canvases_out,
        })

    return contexts_out


# ---------------------------------------------------------------------------
# v2 → v1 format conversion
# ---------------------------------------------------------------------------


def _v1_to_v2(d: dict) -> dict:
    """Convert v1 (legacy/Swift) format dict to v2 (library) format.

    v1 keys → v2 keys:
      header.version (string) → version.{major,minor}
      header.fdl_creator → fdl_creator
      fdl_contexts → contexts
      context_uuid → (dropped, not in v2)
      canvas_uuid → id
      effective_anchor → effective_anchor_point
      fd_uuid → id
      framing_intent → framing_intent_id
      anchor → anchor_point
      protection_anchor → protection_anchor_point
    """
    header = d.get("header", {})
    version_str = header.get("version", "2.0")
    parts = version_str.split(".")
    major = int(parts[0]) if len(parts) > 0 else 2
    minor = int(parts[1]) if len(parts) > 1 else 0

    v2: dict[str, Any] = {
        "uuid": d.get("uuid", header.get("uuid", str(_uuid.uuid4()))),
        "version": {"major": major, "minor": minor},
        "fdl_creator": header.get("fdl_creator", d.get("fdl_creator", "FDL Tool")),
        "framing_intents": d.get("framing_intents", []),
        "contexts": [],
        "canvas_templates": d.get("canvas_templates", []),
    }

    if header.get("default_framing_intent"):
        v2["default_framing_intent"] = header["default_framing_intent"]

    for ctx in d.get("fdl_contexts", []):
        v2_ctx: dict[str, Any] = {
            "label": ctx.get("label", ""),
            "context_creator": ctx.get("context_creator", ""),
            "canvases": [],
        }

        for canvas in ctx.get("canvases", []):
            v2_canvas: dict[str, Any] = {
                "id": canvas.get("canvas_uuid", canvas.get("id", str(_uuid.uuid4()))),
                "label": canvas.get("label", ""),
                "source_canvas_id": canvas.get("source_fdl_uuid", canvas.get("source_canvas_id", "")),
                "dimensions": canvas.get("dimensions", {"width": 0, "height": 0}),
                "anamorphic_squeeze": canvas.get("anamorphic_squeeze", 1.0),
                "framing_decisions": [],
            }

            if canvas.get("effective_dimensions"):
                v2_canvas["effective_dimensions"] = canvas["effective_dimensions"]
            eff_anchor = canvas.get("effective_anchor", canvas.get("effective_anchor_point"))
            if eff_anchor:
                v2_canvas["effective_anchor_point"] = eff_anchor

            for fd in canvas.get("framing_decisions", []):
                v2_fd: dict[str, Any] = {
                    "id": fd.get("fd_uuid", fd.get("id", str(_uuid.uuid4()))),
                    "label": fd.get("label", ""),
                    "framing_intent_id": fd.get("framing_intent", fd.get("framing_intent_id", "")),
                    "dimensions": fd.get("dimensions", {"width": 0, "height": 0}),
                }

                # Ensure dimensions are floats (v2 expects float for FD dims)
                fd_dims = v2_fd["dimensions"]
                v2_fd["dimensions"] = {
                    "width": float(fd_dims.get("width", 0)),
                    "height": float(fd_dims.get("height", 0)),
                }

                anchor = fd.get("anchor", fd.get("anchor_point"))
                if anchor:
                    v2_fd["anchor_point"] = {"x": float(anchor.get("x", 0)), "y": float(anchor.get("y", 0))}
                else:
                    v2_fd["anchor_point"] = {"x": 0.0, "y": 0.0}

                prot_dims = fd.get("protection_dimensions")
                if prot_dims:
                    v2_fd["protection_dimensions"] = {
                        "width": float(prot_dims.get("width", 0)),
                        "height": float(prot_dims.get("height", 0)),
                    }
                prot_anchor = fd.get("protection_anchor", fd.get("protection_anchor_point"))
                if prot_anchor:
                    v2_fd["protection_anchor_point"] = {
                        "x": float(prot_anchor.get("x", 0)),
                        "y": float(prot_anchor.get("y", 0)),
                    }

                v2_canvas["framing_decisions"].append(v2_fd)

            v2_ctx["canvases"].append(v2_canvas)

        v2["contexts"].append(v2_ctx)

    return v2


def _v2_to_v1(d: dict) -> dict:
    """Convert the fdl library's v2 output format to the v1 format
    expected by the Swift frontend.

    v2 keys → v1 keys:
      version.{major,minor} → header.version (string)
      fdl_creator → header.fdl_creator
      contexts → fdl_contexts
      canvas.id → canvas_uuid
      canvas.effective_anchor_point → effective_anchor
      fd.id → fd_uuid
      fd.framing_intent_id → framing_intent
      fd.anchor_point → anchor
      fd.protection_anchor_point → protection_anchor
    """
    fdl_uuid = d.get("uuid", str(_uuid.uuid4()))

    version_obj = d.get("version", {})
    if isinstance(version_obj, dict):
        major = version_obj.get("major", 2)
        minor = version_obj.get("minor", 0)
        version_str = f"{major}.{minor}"
    else:
        version_str = str(version_obj)

    v1: dict[str, Any] = {
        "uuid": fdl_uuid,
        "header": {
            "uuid": fdl_uuid,
            "version": version_str,
            "fdl_creator": d.get("fdl_creator", "FDL Tool"),
        },
        "fdl_contexts": [],
    }

    if d.get("default_framing_intent"):
        v1["header"]["default_framing_intent"] = d["default_framing_intent"]

    for ctx in d.get("contexts", []):
        v1_ctx: dict[str, Any] = {
            "context_uuid": ctx.get("context_uuid", str(_uuid.uuid4())),
            "label": ctx.get("label", ""),
            "context_creator": ctx.get("context_creator", ""),
            "canvases": [],
        }

        for canvas in ctx.get("canvases", []):
            v1_canvas: dict[str, Any] = {
                "canvas_uuid": canvas.get("id", canvas.get("canvas_uuid", str(_uuid.uuid4()))),
                "label": canvas.get("label", ""),
                "dimensions": canvas.get("dimensions", {"width": 0, "height": 0}),
                "framing_decisions": [],
            }

            if canvas.get("effective_dimensions"):
                v1_canvas["effective_dimensions"] = canvas["effective_dimensions"]
            if canvas.get("effective_anchor_point"):
                v1_canvas["effective_anchor"] = canvas["effective_anchor_point"]
            elif canvas.get("effective_anchor"):
                v1_canvas["effective_anchor"] = canvas["effective_anchor"]

            for fd in canvas.get("framing_decisions", []):
                v1_fd: dict[str, Any] = {
                    "fd_uuid": fd.get("id", fd.get("fd_uuid", str(_uuid.uuid4()))),
                    "label": fd.get("label", ""),
                    "dimensions": fd.get("dimensions", {"width": 0, "height": 0}),
                }

                intent = fd.get("framing_intent_id", fd.get("framing_intent"))
                if intent:
                    v1_fd["framing_intent"] = intent

                anchor = fd.get("anchor_point", fd.get("anchor"))
                if anchor:
                    v1_fd["anchor"] = anchor

                prot_dims = fd.get("protection_dimensions")
                if prot_dims:
                    v1_fd["protection_dimensions"] = prot_dims

                prot_anchor = fd.get("protection_anchor_point", fd.get("protection_anchor"))
                if prot_anchor:
                    v1_fd["protection_anchor"] = prot_anchor

                v1_canvas["framing_decisions"].append(v1_fd)

            v1_ctx["canvases"].append(v1_canvas)

        v1["fdl_contexts"].append(v1_ctx)

    return v1

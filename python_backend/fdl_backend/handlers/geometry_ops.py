"""Geometry operations: compute rects, apply alignment, compute protection.

This handler exposes the ASC fdl library's geometry computations over
JSON-RPC so the Swift frontend can request computed rectangles for
all FDL layers (canvas, effective, protection, framing).
"""

from __future__ import annotations

from typing import Any

from fdl_backend.utils.fdl_convert import HAS_FDL, require_fdl

if HAS_FDL:
    from fdl_backend.utils.fdl_convert import (
        dict_to_fdl,
        extract_all_rects,
        fdl_from_string,
        fdl_to_dict,
        point_to_dict,
        rect_to_dict,
    )


def compute_rects(params: dict) -> dict:
    """Compute all geometry rectangles for an FDL document.

    Returns canvas, effective, protection, and framing rects for every
    context/canvas/framing-decision in the document.

    Params:
        fdl_data: dict — the FDL document
        json_string: str — alternative: raw FDL JSON string
    """
    require_fdl()

    fdl_data = params.get("fdl_data")
    json_string = params.get("json_string")

    if json_string:
        fdl_obj = fdl_from_string(json_string, validate=False)
    elif fdl_data:
        fdl_obj = dict_to_fdl(fdl_data)
    else:
        raise ValueError("Either fdl_data or json_string is required")

    contexts = extract_all_rects(fdl_obj)
    return {"contexts": contexts}


def apply_alignment(params: dict) -> dict:
    """Compute anchor point for a framing decision using alignment enums.

    Uses fd.adjust_anchor_point() from the fdl library, which positions
    the framing decision within the canvas according to the specified
    horizontal and vertical alignment.

    Params:
        fdl_data: dict — the FDL document
        context_index: int — which context (default 0)
        canvas_index: int — which canvas (default 0)
        fd_index: int — which framing decision (default 0)
        h_align: str — "left", "center", or "right"
        v_align: str — "top", "center", or "bottom"
    """
    require_fdl()

    fdl_data = params.get("fdl_data")
    if not fdl_data:
        raise ValueError("fdl_data is required")

    ctx_idx = params.get("context_index", 0)
    canvas_idx = params.get("canvas_index", 0)
    fd_idx = params.get("fd_index", 0)
    h_align = params.get("h_align", "center")
    v_align = params.get("v_align", "center")

    fdl_obj = dict_to_fdl(fdl_data)

    ctx = list(fdl_obj.contexts)[ctx_idx]
    canvas = list(ctx.canvases)[canvas_idx]
    fd = list(canvas.framing_decisions)[fd_idx]

    fd.adjust_anchor_point(canvas, h_align, v_align)

    fd_rect = fd.get_rect()
    result: dict[str, Any] = {
        "fdl": fdl_to_dict(fdl_obj),
        "framing_rect": rect_to_dict(fd_rect),
    }

    if fd.anchor_point:
        result["anchor_point"] = point_to_dict(fd.anchor_point)

    return result


def apply_protection_alignment(params: dict) -> dict:
    """Compute protection anchor point using alignment enums.

    Uses fd.adjust_protection_anchor_point() from the fdl library.

    Params:
        fdl_data: dict — the FDL document
        context_index: int — which context (default 0)
        canvas_index: int — which canvas (default 0)
        fd_index: int — which framing decision (default 0)
        h_align: str — "left", "center", or "right"
        v_align: str — "top", "center", or "bottom"
    """
    require_fdl()

    fdl_data = params.get("fdl_data")
    if not fdl_data:
        raise ValueError("fdl_data is required")

    ctx_idx = params.get("context_index", 0)
    canvas_idx = params.get("canvas_index", 0)
    fd_idx = params.get("fd_index", 0)
    h_align = params.get("h_align", "center")
    v_align = params.get("v_align", "center")

    fdl_obj = dict_to_fdl(fdl_data)

    ctx = list(fdl_obj.contexts)[ctx_idx]
    canvas = list(ctx.canvases)[canvas_idx]
    fd = list(canvas.framing_decisions)[fd_idx]

    fd.adjust_protection_anchor_point(canvas, h_align, v_align)

    prot_rect = fd.get_protection_rect()
    result: dict[str, Any] = {
        "fdl": fdl_to_dict(fdl_obj),
    }

    if prot_rect:
        result["protection_rect"] = rect_to_dict(prot_rect)
    if fd.protection_anchor_point:
        result["protection_anchor_point"] = point_to_dict(fd.protection_anchor_point)

    return result


def compute_protection(params: dict) -> dict:
    """Compute protection dimensions from a percentage of framing dimensions.

    This is a convenience function: given a framing decision's dimensions
    and a protection percentage, it calculates the protection dimensions
    and optionally sets them on the FDL.

    Params:
        framing_width: float
        framing_height: float
        protection_percent: float — e.g. 10.0 for 10% overscan
        fdl_data: dict — optional, to update in place
        context_index: int
        canvas_index: int
        fd_index: int
    """
    framing_w = float(params.get("framing_width", 0))
    framing_h = float(params.get("framing_height", 0))
    pct = float(params.get("protection_percent", 0))

    factor = 1.0 + (pct / 100.0)
    prot_w = framing_w * factor
    prot_h = framing_h * factor

    result: dict[str, Any] = {
        "protection_width": prot_w,
        "protection_height": prot_h,
    }

    fdl_data = params.get("fdl_data")
    if HAS_FDL and fdl_data:
        from fdl.fdl_types import DimensionsFloat, PointFloat

        ctx_idx = params.get("context_index", 0)
        canvas_idx = params.get("canvas_index", 0)
        fd_idx = params.get("fd_index", 0)

        fdl_obj = dict_to_fdl(fdl_data)
        ctx = list(fdl_obj.contexts)[ctx_idx]
        canvas = list(ctx.canvases)[canvas_idx]
        fd = list(canvas.framing_decisions)[fd_idx]

        fd.set_protection(
            dims=DimensionsFloat(width=prot_w, height=prot_h),
            anchor=PointFloat(x=0.0, y=0.0),
        )
        fd.adjust_protection_anchor_point(canvas, "center", "center")

        prot_rect = fd.get_protection_rect()
        if prot_rect:
            result["protection_rect"] = rect_to_dict(prot_rect)
        result["fdl"] = fdl_to_dict(fdl_obj)

    return result

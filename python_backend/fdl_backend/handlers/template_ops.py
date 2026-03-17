"""Canvas template operations: validate, apply, preview, export.

Supports both the custom pipeline-based templates (backward compat)
and the ASC fdl library's CanvasTemplate.apply() for spec-compliant
template application.
"""

from __future__ import annotations

import json
import uuid
from typing import Any

from fdl_backend.utils.fdl_convert import HAS_FDL

if HAS_FDL:
    from fdl_backend.utils.fdl_convert import (
        dict_to_fdl,
        fdl_to_dict,
        rect_to_dict,
    )


def validate(params: dict) -> dict:
    """Validate a canvas template JSON string.

    Params:
        json_string: str — the template JSON to validate
    """
    json_string = params.get("json_string", "")
    errors: list[dict] = []
    warnings: list[dict] = []

    if not json_string:
        return {
            "valid": False,
            "errors": [{"path": "", "message": "No JSON input provided", "severity": "error"}],
            "warnings": [],
        }

    try:
        template = json.loads(json_string)
    except json.JSONDecodeError as exc:
        return {
            "valid": False,
            "errors": [{"path": "", "message": f"Invalid JSON: {exc}", "severity": "error"}],
            "warnings": [],
        }

    if not isinstance(template, dict):
        errors.append({"path": "", "message": "Template must be an object", "severity": "error"})
        return {"valid": False, "errors": errors, "warnings": warnings}

    pipeline = template.get("pipeline", [])
    if not isinstance(pipeline, list):
        errors.append({"path": "pipeline", "message": "pipeline must be an array", "severity": "error"})
    elif not pipeline:
        warnings.append({"path": "pipeline", "message": "Pipeline is empty", "severity": "warning"})
    else:
        valid_steps = {"normalize", "scale", "round", "offset", "crop"}
        for i, step in enumerate(pipeline):
            step_path = f"pipeline[{i}]"
            if not isinstance(step, dict):
                errors.append(
                    {"path": step_path, "message": "Each pipeline step must be an object", "severity": "error"}
                )
                continue
            step_type = step.get("type")
            if step_type not in valid_steps:
                errors.append(
                    {
                        "path": f"{step_path}.type",
                        "message": f"Unknown step type: {step_type}. Valid: {', '.join(sorted(valid_steps))}",
                        "severity": "error",
                    }
                )

    return {"valid": len(errors) == 0, "errors": errors, "warnings": warnings}


def apply_template(params: dict) -> dict:
    """Apply a custom pipeline template to an FDL document.

    Params:
        template_json: str — canvas template JSON
        fdl_json: str — FDL document JSON
    """
    template = json.loads(params.get("template_json", "{}"))
    fdl = json.loads(params.get("fdl_json", "{}"))

    pipeline = template.get("pipeline", [])
    contexts = fdl.get("contexts", fdl.get("fdl_contexts", []))

    for ctx in contexts:
        for canvas in ctx.get("canvases", []):
            dims = canvas.get("dimensions", {"width": 0, "height": 0})
            w, h = float(dims["width"]), float(dims["height"])

            for step in pipeline:
                w, h = _apply_step(step, w, h)

            canvas["dimensions"] = {"width": w, "height": h}

    return {"fdl": fdl}


def apply_fdl_template(params: dict) -> dict:
    """Apply a canvas template to an FDL following the ASC spec.

    Uses the native fdl library when available, otherwise falls back to
    a pure-dict implementation that follows the same algorithm.

    Params:
        fdl_json: str — source FDL document JSON
        template_json: str — ASC canvas template JSON
        context_index: int — which context to use (default 0)
        canvas_index: int — which canvas to use (default 0)
        fd_index: int — which framing decision to use (default 0)
    """
    fdl_json = params.get("fdl_json", "{}")
    template_json = params.get("template_json", "{}")
    ctx_idx = params.get("context_index", 0)
    canvas_idx = params.get("canvas_index", 0)
    fd_idx = params.get("fd_index", 0)

    source_fdl = json.loads(fdl_json)
    template_data = json.loads(template_json)
    dict_result = _apply_canvas_template_dict(
        source_fdl,
        template_data,
        ctx_idx,
        canvas_idx,
        fd_idx,
    )

    if HAS_FDL:
        try:
            library_result = _apply_with_library(params)
            new_canvas_id = params.get("new_canvas_id")
            if _template_results_are_compatible(library_result, dict_result, ctx_idx, new_canvas_id):
                return library_result
        except Exception:
            pass

    return dict_result


def _template_results_are_compatible(
    library_result: dict,
    dict_result: dict,
    ctx_idx: int,
    new_canvas_id: str | None,
    tol: float = 1.0,
) -> bool:
    lib_canvas = _pick_canvas_from_result(library_result, ctx_idx, new_canvas_id)
    dict_canvas = _pick_canvas_from_result(dict_result, ctx_idx, new_canvas_id)
    if not lib_canvas or not dict_canvas:
        return False
    if not _dims_close(lib_canvas.get("dimensions"), dict_canvas.get("dimensions"), tol):
        return False
    if not _dims_close(lib_canvas.get("effective_dimensions"), dict_canvas.get("effective_dimensions"), tol):
        return False
    if not _points_close(
        lib_canvas.get("effective_anchor_point"),
        dict_canvas.get("effective_anchor_point"),
        tol,
    ):
        return False
    lib_fds = lib_canvas.get("framing_decisions") or []
    dict_fds = dict_canvas.get("framing_decisions") or []
    if bool(lib_fds) != bool(dict_fds):
        return False
    return not (
        lib_fds
        and dict_fds
        and not _dims_close(
            lib_fds[0].get("dimensions"),
            dict_fds[0].get("dimensions"),
            tol,
        )
    )


def _pick_canvas_from_result(result: dict, ctx_idx: int, canvas_id: str | None) -> dict | None:
    contexts = (result.get("fdl") or {}).get("contexts", [])
    if ctx_idx >= len(contexts):
        return None
    canvases = contexts[ctx_idx].get("canvases", [])
    if canvas_id:
        for canvas in canvases:
            if canvas.get("id") == canvas_id:
                return canvas
    return canvases[-1] if canvases else None


def _dims_close(a: dict | None, b: dict | None, tol: float) -> bool:
    if not a and not b:
        return True
    if not a or not b:
        return False
    return (
        abs(float(a.get("width", 0)) - float(b.get("width", 0))) <= tol
        and abs(float(a.get("height", 0)) - float(b.get("height", 0))) <= tol
    )


def _points_close(a: dict | None, b: dict | None, tol: float) -> bool:
    if not a and not b:
        return True
    if not a or not b:
        return False
    return (
        abs(float(a.get("x", 0)) - float(b.get("x", 0))) <= tol
        and abs(float(a.get("y", 0)) - float(b.get("y", 0))) <= tol
    )


def _apply_with_library(params: dict) -> dict:
    """Apply using the native fdl library's CanvasTemplate."""
    from fdl import CanvasTemplate
    from fdl.constants import FitMethod, GeometryPath, HAlign, RoundingEven, RoundingMode, VAlign
    from fdl.fdl_types import DimensionsInt
    from fdl.rounding import RoundStrategy

    fdl_json = params.get("fdl_json", "{}")
    template_json = params.get("template_json", "{}")
    ctx_idx = params.get("context_index", 0)
    canvas_idx = params.get("canvas_index", 0)
    fd_idx = params.get("fd_index", 0)
    new_canvas_id = params.get("new_canvas_id", str(uuid.uuid4()))
    new_fd_name = params.get("new_fd_name", "Template Output")

    source_fdl = dict_to_fdl(json.loads(fdl_json))
    template_data = json.loads(template_json)

    source_ctx = list(source_fdl.contexts)[ctx_idx]
    source_canvas = list(source_ctx.canvases)[canvas_idx]
    source_fd = list(source_canvas.framing_decisions)[fd_idx]

    target_dimensions = template_data.get("target_dimensions", {})
    maximum_dimensions = template_data.get("maximum_dimensions")
    round_dict = template_data.get("round", {})

    template_kwargs: dict[str, Any] = {
        "id": str(template_data.get("id") or str(uuid.uuid4())),
        "label": str(template_data.get("label", "")),
        "target_dimensions": DimensionsInt(
            width=int(target_dimensions.get("width", 0)),
            height=int(target_dimensions.get("height", 0)),
        ),
        "target_anamorphic_squeeze": float(template_data.get("target_anamorphic_squeeze", 1.0)),
        "fit_source": GeometryPath(template_data.get("fit_source", "framing_decision.dimensions")),
        "fit_method": FitMethod(template_data.get("fit_method", "fit_all")),
        "alignment_method_horizontal": HAlign(template_data.get("alignment_method_horizontal", "center")),
        "alignment_method_vertical": VAlign(template_data.get("alignment_method_vertical", "center")),
        "round": RoundStrategy(
            even=RoundingEven(round_dict.get("even", "even")),
            mode=RoundingMode(round_dict.get("mode", "round")),
        ),
        "pad_to_maximum": bool(template_data.get("pad_to_maximum", False)),
    }

    preserve_from_source_canvas = template_data.get("preserve_from_source_canvas")
    if preserve_from_source_canvas:
        template_kwargs["preserve_from_source_canvas"] = GeometryPath(preserve_from_source_canvas)
    if maximum_dimensions:
        template_kwargs["maximum_dimensions"] = DimensionsInt(
            width=int(maximum_dimensions.get("width", 0)),
            height=int(maximum_dimensions.get("height", 0)),
        )

    template_obj = CanvasTemplate(**template_kwargs)
    result = template_obj.apply(
        source_canvas=source_canvas,
        source_framing=source_fd,
        new_canvas_id=new_canvas_id,
        new_fd_name=new_fd_name,
    )

    result_dict: dict[str, Any] = {
        "fdl": fdl_to_dict(result.fdl),
    }

    if result.canvas:
        result_dict["canvas"] = {
            "label": result.canvas.label,
            "canvas_rect": rect_to_dict(result.canvas.get_rect()),
        }
        eff = result.canvas.get_effective_rect()
        if eff:
            result_dict["canvas"]["effective_rect"] = rect_to_dict(eff)

    if result.framing_decision:
        result_dict["framing_decision"] = {
            "label": result.framing_decision.label,
            "framing_rect": rect_to_dict(result.framing_decision.get_rect()),
        }
        prot = result.framing_decision.get_protection_rect()
        if prot:
            result_dict["framing_decision"]["protection_rect"] = rect_to_dict(prot)

    return result_dict


def _apply_canvas_template_dict(
    source_fdl: dict,
    template: dict,
    ctx_idx: int,
    canvas_idx: int,
    fd_idx: int,
) -> dict:
    """Pure-dict canvas template application per ASC FDL spec phases."""
    import copy
    import math

    contexts = source_fdl.get("contexts", [])
    if ctx_idx >= len(contexts):
        raise ValueError(f"context_index {ctx_idx} out of range")
    src_ctx = contexts[ctx_idx]
    canvases = src_ctx.get("canvases", [])
    if canvas_idx >= len(canvases):
        raise ValueError(f"canvas_index {canvas_idx} out of range")
    src_canvas = canvases[canvas_idx]
    fds = src_canvas.get("framing_decisions", [])
    src_fd = fds[fd_idx] if fd_idx < len(fds) else None
    if not src_fd:
        raise ValueError("framing decision not found")

    source_squeeze = float(src_canvas.get("anamorphic_squeeze", 1.0))
    target_squeeze = float(template.get("target_anamorphic_squeeze", 1.0))
    if target_squeeze == 0.0:
        target_squeeze = source_squeeze
    if target_squeeze <= 0.0:
        target_squeeze = 1.0

    fit_source = template.get("fit_source", "framing_decision.dimensions")
    fit_method = template.get("fit_method", "fit_all")
    preserve_path = template.get("preserve_from_source_canvas") or ""
    align_h = template.get("alignment_method_horizontal", "center")
    align_v = template.get("alignment_method_vertical", "center")
    round_even = template.get("round", {}).get("even", "even")
    round_mode = template.get("round", {}).get("mode", "round")
    max_dims = template.get("maximum_dimensions")
    has_max_dims = bool(max_dims)
    pad_to_max = bool(template.get("pad_to_maximum", False))

    target = template.get("target_dimensions", {})
    target_w = float(target.get("width", 0.0))
    target_h = float(target.get("height", 0.0))

    path_order = [
        "canvas.dimensions",
        "canvas.effective_dimensions",
        "framing_decision.protection_dimensions",
        "framing_decision.dimensions",
    ]

    def _dims_of(path: str) -> dict | None:
        if path == "canvas.dimensions":
            return src_canvas.get("dimensions")
        if path == "canvas.effective_dimensions":
            return src_canvas.get("effective_dimensions")
        if path == "framing_decision.protection_dimensions":
            return src_fd.get("protection_dimensions")
        if path == "framing_decision.dimensions":
            return src_fd.get("dimensions")
        return None

    def _anchor_of(path: str) -> dict:
        if path == "canvas.effective_dimensions":
            return src_canvas.get("effective_anchor_point") or {"x": 0.0, "y": 0.0}
        if path == "framing_decision.protection_dimensions":
            return src_fd.get("protection_anchor_point") or {"x": 0.0, "y": 0.0}
        if path == "framing_decision.dimensions":
            return src_fd.get("anchor_point") or {"x": 0.0, "y": 0.0}
        return {"x": 0.0, "y": 0.0}

    def _resolve(path: str, required: bool = False) -> tuple[tuple[float, float] | None, tuple[float, float] | None]:
        d = _dims_of(path)
        if not d:
            if required:
                raise ValueError(f"Required geometry path missing in source: {path}")
            return None, None
        dims = (float(d.get("width", 0.0)), float(d.get("height", 0.0)) )
        a = _anchor_of(path)
        anchor = (float(a.get("x", 0.0)), float(a.get("y", 0.0)))
        return dims, anchor

    # Validate required paths.
    if preserve_path:
        _resolve(preserve_path, required=True)
    fit_dims_check, _ = _resolve(fit_source, required=True)
    if not fit_dims_check or fit_dims_check[0] <= 0 or fit_dims_check[1] <= 0:
        raise ValueError("fit_source dimensions are zero")

    # Phase 2: two-pass population.
    geom_dims: dict[str, tuple[float, float]] = {
        "canvas.dimensions": (0.0, 0.0),
        "canvas.effective_dimensions": (0.0, 0.0),
        "framing_decision.protection_dimensions": (0.0, 0.0),
        "framing_decision.dimensions": (0.0, 0.0),
    }
    geom_anchor: dict[str, tuple[float, float]] = {
        "canvas.effective_dimensions": (0.0, 0.0),
        "framing_decision.protection_dimensions": (0.0, 0.0),
        "framing_decision.dimensions": (0.0, 0.0),
    }

    def _populate_from(start_path: str) -> None:
        if start_path not in path_order:
            return
        si = path_order.index(start_path)
        for pth in path_order[si:]:
            d, a = _resolve(pth, required=False)
            if d is None:
                continue
            geom_dims[pth] = d
            if pth in geom_anchor and a is not None:
                geom_anchor[pth] = a

    if preserve_path:
        _populate_from(preserve_path)
    _populate_from(fit_source)

    # Phase 3: fill hierarchy gaps.
    def _is_zero(d: tuple[float, float]) -> bool:
        return d[0] == 0.0 and d[1] == 0.0

    if not _is_zero(geom_dims["canvas.dimensions"]):
        ref_dims = geom_dims["canvas.dimensions"]
        ref_anchor = (0.0, 0.0)
    elif not _is_zero(geom_dims["canvas.effective_dimensions"]):
        ref_dims = geom_dims["canvas.effective_dimensions"]
        ref_anchor = geom_anchor["canvas.effective_dimensions"]
    elif not _is_zero(geom_dims["framing_decision.protection_dimensions"]):
        ref_dims = geom_dims["framing_decision.protection_dimensions"]
        ref_anchor = geom_anchor["framing_decision.protection_dimensions"]
    else:
        ref_dims = geom_dims["framing_decision.dimensions"]
        ref_anchor = geom_anchor["framing_decision.dimensions"]

    if _is_zero(geom_dims["canvas.dimensions"]):
        geom_dims["canvas.dimensions"] = ref_dims
    if _is_zero(geom_dims["canvas.effective_dimensions"]):
        geom_dims["canvas.effective_dimensions"] = ref_dims
        geom_anchor["canvas.effective_dimensions"] = ref_anchor
    # protection intentionally not auto-filled from framing.

    fit_dims = geom_dims.get(fit_source, (0.0, 0.0))
    fit_anchor = (0.0, 0.0) if fit_source == "canvas.dimensions" else geom_anchor.get(fit_source, (0.0, 0.0))
    preserve_dims = geom_dims.get(preserve_path, (0.0, 0.0)) if preserve_path else (0.0, 0.0)
    preserve_anchor = (0.0, 0.0) if preserve_path == "canvas.dimensions" else geom_anchor.get(preserve_path, (0.0, 0.0))

    anchor_offset = preserve_anchor if (preserve_path and not _is_zero(preserve_dims)) else fit_anchor
    for pth in [
        "canvas.effective_dimensions",
        "framing_decision.protection_dimensions",
        "framing_decision.dimensions",
    ]:
        ax, ay = geom_anchor[pth]
        geom_anchor[pth] = (ax - anchor_offset[0], ay - anchor_offset[1])

    # Phase 4: scale factor.
    fit_norm_w = fit_dims[0] * source_squeeze
    fit_norm_h = fit_dims[1]
    tgt_norm_w = target_w * target_squeeze
    tgt_norm_h = target_h
    if fit_norm_w <= 0 or fit_norm_h <= 0 or tgt_norm_w <= 0 or tgt_norm_h <= 0:
        raise ValueError("invalid fit/target dimensions")

    ratio_w = tgt_norm_w / fit_norm_w
    ratio_h = tgt_norm_h / fit_norm_h
    if fit_method == "width":
        scale_factor = ratio_w
    elif fit_method == "height":
        scale_factor = ratio_h
    elif fit_method == "fill":
        scale_factor = max(ratio_w, ratio_h)
    else:
        scale_factor = min(ratio_w, ratio_h)

    # Phase 5: normalize + scale + round.
    def _round_value(v: float, mode: str, base: int) -> float:
        if mode == "up":
            return math.ceil(v / base) * base
        if mode == "down":
            return math.floor(v / base) * base
        # round-half-away-from-zero
        if v >= 0:
            return math.floor((v / base) + 0.5) * base
        return -math.floor((-v / base) + 0.5) * base

    base = 2 if round_even == "even" else 1

    def _scale_dims(d: tuple[float, float]) -> tuple[float, float]:
        return (
            (d[0] * source_squeeze * scale_factor) / target_squeeze,
            d[1] * scale_factor,
        )

    def _scale_point(p: tuple[float, float]) -> tuple[float, float]:
        return (
            (p[0] * source_squeeze * scale_factor) / target_squeeze,
            p[1] * scale_factor,
        )

    for pth, d in list(geom_dims.items()):
        sw, sh = _scale_dims(d)
        geom_dims[pth] = (
            _round_value(sw, round_mode, base),
            _round_value(sh, round_mode, base),
        )

    for pth, a in list(geom_anchor.items()):
        sx, sy = _scale_point(a)
        geom_anchor[pth] = (
            _round_value(sx, round_mode, base),
            _round_value(sy, round_mode, base),
        )

    scaled_fit_dims = geom_dims.get(fit_source, (0.0, 0.0))
    scaled_fit_anchor = (0.0, 0.0) if fit_source == "canvas.dimensions" else geom_anchor.get(fit_source, (0.0, 0.0))
    scaled_canvas = geom_dims["canvas.dimensions"]

    # Phase 6: output size + alignment shift.
    max_w = float(max_dims.get("width", 0.0)) if has_max_dims else 0.0
    max_h = float(max_dims.get("height", 0.0)) if has_max_dims else 0.0

    def _output_size(canvas_size: float, max_size: float, has_max: bool, pad: bool) -> float:
        if has_max and pad:
            return max_size
        if has_max and canvas_size > max_size:
            return max_size
        return canvas_size

    out_w = _output_size(scaled_canvas[0], max_w, has_max_dims, pad_to_max)
    out_h = _output_size(scaled_canvas[1], max_h, has_max_dims, pad_to_max)

    def _align_factor(mode: str) -> float:
        if mode in ("left", "top"):
            return 0.0
        if mode in ("right", "bottom"):
            return 1.0
        return 0.5

    def _shift_axis(
        canvas_size: float,
        output_size: float,
        target_size: float,
        fit_size: float,
        fit_anchor_axis: float,
        align_mode: str,
        pad: bool,
    ) -> float:
        overflow = canvas_size - output_size
        if overflow == 0.0 and not pad:
            return 0.0

        is_center = align_mode == "center"
        center_target = pad or is_center
        target_offset = ((output_size - target_size) * 0.5) if center_target else 0.0
        gap = target_size - fit_size
        alignment_offset = gap * _align_factor(align_mode)
        shift = target_offset + alignment_offset - fit_anchor_axis

        if (not pad) and overflow > 0.0:
            shift = max(min(shift, 0.0), -overflow)
        return shift

    shift_x = _shift_axis(
        scaled_canvas[0],
        out_w,
        target_w,
        scaled_fit_dims[0],
        scaled_fit_anchor[0],
        align_h,
        pad_to_max,
    )
    shift_y = _shift_axis(
        scaled_canvas[1],
        out_h,
        target_h,
        scaled_fit_dims[1],
        scaled_fit_anchor[1],
        align_v,
        pad_to_max,
    )

    # Phase 7: apply offsets.
    theo_anchor: dict[str, tuple[float, float]] = {}
    for pth in [
        "canvas.effective_dimensions",
        "framing_decision.protection_dimensions",
        "framing_decision.dimensions",
    ]:
        ax, ay = geom_anchor[pth]
        tx, ty = ax + shift_x, ay + shift_y
        theo_anchor[pth] = (tx, ty)
        geom_anchor[pth] = (max(0.0, tx), max(0.0, ty))

    # Phase 8: crop visible.
    def _crop_dims(
        dims: tuple[float, float],
        theo: tuple[float, float],
        clamped: tuple[float, float],
        canvas: tuple[float, float],
    ) -> tuple[float, float]:
        clip_left = max(0.0, -theo[0])
        clip_top = max(0.0, -theo[1])
        vis_w = dims[0] - clip_left
        vis_h = dims[1] - clip_top
        vis_w = min(vis_w, canvas[0] - clamped[0])
        vis_h = min(vis_h, canvas[1] - clamped[1])
        return (max(0.0, vis_w), max(0.0, vis_h))

    canvas_out = (out_w, out_h)
    eff_dims = _crop_dims(
        geom_dims["canvas.effective_dimensions"],
        theo_anchor["canvas.effective_dimensions"],
        geom_anchor["canvas.effective_dimensions"],
        canvas_out,
    )
    prot_dims = (0.0, 0.0)
    if not _is_zero(geom_dims["framing_decision.protection_dimensions"]):
        prot_dims = _crop_dims(
            geom_dims["framing_decision.protection_dimensions"],
            theo_anchor["framing_decision.protection_dimensions"],
            geom_anchor["framing_decision.protection_dimensions"],
            canvas_out,
        )

    frm_dims = _crop_dims(
        geom_dims["framing_decision.dimensions"],
        theo_anchor["framing_decision.dimensions"],
        geom_anchor["framing_decision.dimensions"],
        canvas_out,
    )

    # Enforce hierarchy containment.
    eff_dims = (min(eff_dims[0], canvas_out[0]), min(eff_dims[1], canvas_out[1]))
    if not _is_zero(prot_dims):
        prot_dims = (min(prot_dims[0], eff_dims[0]), min(prot_dims[1], eff_dims[1]))
        parent = prot_dims
    else:
        parent = eff_dims
    frm_dims = (min(frm_dims[0], parent[0]), min(frm_dims[1], parent[1]))

    # Build output FDL.
    out_fdl = copy.deepcopy(source_fdl)
    out_ctx = out_fdl["contexts"][ctx_idx]
    out_canvas = out_ctx["canvases"][canvas_idx]

    out_canvas["id"] = str(uuid.uuid4())
    out_canvas["source_canvas_id"] = src_canvas.get("id", "")
    out_canvas["dimensions"] = {"width": canvas_out[0], "height": canvas_out[1]}
    out_canvas["anamorphic_squeeze"] = target_squeeze
    out_canvas["effective_dimensions"] = {"width": eff_dims[0], "height": eff_dims[1]}
    out_canvas["effective_anchor_point"] = {
        "x": geom_anchor["canvas.effective_dimensions"][0],
        "y": geom_anchor["canvas.effective_dimensions"][1],
    }

    out_fd = out_canvas["framing_decisions"][fd_idx]
    out_fd["dimensions"] = {"width": frm_dims[0], "height": frm_dims[1]}
    out_fd["anchor_point"] = {
        "x": geom_anchor["framing_decision.dimensions"][0],
        "y": geom_anchor["framing_decision.dimensions"][1],
    }

    if not _is_zero(prot_dims):
        out_fd["protection_dimensions"] = {"width": prot_dims[0], "height": prot_dims[1]}
        out_fd["protection_anchor_point"] = {
            "x": geom_anchor["framing_decision.protection_dimensions"][0],
            "y": geom_anchor["framing_decision.protection_dimensions"][1],
        }
    else:
        out_fd.pop("protection_dimensions", None)
        out_fd.pop("protection_anchor_point", None)

    # Scale additional framing decisions using same geometry transform.
    for i, fd in enumerate(out_canvas.get("framing_decisions", [])):
        if i == fd_idx:
            continue
        dims = fd.get("dimensions", {})
        anchor = fd.get("anchor_point", {})
        sw, sh = _scale_dims((float(dims.get("width", 0.0)), float(dims.get("height", 0.0))))
        sa = _scale_point((float(anchor.get("x", 0.0)), float(anchor.get("y", 0.0))))
        sw = _round_value(sw, round_mode, base)
        sh = _round_value(sh, round_mode, base)
        sax = max(0.0, _round_value(sa[0] + shift_x, round_mode, base))
        say = max(0.0, _round_value(sa[1] + shift_y, round_mode, base))
        fd["dimensions"] = {"width": min(sw, canvas_out[0]), "height": min(sh, canvas_out[1])}
        fd["anchor_point"] = {"x": sax, "y": say}

    return {"fdl": out_fdl}


def preview(params: dict) -> dict:
    """Preview template application step by step.

    Params:
        template_json: str — canvas template JSON
        fdl_json: str — FDL document JSON
    """
    template = json.loads(params.get("template_json", "{}"))
    fdl = json.loads(params.get("fdl_json", "{}"))

    pipeline = template.get("pipeline", [])
    steps_results: list[dict] = []

    contexts = fdl.get("contexts", fdl.get("fdl_contexts", []))
    if not contexts or not contexts[0].get("canvases"):
        return {"steps": [], "error": "No canvas found in FDL for preview"}

    canvas = contexts[0]["canvases"][0]
    dims = canvas.get("dimensions", {"width": 0, "height": 0})
    w, h = float(dims["width"]), float(dims["height"])

    steps_results.append(
        {
            "step": "input",
            "type": "original",
            "width": w,
            "height": h,
        }
    )

    for step in pipeline:
        prev_w, prev_h = w, h
        w, h = _apply_step(step, w, h)
        steps_results.append(
            {
                "step": step.get("type", "unknown"),
                "type": step.get("type", "unknown"),
                "params": {k: v for k, v in step.items() if k != "type"},
                "input_width": prev_w,
                "input_height": prev_h,
                "output_width": w,
                "output_height": h,
            }
        )

    return {"steps": steps_results}


def export_template(params: dict) -> dict:
    """Export a canvas template as canonical JSON.

    Params:
        template_data: dict — the template object
    """
    template_data = params.get("template_data", {})
    json_string = json.dumps(template_data, indent=2, ensure_ascii=False)
    return {"json_string": json_string}


def _apply_step(step: dict, w: float, h: float) -> tuple[float, float]:
    """Apply a single pipeline step to dimensions."""
    step_type = step.get("type", "")

    if step_type == "normalize":
        max_dim = max(w, h) if max(w, h) > 0 else 1
        w, h = w / max_dim, h / max_dim

    elif step_type == "scale":
        scale_x = step.get("scale_x", step.get("scale", 1.0))
        scale_y = step.get("scale_y", step.get("scale", 1.0))
        w *= scale_x
        h *= scale_y

    elif step_type == "round":
        strategy = step.get("strategy", "nearest")
        if strategy == "nearest":
            w, h = round(w), round(h)
        elif strategy == "floor":
            import math

            w, h = math.floor(w), math.floor(h)
        elif strategy == "ceil":
            import math

            w, h = math.ceil(w), math.ceil(h)
        elif strategy == "even":
            w = round(w / 2) * 2
            h = round(h / 2) * 2

    elif step_type == "offset":
        w += step.get("offset_x", 0)
        h += step.get("offset_y", 0)

    elif step_type == "crop":
        crop_w = step.get("width", w)
        crop_h = step.get("height", h)
        w = min(w, crop_w)
        h = min(h, crop_h)

    return w, h

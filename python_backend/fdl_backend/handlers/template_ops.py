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

    if HAS_FDL:
        try:
            return _apply_with_library(params)
        except Exception:
            pass

    return _apply_canvas_template_dict(
        json.loads(fdl_json),
        json.loads(template_json),
        ctx_idx,
        canvas_idx,
        fd_idx,
    )


def _apply_with_library(params: dict) -> dict:
    """Apply using the native fdl library's CanvasTemplate."""
    from fdl import CanvasTemplate

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

    template_obj = CanvasTemplate(**template_data)
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
    """Pure-dict canvas template application per ASC FDL spec.

    Implements the CanvasTemplate.apply() algorithm:
    1. Extract source dimensions based on fit_source
    2. Compute scale factor based on fit_method
    3. Scale all geometry
    4. Round dimensions
    5. Compute anchor positions based on alignment
    6. Apply maximum_dimensions and pad_to_maximum
    7. Build output FDL
    """
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

    canvas_dims = src_canvas.get("dimensions", {})
    canvas_w = float(canvas_dims.get("width", 0))
    canvas_h = float(canvas_dims.get("height", 0))
    squeeze = float(src_canvas.get("anamorphic_squeeze", 1.0))

    eff_dims = src_canvas.get("effective_dimensions")
    eff_w = float(eff_dims["width"]) if eff_dims else canvas_w
    eff_h = float(eff_dims["height"]) if eff_dims else canvas_h

    fd_dims = src_fd.get("dimensions", {}) if src_fd else canvas_dims
    fd_w = float(fd_dims.get("width", canvas_w))
    fd_h = float(fd_dims.get("height", canvas_h))

    prot_dims = (src_fd or {}).get("protection_dimensions")
    prot_w = float(prot_dims["width"]) if prot_dims else None
    prot_h = float(prot_dims["height"]) if prot_dims else None

    target_dims = template.get("target_dimensions", {})
    target_w = float(target_dims.get("width", 1920))
    target_h = float(target_dims.get("height", 1080))

    fit_source = template.get("fit_source", "framing_decision.dimensions")
    fit_method = template.get("fit_method", "fit_all")
    align_h = template.get("alignment_method_horizontal", "center")
    align_v = template.get("alignment_method_vertical", "center")
    round_even = template.get("round", {}).get("even", "even")
    round_mode = template.get("round", {}).get("mode", "up")
    max_dims = template.get("maximum_dimensions")
    pad_to_max = template.get("pad_to_maximum", False)

    # 1. Determine source dimensions for scale computation
    if fit_source == "canvas.dimensions":
        src_w, src_h = canvas_w, canvas_h
    elif fit_source == "canvas.effective_dimensions":
        src_w, src_h = eff_w, eff_h
    elif fit_source == "framing_decision.protection_dimensions":
        src_w = prot_w if prot_w else fd_w
        src_h = prot_h if prot_h else fd_h
    else:
        src_w, src_h = fd_w, fd_h

    if src_w <= 0 or src_h <= 0:
        raise ValueError("Source dimensions are zero")

    # 2. Compute scale factor
    scale_x = target_w / src_w
    scale_y = target_h / src_h

    if fit_method == "fit_all":
        scale = min(scale_x, scale_y)
    elif fit_method == "fill":
        scale = max(scale_x, scale_y)
    elif fit_method == "width":
        scale = scale_x
    elif fit_method == "height":
        scale = scale_y
    else:
        scale = min(scale_x, scale_y)

    # 3. Scale all geometry
    new_canvas_w = canvas_w * scale
    new_canvas_h = canvas_h * scale
    new_eff_w = eff_w * scale
    new_eff_h = eff_h * scale
    new_fd_w = fd_w * scale
    new_fd_h = fd_h * scale
    new_prot_w = prot_w * scale if prot_w else None
    new_prot_h = prot_h * scale if prot_h else None

    # 4. Round
    def _round(val: float) -> float:
        if round_even == "even":
            base = 2
        else:
            base = 1
        if round_mode == "up":
            return math.ceil(val / base) * base
        elif round_mode == "down":
            return math.floor(val / base) * base
        else:
            return round(val / base) * base

    new_canvas_w = _round(new_canvas_w)
    new_canvas_h = _round(new_canvas_h)
    new_eff_w = _round(new_eff_w)
    new_eff_h = _round(new_eff_h)
    new_fd_w = _round(new_fd_w)
    new_fd_h = _round(new_fd_h)
    if new_prot_w is not None:
        new_prot_w = _round(new_prot_w)
        new_prot_h = _round(new_prot_h)

    # 5. Apply maximum dimensions
    if max_dims:
        max_w = float(max_dims.get("width", new_canvas_w))
        max_h = float(max_dims.get("height", new_canvas_h))
        if pad_to_max:
            new_canvas_w = max(new_canvas_w, max_w)
            new_canvas_h = max(new_canvas_h, max_h)
        else:
            new_canvas_w = min(new_canvas_w, max_w)
            new_canvas_h = min(new_canvas_h, max_h)

    # 6. Compute anchor for framing within canvas
    def _align(canvas_dim: float, fd_dim: float, mode: str) -> float:
        if mode in ("left", "top"):
            return 0.0
        elif mode in ("right", "bottom"):
            return canvas_dim - fd_dim
        else:
            return (canvas_dim - fd_dim) / 2.0

    anchor_x = _align(new_canvas_w, new_fd_w, align_h)
    anchor_y = _align(new_canvas_h, new_fd_h, align_v)

    # 7. Build output FDL
    out_fdl = copy.deepcopy(source_fdl)
    out_ctx = out_fdl["contexts"][ctx_idx]
    out_canvas = out_ctx["canvases"][canvas_idx]

    out_canvas["id"] = str(uuid.uuid4())
    out_canvas["source_canvas_id"] = src_canvas.get("id", "")
    out_canvas["dimensions"] = {
        "width": new_canvas_w,
        "height": new_canvas_h,
    }
    out_canvas["anamorphic_squeeze"] = squeeze

    if eff_dims or new_eff_w != new_canvas_w or new_eff_h != new_canvas_h:
        out_canvas["effective_dimensions"] = {
            "width": min(new_eff_w, new_canvas_w),
            "height": min(new_eff_h, new_canvas_h),
        }
    else:
        out_canvas.pop("effective_dimensions", None)

    if src_fd and fd_idx < len(out_canvas.get("framing_decisions", [])):
        out_fd = out_canvas["framing_decisions"][fd_idx]
        out_fd["dimensions"] = {"width": new_fd_w, "height": new_fd_h}
        out_fd["anchor_point"] = {"x": anchor_x, "y": anchor_y}
        if new_prot_w is not None:
            out_fd["protection_dimensions"] = {
                "width": new_prot_w,
                "height": new_prot_h,
            }
            prot_ax = _align(new_canvas_w, new_prot_w, align_h)
            prot_ay = _align(new_canvas_h, new_prot_h, align_v)
            out_fd["protection_anchor_point"] = {
                "x": prot_ax,
                "y": prot_ay,
            }

        # Scale any additional framing decisions
        for i, fd in enumerate(out_canvas.get("framing_decisions", [])):
            if i == fd_idx:
                continue
            other_dims = fd.get("dimensions", {})
            ow = _round(float(other_dims.get("width", 0)) * scale)
            oh = _round(float(other_dims.get("height", 0)) * scale)
            fd["dimensions"] = {"width": ow, "height": oh}
            fd["anchor_point"] = {
                "x": _align(new_canvas_w, ow, align_h),
                "y": _align(new_canvas_h, oh, align_v),
            }

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

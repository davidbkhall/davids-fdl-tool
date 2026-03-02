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
    """Apply a canvas template using the ASC fdl library's CanvasTemplate.

    Uses the reference implementation's CanvasTemplate.apply() which handles
    scale factor computation, content translation, and bounding box calculation
    per the FDL specification.

    Params:
        fdl_json: str — source FDL document JSON
        template_json: str — ASC canvas template JSON
        context_index: int — which context to use (default 0)
        canvas_index: int — which canvas to use (default 0)
        fd_index: int — which framing decision to use (default 0)
        new_canvas_id: str — ID for the new output canvas (optional)
        new_fd_name: str — label for the new framing decision (optional)
    """
    if not HAS_FDL:
        raise ImportError(
            "The ASC fdl library is required for CanvasTemplate.apply(). "
            "Install from https://github.com/ascmitc/fdl/tree/dev"
        )

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

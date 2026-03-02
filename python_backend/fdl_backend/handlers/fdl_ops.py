"""FDL document operations: create, validate, parse, export.

Uses the ASC fdl reference library for all FDL construction, validation,
and serialization. Falls back to raw dict handling only when the library
is unavailable.
"""

from __future__ import annotations

import json
import os
from typing import Any

from fdl_backend.utils.fdl_convert import HAS_FDL

if HAS_FDL:
    from fdl_backend.utils.fdl_convert import (
        add_canvas_to_context,
        add_context_to_fdl,
        add_framing_decision_to_canvas,
        build_fdl,
        fdl_from_path,
        fdl_from_string,
        fdl_to_dict,
        fdl_to_json,
    )


def noop(params: dict) -> dict:
    """No-op placeholder handler."""
    return {"status": "ok"}


def create(params: dict) -> dict:
    """Create a new FDL document from provided parameters.

    Params:
        header: dict with optional fdl_creator, description, default_framing_intent
        contexts: list of context definitions
    """
    if not HAS_FDL:
        return _create_fallback(params)

    header = params.get("header", {})
    contexts = params.get("contexts", [])

    doc = build_fdl(
        fdl_creator=header.get("fdl_creator", "FDL Tool"),
        description=header.get("description", ""),
        default_framing_intent=header.get("default_framing_intent"),
        fdl_uuid=header.get("uuid"),
    )

    for ctx_def in contexts:
        ctx = add_context_to_fdl(
            doc,
            label=ctx_def.get("label", ""),
            context_creator=ctx_def.get("context_creator", "FDL Tool"),
        )

        for canvas_def in ctx_def.get("canvases", []):
            dims = canvas_def.get("dimensions", {"width": 0, "height": 0})
            eff_dims = canvas_def.get("effective_dimensions")
            eff_anchor = canvas_def.get("effective_anchor_point", {})

            canvas = add_canvas_to_context(
                ctx,
                label=canvas_def.get("label", ""),
                width=int(dims.get("width", 0)),
                height=int(dims.get("height", 0)),
                canvas_id=canvas_def.get("id"),
                effective_width=int(eff_dims["width"]) if eff_dims else None,
                effective_height=int(eff_dims["height"]) if eff_dims else None,
                effective_anchor_x=float(eff_anchor.get("x", 0)) if eff_anchor else 0.0,
                effective_anchor_y=float(eff_anchor.get("y", 0)) if eff_anchor else 0.0,
            )

            for fd_def in canvas_def.get("framing_decisions", []):
                fd_dims = fd_def.get("dimensions", {"width": 0, "height": 0})
                anchor = fd_def.get("anchor_point", {})
                prot_dims = fd_def.get("protection_dimensions")
                prot_anchor = fd_def.get("protection_anchor_point", {})

                add_framing_decision_to_canvas(
                    canvas,
                    label=fd_def.get("label", ""),
                    width=float(fd_dims.get("width", 0)),
                    height=float(fd_dims.get("height", 0)),
                    fd_id=fd_def.get("id"),
                    framing_intent_id=fd_def.get("framing_intent_id"),
                    anchor_x=float(anchor["x"]) if "x" in anchor else None,
                    anchor_y=float(anchor["y"]) if "y" in anchor else None,
                    protection_width=float(prot_dims["width"]) if prot_dims else None,
                    protection_height=float(prot_dims["height"]) if prot_dims else None,
                    protection_anchor_x=float(prot_anchor.get("x", 0)) if prot_anchor else 0.0,
                    protection_anchor_y=float(prot_anchor.get("y", 0)) if prot_anchor else 0.0,
                )

    return {"fdl": fdl_to_dict(doc)}


def validate(params: dict) -> dict:
    """Validate an FDL document or file.

    Params:
        path: str — file path to .fdl.json
        json_string: str — raw JSON string (alternative to path)
    """
    if not HAS_FDL:
        return _validate_fallback(params)

    json_string = params.get("json_string")
    path = params.get("path")

    if path:
        if not os.path.exists(path):
            return {
                "valid": False,
                "errors": [{"path": "", "message": f"File not found: {path}", "severity": "error"}],
                "warnings": [],
            }
        with open(path) as f:
            json_string = f.read()

    if not json_string:
        return {
            "valid": False,
            "errors": [{"path": "", "message": "No JSON input provided", "severity": "error"}],
            "warnings": [],
        }

    try:
        doc = fdl_from_string(json_string, validate=True)
        doc.validate()
        return {"valid": True, "errors": [], "warnings": []}
    except Exception as exc:
        error_msg = str(exc)
        return {
            "valid": False,
            "errors": [{"path": "", "message": error_msg, "severity": "error"}],
            "warnings": [],
        }


def parse(params: dict) -> dict:
    """Parse an FDL file and return structured data.

    Params:
        path: str — file path to .fdl.json
        json_string: str — raw JSON string
    """
    json_string = params.get("json_string")
    path = params.get("path")

    if path:
        if not os.path.exists(path):
            raise FileNotFoundError(f"File not found: {path}")
        if HAS_FDL:
            doc = fdl_from_path(path, validate=False)
            return {"fdl": fdl_to_dict(doc)}
        with open(path) as f:
            json_string = f.read()

    if not json_string:
        raise ValueError("No JSON input provided")

    if HAS_FDL:
        doc = fdl_from_string(json_string, validate=False)
        return {"fdl": fdl_to_dict(doc)}

    return {"fdl": json.loads(json_string)}


def export_json(params: dict) -> dict:
    """Export FDL data as canonical JSON string.

    Params:
        fdl_data: dict — the FDL document to export
    """
    fdl_data = params.get("fdl_data", {})

    if HAS_FDL:
        from fdl_backend.utils.fdl_convert import dict_to_fdl

        try:
            doc = dict_to_fdl(fdl_data)
            return {"json_string": fdl_to_json(doc)}
        except Exception:
            pass

    json_string = json.dumps(fdl_data, indent=2, ensure_ascii=False)
    return {"json_string": json_string}


# ---------------------------------------------------------------------------
# Fallback implementations (used when fdl library is not installed)
# ---------------------------------------------------------------------------


def _create_fallback(params: dict) -> dict:
    """Create FDL document using raw dicts in v2.0.1 format (no fdl library)."""
    import uuid as _uuid

    header = params.get("header", {})
    contexts = params.get("contexts", [])

    fdl_uuid = header.get("uuid", str(_uuid.uuid4()))

    doc: dict[str, Any] = {
        "uuid": fdl_uuid,
        "version": {"major": 2, "minor": 0},
        "fdl_creator": header.get("fdl_creator", "FDL Tool"),
        "framing_intents": [],
        "contexts": [],
        "canvas_templates": [],
    }

    if header.get("default_framing_intent"):
        doc["default_framing_intent"] = header["default_framing_intent"]

    for ctx_def in contexts:
        ctx: dict[str, Any] = {
            "label": ctx_def.get("label", ""),
            "context_creator": ctx_def.get("context_creator", "FDL Tool"),
            "canvases": [],
        }

        for canvas_def in ctx_def.get("canvases", []):
            canvas: dict[str, Any] = {
                "id": canvas_def.get("id", canvas_def.get("canvas_uuid", str(_uuid.uuid4()))),
                "label": canvas_def.get("label", ""),
                "source_canvas_id": canvas_def.get("source_canvas_id", ""),
                "dimensions": canvas_def.get("dimensions", {"width": 0, "height": 0}),
                "anamorphic_squeeze": canvas_def.get("anamorphic_squeeze", 1.0),
                "framing_decisions": [],
            }

            if "effective_dimensions" in canvas_def:
                canvas["effective_dimensions"] = canvas_def["effective_dimensions"]
            eff_anchor = canvas_def.get("effective_anchor_point", canvas_def.get("effective_anchor"))
            if eff_anchor:
                canvas["effective_anchor_point"] = eff_anchor

            for fd_def in canvas_def.get("framing_decisions", []):
                fd: dict[str, Any] = {
                    "id": fd_def.get("id", fd_def.get("fd_uuid", str(_uuid.uuid4()))),
                    "label": fd_def.get("label", ""),
                    "framing_intent_id": fd_def.get("framing_intent_id", fd_def.get("framing_intent", "")),
                    "dimensions": fd_def.get("dimensions", {"width": 0, "height": 0}),
                    "anchor_point": fd_def.get("anchor_point", fd_def.get("anchor", {"x": 0, "y": 0})),
                }
                if fd_def.get("protection_dimensions"):
                    fd["protection_dimensions"] = fd_def["protection_dimensions"]
                prot_anchor = fd_def.get("protection_anchor_point", fd_def.get("protection_anchor"))
                if prot_anchor:
                    fd["protection_anchor_point"] = prot_anchor
                canvas["framing_decisions"].append(fd)

            ctx["canvases"].append(canvas)

        doc["contexts"].append(ctx)

    return {"fdl": doc}


def _validate_fallback(params: dict) -> dict:
    """Validate FDL using structural checks (no fdl library)."""
    errors: list[dict] = []
    warnings: list[dict] = []

    json_string = params.get("json_string")
    path = params.get("path")

    if path:
        if not os.path.exists(path):
            return {
                "valid": False,
                "errors": [{"path": "", "message": f"File not found: {path}", "severity": "error"}],
                "warnings": [],
            }
        with open(path) as f:
            json_string = f.read()

    if not json_string:
        return {
            "valid": False,
            "errors": [{"path": "", "message": "No JSON input provided", "severity": "error"}],
            "warnings": [],
        }

    try:
        doc = json.loads(json_string)
    except json.JSONDecodeError as exc:
        return {
            "valid": False,
            "errors": [{"path": "", "message": f"Invalid JSON: {exc}", "severity": "error"}],
            "warnings": [],
        }

    if not isinstance(doc, dict):
        errors.append({"path": "", "message": "Root must be an object", "severity": "error"})
        return {"valid": False, "errors": errors, "warnings": warnings}

    if "uuid" not in doc:
        errors.append({"path": "uuid", "message": "Missing FDL UUID", "severity": "error"})

    if "version" not in doc and "header" not in doc:
        warnings.append({"path": "version", "message": "Missing version", "severity": "warning"})

    contexts = doc.get("contexts", doc.get("fdl_contexts", []))
    if not isinstance(contexts, list):
        errors.append({"path": "contexts", "message": "contexts must be an array", "severity": "error"})
    else:
        for i, ctx in enumerate(contexts):
            ctx_path = f"contexts[{i}]"

            canvases = ctx.get("canvases", [])
            if not isinstance(canvases, list):
                errors.append(
                    {"path": f"{ctx_path}.canvases", "message": "canvases must be an array", "severity": "error"}
                )
                continue

            for j, canvas in enumerate(canvases):
                canvas_path = f"{ctx_path}.canvases[{j}]"
                if "id" not in canvas:
                    errors.append({"path": f"{canvas_path}.id", "message": "Missing canvas id", "severity": "error"})
                if "dimensions" not in canvas:
                    errors.append(
                        {
                            "path": f"{canvas_path}.dimensions",
                            "message": "Missing canvas dimensions",
                            "severity": "error",
                        }
                    )
                else:
                    dims = canvas["dimensions"]
                    if not isinstance(dims, dict) or "width" not in dims or "height" not in dims:
                        errors.append(
                            {
                                "path": f"{canvas_path}.dimensions",
                                "message": "Dimensions must have width and height",
                                "severity": "error",
                            }
                        )
                    elif dims.get("width", 0) <= 0 or dims.get("height", 0) <= 0:
                        warnings.append(
                            {
                                "path": f"{canvas_path}.dimensions",
                                "message": "Dimensions should be positive",
                                "severity": "warning",
                            }
                        )

                fds = canvas.get("framing_decisions", [])
                for k, fd in enumerate(fds):
                    fd_path = f"{canvas_path}.framing_decisions[{k}]"
                    if "id" not in fd:
                        errors.append({"path": f"{fd_path}.id", "message": "Missing FD id", "severity": "error"})
                    if "dimensions" not in fd:
                        errors.append(
                            {"path": f"{fd_path}.dimensions", "message": "Missing FD dimensions", "severity": "error"}
                        )

    return {"valid": len(errors) == 0, "errors": errors, "warnings": warnings}

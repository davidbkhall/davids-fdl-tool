"""FDL document operations: create, validate, parse, export."""

import json
import os
import uuid


def noop(params: dict) -> dict:
    """No-op placeholder handler."""
    return {"status": "ok"}


def create(params: dict) -> dict:
    """Create a new FDL document from provided parameters.

    Params:
        header: dict with optional fdl_creator, description, default_framing_intent
        contexts: list of context definitions
        intents: list of framing intent labels (convenience for simple FDLs)
    """
    header = params.get("header", {})
    contexts = params.get("contexts", [])

    fdl_uuid = header.get("uuid", str(uuid.uuid4()))

    doc = {
        "uuid": fdl_uuid,
        "header": {
            "uuid": fdl_uuid,
            "version": "2.0.1",
            "fdl_creator": header.get("fdl_creator", "FDL Tool"),
            "description": header.get("description", ""),
        },
        "fdl_contexts": [],
    }

    if header.get("default_framing_intent"):
        doc["header"]["default_framing_intent"] = header["default_framing_intent"]

    for ctx_def in contexts:
        ctx_uuid = ctx_def.get("context_uuid", str(uuid.uuid4()))
        ctx = {
            "context_uuid": ctx_uuid,
            "label": ctx_def.get("label", ""),
            "context_creator": ctx_def.get("context_creator", "FDL Tool"),
            "canvases": [],
        }

        for canvas_def in ctx_def.get("canvases", []):
            canvas_uuid = canvas_def.get("canvas_uuid", str(uuid.uuid4()))
            canvas = {
                "canvas_uuid": canvas_uuid,
                "label": canvas_def.get("label", ""),
                "dimensions": canvas_def.get("dimensions", {"width": 0, "height": 0}),
                "framing_decisions": [],
            }

            # Optional fields
            for key in ["effective_anchor", "effective_dimensions", "photosite", "photosite_anchor"]:
                if key in canvas_def:
                    canvas[key] = canvas_def[key]

            for fd_def in canvas_def.get("framing_decisions", []):
                fd_uuid = fd_def.get("fd_uuid", str(uuid.uuid4()))
                fd = {
                    "fd_uuid": fd_uuid,
                    "label": fd_def.get("label", ""),
                    "dimensions": fd_def.get("dimensions", {"width": 0, "height": 0}),
                }
                for key in ["framing_intent", "anchor", "protection_dimensions", "protection_anchor"]:
                    if key in fd_def:
                        fd[key] = fd_def[key]
                canvas["framing_decisions"].append(fd)

            ctx["canvases"].append(canvas)

        doc["fdl_contexts"].append(ctx)

    return {"fdl": doc}


def validate(params: dict) -> dict:
    """Validate an FDL document or file.

    Params:
        path: str — file path to .fdl.json
        json_string: str — raw JSON string (alternative to path)
    """
    errors: list[dict] = []
    warnings: list[dict] = []

    # Load the JSON
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

    # Parse JSON
    try:
        doc = json.loads(json_string)
    except json.JSONDecodeError as exc:
        return {
            "valid": False,
            "errors": [{"path": "", "message": f"Invalid JSON: {exc}", "severity": "error"}],
            "warnings": [],
        }

    # Structural validation
    if not isinstance(doc, dict):
        errors.append({"path": "", "message": "Root must be an object", "severity": "error"})
        return {"valid": False, "errors": errors, "warnings": warnings}

    # Check required top-level fields
    if "uuid" not in doc and ("header" not in doc or "uuid" not in doc.get("header", {})):
        errors.append({"path": "uuid", "message": "Missing FDL UUID", "severity": "error"})

    header = doc.get("header", {})
    if not header:
        errors.append({"path": "header", "message": "Missing header object", "severity": "error"})
    else:
        if "version" not in header:
            warnings.append({"path": "header.version", "message": "Missing version in header", "severity": "warning"})

    # Check contexts
    contexts = doc.get("fdl_contexts", [])
    if not isinstance(contexts, list):
        errors.append({"path": "fdl_contexts", "message": "fdl_contexts must be an array", "severity": "error"})
    else:
        for i, ctx in enumerate(contexts):
            ctx_path = f"fdl_contexts[{i}]"
            if "context_uuid" not in ctx:
                errors.append(
                    {"path": f"{ctx_path}.context_uuid", "message": "Missing context UUID", "severity": "error"}
                )

            canvases = ctx.get("canvases", [])
            if not isinstance(canvases, list):
                errors.append(
                    {"path": f"{ctx_path}.canvases", "message": "canvases must be an array", "severity": "error"}
                )
                continue

            for j, canvas in enumerate(canvases):
                canvas_path = f"{ctx_path}.canvases[{j}]"
                if "canvas_uuid" not in canvas:
                    errors.append(
                        {"path": f"{canvas_path}.canvas_uuid", "message": "Missing canvas UUID", "severity": "error"}
                    )
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

                # Check framing decisions
                fds = canvas.get("framing_decisions", [])
                for k, fd in enumerate(fds):
                    fd_path = f"{canvas_path}.framing_decisions[{k}]"
                    if "fd_uuid" not in fd:
                        errors.append({"path": f"{fd_path}.fd_uuid", "message": "Missing FD UUID", "severity": "error"})
                    if "dimensions" not in fd:
                        errors.append(
                            {"path": f"{fd_path}.dimensions", "message": "Missing FD dimensions", "severity": "error"}
                        )

    return {"valid": len(errors) == 0, "errors": errors, "warnings": warnings}


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
        with open(path) as f:
            json_string = f.read()

    if not json_string:
        raise ValueError("No JSON input provided")

    doc = json.loads(json_string)
    return {"fdl": doc}


def export_json(params: dict) -> dict:
    """Export FDL data as canonical JSON string.

    Params:
        fdl_data: dict — the FDL document to export
    """
    fdl_data = params.get("fdl_data", {})
    json_string = json.dumps(fdl_data, indent=2, ensure_ascii=False)
    return {"json_string": json_string}

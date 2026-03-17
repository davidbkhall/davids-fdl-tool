"""JSON-RPC 2.0 server over stdin/stdout.

Protocol: one JSON object per line (newline-delimited).
Each request is a JSON-RPC 2.0 request; each response is a JSON-RPC 2.0 response.
"""

import json
import sys
import traceback
import time
from typing import Any

from fdl_backend.handlers import chart_gen, clip_id, fdl_ops, frameline_ops, geometry_ops, image_ops, template_ops

# Method dispatch table: "domain.method" -> handler function
HANDLERS: dict[str, Any] = {}


def register_handlers() -> None:
    """Register all handler functions from handler modules."""
    # FDL operations
    HANDLERS["fdl.create"] = fdl_ops.create
    HANDLERS["fdl.validate"] = fdl_ops.validate
    HANDLERS["fdl.parse"] = fdl_ops.parse
    HANDLERS["fdl.export_json"] = fdl_ops.export_json

    # Canvas template operations
    HANDLERS["template.validate"] = template_ops.validate
    HANDLERS["template.apply"] = template_ops.apply_template
    HANDLERS["template.apply_fdl"] = template_ops.apply_fdl_template
    HANDLERS["template.preview"] = template_ops.preview
    HANDLERS["template.export"] = template_ops.export_template

    # Chart generation
    HANDLERS["chart.generate_svg"] = chart_gen.generate_svg
    HANDLERS["chart.generate_png"] = chart_gen.generate_png
    HANDLERS["chart.generate_tiff"] = chart_gen.generate_tiff
    HANDLERS["chart.generate_pdf"] = chart_gen.generate_pdf
    HANDLERS["chart.generate_fdl"] = chart_gen.generate_fdl

    # Image operations
    HANDLERS["image.load_and_overlay"] = image_ops.load_and_overlay
    HANDLERS["image.get_info"] = image_ops.get_info

    # Clip ID operations
    HANDLERS["clip.probe"] = clip_id.probe
    HANDLERS["clip.batch_probe"] = clip_id.batch_probe
    HANDLERS["clip.generate_fdl"] = clip_id.generate_fdl
    HANDLERS["clip.validate_canvas"] = clip_id.validate_canvas

    # Geometry operations
    HANDLERS["geometry.compute_rects"] = geometry_ops.compute_rects
    HANDLERS["geometry.apply_alignment"] = geometry_ops.apply_alignment
    HANDLERS["geometry.apply_protection_alignment"] = geometry_ops.apply_protection_alignment
    HANDLERS["geometry.compute_protection"] = geometry_ops.compute_protection

    # Camera DB
    HANDLERS["camera_db.sync"] = fdl_ops.noop  # Placeholder

    # Manufacturer frameline conversion
    HANDLERS["frameline.status"] = frameline_ops.status
    HANDLERS["frameline.arri.list_cameras"] = frameline_ops.arri_list_cameras
    HANDLERS["frameline.arri.to_xml"] = frameline_ops.arri_to_xml
    HANDLERS["frameline.arri.to_fdl"] = frameline_ops.arri_to_fdl
    HANDLERS["frameline.sony.list_cameras"] = frameline_ops.sony_list_cameras
    HANDLERS["frameline.sony.to_xml"] = frameline_ops.sony_to_xml
    HANDLERS["frameline.sony.to_fdl"] = frameline_ops.sony_to_fdl




def _request_id_from_params(params: Any) -> str:
    if isinstance(params, dict):
        rid = params.get("request_id")
        if isinstance(rid, str):
            return rid.strip()
    return ""


def _trace_event(event: str, **fields: Any) -> None:
    payload = {"event": event, "ts_ms": int(time.time() * 1000), **fields}
    try:
        sys.stderr.write(f"[trace] {json.dumps(payload, sort_keys=True)}\n")
        sys.stderr.flush()
    except Exception:
        # Tracing must never break request handling.
        pass

def make_response(id: int | None, result: Any = None, error: dict | None = None) -> dict:
    """Build a JSON-RPC 2.0 response."""
    resp: dict[str, Any] = {"jsonrpc": "2.0", "id": id}
    if error is not None:
        resp["error"] = error
    else:
        resp["result"] = result
    return resp


def make_error(code: int, message: str, data: Any = None) -> dict:
    """Build a JSON-RPC 2.0 error object."""
    err: dict[str, Any] = {"code": code, "message": message}
    if data is not None:
        err["data"] = data
    return err


def handle_request(request: dict) -> dict:
    """Dispatch a single JSON-RPC request and return a response."""
    req_id = request.get("id")
    method = request.get("method", "")
    params = request.get("params", {})
    request_id = _request_id_from_params(params)

    _trace_event("rpc_request_received", request_id=request_id, rpc_id=req_id, method=method)

    if method not in HANDLERS:
        _trace_event("rpc_request_failed", request_id=request_id, rpc_id=req_id, method=method, reason="method_not_found")
        return make_response(req_id, error=make_error(-32601, f"Method not found: {method}"))

    try:
        handler = HANDLERS[method]
        result = handler(params)
        _trace_event("rpc_request_succeeded", request_id=request_id, rpc_id=req_id, method=method)
        return make_response(req_id, result=result)
    except Exception as exc:
        tb = traceback.format_exc()
        _trace_event(
            "rpc_request_failed",
            request_id=request_id,
            rpc_id=req_id,
            method=method,
            reason=str(exc),
            error_type=exc.__class__.__name__,
        )
        return make_response(
            req_id,
            error=make_error(-32000, str(exc), data={"traceback": tb}),
        )


def main() -> None:
    """Main server loop: read JSON-RPC requests from stdin, write responses to stdout."""
    register_handlers()

    # Signal readiness
    sys.stderr.write("FDL backend server ready\n")
    sys.stderr.flush()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            response = make_response(None, error=make_error(-32700, f"Parse error: {exc}"))
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()
            continue

        response = handle_request(request)
        sys.stdout.write(json.dumps(response) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()

"""JSON-RPC 2.0 server over stdin/stdout.

Protocol: one JSON object per line (newline-delimited).
Each request is a JSON-RPC 2.0 request; each response is a JSON-RPC 2.0 response.
"""

import json
import sys
import traceback
from typing import Any

from fdl_backend.handlers import chart_gen, clip_id, fdl_ops, image_ops, template_ops

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
    HANDLERS["template.preview"] = template_ops.preview
    HANDLERS["template.export"] = template_ops.export_template

    # Chart generation
    HANDLERS["chart.generate_svg"] = chart_gen.generate_svg
    HANDLERS["chart.generate_png"] = chart_gen.generate_png
    HANDLERS["chart.generate_fdl"] = chart_gen.generate_fdl

    # Image operations
    HANDLERS["image.load_and_overlay"] = image_ops.load_and_overlay
    HANDLERS["image.get_info"] = image_ops.get_info

    # Clip ID operations
    HANDLERS["clip.probe"] = clip_id.probe
    HANDLERS["clip.batch_probe"] = clip_id.batch_probe
    HANDLERS["clip.generate_fdl"] = clip_id.generate_fdl
    HANDLERS["clip.validate_canvas"] = clip_id.validate_canvas

    # Camera DB
    HANDLERS["camera_db.sync"] = fdl_ops.noop  # Placeholder


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

    if method not in HANDLERS:
        return make_response(req_id, error=make_error(-32601, f"Method not found: {method}"))

    try:
        handler = HANDLERS[method]
        result = handler(params)
        return make_response(req_id, result=result)
    except Exception as exc:
        tb = traceback.format_exc()
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

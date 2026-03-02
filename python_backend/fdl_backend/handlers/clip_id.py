"""Clip ID operations: probe, batch probe, generate FDL, validate canvas.

Uses the ASC fdl library for FDL document creation and canvas validation
when available.
"""

from __future__ import annotations

import json
import os
import subprocess
import uuid

from fdl_backend.utils.fdl_convert import HAS_FDL

if HAS_FDL:
    from fdl_backend.utils.fdl_convert import (
        add_canvas_to_context,
        add_context_to_fdl,
        add_framing_decision_to_canvas,
        build_fdl,
        dict_to_fdl,
        fdl_to_dict,
    )


VIDEO_EXTENSIONS = {
    ".mov",
    ".mp4",
    ".mxf",
    ".avi",
    ".mkv",
    ".r3d",
    ".braw",
    ".ari",
    ".arx",
    ".dng",
    ".dpx",
    ".exr",
}


def probe(params: dict) -> dict:
    """Probe a single video file with ffprobe.

    Params:
        file_path: str — path to video file
    """
    file_path = params["file_path"]
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File not found: {file_path}")

    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "quiet",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
            file_path,
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed for {file_path}: {result.stderr}")

    data = json.loads(result.stdout)
    return _parse_probe(data, file_path)


def batch_probe(params: dict) -> dict:
    """Probe all video files in a directory.

    Params:
        dir_path: str — directory path
        extensions: list[str] — file extensions to include (optional)
        recursive: bool — search recursively (default False)
    """
    dir_path = params["dir_path"]
    extensions = set(params.get("extensions", VIDEO_EXTENSIONS))
    recursive = params.get("recursive", False)

    if not os.path.isdir(dir_path):
        raise NotADirectoryError(f"Not a directory: {dir_path}")

    clips: list[dict] = []
    errors: list[dict] = []

    if recursive:
        entries = []
        for root, _dirs, files in os.walk(dir_path):
            for f in files:
                entries.append(os.path.join(root, f))
    else:
        entries = [os.path.join(dir_path, f) for f in os.listdir(dir_path)]

    for entry_path in sorted(entries):
        ext = os.path.splitext(entry_path)[1].lower()
        if ext not in extensions:
            continue

        try:
            clip = probe({"file_path": entry_path})
            clips.append(clip)
        except Exception as exc:
            errors.append({"file_path": entry_path, "error": str(exc)})

    return {"clips": clips, "errors": errors, "total": len(clips) + len(errors)}


def generate_fdl(params: dict) -> dict:
    """Generate an FDL document for a clip.

    Params:
        clip_info: dict — probed clip info (width, height, codec, etc.)
        template_fdl: dict — optional template FDL to copy framing decisions from
    """
    clip = params.get("clip_info", {})
    template = params.get("template_fdl")

    width = clip.get("width", 0)
    height = clip.get("height", 0)
    file_name = clip.get("file_name", "unknown")

    if HAS_FDL:
        return _generate_fdl_with_library(width, height, file_name, template)

    return _generate_fdl_fallback(width, height, file_name, template)


def validate_canvas(params: dict) -> dict:
    """Compare FDL canvas dimensions vs actual video dimensions.

    Params:
        fdl_data: dict — FDL document (alternative to fdl_json/fdl_path)
        fdl_path: str — path to FDL file
        fdl_json: str — raw FDL JSON string
        video_path: str — path to video file
        clip_info: dict — clip info with width/height (alternative to video_path)
    """
    fdl_data = params.get("fdl_data")
    fdl_json = params.get("fdl_json")
    fdl_path = params.get("fdl_path")
    clip_info = params.get("clip_info")

    if fdl_path:
        with open(fdl_path) as f:
            fdl_json = f.read()

    if clip_info:
        actual_w = clip_info.get("width", 0)
        actual_h = clip_info.get("height", 0)
    else:
        video_path = params["video_path"]
        clip = probe({"file_path": video_path})
        actual_w = clip.get("width", 0)
        actual_h = clip.get("height", 0)

    if fdl_data:
        return _validate_canvas_fallback(fdl_data, actual_w, actual_h)

    if HAS_FDL and fdl_json:
        return _validate_canvas_with_library(fdl_json, actual_w, actual_h)

    fdl = json.loads(fdl_json) if fdl_json else {}
    return _validate_canvas_fallback(fdl, actual_w, actual_h)


# ---------------------------------------------------------------------------
# fdl library implementations
# ---------------------------------------------------------------------------


def _generate_fdl_with_library(
    width: int,
    height: int,
    file_name: str,
    template: dict | None,
) -> dict:
    """Generate FDL using the ASC fdl library."""
    doc = build_fdl(
        fdl_creator="FDL Tool Clip ID",
        description=f"Generated from clip: {file_name}",
    )

    ctx = add_context_to_fdl(doc, label=file_name, context_creator="FDL Tool Clip ID")

    canvas = add_canvas_to_context(
        ctx,
        label=f"{width}x{height}",
        width=width,
        height=height,
    )

    if template:
        template_contexts = template.get("contexts", template.get("fdl_contexts", []))
        if template_contexts:
            template_canvas = (
                template_contexts[0].get("canvases", [{}])[0] if template_contexts[0].get("canvases") else {}
            )
            for fd_def in template_canvas.get("framing_decisions", []):
                fd_dims = fd_def.get("dimensions", {"width": 0, "height": 0})
                anchor = fd_def.get("anchor_point", fd_def.get("anchor", {}))
                prot_dims = fd_def.get("protection_dimensions")
                prot_anchor = fd_def.get("protection_anchor_point", fd_def.get("protection_anchor", {}))

                add_framing_decision_to_canvas(
                    canvas,
                    label=fd_def.get("label", ""),
                    width=float(fd_dims.get("width", 0)),
                    height=float(fd_dims.get("height", 0)),
                    framing_intent_id=fd_def.get("framing_intent_id", fd_def.get("framing_intent")),
                    anchor_x=float(anchor["x"]) if "x" in anchor else None,
                    anchor_y=float(anchor["y"]) if "y" in anchor else None,
                    protection_width=float(prot_dims["width"]) if prot_dims else None,
                    protection_height=float(prot_dims["height"]) if prot_dims else None,
                    protection_anchor_x=float(prot_anchor.get("x", 0)) if prot_anchor else 0.0,
                    protection_anchor_y=float(prot_anchor.get("y", 0)) if prot_anchor else 0.0,
                )

    return {"fdl": fdl_to_dict(doc)}


def _validate_canvas_with_library(
    fdl_json: str,
    actual_w: int,
    actual_h: int,
) -> dict:
    """Validate canvas dimensions using fdl library geometry."""
    fdl_obj = dict_to_fdl(json.loads(fdl_json))
    results: list[dict] = []

    for ctx in fdl_obj.contexts:
        for canvas in ctx.canvases:
            rect = canvas.get_rect()
            canvas_w = int(rect.width)
            canvas_h = int(rect.height)

            match = canvas_w == actual_w and canvas_h == actual_h
            results.append(
                {
                    "canvas_label": canvas.label,
                    "canvas_width": canvas_w,
                    "canvas_height": canvas_h,
                    "actual_width": actual_w,
                    "actual_height": actual_h,
                    "match": match,
                }
            )

    all_match = all(r["match"] for r in results) if results else False
    return {"match": all_match, "results": results}


# ---------------------------------------------------------------------------
# Fallback implementations
# ---------------------------------------------------------------------------


def _generate_fdl_fallback(
    width: int,
    height: int,
    file_name: str,
    template: dict | None,
) -> dict:
    """Generate FDL in v2.0.1 format using raw dicts (no fdl library)."""
    doc = {
        "uuid": str(uuid.uuid4()),
        "version": {"major": 2, "minor": 0},
        "fdl_creator": "FDL Tool Clip ID",
        "framing_intents": [],
        "contexts": [
            {
                "label": file_name,
                "context_creator": "FDL Tool Clip ID",
                "canvases": [
                    {
                        "id": str(uuid.uuid4()),
                        "label": f"{width}x{height}",
                        "source_canvas_id": "",
                        "dimensions": {"width": width, "height": height},
                        "anamorphic_squeeze": 1.0,
                        "framing_decisions": [],
                    }
                ],
            }
        ],
        "canvas_templates": [],
    }

    if template:
        template_contexts = template.get("contexts", template.get("fdl_contexts", []))
        if template_contexts:
            template_canvas = (
                template_contexts[0].get("canvases", [{}])[0] if template_contexts[0].get("canvases") else {}
            )
            for fd in template_canvas.get("framing_decisions", []):
                new_fd = dict(fd)
                new_fd["id"] = str(uuid.uuid4())
                doc["contexts"][0]["canvases"][0]["framing_decisions"].append(new_fd)

    return {"fdl": doc}


def _validate_canvas_fallback(
    fdl: dict,
    actual_w: int,
    actual_h: int,
) -> dict:
    """Validate canvas dimensions using raw dict (no fdl library)."""
    results: list[dict] = []
    contexts = fdl.get("contexts", fdl.get("fdl_contexts", []))
    for ctx in contexts:
        for canvas in ctx.get("canvases", []):
            dims = canvas.get("dimensions", {})
            canvas_w = dims.get("width", 0)
            canvas_h = dims.get("height", 0)

            match = canvas_w == actual_w and canvas_h == actual_h
            results.append(
                {
                    "canvas_id": canvas.get("id", ""),
                    "canvas_label": canvas.get("label", ""),
                    "canvas_width": canvas_w,
                    "canvas_height": canvas_h,
                    "actual_width": actual_w,
                    "actual_height": actual_h,
                    "match": match,
                }
            )

    all_match = all(r["match"] for r in results) if results else False
    return {"match": all_match, "results": results}


def _parse_probe(data: dict, file_path: str) -> dict:
    """Extract clip info from ffprobe JSON output."""
    streams = data.get("streams", [])
    video_stream = next((s for s in streams if s.get("codec_type") == "video"), {})
    fmt = data.get("format", {})

    width = video_stream.get("width", 0)
    height = video_stream.get("height", 0)
    codec = video_stream.get("codec_name", "unknown")

    fps = 0.0
    r_frame_rate = video_stream.get("r_frame_rate", "0/1")
    parts = r_frame_rate.split("/")
    if len(parts) == 2:
        num, den = float(parts[0]), float(parts[1])
        if den != 0:
            fps = num / den

    duration = float(fmt.get("duration", 0))
    file_size = int(fmt.get("size", 0))
    file_name = os.path.basename(file_path)

    return {
        "file_path": file_path,
        "file_name": file_name,
        "width": width,
        "height": height,
        "codec": codec,
        "fps": round(fps, 3),
        "duration": round(duration, 3),
        "file_size": file_size,
    }

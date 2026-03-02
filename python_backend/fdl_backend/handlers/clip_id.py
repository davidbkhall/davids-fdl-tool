"""Clip ID operations: probe, batch probe, generate FDL, validate canvas."""

import json
import os
import subprocess
import uuid
from typing import Any

# Common video extensions
VIDEO_EXTENSIONS = {
    ".mov", ".mp4", ".mxf", ".avi", ".mkv", ".r3d",
    ".braw", ".ari", ".arx", ".dng", ".dpx", ".exr",
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
            "-v", "quiet",
            "-print_format", "json",
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
        template_fdl: dict — optional template FDL to base on
    """
    clip = params.get("clip_info", {})
    template = params.get("template_fdl")

    width = clip.get("width", 0)
    height = clip.get("height", 0)
    file_name = clip.get("file_name", "unknown")

    fdl_uuid = str(uuid.uuid4())
    context_uuid = str(uuid.uuid4())
    canvas_uuid = str(uuid.uuid4())

    doc = {
        "uuid": fdl_uuid,
        "header": {
            "uuid": fdl_uuid,
            "version": "2.0.1",
            "fdl_creator": "FDL Tool Clip ID",
            "description": f"Generated from clip: {file_name}",
        },
        "fdl_contexts": [
            {
                "context_uuid": context_uuid,
                "label": file_name,
                "context_creator": "FDL Tool Clip ID",
                "canvases": [
                    {
                        "canvas_uuid": canvas_uuid,
                        "label": f"{width}x{height}",
                        "dimensions": {"width": width, "height": height},
                        "framing_decisions": [],
                    }
                ],
            }
        ],
    }

    # If template provided, copy framing decisions
    if template:
        template_contexts = template.get("fdl_contexts", [])
        if template_contexts:
            template_canvas = template_contexts[0].get("canvases", [{}])[0] if template_contexts[0].get("canvases") else {}
            for fd in template_canvas.get("framing_decisions", []):
                new_fd = dict(fd)
                new_fd["fd_uuid"] = str(uuid.uuid4())
                doc["fdl_contexts"][0]["canvases"][0]["framing_decisions"].append(new_fd)

    return {"fdl": doc}


def validate_canvas(params: dict) -> dict:
    """Compare FDL canvas dimensions vs actual video dimensions.

    Params:
        fdl_path: str — path to FDL file (or fdl_json)
        video_path: str — path to video file
    """
    fdl_json = params.get("fdl_json")
    fdl_path = params.get("fdl_path")
    video_path = params["video_path"]

    if fdl_path:
        with open(fdl_path) as f:
            fdl_json = f.read()

    fdl = json.loads(fdl_json) if fdl_json else {}
    clip = probe({"file_path": video_path})

    actual_w = clip.get("width", 0)
    actual_h = clip.get("height", 0)

    results: list[dict] = []
    contexts = fdl.get("fdl_contexts", [])
    for ctx in contexts:
        for canvas in ctx.get("canvases", []):
            dims = canvas.get("dimensions", {})
            canvas_w = dims.get("width", 0)
            canvas_h = dims.get("height", 0)

            match = canvas_w == actual_w and canvas_h == actual_h
            results.append({
                "canvas_uuid": canvas.get("canvas_uuid", ""),
                "canvas_label": canvas.get("label", ""),
                "canvas_width": canvas_w,
                "canvas_height": canvas_h,
                "actual_width": actual_w,
                "actual_height": actual_h,
                "match": match,
            })

    all_match = all(r["match"] for r in results) if results else False
    return {"match": all_match, "comparisons": results}


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

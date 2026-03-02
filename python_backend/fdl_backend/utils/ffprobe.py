"""ffprobe subprocess wrapper."""

import json
import subprocess
from typing import Any


def run_ffprobe(file_path: str) -> dict:
    """Run ffprobe on a file and return parsed JSON output."""
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
        raise RuntimeError(f"ffprobe failed: {result.stderr}")

    return json.loads(result.stdout)


def is_available() -> bool:
    """Check if ffprobe is installed and available."""
    try:
        result = subprocess.run(
            ["ffprobe", "-version"],
            capture_output=True,
            text=True,
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False

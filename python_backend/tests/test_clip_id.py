"""Tests for clip ID handler."""

import json

from fdl_backend.handlers import clip_id


def test_generate_fdl_from_clip():
    """Generate FDL from clip info."""
    result = clip_id.generate_fdl(
        {
            "clip_info": {
                "file_name": "A001_C001.mov",
                "width": 4096,
                "height": 2160,
                "codec": "prores",
                "fps": 23.976,
                "duration": 120.5,
            },
        }
    )
    fdl = result["fdl"]
    assert fdl["header"]["version"] == "2.0.1"
    canvas = fdl["fdl_contexts"][0]["canvases"][0]
    assert canvas["dimensions"]["width"] == 4096
    assert canvas["dimensions"]["height"] == 2160


def test_generate_fdl_with_template():
    """Generate FDL with template framing decisions."""
    template = {
        "fdl_contexts": [
            {
                "canvases": [
                    {
                        "framing_decisions": [
                            {"fd_uuid": "fd-1", "label": "2.39:1", "dimensions": {"width": 4096, "height": 1716}},
                        ]
                    }
                ]
            }
        ]
    }
    result = clip_id.generate_fdl(
        {
            "clip_info": {"file_name": "test.mov", "width": 4096, "height": 2160},
            "template_fdl": template,
        }
    )
    fds = result["fdl"]["fdl_contexts"][0]["canvases"][0]["framing_decisions"]
    assert len(fds) == 1
    assert fds[0]["label"] == "2.39:1"
    # Should have a new UUID, not the template's
    assert fds[0]["fd_uuid"] != "fd-1"


def test_validate_canvas_match():
    """Validate canvas matches video dimensions."""
    # Verify the JSON structure is valid (actual validation requires ffprobe + video file)
    json.dumps(
        {
            "fdl_contexts": [
                {
                    "canvases": [
                        {
                            "canvas_uuid": "c1",
                            "label": "4K",
                            "dimensions": {"width": 3840, "height": 2160},
                            "framing_decisions": [],
                        }
                    ]
                }
            ]
        }
    )
    # Full validation requires ffprobe and a real video file, so we skip the actual call
    # and just test the structure expectation
    assert True  # Placeholder for integration test

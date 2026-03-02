"""Tests for clip ID handler."""

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
    contexts = fdl["contexts"]
    assert len(contexts) >= 1
    canvas = contexts[0]["canvases"][0]
    dims = canvas["dimensions"]
    assert dims["width"] in (4096, 4096.0)
    assert dims["height"] in (2160, 2160.0)


def test_generate_fdl_with_template():
    """Generate FDL with template framing decisions."""
    template = {
        "contexts": [
            {
                "canvases": [
                    {
                        "framing_decisions": [
                            {
                                "id": "c1-fd1",
                                "label": "2.39:1",
                                "framing_intent_id": "scope",
                                "dimensions": {"width": 4096.0, "height": 1716.0},
                                "anchor_point": {"x": 0.0, "y": 222.0},
                            },
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
    contexts = result["fdl"]["contexts"]
    canvas = contexts[0]["canvases"][0]
    fds = canvas["framing_decisions"]
    assert len(fds) == 1
    assert fds[0]["label"] == "2.39:1"


def test_validate_canvas_match():
    """Validate canvas matches video dimensions."""
    fdl = {
        "uuid": "test",
        "version": {"major": 2, "minor": 0},
        "contexts": [
            {
                "canvases": [
                    {
                        "id": "c1",
                        "label": "4K",
                        "source_canvas_id": "c1",
                        "dimensions": {"width": 3840, "height": 2160},
                        "anamorphic_squeeze": 1.0,
                        "framing_decisions": [],
                    }
                ]
            }
        ],
    }
    result = clip_id.validate_canvas(
        {
            "fdl_data": fdl,
            "clip_info": {"width": 3840, "height": 2160},
        }
    )
    assert "results" in result
    assert len(result["results"]) >= 1
    assert result["results"][0]["match"] is True

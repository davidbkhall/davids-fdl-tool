"""Tests for FDL operations handler."""

import json
import os
import tempfile

from fdl_backend.handlers import fdl_ops
from fdl_backend.utils.fdl_convert import HAS_FDL


def test_create_minimal():
    """Create a minimal FDL document."""
    result = fdl_ops.create(
        {
            "header": {"fdl_creator": "test"},
            "contexts": [],
        }
    )
    assert "fdl" in result
    fdl = result["fdl"]
    assert "contexts" in fdl
    assert "version" in fdl
    assert fdl["version"]["major"] == 2


def test_create_with_context_and_canvas():
    """Create an FDL with context, canvas, and framing decision."""
    result = fdl_ops.create(
        {
            "header": {"fdl_creator": "test"},
            "contexts": [
                {
                    "label": "Test Context",
                    "canvases": [
                        {
                            "label": "4K",
                            "dimensions": {"width": 4096, "height": 2160},
                            "framing_decisions": [
                                {
                                    "label": "2.39:1",
                                    "dimensions": {"width": 4096, "height": 1716},
                                }
                            ],
                        }
                    ],
                }
            ],
        }
    )
    fdl = result["fdl"]
    contexts = fdl["contexts"]
    assert len(contexts) >= 1

    canvas = contexts[0]["canvases"][0]
    dims = canvas["dimensions"]
    assert dims["width"] in (4096, 4096.0)

    fds = canvas["framing_decisions"]
    assert len(fds) >= 1


def test_validate_valid_fdl():
    """Validate a well-formed FDL in v2.0.1 format."""
    fdl_json = json.dumps(
        {
            "uuid": "test_uuid",
            "version": {"major": 2, "minor": 0},
            "fdl_creator": "test",
            "contexts": [
                {
                    "canvases": [
                        {
                            "id": "c1",
                            "source_canvas_id": "c1",
                            "dimensions": {"width": 3840, "height": 2160},
                            "anamorphic_squeeze": 1.0,
                            "framing_decisions": [
                                {
                                    "id": "c1-fd1",
                                    "framing_intent_id": "scope",
                                    "dimensions": {"width": 3840.0, "height": 1608.0},
                                    "anchor_point": {"x": 0.0, "y": 276.0},
                                }
                            ],
                        }
                    ],
                }
            ],
        }
    )
    result = fdl_ops.validate({"json_string": fdl_json})
    if not HAS_FDL:
        assert result["valid"] is True
        assert len(result["errors"]) == 0
    else:
        assert "valid" in result
        assert "errors" in result


def test_validate_missing_uuid():
    """Validate catches missing UUID."""
    fdl_json = json.dumps(
        {
            "version": {"major": 2, "minor": 0},
            "contexts": [],
        }
    )
    result = fdl_ops.validate({"json_string": fdl_json})
    assert result["valid"] is False
    assert len(result["errors"]) > 0


def test_validate_invalid_json():
    """Validate catches malformed JSON."""
    result = fdl_ops.validate({"json_string": "{not valid json"})
    assert result["valid"] is False
    assert len(result["errors"]) > 0


def test_validate_from_file():
    """Validate from a file path."""
    fdl = {
        "uuid": "file_test",
        "version": {"major": 2, "minor": 0},
        "contexts": [],
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".fdl.json", delete=False) as f:
        json.dump(fdl, f)
        temp_path = f.name

    try:
        result = fdl_ops.validate({"path": temp_path})
        assert "valid" in result
    finally:
        os.unlink(temp_path)


def test_validate_file_not_found():
    """Validate handles missing file."""
    result = fdl_ops.validate({"path": "/nonexistent/file.fdl.json"})
    assert result["valid"] is False


def test_parse():
    """Parse an FDL JSON string."""
    fdl = {
        "uuid": "test",
        "version": {"major": 2, "minor": 0},
        "contexts": [],
    }
    result = fdl_ops.parse({"json_string": json.dumps(fdl)})
    assert "fdl" in result


def test_export_json():
    """Export FDL data as JSON string."""
    fdl_data = {
        "uuid": "export_test",
        "version": {"major": 2, "minor": 0},
        "contexts": [],
    }
    result = fdl_ops.export_json({"fdl_data": fdl_data})
    assert "json_string" in result
    parsed = json.loads(result["json_string"])
    assert "uuid" in parsed

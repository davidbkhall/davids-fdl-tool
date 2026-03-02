"""Tests for FDL operations handler."""

import json
import os
import tempfile

from fdl_backend.handlers import fdl_ops


def test_create_minimal():
    """Create a minimal FDL document."""
    result = fdl_ops.create({
        "header": {"fdl_creator": "test"},
        "contexts": [],
    })
    assert "fdl" in result
    fdl = result["fdl"]
    assert "uuid" in fdl
    assert fdl["header"]["version"] == "2.0.1"
    assert fdl["header"]["fdl_creator"] == "test"
    assert fdl["fdl_contexts"] == []


def test_create_with_context_and_canvas():
    """Create an FDL with context, canvas, and framing decision."""
    result = fdl_ops.create({
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
    })
    fdl = result["fdl"]
    assert len(fdl["fdl_contexts"]) == 1
    ctx = fdl["fdl_contexts"][0]
    assert ctx["label"] == "Test Context"
    assert len(ctx["canvases"]) == 1
    canvas = ctx["canvases"][0]
    assert canvas["dimensions"]["width"] == 4096
    assert len(canvas["framing_decisions"]) == 1


def test_validate_valid_fdl():
    """Validate a well-formed FDL."""
    fdl_json = json.dumps({
        "uuid": "test-uuid",
        "header": {"uuid": "test-uuid", "version": "2.0.1"},
        "fdl_contexts": [
            {
                "context_uuid": "ctx-1",
                "canvases": [
                    {
                        "canvas_uuid": "c-1",
                        "dimensions": {"width": 3840, "height": 2160},
                        "framing_decisions": [
                            {
                                "fd_uuid": "fd-1",
                                "dimensions": {"width": 3840, "height": 1608},
                            }
                        ],
                    }
                ],
            }
        ],
    })
    result = fdl_ops.validate({"json_string": fdl_json})
    assert result["valid"] is True
    assert len(result["errors"]) == 0


def test_validate_missing_uuid():
    """Validate catches missing UUID."""
    fdl_json = json.dumps({
        "header": {},
        "fdl_contexts": [],
    })
    result = fdl_ops.validate({"json_string": fdl_json})
    assert result["valid"] is False
    assert any("UUID" in e["message"] for e in result["errors"])


def test_validate_invalid_json():
    """Validate catches malformed JSON."""
    result = fdl_ops.validate({"json_string": "{not valid json"})
    assert result["valid"] is False
    assert len(result["errors"]) > 0


def test_validate_from_file():
    """Validate from a file path."""
    fdl = {
        "uuid": "file-test",
        "header": {"uuid": "file-test", "version": "2.0.1"},
        "fdl_contexts": [],
    }
    with tempfile.NamedTemporaryFile(mode="w", suffix=".fdl.json", delete=False) as f:
        json.dump(fdl, f)
        temp_path = f.name

    try:
        result = fdl_ops.validate({"path": temp_path})
        assert result["valid"] is True
    finally:
        os.unlink(temp_path)


def test_validate_file_not_found():
    """Validate handles missing file."""
    result = fdl_ops.validate({"path": "/nonexistent/file.fdl.json"})
    assert result["valid"] is False


def test_parse():
    """Parse an FDL JSON string."""
    fdl = {"uuid": "test", "header": {"uuid": "test"}, "fdl_contexts": []}
    result = fdl_ops.parse({"json_string": json.dumps(fdl)})
    assert result["fdl"]["uuid"] == "test"


def test_export_json():
    """Export FDL data as JSON string."""
    fdl_data = {"uuid": "export-test", "header": {"uuid": "export-test"}}
    result = fdl_ops.export_json({"fdl_data": fdl_data})
    assert "json_string" in result
    parsed = json.loads(result["json_string"])
    assert parsed["uuid"] == "export-test"

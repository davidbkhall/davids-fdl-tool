"""Tests for image operations handler."""

import base64
import os
import tempfile

import pytest

from fdl_backend.handlers import image_ops


def _create_test_image(width=100, height=80):
    """Create a minimal PNG test image and return its path."""
    try:
        from PIL import Image
    except ImportError:
        pytest.skip("Pillow not installed")

    img = Image.new("RGB", (width, height), color=(128, 128, 128))
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        img.save(tmp.name)
        return tmp.name


def test_get_info():
    """Get info from a test image."""
    path = _create_test_image(200, 150)
    try:
        result = image_ops.get_info({"image_path": path})
        assert result["width"] == 200
        assert result["height"] == 150
        assert result["format"] == "PNG"
    finally:
        os.unlink(path)


def test_load_and_overlay_no_framelines():
    """Load image with empty FDL (no framelines drawn)."""
    path = _create_test_image(320, 240)
    try:
        result = image_ops.load_and_overlay(
            {
                "image_path": path,
                "fdl_data": {"contexts": []},
            }
        )
        assert "png_base64" in result
        assert result["width"] == 320
        assert result["height"] == 240
        data = base64.b64decode(result["png_base64"])
        assert data[:4] == b"\x89PNG"
    finally:
        os.unlink(path)


def test_load_and_overlay_with_framelines():
    """Load image and draw FDL framelines."""
    path = _create_test_image(400, 300)
    fdl_data = {
        "contexts": [
            {
                "canvases": [
                    {
                        "id": "c1",
                        "source_canvas_id": "c1",
                        "dimensions": {"width": 400, "height": 300},
                        "anamorphic_squeeze": 1.0,
                        "framing_decisions": [
                            {
                                "id": "c1-scope",
                                "label": "2.39:1",
                                "framing_intent_id": "scope",
                                "dimensions": {"width": 400.0, "height": 167.0},
                                "anchor_point": {"x": 0.0, "y": 66.0},
                            },
                            {
                                "id": "c1-hd",
                                "label": "16:9",
                                "framing_intent_id": "hd",
                                "dimensions": {"width": 400.0, "height": 225.0},
                                "anchor_point": {"x": 0.0, "y": 37.5},
                            },
                        ],
                    }
                ]
            }
        ]
    }
    try:
        result = image_ops.load_and_overlay(
            {
                "image_path": path,
                "fdl_data": fdl_data,
            }
        )
        assert "png_base64" in result
        assert result["width"] == 400
        assert result["height"] == 300
        data = base64.b64decode(result["png_base64"])
        assert len(data) > 100
    finally:
        os.unlink(path)


def test_load_and_overlay_scaled_canvas():
    """Framelines from a canvas larger than the image should scale correctly."""
    path = _create_test_image(200, 100)
    fdl_data = {
        "contexts": [
            {
                "canvases": [
                    {
                        "id": "c1",
                        "source_canvas_id": "c1",
                        "dimensions": {"width": 4000, "height": 2000},
                        "anamorphic_squeeze": 1.0,
                        "framing_decisions": [
                            {
                                "id": "c1-crop",
                                "label": "Center crop",
                                "framing_intent_id": "crop",
                                "dimensions": {"width": 2000.0, "height": 1000.0},
                                "anchor_point": {"x": 1000.0, "y": 500.0},
                            },
                        ],
                    }
                ]
            }
        ]
    }
    try:
        result = image_ops.load_and_overlay(
            {
                "image_path": path,
                "fdl_data": fdl_data,
            }
        )
        assert result["width"] == 200
        assert result["height"] == 100
    finally:
        os.unlink(path)

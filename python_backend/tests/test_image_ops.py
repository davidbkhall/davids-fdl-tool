"""Tests for image operations handler."""

import base64
import io
import os
import tempfile

import pytest

from fdl_backend.handlers import image_ops

# Create a tiny test image for tests
def _create_test_image(width=100, height=80):
    """Create a minimal PNG test image and return its path."""
    try:
        from PIL import Image
    except ImportError:
        pytest.skip("Pillow not installed")

    img = Image.new("RGB", (width, height), color=(128, 128, 128))
    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
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
        result = image_ops.load_and_overlay({
            "image_path": path,
            "fdl_data": {"fdl_contexts": []},
        })
        assert "png_base64" in result
        assert result["width"] == 320
        assert result["height"] == 240
        # Verify it's valid base64 PNG
        data = base64.b64decode(result["png_base64"])
        assert data[:4] == b"\x89PNG"
    finally:
        os.unlink(path)


def test_load_and_overlay_with_framelines():
    """Load image and draw FDL framelines."""
    path = _create_test_image(400, 300)
    fdl_data = {
        "fdl_contexts": [
            {
                "canvases": [
                    {
                        "dimensions": {"width": 400, "height": 300},
                        "framing_decisions": [
                            {
                                "label": "2.39:1",
                                "dimensions": {"width": 400, "height": 167},
                                "anchor": {"x": 0, "y": 66},
                            },
                            {
                                "label": "16:9",
                                "dimensions": {"width": 400, "height": 225},
                            },
                        ],
                    }
                ]
            }
        ]
    }
    try:
        result = image_ops.load_and_overlay({
            "image_path": path,
            "fdl_data": fdl_data,
        })
        assert "png_base64" in result
        assert result["width"] == 400
        assert result["height"] == 300
        # The overlay should produce a larger PNG than the plain image
        data = base64.b64decode(result["png_base64"])
        assert len(data) > 100
    finally:
        os.unlink(path)


def test_load_and_overlay_scaled_canvas():
    """Framelines from a canvas larger than the image should scale correctly."""
    path = _create_test_image(200, 100)
    fdl_data = {
        "fdl_contexts": [
            {
                "canvases": [
                    {
                        "dimensions": {"width": 4000, "height": 2000},
                        "framing_decisions": [
                            {
                                "label": "Center crop",
                                "dimensions": {"width": 2000, "height": 1000},
                            },
                        ],
                    }
                ]
            }
        ]
    }
    try:
        result = image_ops.load_and_overlay({
            "image_path": path,
            "fdl_data": fdl_data,
        })
        assert result["width"] == 200
        assert result["height"] == 100
    finally:
        os.unlink(path)

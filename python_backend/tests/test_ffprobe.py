"""Tests for ffprobe utility."""

from fdl_backend.utils import ffprobe


def test_is_available():
    """Check if ffprobe detection works (may be True or False depending on system)."""
    result = ffprobe.is_available()
    assert isinstance(result, bool)

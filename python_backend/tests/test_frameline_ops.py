"""Tests for manufacturer frameline conversion handlers."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from fdl_backend.handlers import frameline_ops


def test_status_returns_expected_shape():
    result = frameline_ops.status({})
    assert "arri" in result
    assert "sony" in result
    assert "available" in result["arri"]
    assert "available" in result["sony"]


def test_arri_to_xml_requires_camera_fields():
    with pytest.raises(ValueError):
        frameline_ops.arri_to_xml({"fdl_json": "{}"})


def test_sony_to_xml_requires_camera_fields():
    with pytest.raises(ValueError):
        frameline_ops.sony_to_xml({"fdl_json": "{}"})


def test_conversion_report_shape():
    report = frameline_ops._conversion_report(
        conversion="fdl_to_arri_xml",
        mapped_fields=["canvas.dimensions"],
        warnings=["sample warning"],
        mapping_details=[{"source_field": "a", "target_field": "b"}],
        dropped_fields=["fdl.header.default_framing_intent"],
    )
    assert report["conversion"] == "fdl_to_arri_xml"
    assert report["mapped_fields"] == ["canvas.dimensions"]
    assert report["warnings"] == ["sample warning"]
    assert report["mapping_details"]
    assert report["dropped_fields"] == ["fdl.header.default_framing_intent"]
    assert report["lossy"] is True


def test_conversion_report_not_lossy_when_clean():
    report = frameline_ops._conversion_report(
        conversion="sony_xml_to_fdl",
        mapped_fields=["canvas.dimensions"],
        warnings=[],
        mapping_details=[],
        dropped_fields=[],
    )
    assert report["lossy"] is False


def _fixture_root() -> Path:
    env_override = os.environ.get("FDL_FRAMELINE_FIXTURES_DIR")
    if env_override:
        return Path(env_override)
    return Path(__file__).parent / "fixtures" / "frameline"


def _fixture(manufacturer: str) -> Path | None:
    root = _fixture_root()
    if manufacturer == "arri":
        candidate = root / "arri" / "sample.xml"
    else:
        candidate = root / "sony" / "sample.xml"
    return candidate if candidate.exists() else None


def test_arri_xml_fixture_to_fdl_if_available():
    fixture = _fixture("arri")
    if not fixture:
        pytest.skip("ARRI frameline fixture not present")
    try:
        frameline_ops._load_arri_module()
    except Exception:
        pytest.skip("fdl_arri_frameline unavailable")

    result = frameline_ops.arri_to_fdl({"xml_path": str(fixture)})
    assert "fdl" in result
    assert isinstance(result.get("framing_decisions_created"), int)
    assert "report" in result
    assert "lossy" in result["report"]
    assert "mapped_fields" in result["report"]


def test_sony_xml_fixture_to_fdl_if_available():
    fixture = _fixture("sony")
    if not fixture:
        pytest.skip("Sony frameline fixture not present")
    try:
        frameline_ops._load_sony_module()
    except Exception:
        pytest.skip("fdl_sony_frameline unavailable")

    result = frameline_ops.sony_to_fdl({"xml_path": str(fixture)})
    assert "fdl" in result
    assert isinstance(result.get("framing_decisions_created"), int)
    assert "report" in result
    assert "lossy" in result["report"]
    assert "mapped_fields" in result["report"]

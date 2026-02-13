"""
Tests for separator.py
"""

import os
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest
import responses

from separator import (
    check_api_key,
    get_headers,
    is_valid_audio_file,
    upload_file,
    create_job,
    wait_for_completion,
    download_stems,
    VALID_EXTENSIONS,
    API_BASE_URL,
)


class TestValidation:
    """Tests for validation functions."""

    def test_valid_audio_extensions(self):
        """Test that common audio formats are recognized."""
        valid_files = [
            Path("song.mp3"),
            Path("song.MP3"),
            Path("audio.wav"),
            Path("audio.WAV"),
            Path("music.flac"),
            Path("podcast.m4a"),
            Path("sound.ogg"),
            Path("track.aac"),
        ]
        for f in valid_files:
            assert is_valid_audio_file(f), f"{f} should be valid"

    def test_invalid_audio_extensions(self):
        """Test that non-audio formats are rejected."""
        invalid_files = [
            Path("document.pdf"),
            Path("image.png"),
            Path("video.mp4"),
            Path("text.txt"),
            Path("noextension"),
        ]
        for f in invalid_files:
            assert not is_valid_audio_file(f), f"{f} should be invalid"

    def test_check_api_key_missing(self):
        """Test that missing API key returns False."""
        with patch.dict(os.environ, {}, clear=True):
            with patch("separator.API_KEY", None):
                assert check_api_key() is False

    def test_check_api_key_present(self):
        """Test that present API key returns True."""
        with patch("separator.API_KEY", "test_key_123"):
            assert check_api_key() is True

    def test_get_headers(self):
        """Test that headers include authorization."""
        with patch("separator.API_KEY", "test_key_123"):
            headers = get_headers()
            assert "Authorization" in headers
            assert headers["Authorization"] == "Bearer test_key_123"


class TestUpload:
    """Tests for file upload functionality."""

    @responses.activate
    def test_upload_file_success(self, tmp_path):
        """Test successful file upload."""
        # Create a test file
        test_file = tmp_path / "test.mp3"
        test_file.write_bytes(b"fake audio content")

        # Mock the API response
        responses.add(
            responses.POST,
            f"{API_BASE_URL}/upload",
            json={"id": "asset_123"},
            status=200,
        )

        with patch("separator.API_KEY", "test_key"):
            asset_id = upload_file(test_file, quiet=True)

        assert asset_id == "asset_123"

    @responses.activate
    def test_upload_file_failure(self, tmp_path):
        """Test failed file upload."""
        test_file = tmp_path / "test.mp3"
        test_file.write_bytes(b"fake audio content")

        responses.add(
            responses.POST,
            f"{API_BASE_URL}/upload",
            json={"error": "Invalid file"},
            status=400,
        )

        with patch("separator.API_KEY", "test_key"):
            asset_id = upload_file(test_file, quiet=True)

        assert asset_id is None


class TestJobCreation:
    """Tests for job creation."""

    @responses.activate
    def test_create_job_success(self):
        """Test successful job creation."""
        responses.add(
            responses.POST,
            f"{API_BASE_URL}/job",
            json={"id": "job_456"},
            status=201,
        )

        with patch("separator.API_KEY", "test_key"):
            job_id = create_job("asset_123", quiet=True)

        assert job_id == "job_456"

    @responses.activate
    def test_create_job_failure(self):
        """Test failed job creation."""
        responses.add(
            responses.POST,
            f"{API_BASE_URL}/job",
            json={"error": "Invalid asset"},
            status=400,
        )

        with patch("separator.API_KEY", "test_key"):
            job_id = create_job("invalid_asset", quiet=True)

        assert job_id is None


class TestJobPolling:
    """Tests for job status polling."""

    @responses.activate
    def test_wait_for_completion_success(self):
        """Test successful job completion."""
        responses.add(
            responses.GET,
            f"{API_BASE_URL}/job/job_123",
            json={"status": "completed", "outputAssets": []},
            status=200,
        )

        with patch("separator.API_KEY", "test_key"):
            result = wait_for_completion("job_123", poll_interval=0, quiet=True)

        assert result is not None
        assert result["status"] == "completed"

    @responses.activate
    def test_wait_for_completion_failure(self):
        """Test failed job."""
        responses.add(
            responses.GET,
            f"{API_BASE_URL}/job/job_123",
            json={"status": "failed", "error": "Processing error"},
            status=200,
        )

        with patch("separator.API_KEY", "test_key"):
            result = wait_for_completion("job_123", poll_interval=0, quiet=True)

        assert result is None


class TestDownload:
    """Tests for stem downloading."""

    @responses.activate
    def test_download_stems_success(self, tmp_path):
        """Test successful stem download."""
        output_dir = tmp_path / "output"

        # Mock the download URL
        responses.add(
            responses.GET,
            "https://example.com/vocals.wav",
            body=b"fake audio data",
            status=200,
        )

        job_data = {
            "outputAssets": [
                {"name": "vocals", "link": "https://example.com/vocals.wav"}
            ]
        }

        saved = download_stems(job_data, output_dir, "song.mp3", quiet=True)

        assert len(saved) == 1
        assert saved[0].exists()
        assert "vocals" in saved[0].name

    def test_download_stems_empty(self, tmp_path):
        """Test handling of empty output assets."""
        output_dir = tmp_path / "output"
        job_data = {"outputAssets": []}

        saved = download_stems(job_data, output_dir, "song.mp3", quiet=True)

        assert len(saved) == 0# Tests package
"""
Tests for batch.py
"""

from pathlib import Path
from unittest.mock import patch

import pytest

from batch import find_audio_files, VALID_EXTENSIONS


class TestFindAudioFiles:
    """Tests for file discovery."""

    def test_find_files_in_directory(self, tmp_path):
        """Test finding audio files in a directory."""
        # Create test files
        (tmp_path / "song1.mp3").touch()
        (tmp_path / "song2.wav").touch()
        (tmp_path / "document.pdf").touch()
        (tmp_path / "image.png").touch()

        files = find_audio_files(tmp_path, recursive=False)

        assert len(files) == 2
        names = [f.name for f in files]
        assert "song1.mp3" in names
        assert "song2.wav" in names
        assert "document.pdf" not in names

    def test_find_files_recursive(self, tmp_path):
        """Test recursive file discovery."""
        # Create nested structure
        subdir = tmp_path / "subdir"
        subdir.mkdir()

        (tmp_path / "song1.mp3").touch()
        (subdir / "song2.mp3").touch()

        # Non-recursive
        files_flat = find_audio_files(tmp_path, recursive=False)
        assert len(files_flat) == 1

        # Recursive
        files_recursive = find_audio_files(tmp_path, recursive=True)
        assert len(files_recursive) == 2

    def test_find_files_single_file(self, tmp_path):
        """Test with a single file input."""
        test_file = tmp_path / "song.mp3"
        test_file.touch()

        files = find_audio_files(test_file)

        assert len(files) == 1
        assert files[0] == test_file

    def test_find_files_invalid_single_file(self, tmp_path):
        """Test with an invalid single file."""
        test_file = tmp_path / "document.pdf"
        test_file.touch()

        files = find_audio_files(test_file)

        assert len(files) == 0

    def test_find_files_empty_directory(self, tmp_path):
        """Test with empty directory."""
        files = find_audio_files(tmp_path)
        assert len(files) == 0

    def test_find_files_case_insensitive(self, tmp_path):
        """Test that file extensions are case-insensitive."""
        (tmp_path / "song.MP3").touch()
        (tmp_path / "audio.WAV").touch()
        (tmp_path / "music.Flac").touch()

        files = find_audio_files(tmp_path)

        # Should find at least the uppercase versions
        assert len(files) >= 2


class TestValidExtensions:
    """Tests for extension configuration."""

    def test_common_extensions_included(self):
        """Test that common audio extensions are in the valid set."""
        expected = {".mp3", ".wav", ".flac", ".m4a"}
        for ext in expected:
            assert ext in VALID_EXTENSIONS, f"{ext} should be valid"
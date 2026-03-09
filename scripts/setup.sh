#!/bin/bash
set -euo pipefail

echo "=== FDL Tool Setup ==="

# Check Python
if command -v python3 &>/dev/null; then
    PY_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    echo "✓ Python $PY_VERSION found"
    PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
    PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
    if [ "$PY_MAJOR" -lt 3 ] || ([ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 10 ]); then
        echo "✗ Python 3.10+ required (found $PY_VERSION)"
        exit 1
    fi
else
    echo "✗ Python 3 not found. Install via: brew install python@3.12"
    exit 1
fi

# Check ffprobe
if command -v ffprobe &>/dev/null; then
    echo "✓ ffprobe found: $(ffprobe -version 2>&1 | head -1)"
else
    echo "✗ ffprobe not found. Install via: brew install ffmpeg"
    exit 1
fi

# Install Python backend
echo ""
echo "Installing Python backend dependencies..."
cd "$(dirname "$0")/../python_backend"
pip3 install -e ".[dev]"

echo ""
echo "Installing additional runtime dependencies..."
# pydantic: required by vendored fdl / fdl_arri_frameline / fdl_sony_frameline packages
# cairosvg + svgwrite: required for chart PDF/SVG export
# Force public PyPI to avoid corporate mirror timeouts
python3 -m pip install --break-system-packages --index-url https://pypi.org/simple \
    pydantic cairosvg svgwrite \
    && echo "✓ Installed pydantic, cairosvg, svgwrite" \
    || echo "⚠︎  Some optional packages unavailable; PDF/SVG chart export and ARRI/Sony XML conversion may not work"

echo ""
echo "=== Setup complete ==="
echo "Build the Swift app:  cd FDLTool && swift build"
echo "Run Python tests:     cd python_backend && pytest"

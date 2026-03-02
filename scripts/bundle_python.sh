#!/bin/bash
set -euo pipefail

# Bundle the Python backend into a standalone virtual environment
# suitable for inclusion in an app distribution.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_DIR/python_backend"
BUNDLE_DIR="$PROJECT_DIR/dist/python_env"

echo "=== Bundling Python Backend ==="

# Clean previous bundle
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

# Find python3
PYTHON=$(command -v python3 || true)
if [ -z "$PYTHON" ]; then
    echo "✗ Python 3 not found"
    exit 1
fi
echo "Using Python: $PYTHON ($($PYTHON --version))"

# Create virtual environment
echo "Creating virtual environment..."
$PYTHON -m venv "$BUNDLE_DIR/venv"
source "$BUNDLE_DIR/venv/bin/activate"

# Install the backend package
echo "Installing fdl-backend..."
pip install --upgrade pip wheel
pip install "$BACKEND_DIR"

# Verify installation
echo "Verifying installation..."
python -c "from fdl_backend import server; print('fdl_backend imported successfully')"

# Copy the backend source for reference
cp -r "$BACKEND_DIR/fdl_backend" "$BUNDLE_DIR/fdl_backend"

# Create a launcher script
cat > "$BUNDLE_DIR/run_server.sh" << 'LAUNCHER'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/venv/bin/activate"
exec python -m fdl_backend.server
LAUNCHER
chmod +x "$BUNDLE_DIR/run_server.sh"

# Calculate bundle size
BUNDLE_SIZE=$(du -sh "$BUNDLE_DIR" | awk '{print $1}')
PACKAGE_COUNT=$(pip list --format=freeze | wc -l | tr -d ' ')

deactivate

echo ""
echo "=== Bundle Complete ==="
echo "Location: $BUNDLE_DIR"
echo "Size:     $BUNDLE_SIZE"
echo "Packages: $PACKAGE_COUNT"
echo ""
echo "To use in the app, set FDL_PYTHON_BACKEND=$BUNDLE_DIR"
echo "Or include $BUNDLE_DIR in the app bundle at Contents/Resources/python_env"

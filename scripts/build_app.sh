#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FDL Tool"
BUNDLE_ID="com.fdltool.app"
APP_DIR="$HOME/Desktop/$APP_NAME.app"

echo "Building release binary..."
cd "$PROJECT_DIR/FDLTool"
swift build -c release 2>&1 | tail -5

BINARY="$(swift build -c release --show-bin-path)/FDLTool"

echo "Creating app bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/FDLTool"

# Copy icon
if [ -f "$PROJECT_DIR/resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Copy bundled resources
[ -f "$PROJECT_DIR/resources/camera_db/cameras.json" ] && cp "$PROJECT_DIR/resources/camera_db/cameras.json" "$APP_DIR/Contents/Resources/"
[ -d "$PROJECT_DIR/resources/fdl_schemas" ] && cp -r "$PROJECT_DIR/resources/fdl_schemas" "$APP_DIR/Contents/Resources/"
[ -d "$PROJECT_DIR/resources/sample_fdls" ] && cp -r "$PROJECT_DIR/resources/sample_fdls" "$APP_DIR/Contents/Resources/"

# Bundle Python backend
if [ -d "$PROJECT_DIR/python_backend" ]; then
    echo "Bundling Python backend..."
    mkdir -p "$APP_DIR/Contents/Resources/python_backend"
    cp -r "$PROJECT_DIR/python_backend/fdl_backend" "$APP_DIR/Contents/Resources/python_backend/"
    # Copy setup files needed for imports
    [ -f "$PROJECT_DIR/python_backend/pyproject.toml" ] && cp "$PROJECT_DIR/python_backend/pyproject.toml" "$APP_DIR/Contents/Resources/python_backend/"
fi

# Write Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FDLTool</string>
    <key>CFBundleIdentifier</key>
    <string>com.fdltool.app</string>
    <key>CFBundleName</key>
    <string>FDL Tool</string>
    <key>CFBundleDisplayName</key>
    <string>FDL Tool</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>FDL Document</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>fdl</string>
                <string>json</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "Build complete: $APP_DIR"
echo "Launching..."
open "$APP_DIR"

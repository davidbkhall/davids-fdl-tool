#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FDL Tool"
BUNDLE_ID="com.fdltool.app"
APP_DIR="$HOME/Applications/$APP_NAME.app"

# Kill any running instance first
pkill -f "$APP_DIR/Contents/MacOS/FDLTool" 2>/dev/null || true
sleep 0.5

echo "Cleaning build cache..."
cd "$PROJECT_DIR/FDLTool"
swift package clean 2>/dev/null || true

echo "Building release binary..."
swift build -c release 2>&1 | tail -5

BINARY="$(swift build -c release --show-bin-path)/FDLTool"

echo "Removing old app bundle..."
rm -rf "$APP_DIR"
rm -rf "$HOME/Desktop/$APP_NAME.app"

echo "Creating app bundle at $APP_DIR..."
mkdir -p "$(dirname "$APP_DIR")"
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
    mkdir -p "$APP_DIR/Contents/Resources/python_backend/vendor"
    # Copy setup files needed for imports
    [ -f "$PROJECT_DIR/python_backend/pyproject.toml" ] && cp "$PROJECT_DIR/python_backend/pyproject.toml" "$APP_DIR/Contents/Resources/python_backend/"
fi

# Bundle optional manufacturer conversion libraries so end users do not need local installs.
# Source paths can be provided through env vars or pre-populated vendor source folders.
ARRI_SRC="${FDL_ARRI_FRAMELINE_SRC:-$PROJECT_DIR/vendor_sources/fdl_arri_frameline}"
SONY_SRC="${FDL_SONY_FRAMELINE_SRC:-$PROJECT_DIR/vendor_sources/fdl_sony_frameline}"
resolve_module_dir() {
    local src="$1"
    local module="$2"
    if [ -d "$src/$module" ]; then echo "$src/$module"; return; fi
    if [ -d "$src/src/$module" ]; then echo "$src/src/$module"; return; fi
    if [ -d "$src/site-packages/$module" ]; then echo "$src/site-packages/$module"; return; fi
    if [ "$(basename "$src")" = "$module" ] && [ -d "$src" ]; then echo "$src"; return; fi
    echo ""
}

ARRI_MODULE_DIR="$(resolve_module_dir "$ARRI_SRC" "fdl_arri_frameline")"
SONY_MODULE_DIR="$(resolve_module_dir "$SONY_SRC" "fdl_sony_frameline")"
if [ -n "$ARRI_MODULE_DIR" ]; then
    echo "Bundling fdl_arri_frameline from $ARRI_MODULE_DIR..."
    cp -r "$ARRI_MODULE_DIR" "$APP_DIR/Contents/Resources/python_backend/vendor/"
fi
if [ -n "$SONY_MODULE_DIR" ]; then
    echo "Bundling fdl_sony_frameline from $SONY_MODULE_DIR..."
    cp -r "$SONY_MODULE_DIR" "$APP_DIR/Contents/Resources/python_backend/vendor/"
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
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.ascmitc.framing-decision-list</string>
            <key>UTTypeDescription</key>
            <string>ASC Framing Decision List</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.json</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>fdl</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "Registering app bundle with Launch Services..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" 2>/dev/null || true

echo "Build complete: $APP_DIR"
echo "Launching..."
open -n "$APP_DIR"

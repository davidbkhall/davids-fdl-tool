# FDL Tool — Project Conventions

## Overview
macOS native multi-tool utility for ASC Framing Decision Lists (FDL).
SwiftUI frontend + Python backend communicating via JSON-RPC 2.0 over stdin/stdout.

## Project Structure
- `FDLTool/` — Swift Package (macOS app, SwiftUI, MVVM)
- `python_backend/` — Python backend service (JSON-RPC server)
- `resources/` — Bundled data (camera DB, FDL schemas, sample FDLs)
- `scripts/` — Setup and build scripts

## Build & Run

### Swift App
```bash
cd FDLTool && swift build
swift run FDLTool
```

### App Bundle (for testing)
```bash
bash scripts/build_app.sh   # Cleans, builds release, bundles to ~/Desktop/FDL Tool.app, launches
```
NOTE: `swift build` and `swift build -c release` frequently fail with "Command failed to spawn: Aborted" in sandboxed environments. Always use `required_permissions: ["all"]` when running these commands.

### Python Backend (standalone testing)
```bash
cd python_backend
pip install -e ".[dev]"
python -m fdl_backend.server  # Starts JSON-RPC stdin/stdout server
```

### Setup
```bash
./scripts/setup.sh  # Installs Python deps, verifies ffmpeg
```

## Architecture

### IPC Protocol
JSON-RPC 2.0 over stdin/stdout. Swift `PythonBridge` actor launches Python subprocess.
- Requests: `{"jsonrpc":"2.0","id":N,"method":"...","params":{...}}`
- Responses: `{"jsonrpc":"2.0","id":N,"result":{...}}` or `{"jsonrpc":"2.0","id":N,"error":{...}}`

### Swift Conventions
- **MVVM**: Each tool has a View + ViewModel (ObservableObject)
- **AppState**: Shared ObservableObject for cross-tool state (current project, Python bridge, library store)
- **Navigation**: `NavigationSplitView` with sidebar tool selector
- **Models**: Codable structs in `Models/` directory — custom `encode(to:)` methods control JSON key ordering to match ASC FDL reference format
- **Services**: Backend communication in `Services/` directory

### Python Conventions
- Handlers in `fdl_backend/handlers/` — one module per domain
- Each handler function takes a dict of params, returns a dict result
- Server dispatches methods like `fdl.validate` → `fdl_ops.validate(params)`

### FDL Template Application
- Implemented entirely in Swift in `ViewerViewModel.applyTemplateLocally()` (no Python dependency)
- Follows the 10-step ASC FDL Template Application Algorithm: preserve → fill hierarchy → normalize → scale → round → output size → align → offset → crop → build
- Uses `GeoLayer` struct for 4 geometry layers: canvas(0), effective(1), protection(2), framing(3)
- Protection is NEVER filled from framing during hierarchy gap filling
- Asymmetric squeeze: width/x scaled by `(value * inputSqueeze * scale) / targetSqueeze`; height/y scaled by `value * scale`
- Reference C++ implementation: `/Users/dhall/Documents/GitHub/ascmitc/fdl/native/core/src/`
- Test scenarios: `/Users/dhall/Downloads/scenario_resources_20260215/`

### Framing-from-Intent (Chart Generator)
- `fitAspectIntoWorkingArea` uses desqueezed (display) aspect for letterbox/pillarbox determination
- Letterbox: `h = (w * squeeze) / intentAspect`; Pillarbox: `w = (h * intentAspect) / squeeze`
- Verified against Scen_10 source FDL (4320x3456, 2x squeeze → protection 4124x3456)
- `roundToEven` implements spec default "even + round" rounding strategy
- Framelines auto-recalculate via Combine when squeeze, camera, or canvas dimensions change

## Data Storage
- SQLite database at `~/Library/Application Support/FDLTool/fdltool.db`
- FDL files at `~/Library/Application Support/FDLTool/projects/{project_id}/{entry_id}.fdl.json`
- Canvas templates at `~/Library/Application Support/FDLTool/templates/{template_id}.json`

## Dependencies
- Swift: SQLite.swift (0.15.0+)
- Python: fdl, Pillow, svgwrite, cairosvg
- System: Python 3.10+, ffmpeg/ffprobe

## Testing
```bash
# Swift tests
cd FDLTool && swift test

# Python tests
cd python_backend && pytest
```

## Session Notes (2026-03-03)

### Uncommitted changes (11 files modified, ~1059 insertions)
All changes are staged in the working tree but NOT committed.

### What was done this session:
1. **Audited Framing Charts page** against reference `fdl_framing.cpp` and golden test vectors
2. **Fixed `buildLocalFDLDocument`** — now produces spec-compliant FDL documents:
   - `framing_intents` array, `default_framing_intent`, `source_canvas_id` (self-ref), `anamorphic_squeeze` always included
   - Proper FD IDs ("1-1" format) and `framing_intent_id` linking
3. **Fixed `addPreset`** — now uses `fitAspectIntoWorkingArea` for correct anamorphic handling
4. **Fixed `fitAspectIntoWorkingArea`** — uses desqueezed aspect ratio for letterbox/pillarbox determination (fixes dimensions exceeding canvas for anamorphic sensors)
5. **Added auto-recalculation** — Combine subscribers recalculate intent-linked framelines when squeeze, camera, mode, or canvas dimensions change
6. **Fixed chart canvas preview** — effective area and protection use actual anchor positions instead of always centering
7. **Fixed JSON key ordering** — custom `encode(to:)` on FDLDocument, FDLCanvas, FDLFramingDecision, FDLFramingIntent, FDLCanvasTemplate to match reference ordering (version/uuid header first, label before id). Removed `.sortedKeys` from JSONEncoder.

### What still needs to be done:
- **BUILD AND TEST**: The last `swift build` hit a sandbox abort. Need to rebuild with `required_permissions: ["all"]` and run `build_app.sh` to verify all changes.
- **Verify JSON output**: Load an FDL in the Viewer, apply a template, check that the Details > Output JSON has header fields at top matching reference format.
- **Verify anamorphic Framing Charts**: Test with ARRI ALEXA 35 + 2.0x squeeze + 2.39:1 intent — dimensions should fit within canvas (pillarbox, not overflowing letterbox).
- **Commit and push** once validated.

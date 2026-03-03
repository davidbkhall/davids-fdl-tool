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
- **Models**: Codable structs in `Models/` directory
- **Services**: Backend communication in `Services/` directory
- **JSON Serialization**: `FDLJSONSerializer` (in `FDLDocument.swift`) produces reference-ordered JSON. Do NOT use JSONEncoder for display JSON — its dictionary-backed keyed containers ignore insertion order. The serializer encodes → parses via JSONSerialization → re-serializes with explicit key order arrays matching ASC FDL reference format.

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

## Session Notes

### Latest session: 2026-03-01 (commit 71b6c90, pushed to main)

**What was done:**
1. **Fixed JSON key ordering** — Discovered that Swift's `JSONEncoder` ignores insertion order from custom `encode(to:)` methods (dictionary-backed keyed containers). Replaced with `FDLJSONSerializer` in `FDLDocument.swift` — a recursive serializer that encodes → parses → re-serializes with explicit key ordering matching ASC FDL reference format (version/uuid at top, label before id in nested objects). Removed all custom `encode(to:)` methods from FDL model structs.
2. **Fixed `fitAspectIntoWorkingArea`** — Uses desqueezed (display) aspect ratio for letterbox/pillarbox determination. Verified against Scen_10 (4320x3456, 2x squeeze → protection 4124x3456), Scen_3 (8640x5760, 1x → 8640x4860), golden vector (4096x3432, 2x → height 3428).
3. **Added auto-recalculation** — Combine subscribers in `ChartGeneratorViewModel` recalculate intent-linked framelines when anamorphic squeeze, camera, mode, or canvas dimensions change.
4. **Fixed `buildLocalFDLDocument`** — Produces spec-compliant FDL documents with `framing_intents`, `default_framing_intent`, `source_canvas_id`, proper FD IDs, and `framing_intent_id` linking.
5. **Enhanced Details tab** — Side-by-side source/output document views, full template summary in output document section.
6. **Dimension label positioning** — Refactored `dimLabel` in canvas views to use `overlay` with `Alignment` for precise inside-bounding-box positioning.
7. **Anamorphic circle** — Fixed to squeeze horizontally (`rx = radius / squeeze`), not vertically.
8. **UI refinements** — "Import Template" labels, "Choose Framing Decision" module name, Document Structure as expandable DisclosureGroup inside Source FDL module, consistent HUD between source/output.

**Build validated:** All framing test vectors pass. App bundle built and launched from `~/Desktop/FDL Tool.app`.

### Previous session work (also in commit 71b6c90):
- Full 10-step ASC FDL template application pipeline in `ViewerViewModel.applyTemplateLocally()`
- Reference image rendering in Output/Comparison tabs
- Pinch-to-zoom with `MagnificationGesture` in canvas views
- Library template editing, project assignment, zoom/layer controls
- "Open in Viewer" button in Chart Generator
- Default Creator setting in app preferences
- `Text(verbatim:)` for all dimension displays (no locale commas)

### Known areas for future work:
- **User should manually test**: Load FDL in Viewer → apply template → verify Details tab JSON has header at top and output is correct
- **User should manually test**: Framing Charts with 2.0x anamorphic squeeze → verify dimensions fit canvas and recalculate on squeeze change
- The sidebar collapse behavior was previously reported as problematic (icons disappearing). It was reverted to the standard `NavigationSplitView` behavior. User may revisit.
- Library Canvas Templates: preview panel could be further refined for parity with FDL Viewer controls
- Comparison tab reference image rendering may need additional testing with various source/template combinations

### Key file locations:
- Template application algorithm: `ViewerViewModel.swift` → `applyTemplateLocally()`
- JSON serializer: `FDLDocument.swift` → `FDLJSONSerializer`
- Framing calculation: `ChartGeneratorViewModel.swift` → `fitAspectIntoWorkingArea()`
- Combine recalculation: `ChartGeneratorViewModel.swift` → `setupRecalculationSubscribers()`
- Reference C++ implementation: `/Users/dhall/Documents/GitHub/ascmitc/fdl/native/core/src/`
- Test scenarios: `/Users/dhall/Downloads/scenario_resources_20260215/`
- Reference FDL spec documentation: https://ascmitc.github.io/fdl/dev/FDL_Apply_Template_Logic/

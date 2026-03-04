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

### Latest session: 2026-03-03 (commit 3d1d3e8, pushed to main)

**What was done:**

#### Camera Database Expansion & Cleanup
1. **Expanded bundled cameras.json** from 13 → 25 cameras with manufacturer-verified data:
   - ARRI: ALEXA 35 (8 modes), Mini LF (8), Mini (5), LF (4), SXT (4), 65 (3), 265 (3), AMIRA (3) — sourced from ARRI Formats PDF v6.1
   - RED: V-RAPTOR [X] 8K VV (5 modes), KOMODO 6K (3) — sourced from RED Technical Specifications
   - Sony: VENICE (5 modes), VENICE 2 (6), BURANO (3) — sourced from Sony Venice Calculator
   - Canon: EOS C80 (4), C70 (3), C700 (3), plus updated C400/C500 Mark II/C300 Mark III — sourced from Canon Official Specifications
   - All entries include `sync_sources` metadata for attribution
2. **Removed `commonDeliverables`** field entirely from `CameraSpec` model, `CodingKeys`, `init`, decoders, `CameraDatabaseView` UI, `CameraDBStore` enrichment logic, `CineDSyncService`, `CameraDBSyncService`, `cameras.json`, and tests
3. **Added CineD sync service** (`CineDSyncService.swift`) for web-scraping CineD Camera Database with credential support stored in app Settings
4. **Camera deduplication** — name-based dedup in `CameraDBStore.mergeFromLocal` prevents duplicate entries across bundled/synced sources
5. **Metadata preservation** — `enrichFromExisting` helper ensures rich bundled metadata isn't lost during API syncs
6. **Camera model deletion** — right-click context menu and detail-pane trash button for non-bundled cameras
7. **Resync feedback** — success/error messages with auto-dismiss after 5 seconds
8. **UI selection stability** — dynamic camera lookup by ID instead of stale array index; `orderedIDs` preserves ordering in `mergeFromAPI`

#### UI/UX Overhaul (Apple HIG alignment)
9. **Camera Database UI** — Source badges increased from 7–8pt (unreadable) to 9pt semibold with full-opacity colors via reusable `SourceBadge` component. Manufacturer section headers changed from loud accent background to clean uppercase `.caption .semibold .secondary`. Detail pane uses icon-labeled GroupBoxes, Grid with `.leadingFirstTextBaseline` alignment, `.callout` font for data. Badges display per-manufacturer colors (ARRI=teal, RED=red, Sony=indigo, Canon=pink, MMM=blue, CineD=purple).
10. **Sidebar** — Updated SF Symbols: `tray.full`, `viewfinder.rectangular`, `rectangle.on.rectangle.angled`, `film.stack`, `camera.aperture` with `.symbolRenderingMode(.hierarchical)`
11. **FDL Viewer** — All GroupBox sections use icon-labeled headers (`.headline`), field labels bumped from `.caption2` to `.caption`
12. **Chart Generator** — All 7 config panel sections upgraded to icon-labeled GroupBoxes
13. **FDL Library** — Template detail panel switched from fixed-width `paramRow` to `Grid` layout to prevent field clipping. Empty states standardized: `.quaternary` icons, `.title3` headings, `.callout` descriptions
14. **All empty states** standardized across the app per Apple HIG patterns

#### Library Canvas Templates Fixes
15. **Info panel not updating on selection** — Root cause: nested `ObservableObject` (`canvasTemplateViewModel` inside `AppState`) changes didn't propagate. Fixed with `wireUpNestedObservables()` in `AppState` that forwards `objectWillChange` via Combine from `canvasTemplateViewModel` and `libraryViewModel`
16. **State not persisting across navigation** — `selectedSection` was `@State` in `LibraryView` (reset on view recreation). Moved to `AppState.librarySelectedSection` as `@Published`

#### Other Changes from Prior Session (also in this commit)
17. **Viewer state persistence** — `ViewerViewModel` held by `AppState` as `@ObservedObject` to survive tool switching
18. **Output HUD** — Shows before/after values for transformed dimensions (Effective, Framing, Protection) and output-only for Canvas
19. **`context_creator` in output FDL** — Set to "FDL Tool v1.0 - {defaultCreator}" in output documents
20. **Template menu UX** — "Custom" renamed to "New Blank Template", dropdown label changed to fixed "Load Template" with template name shown in header
21. **Layers toggle bar** — Moved from toolbar dropdown to bottom of viewer, enlarged for usability, includes reference image toggle
22. **Output reference image** — Clipped to output canvas dimensions
23. **App permissions** — Mitigated recurring Desktop TCC prompts by avoiding `NSOpenPanel` with Desktop initial directory

**Build validated:** App bundle at `~/Applications/FDL Tool.app`. Build requires `required_permissions: ["all"]` in sandboxed environments.

### Known areas for future work:
- **Library Canvas Templates**: preview panel could be further refined for parity with FDL Viewer controls (zoom, all layer toggles)
- **Sidebar collapse**: previously reported icons disappearing. Reverted to standard `NavigationSplitView`. User may revisit
- **CineD scraping**: `CineDSyncService` has unused variables (`manufacturerPattern`, `linkRegex`). HTML parsing may need maintenance as site structure changes
- **Manufacturer data sources**: ARRI AFDC, RED crop-factor tool, Sony/Canon calculators were explored but deemed too complex to scrape dynamically — data was manually bundled instead. Consider periodic manual refresh of `cameras.json`
- **Comparison tab**: reference image rendering may need additional testing with various source/template combinations
- **Framing Charts**: user should verify 2.0x anamorphic squeeze dimensions recalculate correctly
- **Testing coverage**: only `CameraDBStoreTests` exist for Swift. Consider adding ViewerViewModel template application tests

### Previous session: 2026-03-01 (commit 71b6c90)
- Fixed JSON key ordering with `FDLJSONSerializer`
- Fixed `fitAspectIntoWorkingArea` desqueezed aspect logic
- Added Combine auto-recalculation for Chart Generator
- Full 10-step ASC FDL template application pipeline
- Reference image rendering, pinch-to-zoom, Library template editing
- `Text(verbatim:)` for all dimension displays (no locale commas)

### Key file locations:
- Template application algorithm: `ViewerViewModel.swift` → `applyTemplateLocally()`
- JSON serializer: `FDLDocument.swift` → `FDLJSONSerializer`
- Framing calculation: `ChartGeneratorViewModel.swift` → `fitAspectIntoWorkingArea()`
- Combine recalculation: `ChartGeneratorViewModel.swift` → `setupRecalculationSubscribers()`
- Camera data enrichment: `CameraDBStore.swift` → `enrichFromExisting()`
- CineD sync: `CineDSyncService.swift`
- Nested observable forwarding: `AppState.swift` → `wireUpNestedObservables()`
- Source badge component: `CameraDatabaseView.swift` → `SourceBadge`
- Bundled camera data: `resources/camera_db/cameras.json`
- Reference C++ implementation: `/Users/dhall/Documents/GitHub/ascmitc/fdl/native/core/src/`
- Test scenarios: `/Users/dhall/Downloads/scenario_resources_20260215/`
- Reference FDL spec documentation: https://ascmitc.github.io/fdl/dev/FDL_Apply_Template_Logic/

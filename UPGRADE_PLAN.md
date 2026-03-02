# FDL Tool Major Upgrade Plan

## Context
The FDL Tool has all 7 original phases complete but has significant gaps vs the ASC reference implementation: no ASC `fdl` library integration (all Python handlers use raw JSON dicts), only framing decision rendering (missing canvas/effective/protection layers), no framing decision positioning controls in the chart generator, broken FDL file import, and a static camera database with no sync. This upgrade addresses all of these.

## Reference Implementation
- Documentation: https://ascmitc.github.io/fdl/dev/fdl_viewer/
- Source: https://github.com/ascmitc/fdl/tree/dev
- Camera DB API: https://camdb.matchmovemachine.com/docs

## 5 Work Streams — Executed Sequentially

---

### WS1: Integrate ASC `fdl` Library into Python Backend
**Goal:** Replace all hand-rolled FDL dict construction, parsing, validation, and geometry computation with the official `fdl` library. Foundation for WS2-WS4.

**Files to modify:**
- `python_backend/pyproject.toml` — move `fdl` from optional to core dependency
- NEW: `python_backend/fdl_backend/utils/fdl_convert.py` — bridge utils (`dict_to_fdl`, `fdl_to_dict`, `rect_to_dict`, `fdl_from_path`)
- `python_backend/fdl_backend/handlers/fdl_ops.py` — rewrite `create()` using `fdl.FDL()`, `add_context()`, `add_canvas()`, `add_framing_decision()`; rewrite `validate()` using `fdl.read_from_string()` + `validate()`; rewrite `parse()` using library I/O
- `python_backend/fdl_backend/handlers/template_ops.py` — add new `apply_fdl_template()` using `CanvasTemplate.apply()` returning `TemplateResult` with `scale_factor`, `content_translation`, `scaled_bounding_box`; keep existing pipeline system for backward compat
- `python_backend/fdl_backend/handlers/chart_gen.py` — rewrite `generate_fdl()` using fdl library objects with anchor positioning (`fd.adjust_anchor_point(canvas, h_align, v_align)`) and protection support
- `python_backend/fdl_backend/handlers/image_ops.py` — use `dict_to_fdl()` then `canvas.get_rect()`, `canvas.get_effective_rect()`, `fd.get_rect()`, `fd.get_protection_rect()` for geometry
- `python_backend/fdl_backend/handlers/clip_id.py` — rewrite `generate_fdl()` with fdl library
- NEW: `python_backend/fdl_backend/handlers/geometry_ops.py` — `compute_rects(fdl_data)` returns all geometry rects, `apply_alignment(canvas_dims, framing_dims, h_align, v_align)` computes anchor, `compute_protection(framing_dims, protection_percent)` computes protection rect
- `python_backend/fdl_backend/server.py` — register `geometry.*` handlers
- Update all tests + NEW: `test_geometry_ops.py`

**Key fdl library API to use:**
- `fdl.read_from_string()` / `fdl.write_to_string()` / `fdl.read_from_file()`
- `fdl.FDL()`, `.add_context()`, `.add_canvas()`, `.add_framing_decision()`
- `canvas.get_rect()`, `canvas.get_effective_rect()`, `fd.get_rect()`, `fd.get_protection_rect()`
- `fd.adjust_anchor_point(canvas, h_align, v_align)`, `fd.set_protection()`
- `CanvasTemplate.apply(source_canvas, source_framing, new_canvas_id, new_fd_name) -> TemplateResult`
- `DimensionsInt`, `DimensionsFloat`, `PointFloat`, `Rect`
- `FitMethod`, `HAlign`, `VAlign`, `RoundStrategy`

**Implementation details for fdl_convert.py:**
```python
"""Conversion utilities between fdl library objects and JSON-RPC dicts."""
import json
import fdl

def dict_to_fdl(data: dict) -> fdl.FDL:
    json_str = json.dumps(data)
    return fdl.read_from_string(json_str)

def fdl_to_dict(fdl_obj: fdl.FDL) -> dict:
    json_str = fdl.write_to_string(fdl_obj)
    return json.loads(json_str)

def fdl_from_path(path: str) -> fdl.FDL:
    return fdl.read_from_file(path)

def rect_to_dict(rect) -> dict:
    return {"x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height}
```

**Implementation details for geometry_ops.py:**
```python
"""Geometry computation handlers using the fdl library."""
import fdl
from fdl_backend.utils.fdl_convert import dict_to_fdl, rect_to_dict

def compute_rects(params: dict) -> dict:
    """Compute all geometry rects for a given FDL context/canvas."""
    fdl_obj = dict_to_fdl(params["fdl_data"])
    ctx = fdl_obj.contexts[params.get("context_index", 0)]
    canvas = ctx.canvases[params.get("canvas_index", 0)]
    result = {
        "canvas_rect": rect_to_dict(canvas.get_rect()),
        "effective_rect": rect_to_dict(canvas.get_effective_rect()) if canvas.get_effective_rect() else None,
        "framing_decisions": [],
    }
    for fd in canvas.framing_decisions:
        fd_info = {
            "label": fd.label or "",
            "framing_intent": fd.framing_intent_id or "",
            "rect": rect_to_dict(fd.get_rect()),
            "protection_rect": rect_to_dict(fd.get_protection_rect()) if fd.get_protection_rect() else None,
            "anchor_point": {"x": fd.anchor_point.x, "y": fd.anchor_point.y} if fd.anchor_point else None,
        }
        result["framing_decisions"].append(fd_info)
    return result

def apply_alignment(params: dict) -> dict:
    """Compute anchor from alignment method using fdl library."""
    doc = fdl.FDL(fdl_creator="FDL Tool")
    ctx = doc.add_context(label="temp")
    canvas = ctx.add_canvas(id="temp", label="temp",
        dimensions=fdl.DimensionsInt(int(params["canvas_width"]), int(params["canvas_height"])))
    fd = canvas.add_framing_decision(id="temp", label="temp",
        dimensions=fdl.DimensionsFloat(params["framing_width"], params["framing_height"]))
    fd.adjust_anchor_point(canvas, params.get("h_align", "center"), params.get("v_align", "center"))
    return {"anchor_point": {"x": fd.anchor_point.x, "y": fd.anchor_point.y}}

def compute_protection(params: dict) -> dict:
    """Compute protection rect from framing dims + percentage."""
    fw, fh = params["framing_width"], params["framing_height"]
    pct = params.get("protection_percent", 0.9)
    ax, ay = params.get("anchor_x", 0), params.get("anchor_y", 0)
    pw, ph = fw * pct, fh * pct
    px, py = ax + (fw - pw) / 2, ay + (fh - ph) / 2
    return {"protection_rect": {"x": px, "y": py, "width": pw, "height": ph}}
```

**Implementation details for rewritten fdl_ops.py (create):**
```python
import fdl as fdl_lib
from fdl_backend.utils.fdl_convert import fdl_to_dict

def create(params: dict) -> dict:
    header = params.get("header", {})
    doc = fdl_lib.FDL(
        uuid=header.get("uuid"),
        fdl_creator=header.get("fdl_creator", "FDL Tool"),
    )
    for ctx_def in params.get("contexts", []):
        ctx = doc.add_context(label=ctx_def.get("label", ""))
        for canvas_def in ctx_def.get("canvases", []):
            dims = canvas_def.get("dimensions", {"width": 0, "height": 0})
            canvas = ctx.add_canvas(
                id=canvas_def.get("canvas_uuid"), label=canvas_def.get("label", ""),
                source_canvas_id=canvas_def.get("source_canvas_id"),
                dimensions=fdl_lib.DimensionsInt(int(dims["width"]), int(dims["height"])),
                anamorphic_squeeze=canvas_def.get("anamorphic_squeeze", 1.0),
            )
            if "effective_dimensions" in canvas_def:
                ed = canvas_def["effective_dimensions"]
                canvas.effective_dimensions = fdl_lib.DimensionsFloat(ed["width"], ed["height"])
            for fd_def in canvas_def.get("framing_decisions", []):
                fd_dims = fd_def.get("dimensions", {"width": 0, "height": 0})
                fd = canvas.add_framing_decision(
                    id=fd_def.get("fd_uuid"), label=fd_def.get("label", ""),
                    framing_intent_id=fd_def.get("framing_intent"),
                    dimensions=fdl_lib.DimensionsFloat(fd_dims["width"], fd_dims["height"]),
                )
                if "anchor" in fd_def:
                    fd.anchor_point = fdl_lib.PointFloat(fd_def["anchor"]["x"], fd_def["anchor"]["y"])
                if "protection_dimensions" in fd_def:
                    pd = fd_def["protection_dimensions"]
                    fd.protection_dimensions = fdl_lib.DimensionsFloat(pd["width"], pd["height"])
    return {"fdl": fdl_to_dict(doc)}
```

---

### WS2: Fix FDL File Import
**Goal:** Fix Cmd+O, add file picker to import sheet, register .fdl UTType.

**Root causes identified:**
1. `FDLToolApp.swift` line 32-34: "Open FDL File..." only switches to viewer tool, never opens file dialog
2. No UTType declared for .fdl files
3. `ViewerViewModel.openFile()` only accepts `UTType.json`, not .fdl
4. `FDLImportSheet` only has text paste and manual entry — no file picker
5. No `onOpenURL` handler for file association

**Files to modify:**
- NEW: `FDLTool/Sources/FDLTool/Models/UTType+FDL.swift` — `UTType.fdl` extension (conforming to `.json`)
- `FDLTool/Sources/FDLTool/App/FDLToolApp.swift` — update "Open FDL File..." command to trigger file dialog, add `.fileImporter()` to ContentView accepting `.json` and `.fdl`, add `.onOpenURL` handler
- `FDLTool/Sources/FDLTool/App/AppState.swift` — add `@Published var pendingOpenURL: URL?`, `@Published var showOpenFDLPanel: Bool = false`
- `FDLTool/Sources/FDLTool/Viewer/ViewerViewModel.swift` — update `openFile()` to accept `[.json, .fdl]` content types
- `FDLTool/Sources/FDLTool/Viewer/ViewerView.swift` — observe `appState.pendingOpenURL` and auto-load
- `FDLTool/Sources/FDLTool/Library/FDLImportSheet.swift` — add "Choose File..." button with `.fileImporter()` that reads file contents into `importJSONText`

---

### WS3: Multi-Layer Geometry Rendering in Viewer
**Goal:** Render canvas, effective, protection, and framing layers with dimension labels, crosshairs, anchor indicators, and grid. Add layer visibility toggles.

**Files to modify:**
- NEW: `FDLTool/Sources/FDLTool/Models/ComputedGeometry.swift` — models for geometry RPC response:
```swift
struct ComputedGeometry: Codable {
    let canvasRect: GeometryRect
    let effectiveRect: GeometryRect?
    let framingDecisions: [ComputedFramingDecision]
}
struct GeometryRect: Codable {
    let x: Double, y: Double, width: Double, height: Double
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
struct ComputedFramingDecision: Codable {
    let label: String
    let framingIntent: String
    let rect: GeometryRect
    let protectionRect: GeometryRect?
    let anchorPoint: FDLPoint?
}
```
- `FDLTool/Sources/FDLTool/Viewer/ViewerViewModel.swift` — add layer visibility toggles (`showCanvasLayer`, `showEffectiveLayer`, `showProtectionLayer`, `showFramingLayer`, `showDimensionLabels`, `showAnchorPoints`, `showGridOverlay`, `gridSpacing`), add `@Published var computedGeometry: ComputedGeometry?`, add `computeGeometry(pythonBridge:)` method calling `geometry.compute_rects`
- `FDLTool/Sources/FDLTool/Viewer/FramelineOverlayView.swift` — rewrite for multi-layer rendering:
  - Canvas boundary (gray, 1px solid)
  - Effective area (teal, 1.5px solid)
  - Per-framing-decision: protection (orange, dashed), framing (colored, 2px solid), crosshair at center
  - Dimension labels (width x height annotations)
  - Anchor point indicators (small markers)
  - Grid overlay (thin lines at configurable spacing)
  - All layers independently toggleable
  - Keep existing app color aesthetic (do NOT match reference implementation colors)
- `FDLTool/Sources/FDLTool/Viewer/ViewerView.swift` — add layer toggle Menu in toolbar, call `computeGeometry()` after document load, pass all new props to `FramelineOverlayView`
- `python_backend/fdl_backend/handlers/image_ops.py` — update `load_and_overlay()` to draw all geometry layers using fdl library, add dashed rect and crosshair drawing helpers

---

### WS4: Chart Generator Enhancements
**Goal:** Add framing decision positioning (anchor/alignment), protection dimensions, effective dimensions, anamorphic squeeze, crosshair, grid, squeeze circle, layer visibility.

**Files to modify:**
- `FDLTool/Sources/FDLTool/ChartGenerator/ChartGeneratorViewModel.swift`:
  - Extend `Frameline` struct: add `hAlign` (Left/Center/Right enum), `vAlign` (Top/Center/Bottom enum), `anchorX: Double?`, `anchorY: Double?`, `protectionWidth: Double?`, `protectionHeight: Double?`, `protectionAnchorX: Double?`, `protectionAnchorY: Double?`, `framingIntent: String`
  - Add canvas-level: `canvasEffectiveWidth/Height`, `canvasEffectiveAnchorX/Y`, `anamorphicSqueeze`
  - Add layer visibility toggles (same set as viewer + `showCrosshairs`, `showSqueezeCircle`)
  - Add metadata: `metadataShowName`, `metadataDOP`, `metadataOverlayShow`
  - Update `chartParams()` and `fdlParams()` to include new fields
- `FDLTool/Sources/FDLTool/ChartGenerator/ChartConfigPanel.swift`:
  - Per-frameline: add `DisclosureGroup("Anchor")` with HAlign/VAlign segmented pickers + manual X/Y fields
  - Per-frameline: add `DisclosureGroup("Protection")` with width/height fields
  - Canvas-level: add `DisclosureGroup("Effective Dimensions")` with width/height/anchor fields
  - Canvas-level: add anamorphic squeeze picker (1.0x/1.3x/1.5x/2.0x segmented)
  - Add `GroupBox("Layers")` with toggles
- `FDLTool/Sources/FDLTool/ChartGenerator/ChartCanvasView.swift` — update native preview: canvas boundary, effective area, grid, protection (dashed via `StrokeStyle(dash:)`), framing with crosshair, squeeze reference ellipse, dimension labels
- `python_backend/fdl_backend/handlers/chart_gen.py`:
  - `generate_svg()` / `generate_png()`: accept `layers` dict, `anamorphic_squeeze`, `effective_*`, `metadata_*` params; render all layers; add crosshair, grid, squeeze circle, dashed protection
  - `generate_fdl()`: already rewritten in WS1

---

### WS5: Camera Database — matchmovemachine.com API Integration
**Goal:** Sync camera data from the open-source matchmovemachine.com API. Add search-by-resolution.

**API:** `https://camdb.matchmovemachine.com`
- `GET /cameras/` — list cameras (filter: `make`, `cam_name`, `cam_type`)
- `GET /cameras/{cam_id}/sensors/` — sensors for a camera (`sensor_width`/`sensor_height` mm, `res_width`/`res_height` px, `mode_name`, `format_aspect`)
- `GET /sensors/search/` — search by resolution (`res_width`, `res_height`, `search_o`, `search_w`, `search_h`, `search_x2`, `search_x4`, `camera_name`)

**Data models from API:**
- Camera: `id` (int), `make` (string), `name` (string), `cam_type` (string)
- Sensor: `id` (int), `cam_id` (int), `sensor_width` (float, mm), `sensor_height` (float, mm), `res_width` (int, px), `res_height` (int, px), `mode_name` (string), `format_aspect` (string)

**Files to modify:**
- NEW: `FDLTool/Sources/FDLTool/Services/CameraDBSyncService.swift` — `CameraDBSyncService` class with:
  - `syncAll(cameraDBStore:)` — fetch all cameras + sensors, map to `CameraSpec`/`RecordingMode`
  - `searchByResolution(width:height:)` — use `/sensors/search/` endpoint
  - API response models (`APICamera`, `APISensor`, `APICameraWithSensors`, `APISensorMatch`)
  - Mapping from API models to existing `CameraSpec`/`RecordingMode` models
- `FDLTool/Sources/FDLTool/App/AppState.swift` — add `let cameraDBSyncService = CameraDBSyncService()`
- `FDLTool/Sources/FDLTool/CameraDB/CameraDatabaseView.swift` — add sync button with progress, add resolution search mode
- `FDLTool/Sources/FDLTool/App/FDLToolApp.swift` (SettingsView) — add sync controls in "Camera Database" section
- Keep bundled `cameras.json` as offline fallback

---

## Verification Plan

1. **WS1**: `cd python_backend && pip install -e ".[dev]" && python3 -m pytest tests/ -v` — all existing + new geometry tests pass
2. **WS2**: `cd FDLTool && swift build` — compiles; manually open a sample FDL via Cmd+O (both .fdl and .json), verify file picker in import sheet works
3. **WS3**: Load a sample FDL with effective/protection dimensions in viewer, verify all 4 geometry layers render with toggles working
4. **WS4**: In chart generator, add framelines with different alignments, verify anchor positioning, add protection, enable crosshair/grid/squeeze, export SVG
5. **WS5**: Click sync button in Camera Database view, verify cameras populate from API, test resolution search

Sample FDL files with all geometry types: `resources/sample_fdls/` (verify these exist or create test fixtures)

## Implementation Order
WS1 → WS2 → WS3 → WS4 → WS5 (WS1 is foundation; WS2 is quick win; WS3 builds on WS1; WS4 builds on WS1+WS3 patterns; WS5 is independent)

## Important Notes
- Do NOT match the reference implementation's color scheme — keep aesthetically consistent with our app's design philosophy
- The ASC `fdl` library is essential — use it for ALL geometry, scaling math, and FDL operations to ensure consistency with the reference implementation
- The `fdl` Python package wraps a C core library (`libfdl_core`) via CFFI — install via `pip install fdl`
- Default python on this machine is 3.14; pip deps are installed for 3.11. Use `/opt/homebrew/bin/python3.11` or `python3 -m pytest` from the venv

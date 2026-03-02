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

### Python Conventions
- Handlers in `fdl_backend/handlers/` — one module per domain
- Each handler function takes a dict of params, returns a dict result
- Server dispatches methods like `fdl.validate` → `fdl_ops.validate(params)`

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

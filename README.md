# FDL Tool

A macOS native multi-tool utility for working with **ASC Framing Decision Lists (FDL)** — the emerging standard for communicating framing intent across the production pipeline.

FDL Tool combines framing chart generation, FDL library management, visual validation, and batch clip processing into a single cohesive application.

## Features

### FDL Library (Tool 1)
- Create and manage projects containing FDL documents
- Import FDLs from JSON files or create them via manual entry forms
- Tag, search, and organize FDLs across projects
- View FDL document structure as an interactive tree (Header → Contexts → Canvases → Framing Decisions)
- Validate FDLs against the ASC spec with detailed error/warning reports
- Export individual FDLs or entire projects as ZIP archives

### Canvas Templates
- Create, import, and manage canvas transformation templates
- Pipeline editor with normalize, scale, round, offset, and crop steps
- Preview template application step-by-step against any FDL document
- Assign templates to projects as deliverable specifications

### Framing Chart Generator (Tool 2)
- Select from 14 bundled cinema cameras or enter custom sensor specs
- Choose recording modes with real-time resolution and aspect ratio display
- Add framing intents from 7 common presets (2.39:1, 1.85:1, 16:9, etc.) or custom dimensions
- Live chart preview with native SwiftUI rendering and Python SVG generation
- Export as SVG, PNG (72/150/300 DPI), or ASC FDL JSON
- Save generated FDLs directly to library projects

### FDL Viewer & Validator (Tool 3)
- Open FDL files from disk or the library
- Hierarchical tree view of the complete FDL document structure
- Real-time validation with error/warning severity levels and field paths
- Load reference images and see frameline overlays rendered in real-time
- Dual renderer: native SwiftUI overlay (interactive) or Python-generated overlay (pixel-accurate)
- Export overlay images as PNG
- Drag-and-drop support for both FDL files and images

### Clip ID Parser (Tool 4)
- Scan directories (optionally recursive) for video files using ffprobe
- Display clip metadata table: filename, resolution, codec, frame rate, duration
- Select or paste an FDL template to apply framing decisions to all clips
- Batch-generate per-clip FDL documents
- Validate generated FDL canvas dimensions against actual clip resolution
- Export all generated FDLs or save them to a library project

### Camera Database
- 14 professional cinema cameras with full sensor specifications
- ARRI (ALEXA 35, Mini LF, Mini), RED (V-RAPTOR [X], DSMC3), Sony (VENICE 2, BURANO, FR7), Canon (C500 II, C400, C300 III), Blackmagic (URSA Cine, Mini Pro 12K), Panavision (DXL2)
- Recording modes with active photosites, physical image area, max FPS, codec options
- Sensor visualization showing recording mode areas proportionally
- Searchable by manufacturer, model, and sensor name
- Reusable camera picker component available across all tools

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  SwiftUI App (macOS 14+)                                     │
│  ┌─────────────┐ ┌──────────┐ ┌────────┐ ┌───────┐ ┌──────┐│
│  │ FDL Library  │ │  Chart   │ │ Viewer │ │ClipID │ │CamDB ││
│  │ + Templates  │ │Generator │ │        │ │       │ │      ││
│  └──────┬───────┘ └─────┬────┘ └───┬────┘ └───┬───┘ └──┬───┘│
│         │               │          │           │        │    │
│  ┌──────┴───────────────┴──────────┴───────────┴────────┴──┐ │
│  │  Services: PythonBridge │ LibraryStore │ CameraDBStore  │ │
│  └──────────────┬──────────────────────────────────────────┘ │
└─────────────────┼────────────────────────────────────────────┘
                  │ JSON-RPC 2.0 (stdin/stdout)
┌─────────────────┼────────────────────────────────────────────┐
│  Python Backend  │                                            │
│  ┌───────────────┴──────────────────────────────────────────┐│
│  │  fdl_backend/server.py (JSON-RPC dispatcher)             ││
│  │  ├── handlers/fdl_ops.py     (create/validate/parse)     ││
│  │  ├── handlers/template_ops.py (validate/apply/preview)   ││
│  │  ├── handlers/chart_gen.py   (SVG/PNG/FDL generation)    ││
│  │  ├── handlers/clip_id.py     (probe/batch/validate)      ││
│  │  └── handlers/image_ops.py   (overlay/info)              ││
│  └──────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘
```

| Layer | Technology | Purpose |
|-------|-----------|---------|
| UI | SwiftUI (macOS 14+) | Native sidebar navigation, MVVM |
| Backend | Python 3.10+ | ASC FDL operations, image processing |
| IPC | JSON-RPC 2.0 | stdin/stdout communication |
| Storage | SQLite | Project/FDL/template metadata |
| Files | .fdl.json | ASC FDL documents on disk |
| Camera DB | JSON | Bundled camera specifications |
| Media probe | ffprobe | Video file metadata extraction |
| Charts | svgwrite + Pillow | SVG/PNG chart rendering |

## Prerequisites

- **macOS 14.0+** (Sonoma or later)
- **Xcode 15+** / Swift 5.9+ toolchain
- **Python 3.10+**
- **ffmpeg/ffprobe** (for Clip ID tool)

## Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/davids-fdl-tool.git
cd davids-fdl-tool

# Run the setup script (checks dependencies, installs Python packages)
./scripts/setup.sh

# Build the Swift app
cd FDLTool && swift build

# Run the app
swift run FDLTool
```

### Manual Setup

```bash
# Install Python dependencies
cd python_backend
pip3 install -e ".[dev]"

# Install ffmpeg (if not already installed)
brew install ffmpeg

# Build and run
cd ../FDLTool
swift build
swift run FDLTool
```

## Testing

```bash
# Swift tests (from FDLTool/)
cd FDLTool && swift test

# Python tests (from python_backend/)
cd python_backend && pytest tests/ -v
```

## Project Structure

```
davids-fdl-tool/
├── FDLTool/                        # Swift Package (macOS app)
│   ├── Package.swift
│   ├── Sources/FDLTool/
│   │   ├── App/                    # App entry, global state, settings
│   │   ├── Navigation/             # Sidebar, tool routing
│   │   ├── Library/                # FDL Library (projects, entries, import/export)
│   │   ├── CanvasTemplates/        # Canvas template management
│   │   ├── ChartGenerator/         # Framing chart generation
│   │   ├── Viewer/                 # FDL viewer, tree, validation, image overlay
│   │   ├── ClipID/                 # Clip ID batch processing
│   │   ├── CameraDB/              # Camera database browser and picker
│   │   ├── Models/                 # Swift data models (FDL, Project, Camera, etc.)
│   │   ├── Services/              # PythonBridge, LibraryStore, CameraDBStore, FFProbe
│   │   └── Shared/                # Reusable UI components
│   └── Tests/FDLToolTests/
├── python_backend/                 # Python backend service
│   ├── fdl_backend/
│   │   ├── server.py              # JSON-RPC stdin/stdout server
│   │   ├── handlers/              # Request handlers (fdl, template, chart, clip, image)
│   │   ├── camera_db/             # Camera database models and sync
│   │   └── utils/                 # ffprobe wrapper, SVG renderer
│   └── tests/
├── resources/
│   ├── camera_db/cameras.json     # 14 cinema cameras with full specs
│   ├── fdl_schemas/               # ASC FDL JSON schemas (v2.0, v2.0.1)
│   └── sample_fdls/               # Example FDL documents
├── scripts/
│   ├── setup.sh                   # Development environment setup
│   └── bundle_python.sh           # Package Python for distribution
├── CLAUDE.md                      # AI assistant conventions
└── README.md
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+1 | FDL Library |
| Cmd+2 | Framing Charts |
| Cmd+3 | FDL Viewer |
| Cmd+4 | Clip ID |
| Cmd+5 | Camera Database |
| Cmd+Shift+N | New Project |
| Cmd+I | Import FDL |
| Cmd+O | Open FDL File |

## Data Storage

FDL Tool stores its data in `~/Library/Application Support/FDLTool/`:

```
~/Library/Application Support/FDLTool/
├── fdltool.db                     # SQLite database (projects, entries, templates)
├── projects/
│   └── {project-id}/
│       └── {entry-id}.fdl.json    # FDL document files
└── templates/
    └── {template-id}.json         # Canvas template files
```

## Python Backend Protocol

The Swift app communicates with the Python backend via JSON-RPC 2.0 over stdin/stdout:

```json
// Request
{"jsonrpc": "2.0", "id": 1, "method": "fdl.validate", "params": {"path": "/path/to/file.fdl.json"}}

// Response
{"jsonrpc": "2.0", "id": 1, "result": {"valid": true, "errors": [], "warnings": []}}
```

Available methods: `fdl.create`, `fdl.validate`, `fdl.parse`, `fdl.export_json`, `template.validate`, `template.apply`, `template.preview`, `template.export`, `chart.generate_svg`, `chart.generate_png`, `chart.generate_fdl`, `image.load_and_overlay`, `image.get_info`, `clip.probe`, `clip.batch_probe`, `clip.generate_fdl`, `clip.validate_canvas`

## ASC FDL Reference

This tool implements the [ASC Framing Decision List](https://github.com/ascmitc/fdl) specification (v2.0.1). The FDL standard provides a structured way to communicate framing intent — the relationship between the camera sensor, recorded canvas, and deliverable aspect ratios — across the entire production pipeline.

## License

See [LICENSE](LICENSE) for details.

# FDL Tool Implementation Backlog

This backlog translates the current roadmap into concrete, buildable work items with acceptance criteria.

## Phase 1 - Stability and Reference Correctness (complete)

### Epic 1: Single authoritative template application path
- [x] Make template application backend-first via `template.apply_fdl`.
- [x] Keep local Swift apply as explicit fallback for offline/error scenarios.
- [x] Add lightweight fallback telemetry (debug/log + non-intrusive warning only; no persistent badge).
- [x] Add regression tests that compare output against ASC reference scenarios.

Acceptance criteria:
- [x] Viewer applies templates through Python ASC library path by default.
- [x] On backend failure, fallback succeeds and emits a visible non-fatal warning.
- [x] Output JSON is valid FDL and remains deterministic in formatting.

### Epic 2: Credential and security hardening
- [x] Migrate CineD password storage from `UserDefaults` to macOS Keychain.
- [x] Add one-time migration path for existing installs.
- [x] Remove plaintext credential remnants from existing support files and docs.
- [x] Add a small diagnostics section in Settings (credential status only; no password reveal).

Acceptance criteria:
- No CineD password persists in `UserDefaults`.
- Existing users keep working without re-entering credentials.

### Epic 3: Core validation harness
- [x] Add Swift tests for Viewer output metadata (`context_creator`, HUD dimensions).
- [x] Add Python tests for `template.apply_fdl` request/response schema.
- [x] Add fixture-based parity tests from ASC scenario examples.

Acceptance criteria:
- [x] CI executes deterministic template parity tests against known fixtures.
- [x] Failing parity blocks merges.

## Phase 2 - Project Graph Library Model

### Epic 4: Project-connected asset graph
- [x] Add tables: `project_assets`, `asset_links`, `project_camera_modes`.
- [x] Define typed assets: `fdl`, `chart`, `template`, `camera_mode`, `reference_image`.
- [x] Add link semantics: `derived_from`, `uses_template`, `shot_with`, `input_of`.
- [x] Add migration + backfill from existing library entries.

Acceptance criteria:
- A Project can store many interlinked artifacts and resolve dependencies quickly.
- Existing projects migrate without data loss.

### Epic 5: Cross-tool integration workflow
- [x] "Save to Project" from Viewer output with provenance links.
- [x] "Open in Viewer" from Chart Generator and Library preserves selections.
- [x] Camera mode assignment from Camera DB into Project scope.

Acceptance criteria:
- User can round-trip Camera DB -> Chart -> Viewer -> Library with preserved links.

## Phase 3 - Production Framing Chart Exports

### Epic 6: Professional chart rendering pipeline
- [x] Introduce `ChartScene` canonical render model in backend.
- [x] Support styles, labels, markers, logos, and burn-in metadata (multiple framelines deferred).
- [x] Add high-fidelity exports: SVG/PDF/PNG/TIFF with automatic optimal DPI.
- [x] Add clip-safe text/line sizing rules and print-safe margins.

Acceptance criteria:
- Charts are publication-ready and consistent across output formats.
- Rendering matches ASC logic for framing geometry and squeeze handling.

### Epic 7: Viewer scenario templates and workflow ergonomics
- [x] Add scenario Canvas Template presets in Viewer/Library (Dailies, On-set, VFX, Editorial).
- [x] Map each scenario preset to explicit template logic defaults (fit source/method, alignment, rounding, max dims, preserve rules).
- [x] Add "apply preset template" flow in Viewer so Source FDL + selected framing decision can be transformed with one click.
- [x] Add chart preview controls parity where needed (zoom/pan/layers), but keep scenario presets out of Chart Generator.

Acceptance criteria:
- User can start from a Source FDL and quickly apply scenario-appropriate template logic in Viewer.
- Presets are transparent/editable and produce deterministic output JSON.

### Epic 8: Batch scenario chart/report export
- [x] Add batch action in Viewer/Library: select one Source framing decision and one-or-more templates.
- [x] Generate a chart set package containing source chart + per-template result charts + output FDL JSON artifacts.
- [x] Persist package assets + provenance links in Project graph (`derived_from`, `uses_template`, `input_of`).
- [x] Add export target options (folder + zip) with predictable naming conventions.

Acceptance criteria:
- A single operation can produce a scenario pack across selected templates.
- Output artifacts are traceable back to source FDL, framing decision, and template IDs.

## Phase 4 - Native Manufacturer Frameline Interop

### Epic 9: ARRI and Sony conversion integration
- [x] Add backend handlers wrapping ARRI/Sony converter libraries with portable discovery:
  - installed Python package
  - bundled `python_backend/vendor/*` modules
  - optional env-var override paths
- [x] Add conversions:
  - FDL -> ARRI XML
  - ARRI XML -> FDL
  - FDL -> Sony XML
  - Sony XML -> FDL
- [x] Preserve metadata mappings and emit conversion warnings where lossy.

Acceptance criteria:
- [x] Users can import/export supported XML formats from UI.
- [x] Round-trip tests quantify any non-lossless fields.

### Epic 10: UI integration and validation
- [x] Add import/export options in Viewer and Library detail panes.
- [x] Add per-format validation summary and field mapping report.
- [x] Add fixture suite support for ARRI/Sony XML samples (repo fixture path + optional local override).
- [x] Add conversion report export (`.json`) and save report artifacts into Project graph with provenance links.

Acceptance criteria:
- [x] Conversion is discoverable, validated, and test-covered.

## Current Sprint Focus

- [x] Phase 4 polish: conversion report UX (readability, sorting, and copy/export ergonomics).
- [x] Expand interop tests with additional ARRI/Sony fixtures and expected lossy-field assertions.
- [x] Add report assets visibility in Library project graph UI (typed grouping + link drill-down).

Sprint status: complete.

## Next Sprint - UI/UX Assessment and Refinement

### Goal
Evaluate usability, performance, and visual polish across Viewer, Library, Chart Generator, and Camera DB; convert findings into prioritized implementation tasks.
`ClipID` is intentionally out-of-scope for this sprint and will be revisited in a follow-up sprint once requirements are clarified.

### Initial workstream
- [x] Run UI/UX audit for interaction clarity (navigation, hierarchy, affordances, empty/error states).
- [x] Run performance audit for heavy screens (Viewer overlays, Library preview, chart rendering controls).
- [x] Run visual design audit for consistency (spacing, typography, control density, contrast, modern macOS feel).
- [x] Produce prioritized remediation list with severity, scope, and acceptance criteria.

### Prioritized remediation list (Sprint N+1)
1. **High** - Unify report interactions into a reusable compact component with disclosure-based detail expansion.
   - Scope: Viewer + Library details report sections.
   - Acceptance: Reduced vertical clutter, actionable controls always visible, heavy detail collapsed by default.
2. **High** - Add report asset visibility and link drill-down in Library project graph header.
   - Scope: Project graph summary + report-specific disclosure.
   - Acceptance: User can immediately discover report artifacts and provenance links.
3. **Medium** - Improve top action ergonomics in Chart Generator (prominence + compact controls + status context).
   - Scope: Chart toolbar action row.
   - Acceptance: Primary path is obvious; controls are visually consistent and compact.
4. **Medium** - Continue consistency pass on control sizes/button styles across Camera DB/Viewer/Library.
   - Scope: Remaining mixed control densities and spacing irregularities.
   - Acceptance: Uniform small-control patterns for dense tool UIs without readability regressions.

### Execution status (current pass)
- [x] Implemented reusable `FramelineReportCard` and replaced duplicated report UI blocks.
- [x] Added report disclosure sections and compact status pills to improve readability and reduce visual noise.
- [x] Added Library Project Graph report visibility + link drill-down.
- [x] Applied cross-screen control consistency baseline (`.controlSize(.small)` and bordered button styling) across Viewer/Library/Camera DB dense action rows.
- [x] Reduced Viewer details JSON render overhead via collapsed disclosure panels for Source/Output JSON.
- [x] Introduced shared UI style tokens/extensions (`UIStyle`) and adopted them in key section headers/controls.
- [x] Cleaned non-blocking build warnings in `CineDSyncService` (unused regex variables).
- [x] Aligned Camera detail section header hierarchy with shared style tokens for cleaner visual rhythm.

### Deferred follow-up
- [ ] Revisit `ClipID` product scope, UX flows, and acceptance criteria in a dedicated post-sprint planning pass.

### UI/UX Sprint Closeout Checklist
- [x] Viewer: reduce heavy Details rendering cost (JSON panes collapsed by default).
- [x] Viewer + Library: interop report UI consolidated into reusable card.
- [x] Viewer + Library: report actions standardized (copy/export/save).
- [x] Library: Project Graph surfaces report asset counts and provenance links.
- [x] Camera DB: dense control/button consistency pass applied.
- [x] Chart Generator: action row hierarchy and control density improved.
- [x] Shared style tokens introduced and adopted in touched screens.
- [x] Known non-blocking build warnings addressed in touched areas.
- [ ] Manual UX review in running app (navigation, readability, spacing, interaction flow).

## Carry-over To Next Session (hold merge to main)

Status: PR is open, but merge is intentionally blocked pending these fixes.

Compatibility note:
- `template.apply_fdl` now includes a deterministic ASC-parity guard so behavior stays stable across different installed `fdl` library versions. Native library output is used only when geometry matches the spec-aligned deterministic path; otherwise backend falls back to deterministic output for consistent CI and user results.

- [ ] Chart Generator export interactions still not working reliably.
  - Added stronger export payload error surfacing in `ChartGeneratorViewModel`; still needs manual reliability verification in-app.
- [x] Logo overlay should follow the same anisotropic squeeze/de-squeeze deformation behavior as Siemens stars/canvas when anamorphic > 1.0.
- [ ] Dimension and anchor label positioning still needs refinement.
  - Improved protection/framing anchor pinning and edge placement; continue tuning to avoid collisions in dense layouts.
- [ ] Protection label visibility bug at small percentages (e.g., 5%).
  - In `ChartCanvasView`, protection dimension/anchor labels can still clip or disappear in narrow bands despite placement guards.
  - Next pass should use deterministic center-based placement with explicit measured text frames and guaranteed in-bounds rendering (preview and export parity).
- [ ] Canvas dimensions label visibility regression.
  - In Chart Preview, the `Canvas: WxH` label is currently not rendering and should always appear when dimension labels are enabled.
  - Restore visibility and verify placement remains inside canvas bounds across zoom levels.
- [x] Chart Preview default theme should be `White` (not `Dark`).
- [x] Remove `Squeeze Circle` and `Center Marker` from Layers options.
- [x] Add boundary arrows for dimension regions similar to reference chart example.
- [x] In Chart Preview White theme, replace inset stroked boundary boxes with exact-pixel region shading for canvas/effective/protection/framing areas (reference chart style).


## Conformance Plan v1 - Priority Tickets (Workspace + Charts + Library)

### P0 - Math/Logic Parity (Highest)

- [ ] Workspace: Template application parity against ASC reference scenarios.
  - Acceptance: For prioritized scenario set, output dimensions/anchors/protection/effective fields match reference expectations.
- [ ] Workspace: Squeeze/de-squeeze and alignment parity validation.
  - Acceptance: Scenario comparisons show no P0 mismatches in squeeze-driven geometry outcomes.
- [ ] Charts: Framing-from-intent math parity (fit, protection, framing hierarchy).
  - Acceptance: Generated framing/protection dimensions and anchors align with ASC scenario expectations for equivalent inputs.
- [ ] Charts: Renderer parity vs `asc-fdl-frameline-generator` for prioritized scenarios.
  - Acceptance: For prioritized chart scenarios, rendered geometry/layer semantics match reference renderer expectations (frameline, protection, effective, canvas behavior).
  - Progress: Added prioritized charts parity scaffold at `python_backend/tests/test_chart_renderer_parity.py` (spherical/anamorphic/top-aligned source cases) and CI step to execute with `RUN_ASC_CHARTS_PARITY=1` against ASC resources. Added explicit extension-layer preservation checks (Siemens stars, boundary arrows, and white/gray print-boundary styling) plus layer-toggle semantics checks proving extension toggles do not alter core framing/protection geometry.
- [ ] Cross-oracle parity harness in CI (primary native reference, secondary Python, NPM cross-check).
  - Acceptance: CI publishes conformance report and blocks merges on new P0 mismatches.
  - Progress: Added initial ASC scenario parity test scaffold at `python_backend/tests/test_workspace_template_conformance.py` (auto-discovers scenario/template/source/result files via local ASC repo path and validates output geometry fields).
  - Progress: Expanded ASC scenario conformance discovery and now exercising 82 scenario/source/result pairs; added structured report generator (`python_backend/tests/generate_workspace_conformance_report.py`) and iterative remediation passes. Current strict report summary: 41 evaluated cases, 41 passing, 0 failing (no tolerance masking).

### P1 - Export Reliability

- [ ] Charts: Fix single-format export reliability for TIFF/PNG/PDF/SVG/FDL (.fdl).
  - Acceptance: Each single export either writes a valid file or displays explicit error feedback.
  - Deferred validation checkpoint: Re-run manual formatting verification for SVG visual parity versus TIFF and `.fdl` key ordering (`width` before `height`) before merge/release sign-off.
  - Progress: Added backend acceptance tests at `python_backend/tests/test_chart_export_reliability.py` validating deterministic file creation/signatures for SVG/PNG/TIFF/PDF plus FDL structure generation and `.fdl` JSON roundtrip file verification. Added explicit CI gate step `Run chart export reliability acceptance tests` (Python 3.12).
  - Progress: Hardened single-export cancellation telemetry (`single_export_cancelled`) and no-format-selected handling to ensure deterministic user-facing failure text instead of silent return paths.
  - Progress: Added focused manual validation checklist at `docs/EXPORT_VALIDATION_RUNBOOK.md` for single/multi/cancel export verification and request-id based diagnostics triage.
- [ ] Charts: Fix multi-format export reliability including FDL (.fdl).
  - Acceptance: Multi-export writes all selected formats or reports per-format failures explicitly.
  - Progress: Hardened Chart Generator multi-export failure path to report deterministic partial-progress status (`Completed X/Y`, failed format, reason) instead of generic silent failure.
- [ ] Workspace: Validate/export parity for output FDL and related artifacts.
  - Acceptance: Workspace export outputs match expected content and format naming conventions.
- [ ] Export telemetry hardening.
  - Acceptance: Export traces include request start/end, payload validation, write outcome, and surfaced error path.
  - Progress: Added structured export telemetry events with per-request IDs in `ChartGeneratorViewModel` for multi-export start/item-complete/item-failed/complete paths.
  - Progress: Added frontend->backend request-id propagation for chart export RPC calls and backend JSON-RPC trace logging (`rpc_request_received`/`rpc_request_succeeded`/`rpc_request_failed`) in `python_backend/fdl_backend/server.py` to enable end-to-end export correlation.

### P2 - Save-to-Library Reliability

- [ ] Charts -> Library: Save generated outputs to project graph with stable links.
  - Progress: Added `LibraryStore` reliability tests in `FDLTool/Tests/FDLToolTests/LibraryStoreTests.swift` covering persisted `.fdl` file creation, project-asset graph insertion (`asset_type = fdl`), and tag persistence for saved chart outputs.
  - Progress: Added delete-path cleanup for chart-saved FDL entries in `LibraryStore.deleteFDLEntry` to remove stale graph assets/links, plus test coverage (`testDeleteFDLEntryRemovesFileAndGraphAsset`).
  - Progress: `ChartGeneratorViewModel.saveToLibrary(...)` now persists a companion `chart` project asset and links the saved FDL asset to that chart asset via `derived_from`; covered by `ChartGeneratorSaveToLibraryTests`.
  - Progress: Added manual verification steps in `docs/LIBRARY_VALIDATION_RUNBOOK.md` (Test A).
  - Acceptance: Saved items appear in expected project, reopen successfully, and preserve provenance links.
- [ ] Workspace -> Library: Save transformed outputs with template/source relationships.
  - Progress: Hardened `ViewerViewModel.saveOutputToProject(...)` to persist `derived_from` links back to source FDL assets when source/output are in the same project, while still skipping invalid cross-project derived links.
  - Progress: Added `FDLTool/Tests/FDLToolTests/ViewerSaveOutputToProjectTests.swift` coverage for same-project (`uses_template` + `derived_from`) and cross-project safety behavior.
  - Progress: Added manual verification steps in `docs/LIBRARY_VALIDATION_RUNBOOK.md` (Test B/C).
  - Acceptance: Library records maintain correct source/template linkage and metadata.
- [ ] Library preview/state consistency for saved artifacts.
  - Progress: Hardened `LibraryViewModel` state reconciliation so `loadEntries()` now clears stale selection/detail state when an entry disappears and refreshes selected entry snapshots when still present; added stale-async-result guards in `loadAndValidateEntry`.
  - Progress: Added `FDLTool/Tests/FDLToolTests/LibraryViewModelTests.swift` coverage for stale-selection clearing and valid-selection retention across entry reloads.
  - Progress: Added manual verification steps in `docs/LIBRARY_VALIDATION_RUNBOOK.md` (Test D).
  - Acceptance: Selecting saved assets updates preview/details deterministically without stale state.

### P1/P2 - UI Issues Coupled to Correctness

- [ ] Charts: Protection labels remain visible/in-bounds for small protection percentages.
  - Acceptance: Protection dimension/anchor labels remain readable and inside valid bounds in edge cases (including 5%).
- [ ] Charts: Canvas dimensions label always visible when dimension labels are enabled.
  - Acceptance: Canvas label renders consistently across zoom levels and does not clip.
- [ ] Charts/Workspace: Export UI clarity and action feedback.
  - Acceptance: Export selection model is unambiguous and completion/failure feedback is explicit.
  - Progress: Added `Copy Diagnostics` action in Chart Generator toolbar to copy a support-ready export diagnostics bundle (latest statuses + export trace tail + backend trace tail) to clipboard.
- [ ] Library: Save/open interaction feedback and selection stability.
  - Acceptance: User receives clear success/failure state and current selection remains predictable after operations.
  - Progress: Added explicit success feedback alerts for Chart export completion and Chart save-to-library completion in `ChartGeneratorView`/`ChartGeneratorViewModel`.
  - Progress: Added focused save/open feedback + selection stability checks in `docs/LIBRARY_VALIDATION_RUNBOOK.md`.

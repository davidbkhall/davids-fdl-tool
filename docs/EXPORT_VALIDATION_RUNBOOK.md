# Export Validation Runbook (P1 Core)

Use this runbook to verify Chart Generator export reliability in-app and quickly capture actionable diagnostics when something fails.

## Scope

This validates P1 export reliability for:
- single-format export
- multi-format export
- cancel behavior
- deterministic user feedback and traceability

## Before You Start

1. Build and launch the app.
2. Open `Framing Chart Generator`.
3. Create/load a chart with at least one framing decision.
4. Keep a writable test folder ready (for example `~/Desktop/fdl-export-tests`).

## Core Manual Test Matrix

### Test A - Single TIFF export

1. Click `Export`.
2. Select only `TIFF`.
3. Click `Export`, choose a destination, then `Save`.

Expected:
- Success feedback appears (`Export complete...`).
- TIFF file exists at chosen destination.

### Test B - Single SVG export (backend path)

1. Click `Export`.
2. Select only `SVG`.
3. Click `Export`, choose destination, `Save`.

Expected:
- Success feedback appears.
- SVG file exists at chosen destination.
- Diagnostics include backend RPC trace for `chart.generate_svg`.

### Test C - Multi-format export (TIFF + PNG + PDF + FDL)

1. Click `Export`.
2. Select `TIFF`, `PNG`, `PDF`, and `FDL`.
3. Click `Export`, choose destination folder.

Expected:
- Success feedback appears with format count.
- All selected files exist in target folder.
- Multi-export trace events are present (`multi_export_started`, `multi_export_item_complete`, `multi_export_complete`).

### Test D - Cancel behavior

1. Click `Export`.
2. Select one format (for example TIFF).
3. Click `Export`.
4. In save panel, click `Cancel`.

Expected:
- No crash, no hang.
- No file created.
- Trace contains `single_export_cancelled` event.

### Test E - Multi-export partial failure smoke check (optional)

Use this if you can reproduce a specific failing format in your environment.

Expected:
- Error feedback includes partial progress (`Completed X/Y...`).
- Trace contains `multi_export_item_failed` with `format`, `reason`, `completed`, `total`.

## Capturing Diagnostics

If any test fails:

1. Click `Copy Diagnostics` in Chart Generator toolbar.
2. Paste into ticket/chat.

The copied bundle includes:
- timestamp
- latest error/status
- tail of `export_trace.log` (frontend events)
- tail of `backend_trace.log` (Python stderr/trace events)

## What “Good” Looks Like in Trace

For successful multi-export:
- `multi_export_started`
- one or more `multi_export_item_complete`
- `multi_export_complete`

For cancelled single export:
- `single_export_started`
- `single_export_cancelled`

For backend-routed calls (for example SVG/XML):
- frontend events: `backend_call_started` and `backend_call_complete` (or `backend_call_failed`)
- backend events: `rpc_request_received` then `rpc_request_succeeded` (or `rpc_request_failed`)

## Log Locations (local)

- `~/Library/Application Support/FDLTool/export_trace.log`
- `~/Library/Application Support/FDLTool/backend_trace.log`

## Triage Notes

When a failure is reported, prioritize in this order:
1. Did the save panel complete or get cancelled?
2. Is there a matching frontend `request_id` event?
3. Is there matching backend RPC activity for the same `request_id`?
4. Did write succeed after response (`file exists` + size > 0)?

If (2) exists but (3) is missing, suspect frontend-to-backend handoff.
If (3) failed with explicit reason, fix backend/handler path.
If both succeeded but file missing, focus on destination access/write path.

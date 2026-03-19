# Library Save/Open Validation Runbook

This runbook verifies P2 Save-to-Library reliability for Charts, Workspace, and Library preview state.

## Session Handoff - 2026-03-19

Current status:
- Library UI/project graph pass is in active manual validation.
- Chart title editing controls are now present in both:
  - Framing Chart Generator (`Auto` off supports manual naming), and
  - FDL Library (`Edit Title` in details pane + chart row context menu).
- Camera format project management safeguards are active:
  - format removal is blocked when linked charts still reference it,
  - chart deletion prompts optional orphaned-format cleanup.

Important launch note for manual validation:
- Debug executable launched directly from terminal/Cursor can capture keyboard focus in host terminal/editor.
- For reliable text-input validation, launch using wrapper app:
  - `open -na "~/Applications/FDLTool-Dev.app"`

Next checkpoint to continue:
- Resume remaining runbook checkpoints from current validation session using wrapper-launched app instance.

## Preconditions

- Build succeeds (`cd FDLTool && swift build`).
- App launches with Python bridge running.
- At least one Library project exists.

## Test A - Charts -> Library save creates stable graph links

1. Open **Framing Charts**.
2. Configure any valid chart and click **Save to Library**.
3. Select a project and save.
4. Open **FDL Library** for that project.
5. Confirm a new FDL entry exists and opens.
6. In the project graph, confirm:
   - an `fdl` asset exists for the saved file
   - a companion `chart` asset exists
   - a `derived_from` link connects the FDL asset to the chart asset

Expected result:
- Save shows success feedback.
- FDL reopens correctly from Library.
- Provenance links are present and stable after reload.

## Test B - Workspace -> Library output keeps template/source relationships

1. Open **Framing Workspace**.
2. Load a Source FDL from Library project **P**.
3. Apply a template and use **Save Output to Project** into project **P**.
4. Open **FDL Library** project **P**.
5. Confirm output entry opens.
6. In project graph, confirm:
   - `uses_template` link from output FDL to template asset
   - `derived_from` link from output FDL to source FDL (same project)

Expected result:
- Output save produces both template and source relationships.

## Test C - Workspace cross-project safety (no invalid derived link)

1. Load Source FDL from project **A** in Workspace.
2. Save transformed output to project **B**.
3. Open Library project **B** graph.

Expected result:
- Output FDL saves successfully.
- `uses_template` link exists.
- No invalid cross-project `derived_from` link to project **A** assets is created.

## Test D - Library preview/state consistency after mutations

1. In Library, select an FDL entry and verify preview/details are visible.
2. Delete that selected entry.
3. Confirm selection/preview clears immediately (no stale detail content).
4. Select another existing entry and verify preview/details update deterministically.
5. Switch projects and return to confirm stable state.

Expected result:
- No stale selection or stale preview data after delete/reload.
- Entry changes always refresh details to the currently selected item.

## Diagnostics to capture on failure

- Screenshot of failing panel.
- Project name + entry name.
- Expected vs actual link/type behavior.
- `Copy Diagnostics` output from Charts when save/export path is involved.

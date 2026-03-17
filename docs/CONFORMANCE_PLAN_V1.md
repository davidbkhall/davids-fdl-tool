# Conformance Plan v1

This plan defines a concrete, oracle-first path to bring `FDL Tool` into measurable conformance with the ASC FDL reference implementation while improving workflow reliability and UI behavior in the highest-impact areas.

## Scope

- In scope:
  - Framing Workspace
  - Framing Charts
  - FDL Library where required for project-linked save/open/export workflows
- Out of scope for v1:
  - Clip ID

## Priority Order

1. Math/logic parity
2. Export reliability
3. Save-to-Library reliability

## Source of Truth Hierarchy

1. Primary oracle:
   - ASC FDL native C reference implementation and official scenario resources
2. Secondary oracle:
   - Official `asc-fdl` Python package
3. Cross-check oracle:
   - Official `@asc-mitc/fdl` NPM package

Reference URLs:
- https://github.com/ascmitc/fdl
- https://ascmitc.github.io/fdl/
- https://pypi.org/org/asc-mitc/
- https://www.npmjs.com/package/@asc-mitc/fdl

## Conformance Goals

- Produce `FDL (.fdl)` outputs that are valid, deterministic, and behaviorally aligned to ASC reference outcomes.
- Ensure template and geometry math in Workspace and Charts matches official logic (squeeze, alignment, preserve rules, rounding order).
- Ensure Framing Charts renderer behavior is validated against `asc-fdl-frameline-generator` for geometry and layer semantics.
- Ensure export/save flows are observable, deterministic, and fail loudly (no silent no-op outcomes).
- Ensure Library interconnection preserves provenance and project relationships across workflows.

## Phased Approach

### Phase 0 - Reliability Baseline (Execution Safety)

Focus:
- Make export and save operations deterministic and visible.
- Remove silent failure modes.

Work items:
- Normalize export trigger lifecycle in Charts and Workspace.
- Add mandatory UI error surfacing for every failure path.
- Add trace logging for request/response, write attempts, and final status.
- Add save-to-library confirmation and failure details.

Acceptance criteria:
- Every export attempt ends in either file output or explicit user-visible error.
- Every save-to-library action ends in either persisted entry or explicit user-visible error.
- No silent stalls in single or multi-format exports.

### Phase 1 - Conformance Harness v1 (Measurement Layer)

Focus:
- Build repeatable parity measurement against ASC reference resources.

Work items:
- Create scenario runner using ASC scenario datasets from official resources.
- Define normalized comparison for:
  - canvas/effective/protection/framing dimensions
  - anchor points
  - output canvas and framing decisions after transforms
  - `FDL (.fdl)` structure validity and deterministic serialization
  - chart renderer geometry parity (frameline/protection/effective/canvas boundaries)
- Add mismatch classifier tags:
  - rounding
  - alignment
  - squeeze/desqueeze
  - preserve rules
  - hierarchy propagation
  - serialization/formatting
  - renderer-parity
- Produce machine-readable and human-readable reports.

Acceptance criteria:
- CI produces scenario-level pass/fail report on every run.
- Every mismatch includes field path and category.
- No unclassified mismatches.

### Phase 2 - Math/Logic + Renderer Parity Remediation

Focus:
- Resolve P0/P1 conformance mismatches in core logic.

Work items:
- Template application stage-by-stage parity pass.
- Squeeze/desqueeze and alignment parity pass.
- Rounding rule parity pass (order + strategy + target fields).
- Protection/effective/framing hierarchy parity pass.
- Framing Charts renderer parity pass against `asc-fdl-frameline-generator` output behavior (geometry and layer semantics).

Acceptance criteria:
- No unresolved P0 math/logic mismatches in harness report.
- All prioritized ASC scenarios pass for Workspace and Charts logic outputs.
- Renderer parity checks pass for prioritized chart scenarios.

### Phase 3 - Interconnection and Workflow Parity

Focus:
- Ensure Workspace, Charts, and Library interactions preserve correctness and provenance.

Work items:
- Round-trip coverage:
  - Charts -> Workspace
  - Workspace -> Library
  - Library -> Workspace/Charts
- Verify project graph links for saved outputs, templates, and camera-mode context.
- Validate state persistence and reproducibility after reopen/reload.

Acceptance criteria:
- Round-trip scenarios preserve expected values and links.
- Re-opened artifacts reproduce expected math and output structures.

### Phase 4 - UI/UX Parity Remediation

Focus:
- Address UI issues that hide, distort, or reduce trust in correctness.

Work items:
- Workspace overlay readability and placement fixes.
- Charts label/overlay visibility and declutter fixes.
- Export panel clarity and consistency improvements.
- Library preview and save feedback consistency.

Acceptance criteria:
- P0/P1 UI issues resolved with no regressions in conformance harness.
- UI reflects underlying computed state accurately in all core workflows.

## Validation Matrix v1

For each scenario:
- Input set:
  - source FDL
  - template/configuration
  - chart/workspace relevant settings
- Execute against:
  - FDL Tool
  - primary ASC reference expectation
  - secondary Python oracle
  - NPM cross-check oracle
- Compare:
  - geometric outputs
  - logical outputs
  - serialized outputs (`.fdl`)
  - chart renderer outputs/metadata for parity scenarios
- Record:
  - pass/fail
  - mismatch category
  - ticket reference (if fail)

Acceptance criteria:
- All scenarios produce complete comparison records.
- Failing scenarios are linked to active backlog tickets.

## CI Integration v1

- Add required conformance stage that publishes report artifacts.
- Fail CI on new P0/P1 mismatches.
- Run secondary oracle checks against pinned + latest package versions to detect drift early.

Acceptance criteria:
- Conformance report is generated in CI for every PR.
- PR cannot merge if it introduces new P0/P1 conformance regressions.

## Initial Exit Criteria for v1

- Reliability baseline achieved for export and save-to-library on Workspace/Charts workflows.
- Renderer parity baseline established against `asc-fdl-frameline-generator`.
- Conformance harness live in CI with actionable mismatch reporting.
- P0 backlog items completed or explicitly waived with rationale.

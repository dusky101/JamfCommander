# Policy Overhaul — Live Status & Checklist

> **This is a living document.** It tracks every deliverable for the Policy Editing & Bulk-Clone
> overhaul and is updated as work progresses, so anyone can see at a glance where we are.
> The implementation brief is `docs/POLICY_OVERHAUL_PROMPT.md`.

## How to keep this file current (read me)

- **Update at the end of every phase — and every sub-phase.** If a phase is split (e.g. 2.1, 2.2),
  update this file at 2.1 *and* again at 2.2, and so on.
- Tick items by changing `- [ ]` to `- [x]`. Use `- [~]` for "in progress / partially done".
- **Add new items** here whenever scope grows during the work (put genuinely new scope under
  "Added during the overhaul"). Never silently drop a planned item — strike it through and note why.
- Update **Current status** at the top of "Progress" and append a dated line to the **Progress log**.
- Keep wording British English, consistent with the rest of the repo.

Status legend: `- [ ]` not started · `- [~]` in progress · `- [x]` done.

## Decisions locked in

- **Edit scope:** Both — edit existing policies in place **and** configure during cloning.
- **Self Service icons:** Both — upload a local image **and** reuse an icon already in Jamf.
- **Custom-trigger token:** derived from the policy/app name, slugified (lower-case, spaces → hyphens,
  unsafe characters stripped), with a live per-row preview and per-row override.
- **XML for new policies** is built from explicit elements; regex transforms are kept only for *fetched*
  payloads.
- **Raw JSON** view is retained as read-only ("Advanced"); no JSON editing required for the new fields.

## Progress

**Current status:** Phase 2 complete (code) — single-policy Frequency + Triggers form editor
(`PolicyEditorView`) wired into the inspector with Settings/Advanced(JSON) tabs; save is confirmed and
reports a real per-item result. macOS build passes; live verification awaiting manual test on a
non-production tenant. Awaiting review before Phase 3.
**Last updated:** 2026-06-07.

### Phase 1 — Models + read/write API (little/no UI)
- [x] `PolicyFrequency` enum (Jamf values + British labels, `Sendable`)
- [x] `PolicyTriggers` (six event booleans + `customTrigger`/`trigger_other`, `Sendable`)
- [x] `SelfServiceSettings` (fields incl. categories + icon reference, `Sendable`)
- [x] Policy detail decode reads these from `JSSResource/policies/id/{id}`
- [x] `JamfAPIService+PolicyEditing.swift`: `fetchPolicyEditable(id:)`
- [x] `updatePolicyGeneral(id:frequency:triggers:)` (escaped XML PUT)
- [x] `updatePolicySelfService(id:settings:)` (escaped XML PUT)
- [~] Builds (✓) + existing list/inspector unaffected (additive only, ✓); live read round-trip on a
  real policy pending manual test on a non-production tenant

### Phase 2 — Single-policy form editor: Frequency + Triggers
- [x] Form editor (`PolicyEditorView`, embedded in the inspector's Settings tab)
- [x] Execution Frequency `Picker` (native macOS popup — `.wheel` is unavailable on macOS)
- [x] Triggers toggle selector (six standard) + optional custom-trigger field
- [x] Save → confirm → `updatePolicyGeneral` → results → refresh
- [x] Raw JSON kept as Advanced (read-only) tab
- [~] Verified: change frequency + add custom trigger, confirmed in Jamf — pending manual test on a
  non-production tenant

### Phase 3 — Single-policy Self Service editor + icons
- [ ] SS fields: enable, display name, install/reinstall button text, description, force view, feature on main page
- [ ] SS categories (reuse `CategorySelectionSheet`; `display_in`/`feature_in`)
- [ ] Show current icon
- [ ] Icon: upload local image (`NSOpenPanel` → multipart) — *spike the endpoint/privileges first*
- [ ] Icon: pick an existing Jamf icon
- [ ] Save → confirm → `updatePolicySelfService` (+ icon assignment) → results
- [ ] Verified in Jamf (fields + uploaded icon + reused icon)

### Phase 4 — Multi-select bulk clone with naming + custom-trigger templates
- [ ] "Clone Selected (N)" action wired into the policies multi-selection
- [ ] `BulkCloneSheet`: target category
- [ ] Naming template (prefix/suffix + `{originalName}`) with live per-row preview
- [ ] Custom-trigger template (`install-{appName}`) slugified + per-row preview/override + blank allowed
- [ ] Carry over safety options (clones disabled by default; optional strip scope/triggers/frequency/SS)
- [ ] Apply chosen frequency/triggers/custom trigger/SS to each new clone
- [ ] `JamfAPIService+Cloning` batch clone — rate-limited, per-item results, single confirmation
- [ ] Verified: 3 policies → 3 disabled, correctly named clones with the right `install-…` triggers

### Phase 5 — Bulk in-place settings editor
- [ ] Bulk set frequency for selected policies
- [ ] Bulk add/set a templated custom trigger for selected policies
- [ ] Bulk set/sync Self Service settings/category (build on `setPolicySelfServiceCategory`)
- [ ] Reuse Phase 2/3 writes + Phase 4 batch plumbing + confirmation + results
- [ ] Verified in Jamf

### Phase 6 — Visual polish & Liquid Glass design pass
> A dedicated design pass over **all** the new policy-overhaul UI, to make it look polished and native
> rather than merely functional. Can run as a final pass or be folded into each phase as surfaces are
> built. Added after review (see "Added during the overhaul").
- [ ] Replace the plain `InfoSection`/default-control layout in the editor with the Liquid Glass helpers
  (`liquidGlassRect`, `liquidGlassCapsule`) and a consistent card/section treatment
- [ ] Fix layout & alignment: full-width, left-aligned trigger rows (leading icon + label, trailing
  switch), aligned frequency control, consistent spacing/padding
- [ ] Stronger typography hierarchy, semantic colours, and refined section headers
- [ ] Polish the inspector header, segmented tab control, and save/revert bar (idle / unsaved / saving)
- [ ] Polished loading / empty / saving / error states
- [ ] Apply the same treatment across every new surface (single-policy editor, Self Service editor,
  `BulkCloneSheet`, bulk in-place editor)
- [ ] Accessibility preserved (labels/hints, Dynamic Type, keyboard focus, never colour-alone); restrained
  Apple-26 treatment (no gratuitous blur/transparency/motion)
- [ ] Builds; British English throughout; no functional regressions

### Cross-cutting acceptance criteria
- [ ] No raw-JSON editing required for frequency, triggers, or Self Service
- [ ] Every write is confirmed and reports real per-item results
- [ ] Bulk operations are throttled and degrade gracefully on partial failure
- [ ] All new copy is British English; UI uses existing `SharedUI`/Liquid Glass components
- [ ] App builds at the end of every phase; nothing committed or pushed

## Added during the overhaul

_(New scope discovered while building goes here, with the date it was added.)_

- 2026-06-07 — **Decode-layer / edit-layer split.** Phase 1 keeps the snake_case, all-optional Classic
  decode types (`PolicySelfServiceXML`, `PolicySelfServiceCategoryXML`, `PolicySelfServiceIconXML`) in
  `Models/PolicyModels.swift`, and the clean, `Sendable`, UI/edit value types (`PolicyFrequency`,
  `PolicyTriggers`, `SelfServiceSettings`, `SelfServiceCategory`, `SelfServiceIcon`, `PolicyEditable`) in
  a new `Models/PolicyEditingModels.swift`. Mirrors the existing `PolicyDetailXML` (decode) vs `Policy`
  (clean) pattern.
- 2026-06-07 — **Temporary read-only inspector section.** `PoliciesInspectorView` now shows a
  "Parsed policy settings — read-only" block (Execution / Triggers / Self Service) purely to verify the
  Phase 1 read path. This is scaffolding and will be **replaced** by the real form editor in Phase 2/3.
- 2026-06-07 — **Xcode project uses file-system-synchronized groups.** New `.swift` files under
  `JamfCommander/` are compiled automatically; no `.pbxproj` edits are needed when adding files.
- 2026-06-07 — **`updatePolicySelfService` already writes the icon by id** (reuse-existing path) when an
  icon id is present, but local-image **upload** remains a Phase 3 multipart spike (not yet implemented).
- 2026-06-07 — **No wheel picker on macOS.** The brief's "rolling/wheel" frequency selector is
  implemented with the native macOS popup `Picker` (`.menu`); `WheelPickerStyle` is iOS/watchOS-only and
  would not compile. This matches Jamf's own admin-console dropdown.
- 2026-06-07 — **Inspector is now tabbed** (Settings / Advanced). The Phase 1 read-only Execution +
  Triggers blocks were replaced by the editable form; a read-only **Self Service** summary remains as a
  placeholder until the Phase 3 editor. The raw JSON view is now genuinely read-only (no `onSave`).
- 2026-06-07 — **New Phase 6 — Visual polish & Liquid Glass design pass.** The original brief scoped
  phases 1–5 as functional only, with visual quality covered solely by the cross-cutting "reuse
  SharedUI/Liquid Glass components" line. After reviewing the Phase 2 editor, a dedicated polish phase was
  requested and added to both this tracker and `POLICY_OVERHAUL_PROMPT.md`.

## Progress log

_(Append-only. One line per phase/sub-phase completion: date — phase — what changed.)_

- 2026-06-07 — Setup — Brief (`POLICY_OVERHAUL_PROMPT.md`) and this status file created; no code yet.
- 2026-06-07 — Phase 1 — Added `PolicyFrequency`/`PolicyTriggers`/`SelfServiceSettings`/`PolicyEditable`
  (+ Self Service decode types); extended `PolicyDetailXML` to decode `self_service` defensively; added
  `JamfAPIService+PolicyEditing.swift` (`fetchPolicyEditable`, `updatePolicyGeneral`,
  `updatePolicySelfService` — escaped XML PUTs); surfaced parsed settings read-only in
  `PoliciesInspectorView`. macOS build passes; live round-trip pending manual test.
- 2026-06-07 — Phase 2 — Added `PolicyEditorView` (Execution Frequency popup `Picker` + six trigger
  toggles + optional custom-trigger field; Save → `CommanderConfirmation` → `updatePolicyGeneral` →
  `OperationResultView` → inspector refresh). Reworked `PoliciesInspectorView` into Settings / Advanced
  (read-only JSON) tabs and kept a read-only Self Service summary. macOS build passes; live verification
  pending manual test.
- 2026-06-07 — Planning — Added **Phase 6 (Visual polish & Liquid Glass design pass)** to the plan after
  review of the Phase 2 editor UI; documentation only, no code yet.

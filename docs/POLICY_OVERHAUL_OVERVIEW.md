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

**Current status:** Not started — brief written, awaiting Phase 1.
**Last updated:** 2026-06-07.

### Phase 1 — Models + read/write API (little/no UI)
- [ ] `PolicyFrequency` enum (Jamf values + British labels, `Sendable`)
- [ ] `PolicyTriggers` (six event booleans + `customTrigger`/`trigger_other`, `Sendable`)
- [ ] `SelfServiceSettings` (fields incl. categories + icon reference, `Sendable`)
- [ ] Policy detail decode reads these from `JSSResource/policies/id/{id}`
- [ ] `JamfAPIService+PolicyEditing.swift`: `fetchPolicyEditable(id:)`
- [ ] `updatePolicyGeneral(id:frequency:triggers:)` (escaped XML PUT)
- [ ] `updatePolicySelfService(id:settings:)` (escaped XML PUT)
- [ ] Builds; existing list/inspector unaffected; read round-trips a real policy

### Phase 2 — Single-policy form editor: Frequency + Triggers
- [ ] Form editor (`PolicyEditorView` or extended inspector)
- [ ] Execution Frequency rolling `Picker`
- [ ] Triggers button/toggle selector (six standard) + optional custom-trigger field
- [ ] Save → confirm → `updatePolicyGeneral` → results → refresh
- [ ] Raw JSON kept as Advanced (read-only) tab
- [ ] Verified: change frequency + add custom trigger, confirmed in Jamf

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

### Cross-cutting acceptance criteria
- [ ] No raw-JSON editing required for frequency, triggers, or Self Service
- [ ] Every write is confirmed and reports real per-item results
- [ ] Bulk operations are throttled and degrade gracefully on partial failure
- [ ] All new copy is British English; UI uses existing `SharedUI`/Liquid Glass components
- [ ] App builds at the end of every phase; nothing committed or pushed

## Added during the overhaul

_(New scope discovered while building goes here, with the date it was added.)_

- _none yet_

## Progress log

_(Append-only. One line per phase/sub-phase completion: date — phase — what changed.)_

- 2026-06-07 — Setup — Brief (`POLICY_OVERHAUL_PROMPT.md`) and this status file created; no code yet.

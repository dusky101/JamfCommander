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

**Current status:** Phases 1–5 complete; **Phase 6 in progress** — a shared `AppBackground` (the home
gradient) now sits behind every sheet and the detail pane (no flat black), and the editor's centred
toggles are fixed (left-aligned, full-width rows). Remaining Phase 6 polish (typography hierarchy,
inspector header/tab/save-bar refinement, richer Liquid Glass cards, loading/empty-state polish, a
Dynamic Type/contrast pass) is still open. The action bars (single + bulk, policies + profiles) now
share one look via `SharedUI/ActionBarComponents.swift` — soft tinted icon buttons under centred
headers, a searchable blue-chip move-to-category popover, and the frosted `.appBarBackground()`.
macOS build passes; live verification awaiting manual test.
**Last updated:** 2026-06-08.

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
**Phase 3.1 — Self Service fields (done):**
- [x] SS fields: enable, display name, install/reinstall button text, description, force view, feature on main page
- [x] SS categories with `display_in`/`feature_in` (used the category *list* + an "Add Category" menu, not
  `CategorySelectionSheet` — see note in "Added during the overhaul")
- [x] Show current icon (read-only)
- [x] Save → confirm → `updatePolicySelfService` → results → refresh (fields + categories)
- [~] Verified in Jamf (fields + categories) — pending manual test on a non-production tenant

**Phase 3.2 — Icons (done):**
- [x] Spiked the upload: Jamf Pro API `POST /api/v1/icon` (multipart part `file`) → `{ id, url }`;
  preview via `GET /api/v1/icon/download/{id}`. No dedicated icon privilege is documented (a valid token
  suffices); **Update Policies** is needed to attach. Chosen over the legacy Classic `fileuploads`
  endpoint (see "Added during the overhaul").
- [x] Icon: upload local image (`NSOpenPanel` → `POST /api/v1/icon` → staged) — attached on Save
- [x] Icon: reuse an existing icon (initially by id — replaced by a searchable picker in 3.3)
- [x] Two-stage assign: upload to the icon library → write the icon id to the policy via
  `updatePolicySelfService`
- [~] Verify uploaded **and** reused icon in Jamf — pending manual test on a non-production tenant

**Phase 3.3 — Icon picker + reliable preview (done):**
- [x] Fixed the preview: resolve each icon's CDN URL via `GET /api/v1/icon/{id}` and render that (the
  `…/icon/download/{id}` endpoint was failing on the auth-redirect to the CDN)
- [x] Instant refresh after upload — the uploaded bytes are cached under the new icon id so the
  thumbnail appears immediately
- [x] `SelfServiceIconPickerView`: search policies by name/id → fetch icons from matching policies →
  de-dupe by icon id → grid picker (replaces entering an id by hand)
- [x] On-disk image cache (`IconImageCache`) keyed by icon id (immutable → never stale); the available
  icon set is fetched live per search, capped at 50 matching policies for rate limits
- [~] Verify preview, post-upload refresh, and the picker in Jamf — pending manual test

### Phase 4 — Multi-select bulk clone with naming + custom-trigger templates
- [x] "Clone Selected (N)" action wired into the policies multi-selection (`ActionPanelView`)
- [x] `BulkCloneSheet`: target category
- [x] Naming template — prefix + original + suffix (the `{originalName}` is the middle), live per-row
  preview; validates that a prefix or suffix is set so clones are uniquely named
- [x] Custom-trigger template (`install-{appName}`) slugified + per-row preview/override + blank allowed
- [x] Carry over safety options (clones disabled by default; optional strip scope/triggers/frequency/SS)
- [~] Apply chosen settings to each clone — **custom trigger + optional frequency applied**; applying
  standard event triggers and full Self Service templating to clones is **deferred** (see note)
- [x] `JamfAPIService+Cloning` batch clone (`bulkClonePolicies`) — rate-limited (batches of 5 + 0.5s),
  per-item `OperationResultView` results, single confirmation
- [~] Verified: 3 policies → 3 disabled, correctly named clones with the right `install-…` triggers —
  pending manual test on a non-production tenant

### Phase 5 — Bulk in-place settings editor
- [x] Bulk set frequency for selected policies
- [x] Bulk add/set a templated custom trigger for selected policies (per-row preview + override)
- [x] Bulk set/sync Self Service category (reuses `setPolicySelfServiceCategory`)
- [x] Bulk **remove scope** (unscope in place — added on request; uses the proven empty-scope shape)
- [x] Reuses the Phase 4 batch plumbing (throttled) + `CommanderConfirmation` + `OperationResultView`;
  general writes use a partial `<general>` PUT so untouched fields aren't clobbered
- [~] Verified in Jamf — pending manual test on a non-production tenant

### Phase 6 — Visual polish & Liquid Glass design pass
> A dedicated design pass over **all** the new policy-overhaul UI, to make it look polished and native
> rather than merely functional. Can run as a final pass or be folded into each phase as surfaces are
> built. Added after review (see "Added during the overhaul").
- [x] Shared `AppBackground` — the home gradient behind **every** sheet and the detail pane; no flat
  black anywhere (adaptive window base + the signature purple→blue wash, applied via `.appBackground()`)
- [x] Fix layout & alignment: `InfoSection` content is now left-aligned + full-width and the editor's
  trigger switches span the row (no more centred toggles)
- [x] Real Liquid Glass: `liquidGlass*` helpers now use the genuine `glassEffect` (macOS 26+), so every
  `InfoSection` card and `.liquidGlass()` surface is real glass; the editor's Triggers are interactive
  Liquid Glass **chips** (`GlassEffectContainer` + `.glassEffect(.regular.tint(.blue).interactive(), in: .capsule)`)
  instead of plain switches
- [x] Apply the shared backdrop across every new surface (inspector, single-policy editor, Self Service
  editor, icon picker, `BulkCloneSheet`, bulk in-place editor) **and** the older sheets (clone/config/
  category/deployment/configuration)
- [ ] Stronger typography hierarchy, semantic colours, and refined section headers
- [ ] Polish the inspector header, segmented tab control, and save/revert bar (idle / unsaved / saving)
- [ ] Polished loading / empty / saving / error states
- [~] Accessibility preserved (labels/hints already present; Dynamic Type/contrast pass pending);
  restrained Apple-26 treatment (no gratuitous blur/transparency/motion)
- [x] Builds; British English throughout; no functional regressions

### Cross-cutting acceptance criteria
- [x] No raw-JSON editing required for frequency, triggers, or Self Service (JSON is read-only "Advanced")
- [x] Every write is confirmed (`CommanderConfirmation`) and reports real per-item results (`OperationResultView`)
- [x] Bulk operations are throttled (batches + delays) and degrade gracefully on partial failure
- [x] All new copy is British English; UI uses existing `SharedUI`/Liquid Glass components
- [x] App builds at the end of every phase; nothing committed or pushed by the assistant

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
- 2026-06-07 — **Phase 3 split into 3.1 (fields) and 3.2 (icons).** Icon upload/reuse needs a fileuploads
  multipart spike and has API uncertainty (there is no documented "list all Self Service icons"
  endpoint), so it is isolated as 3.2 per the brief's sub-phase allowance.
- 2026-06-07 — **Self Service categories use the category list, not `CategorySelectionSheet`.** That
  sheet is themed for move/deploy and returns only a category *name*; Self Service needs the id plus
  `display_in`/`feature_in`. So `PolicySelfServiceEditorView` reuses `api.fetchCategories()` with an
  "Add Category" menu + per-row Display/Feature checkboxes. The inspector fetches the category list
  resiliently (a failure leaves an empty picker rather than blanking the inspector).
- 2026-06-07 — **Icon-upload spike result (corrected).** Initially built against the Classic
  `POST /JSSResource/fileuploads/policies/id/{id}` (multipart part `name`), but switched on review to the
  modern Jamf Pro API: **`POST /api/v1/icon`** (multipart part **`file`**) → `{ id, url }`, then attach
  the id to the policy via `updatePolicySelfService`. This decouples the icon from the policy (true
  reuse) and enables a live **preview-by-id** through `GET /api/v1/icon/download/{id}?res=…`. Per the
  OpenAPI spec the icon endpoints need only authentication (no dedicated privilege); **Update Policies**
  is required to attach. The library upload is inert, so it isn't gated by a confirmation; the policy
  `PUT` (which actually assigns the icon, alongside the SS fields) is the confirmed write.
- 2026-06-07 — **No "list all icons" endpoint**, so the icon picker (3.3) enumerates icons from the
  policies matching a name/id search instead. Reuse-by-id (3.2) was replaced by this searchable grid.
- 2026-06-07 — **Preview root cause + fix (3.3).** The first preview attempt used
  `GET /api/v1/icon/download/{id}`, which 302-redirects to the icon CDN; `URLSession` carried the bearer
  token across the redirect, breaking it (blank thumbnail, as seen on the uploaded icon). Fix: resolve
  the icon's public CDN URL via `GET /api/v1/icon/{id}` (authenticated) and download that **without**
  auth (foreign host → token withheld by the existing guard). Uploaded bytes are also cached immediately
  under the new id, so the thumbnail appears at once.
- 2026-06-07 — **Icon cache is by-id, not count-based.** Icons are immutable by id, so `IconImageCache`
  (memory + `~/Library/Caches/.../JamfCommanderIcons/{id}.img`) never goes stale; the *available* icons
  are fetched live per search, so a "count check to refresh" isn't needed. The picker caps hydration at
  50 matching policies per search to respect rate limits.
- 2026-06-07 — **Bulk-clone naming uses prefix + original + suffix** (not a free `{originalName}`
  template string), which keeps clone names unique by construction and still preserves the original name.
  The Clone button is disabled until a prefix or suffix is set. The custom trigger is applied to each
  clone via a **partial `<general>` PUT** (`trigger_other`, plus `frequency` when chosen) so the clone's
  other general fields aren't clobbered — no extra read needed.
- 2026-06-07 — **Deferred in Phase 4:** applying *standard event triggers* and *full Self Service*
  settings as bulk-clone templates. The headline acceptance (named, disabled clones with the right
  custom trigger) plus optional frequency is covered; standard-trigger templating is an unusual workflow
  and SS templating across clones is heavy. Both can be added on request (would extend `BulkCloneConfig`
  + `applyClonedGeneral` and add a sheet section).
- 2026-06-07 — **Icon preview is fetched with an auth guard.** `downloadIconData` only attaches the
  bearer token when the URL host matches the configured Jamf instance (the `api/v1/icon/download` URL is
  on the tenant host → token attached; the upload-response `url` is an icon-CDN host → token withheld).
  Sandbox file read works via the existing `ENABLE_USER_SELECTED_FILES = readwrite` build setting —
  entitlements/sandbox were **not** changed.

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
- 2026-06-07 — Phase 3.1 — Added `PolicySelfServiceEditorView` (availability, display name, install/
  reinstall button text, description, force-view, feature-on-main-page, and Self Service categories with
  Display/Feature toggles; Save → `CommanderConfirmation` → `updatePolicySelfService` →
  `OperationResultView` → refresh). Inspector now fetches the category list and embeds the editor in the
  Settings tab; current icon shown read-only and preserved on save. macOS build passes; live verification
  pending manual test. Icons (3.2) still to do.
- 2026-06-07 — Phase 3.2 — Added `JamfAPIService+Icons.swift` using the Jamf Pro API (`uploadIcon` via
  `POST /api/v1/icon`, `downloadIconData` with a same-host token guard) and upgraded the Self Service
  editor's icon section: "Upload Image…" (NSOpenPanel → upload to icon library → staged) and "Reuse
  Existing…". The icon id is attached to the policy on the confirmed Save Self Service. (Replaced an
  initial Classic `fileuploads` attempt after review.) macOS build passes.
- 2026-06-07 — Phase 3.3 — Fixed the icon preview (resolve CDN URL via `GET /api/v1/icon/{id}`, download
  without auth) and made upload cache its bytes for an instant thumbnail. Added `IconImageCache`
  (memory + disk, by icon id), `fetchIconURL`/`fetchPolicyList`/`fetchSelfServiceIcons` (throttled), and
  `SelfServiceIconPickerView` — a searchable grid picker over icons used by matching policies. macOS
  build passes; live verification pending manual test.
- 2026-06-07 — Phase 4 — Added `BulkCloneModels` (plan/config + slug & template helpers), a throttled
  `bulkClonePolicies` (+ partial-`<general>` `applyClonedGeneral`) in `+Cloning`, and `BulkCloneSheet`
  (category, prefix/suffix naming with per-row preview, `install-{appName}` custom-trigger template with
  per-row override, safety strips, optional frequency). Wired "Clone Selected (N)" in `ActionPanelView`
  (policies → `BulkCloneSheet`; profiles unchanged) with a single confirmation + per-item results. macOS
  build passes; live verification pending manual test.
- 2026-06-07 — Phase 5 — Added `BulkSettingsModels`, `updatePolicyGeneralFields` (partial `<general>`
  PUT) + throttled `bulkUpdatePolicySettings` in `+PolicyEditing` (reuses `setPolicySelfServiceCategory`
  for the SS category), and `BulkSettingsSheet` (independently-toggled frequency / templated custom
  trigger with per-row override / Self Service category). Wired "Edit Settings (N)" in `ActionPanelView`
  (policies) with a single confirmation + per-item results. Completes phases 1–5; macOS build passes;
  live verification pending manual test.
- 2026-06-07 — Phase 5 (addition) — Added a bulk **Remove scope** toggle to `BulkSettingsSheet` +
  `removePolicyScope(id:)` in `+PolicyEditing` (empty-scope PUT, same shape as `clonePolicy`'s strip),
  wired through `bulkUpdatePolicySettings` and the confirmation summary. macOS build passes.
- 2026-06-07 — Auto-refresh — Added `Services/RefreshCoordinator.swift` (debounced app-wide "data
  changed" signal). `JamfAPIService.genericRequest` (every Classic write/delete) and the clone POSTs call
  `requestRefresh()`, and the Policies/Profiles/Scripts/Packages dashboards reload on it via
  `.onChange(of: refreshCoordinator.token)`. So inspector edits, bulk actions, clones, deletes, moves,
  etc. now refresh the list automatically (a 0.6s debounce coalesces write bursts into one reload). The
  manual refresh button already worked; the `ViewBridge … NSViewBridgeErrorCanceled` console line is a
  benign macOS message (system view-controller dismissal), not a refresh failure.
- 2026-06-07 — Phase 6 (part 1) — Added `SharedUI/AppBackground.swift` (the app's single signature
  gradient) + `.appBackground()`. Refactored `ContentView` to use it and applied it behind every sheet
  (inspector, BulkClone/BulkSettings/IconPicker, OperationResultView, CloneConfig/Deployment/Category/
  Configuration) so nothing is a flat black background. Fixed the centred-toggle layout (`InfoSection`
  now left-aligned + full-width; editor trigger switches span the row). macOS build passes. Remaining
  Phase 6 polish (typography, inspector chrome, richer cards, state polish) still open.
- 2026-06-07 — Phase 6 (part 2) — Adopted **real Liquid Glass** (per the `swiftui-liquid-glass` skill +
  Apple docs): `LiquidGlassModifier` now uses `glassEffect(.regular, in:)` on macOS 26+, so every
  `InfoSection`/`.liquidGlass()` card is genuine glass. Rebuilt the editor's **Triggers** as interactive
  glass chips in a `GlassEffectContainer` (tap to toggle; accent-tinted + checkmark when on) and gave
  `FlowLayout` a `.leading` alignment option. macOS build passes.
- 2026-06-07 — Phase 6 (fix) — `glassEffect` (unlike a material `.background`) doesn't fill the hit area,
  so list rows only registered taps on their text and the right-click menu was lost. Added
  `.contentShape(Rectangle())` to `PolicyCardView`/`ProfileCardView`/`ScriptCardView`/`PackageCardView`
  to restore full-row tap + context-menu hit-testing. macOS build passes.
- 2026-06-07 — Phase 6 (single action bar) — Added `SingleActionBar` (shown when exactly one policy is
  selected). Singular wording; **"Edit Policy" opens the inspector** (the right-click → Inspect view)
  rather than the bulk sheet; Move/Match Self Service/Clone/Delete operate on the one policy (confirmed +
  results). Bulk bar (2+) renamed "Edit Settings" → **"Edit Policies"**; right-aligned the Bulk Edit
  Settings toggles. Wired for policies only for review.
- 2026-06-07 — Phase 6 (single bar refinement) — Action text moved into centred per-column **headers**;
  buttons are now compact **icon-only** tinted buttons with tooltips. **Move to Category** opens a
  `.popover` glass card with searchable Liquid Glass category chips (`GlassEffectContainer`) that
  animates from the button and dismisses on outside-click; picking a chip confirms + moves. (A full
  "morph to screen-centre and back" was deferred — a native popover gives the same interaction
  reliably.) Removed the unused `ActionTileButton`. macOS build passes.
- 2026-06-07 — Phase 6 (move popover polish) — Widened the move-to-category popover to 600pt, gave each
  category chip a capsule outline (distinct tappable areas), and made the card auto-size to the chips via
  `.onGeometryChange` (grows as categories are added, capped at 480pt then scrolls). macOS build passes.
- 2026-06-08 — Phase 6 (move chips restyle) — Category chips now use the blue selected-category look
  (blue fill/text/outline capsule) instead of the glass tint, fixing the "capsule + opaque square"
  double-layer. macOS build passes.
- 2026-06-08 — Phase 6 (Profiles single bar + bar backgrounds) — Added `SingleProfileActionBar`
  (Move/Set Scope/Edit/Clone/Delete, same look as the policies single bar) and wired
  `ProfileDashboardView` (1 profile → single bar, 2+ → `ActionPanelView`). Added an `elevated`
  `AppBackground` variant + `.appBarBackground()` (frosted gradient, blurs behind) and applied it to
  `SingleActionBar`/`SingleProfileActionBar`/`ActionPanelView`; removed the `controlBackgroundColor`
  black band behind the bars in both dashboards. macOS build passes. **Still to do:** restyle the bulk
  `ActionPanelView` buttons to the single-bar icon+header tile look (it currently has the new background
  but the original button layout).
- 2026-06-08 — Phase 6 (shared action-bar components + soft colours) — Extracted the action-bar look
  into `SharedUI/ActionBarComponents.swift`: `ActionBarColumn` (centred 2-line header + control),
  `SoftIconLabel`/`SoftIconButton` (light tinted fill + coloured glyph + outline capsule — softer than
  the previous solid `.borderedProminent`), and `CategoryMovePicker` (600pt searchable card of blue
  category chips, auto-sizing to its content). Restyled `SingleActionBar` and `SingleProfileActionBar`
  to these, sizing the profiles **Set Scope** menu identically to the other buttons via a `SoftIconLabel`
  menu (`.menuStyle(.borderlessButton)` + `.menuIndicator(.hidden)`). Restyled the bulk `ActionPanelView`
  (both `.policies` and `.profiles` modes) to match: Move-to-Category opens the blue-chip popover, and
  Match Self Service / Edit Policies / Set Scope / Clone / Delete are now soft tinted icon buttons under
  centred headers. macOS build passes. **Phase 6 remaining:** typography hierarchy, inspector
  header/tab/save-bar refinement, richer cards, loading/empty-state polish, Dynamic Type/contrast pass.
- 2026-06-08 — Phase 6 (Set Scope capsule fix) — The "Set Scope" control had lost its tinted capsule:
  a `Menu` label with `.menuStyle(.borderlessButton)` strips the `SoftIconLabel` background/foreground.
  Replaced it with a shared `ScopeActionButton` (plain button + compact popover offering "Scope to All
  Computers" / "Remove Scope"), so it renders the same green capsule as the other action buttons. Used
  in both `SingleProfileActionBar` and the bulk `ActionPanelView` (profiles mode). macOS build passes.
- 2026-06-08 — Phase 6 (Self Service icon browser) — Added a "Show all" path to the icon reuse picker.
  New `Modules/Policies/IconBrowserView.swift`: a paginated, **icons-only** browser (8×5 per page)
  modelled on the Jamf Pro "Choose Image" picker — ‹ / › page arrows with a horizontal slide (next
  enters from the right, back from the left), a page indicator, Cancel, and two-step selection (tap to
  highlight → "Make Selection"; double-click confirms). `SelfServiceIconPickerView` gained a **Show All**
  button that scans every policy for its Self Service icon (chunked, with a determinate progress bar and
  a cancellable scan — reusing the rate-limited `fetchSelfServiceIcons`), de-duplicates by icon id, and
  opens the browser. Note: there is no Jamf API to list the full icon/clip-art library without guessing
  an endpoint (invariant #2), so "all" means **all icons currently in use across policies** — which, for
  a real estate, mirrors the Jamf picker. macOS build passes. The existing search-and-pick flow is
  unchanged.

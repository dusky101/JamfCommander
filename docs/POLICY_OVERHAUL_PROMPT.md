# Implementation Prompt — Policy Editing & Bulk-Clone Overhaul

> Hand this to Claude Code in the JamfCommander repo. It is a multi-phase brief. **Work in phases,
> stop at the end of each phase, and leave the app building and manually testable before stopping**
> (see "How to work" below).
>
> **Live status lives in `docs/POLICY_OVERHAUL_OVERVIEW.md`.** That file is the running checklist and
> progress log; keep it updated as you go (see "How to work"). Read it at the start of a session to see
> what's already done.

## Context & goal

JamfCommander currently lets you clone a single policy and inspect policies as raw JSON. This overhaul
adds **form-based policy editing** (no more hand-editing JSON to change a policy) and **bulk cloning
with templated naming and custom triggers**. It is a foundation for a larger downstream project, so the
editing/clone capability should be robust and reusable.

Deliver, end to end:

1. **Multi-select bulk cloning** of policies (not just one at a time).
2. **Bulk rename on clone** via a naming template — e.g. add a word as a prefix/suffix to every selected
   clone at once (`{originalName}` token supported).
3. **Templated custom triggers on bulk clone** — e.g. `install-{appName}`; cloning a policy that installs
   Word produces the custom trigger `install-word`. The token is derived from the policy/app name,
   slugified (lower-case, spaces → hyphens, strip unsafe characters), with a **live per-row preview** and
   a **per-row override**.
4. **Per-field policy controls** (replacing the need to edit JSON), for both **existing policies (edit in
   place)** and **during cloning**:
   - **Execution Frequency** — a rolling/wheel selector (`Picker`) of the Jamf frequency values.
   - **Triggers** — a button/toggle selector for the standard event triggers, plus an **optional custom
     trigger** text field.
   - **Self Service** — fuller control of the Self Service page fields, **including adding an icon**
     (upload a local image *or* reuse an icon already in Jamf).
5. **Bulk apply** of the above settings across multiple selected existing policies.

Keep the existing raw-JSON inspector as an **"Advanced (read-only)"** view alongside the new forms.

## Guardrails (already documented — do not restate, just follow)

Follow the repo's existing instructions; they are authoritative:

- Root `CLAUDE.md` — the non-negotiable invariants.
- `.claude/rules/services-and-networking.md`, `swiftui-views.md`, `models-and-decoding.md`,
  `design-system.md`, `exports.md`.
- `docs/PROJECT_OVERVIEW.md`, `docs/JAMF_API_REFERENCE.md`, and the maintainer `JamfCommander/README.md`.

The ones that bite this feature hardest, as a reminder only:

- **These are writes to a live production Jamf tenant.** Every save/clone/bulk action is high-risk:
  gate it behind explicit confirmation (`CommanderConfirmation`), report real per-item outcomes
  (`OperationResultView`), and never fake success. Test against a **non-production** tenant first.
- **XML-escape every interpolated value** via `JamfAPIService.xmlEscape(_:)`.
- **Respect rate limits** — batch + delay + capped concurrency + bounded retry for any bulk loop.
- **British English** throughout the UI; reuse `SharedUI` components and the Liquid Glass helpers.
- **Do not commit or push.** Leave the working tree for the user to review.

## Jamf API notes (verify exact strings against the tenant before relying on them)

Classic API, `PUT /JSSResource/policies/id/{id}` with a `<policy>` XML body. Relevant elements:

- **Frequency** — `<general><frequency>`. Standard values: `Once per computer`,
  `Once per user per computer`, `Once per user`, `Once every day`, `Once every week`,
  `Once every month`, `Ongoing`.
- **Triggers** — under `<general>`: `trigger_checkin` (Recurring Check-in), `trigger_enrollment_complete`
  (Enrollment Complete), `trigger_login` (Login), `trigger_logout` (Logout),
  `trigger_network_state_changed` (Network State Change), `trigger_startup` (Startup) — all booleans —
  plus `trigger_other` (the **custom event trigger** string). These match the elements
  `JamfAPIService+Cloning` already strips.
- **Self Service** — `<self_service>`: `use_for_self_service`, `self_service_display_name`,
  `install_button_text`, `reinstall_button_text`, `self_service_description`,
  `force_users_to_view_description`, `feature_on_main_page`, `self_service_categories`
  (`category` → `id`/`name`/`display_in`/`feature_in`), and `self_service_icon` (`id`/`filename`/`uri`).
- **Icon upload (spike required)** — Classic `POST /JSSResource/fileuploads/policies/id/{id}` as
  `multipart/form-data` (image in the `name` field), then reference the resulting icon via
  `<self_service_icon><id>…</id></self_service_icon>`. Reusing an existing icon = set `<id>` only.
  Confirm the multipart shape and required Jamf privileges (Update Policies; plus whatever the
  fileuploads endpoint needs) during the spike before building the UI on top.

Architectural note: when **creating** policy XML, build it from explicit elements (clearer and safer
than regex). Keep the existing `NSRegularExpression` surgery only for transforming *fetched* payloads,
and verify any regex change against a real exported policy (per `services-and-networking.md`).

## Phases

Each phase must compile, keep existing features working, and end with manual test steps. There is **no
test target**, so "tested" = `xcodebuild -scheme JamfCommander -destination "platform=macOS" build`
succeeds + the manual checks pass against a non-production tenant.

### Phase 1 — Models + read/write API for policy settings (little/no UI)
- Add models/enums (in `Models/`): `PolicyFrequency` (the values above, with British display labels),
  `PolicyTriggers` (the six event booleans + `customTrigger`/`trigger_other`), and `SelfServiceSettings`
  (the fields above, incl. categories and an icon reference). Mark them `Sendable`; decode defensively
  where Jamf shapes vary (see `models-and-decoding.md`).
- Extend the policy detail decode so these read off `JSSResource/policies/id/{id}`.
- Add `JamfAPIService+PolicyEditing.swift` with: a read (`fetchPolicyEditable(id:)`), and writes
  `updatePolicyGeneral(id:frequency:triggers:)` and `updatePolicySelfService(id:settings:)` — explicit,
  escaped Classic XML PUTs.
- **Done when:** builds; existing policy list/inspector unaffected; the read method round-trips a real
  policy (temporarily surface the parsed values read-only to verify).

### Phase 2 — Single-policy form editor: Frequency + Triggers
- Add a form editor (extend `PoliciesInspectorView` or a new `PolicyEditorView`):
  - Execution Frequency as a rolling `Picker`.
  - Triggers as a button/toggle/segmented selector for the six standard triggers + an optional Custom
    Trigger text field (`trigger_other`).
- **Save** → confirm → `updatePolicyGeneral` → results → refresh. Keep raw JSON as an Advanced
  (read-only) tab.
- **Done when:** you can change a policy's frequency and add a custom trigger from the UI and see it in
  the Jamf console.

### Phase 3 — Single-policy Self Service editor + icons (upload OR reuse)
- Self Service fields: enable toggle, display name, install/reinstall button text, description, force
  users to view description, feature on main page, and Self Service categories (reuse the category list /
  `CategorySelectionSheet`, with `display_in`/`feature_in`).
- Icon: show the current icon; allow **uploading a local image** (`NSOpenPanel` → multipart upload) **or**
  **picking an icon already in Jamf**; assign it to the policy.
- **Save** → confirm → `updatePolicySelfService` (+ icon assignment) → results.
- **Done when:** you can edit the Self Service page fields, upload a new icon, and reuse an existing icon,
  all verified in Jamf.

### Phase 4 — Multi-select bulk clone with naming + custom-trigger templates
- Wire a **"Clone Selected (N)"** action into the policies multi-selection (`ActionPanelView` /
  `PoliciesDashboardView`).
- New `BulkCloneSheet`:
  - Target category.
  - **Naming template** — prefix/suffix word and/or `{originalName}` token, with a live per-row preview.
  - **Custom-trigger template** — e.g. `install-{appName}`; token slugified from the policy/app name,
    per-row preview + override, blank allowed.
  - Carry over the existing safety options (clones **disabled by default**; optional strip
    scope/triggers/frequency/Self Service from `CloneConfigSheet`), then **apply** the chosen
    frequency/triggers/custom trigger/Self Service from the templates to each new clone.
- Extend `JamfAPIService+Cloning` for the batch: clone each selected policy (reuse `clonePolicy`), then
  apply Phase 1 settings. **Rate-limited batches**, per-item `OperationResultView`, single confirmation.
- **Done when:** selecting 3 policies and bulk-cloning with a prefix + `install-{appName}` yields 3
  disabled clones, correctly named, each with the right `install-…` custom trigger.

### Phase 5 — Bulk in-place settings editor
- For multiple selected **existing** policies, bulk-apply: set frequency for all; add/set a templated
  custom trigger for all; set/sync Self Service settings/category for all (build on the existing
  `setPolicySelfServiceCategory`).
- Reuse Phase 2/3 write methods + Phase 4 batch plumbing + confirmation + results.
- **Done when:** selecting N policies and setting frequency + a custom trigger across all of them is
  verified in Jamf.

## Cross-cutting acceptance criteria
- No raw JSON editing required for frequency, triggers, or Self Service (JSON stays as read-only
  Advanced view).
- Every destructive/write action is confirmed and reports real per-item results.
- Bulk operations are throttled and degrade gracefully on partial failure (one failure doesn't abort the
  batch).
- All new copy is British English; UI uses existing `SharedUI`/Liquid Glass components.
- App builds at the end of every phase; nothing committed or pushed.

## How to work
- One phase at a time. At the end of each, give the phase-complete summary required by `CLAUDE.md`
  (what changed, files, how to test, checks, safe-to-commit, one-line suggested commit message) and
  **stop for review**.
- **Always update `docs/POLICY_OVERHAUL_OVERVIEW.md` as part of finishing a phase, before you stop** —
  tick the completed items (`- [ ]` → `- [x]`), set "Current status" and "Last updated", append a dated
  line to the Progress log, and add any newly-discovered scope under "Added during the overhaul". **If a
  phase is split into sub-phases (e.g. 2.1, 2.2), update the overview at the end of *each* sub-phase**
  (2.1 and again at 2.2, and so on), not just at the end of the whole phase.
- Prefer new focused files (e.g. `JamfAPIService+PolicyEditing.swift`, `PolicyEditorView`,
  `BulkCloneSheet`) over enlarging existing large views.
- If the icon-upload spike reveals the endpoint/privileges differ from the notes above, surface that and
  adjust rather than guessing.

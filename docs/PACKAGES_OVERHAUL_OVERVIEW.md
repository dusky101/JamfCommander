# Packages Overhaul — Live Status & Checklist

> **This is a living document.** It tracks every deliverable for the Packages / Installomator Manager
> overhaul and is updated as work progresses, so anyone can see at a glance where we are.
> The implementation brief is `docs/PACKAGES_OVERHAUL_PROMPT.md`.

## How to keep this file current (read me)

- **Update at the end of every phase — and every sub-phase.** If a phase is split (e.g. 4.1, 4.2),
  update this file at 4.1 *and* again at 4.2, and so on.
- Tick items by changing `- [ ]` to `- [x]`. Use `- [~]` for "in progress / partially done".
- **Add new items** here whenever scope grows during the work (put genuinely new scope under
  "Added during the overhaul"). Never silently drop a planned item — strike it through and note why.
- Update **Current status** at the top of "Progress" and append a dated line to the **Progress log**.
- Keep wording British English, consistent with the rest of the repo.

Status legend: `- [ ]` not started · `- [~]` in progress · `- [x]` done.

## Findings that shaped this plan (verified 2026-08-03)

Established during the pre-work review; the brief explains each in full. Do not re-derive these.

| # | Finding | Consequence |
|---|---------|-------------|
| F1 | `$(arch)` in a label is evaluated **on the target Mac at install time**; JamfCommander only writes the label into `parameter4`. | An arch-variant label cannot fail *creation* for that reason. 114 of 1,224 labels are arch-conditional and already work correctly per device. No "Silicon or Intel" picker. |
| F2 | `Labels.txt` has 1,225 lines but 1,224 unique labels — `omnissahorizonclient` is duplicated. | Second POST in a run returns HTTP 409. De-duplicate the label list. |
| F3 | **CONFIRMED ROOT CAUSE.** `createInstallomatorPolicyAsync` interpolates `policyName`, `label`, `categoryName` **raw** into Classic XML. Reproduced by the user 2026-08-03: a target category whose name contained `&` failed every label; renaming it to "and" fixed it. `createCategory` / `updateCategory` (`+Dashboard.swift:61`, `:67`) share the defect — and the **New Category** field inside `DeploymentConfigSheet` calls `createCategory`. | A category name with `&` is legal in Jamf, so this is an app defect, not a usage error. Route all three through `xmlEscape`; fix and verify first. |
| F4 | "Deployed" is detected only via a script whose *name* contains "installomator" plus a non-empty `parameter4`. | Hand-made or differently-named policies are invisible → the label shows Available → 409 on the duplicate name. |
| F5 | Failures surface as `error.localizedDescription`, and the raw Jamf body is `print()`ed (breaks invariant 4). | The real cause is hidden from the user — which is why this was first misdiagnosed as an architecture problem. Make failures legible; stop printing bodies. |
| F6 | `Installomator.sh` re-evaluates `key=value` arguments **after** the label `case` block (`# MARK: reading arguments again`, ~line 12732). `parameter4`–`parameter11` all exist and are modelled; 4/5/6 are in use, **7–11 are free**. | Version/variant pinning is implementable as admin-supplied overrides in `parameter7`–`parameter11`. |
| F7 | The app **cannot** compute a pinned URL — labels scrape vendor pages in shell at run time. | Pinning is admin-supplied, never app-resolved. Warn that pinned URLs go stale. |
| F8 | Per-label source is readable at `fragments/labels/<label>.sh` (verified HTTP 200, 705 bytes for `mysqlworkbenchce`). | Cheap enough to fetch on demand to *explain* variance (arch-aware / always-latest / type / team ID). |
| F9 | Ruled out by measurement: display-name collisions (**0** across 1,224 labels) and reserved entries (`version`, `longversion`, `valuesfromarguments`, `broken*` — none present). | Don't chase these. |
| F10 | Already built by the policy overhaul and to be reused: `JamfAPIService+Icons.swift`, `SelfServiceIcon`, `IconImageCache`, `SelfServiceIconPickerView`, `IconBrowserView`, and the `NSOpenPanel` upload flow in `PolicySelfServiceEditorView`. `fetchComputers()` already requests `USER_AND_LOCATION`. | Phases 2 and 3 are wiring, not new infrastructure. |

## Decisions locked in

- **Order of work:** fix creation first (Phase 1), because the failures the user is hitting are real and
  currently unexplained; the variant/version feature (Phase 4) is built on that evidence, not on a guess.
- **No architecture picker as a normal option.** Any arch override is opt-in, warned, never default (F1).
- **Version pinning is admin-supplied** `key=value` overrides written to `parameter7`–`parameter11`,
  strictly validated and XML-escaped. The app never scrapes vendor pages (F6, F7).
- **A genuine architecture split** is documented as a Jamf recipe (two policies, each scoped to an
  arch-based smart group), not built as a code feature.
- **Icons:** one icon per deploy run is the baseline — uploaded once, id reused across the batch.
  Per-label icon override is a nice-to-have only after the batch case is solid.
- **Safe defaults everywhere:** no pin, no arch override, no icon ⇒ identical behaviour to today.
- **Label-source inspection is informational only** and must degrade quietly if GitHub is unreachable.

## Progress

**Current status:** Planning complete. **The F3 escaping fix is done** — `createInstallomatorPolicyAsync`,
`createCategory` and `updateCategory` now route every interpolated value through `Self.xmlEscape(_:)`, and
a sweep found no other raw interpolation into Classic XML. macOS build green; live re-test with a `&` in a
category name still outstanding. The rest of Phase 1 (label de-duplication, legible failure messages,
dropping the raw-error-body `print()`, pre-flight duplicate check, wider deployed-policy detection) and
Phases 2–5 are not started.
**Last updated:** 2026-08-03.

### Phase 1 — Fix and harden policy creation (the actual bug)
- [ ] De-duplicate labels in `fetchInstallomatorLabelsFromGitHub()` (stable order, case-insensitive; log the drop) — F2
- [x] `xmlEscape` `policyName`, `label`, `categoryName`, Self Service display name in `createInstallomatorPolicyAsync` — F3 **(confirmed root cause — done ahead of the rest of Phase 1, 2026-08-03)**
- [x] `xmlEscape` `createCategory(name:)` and `updateCategory(id:newName:)` (`+Dashboard.swift:62`, `:68`) — the New Category field in this same sheet uses `createCategory` — F3
- [x] Sweep for any remaining raw interpolation into Classic XML — clean; every `<name>`/`<parameter*>`/Self Service text element now interpolates an escaped variable
- [ ] Remove the raw-error-body `print()`; no bodies logged anywhere — F5
- [ ] Map Jamf responses to actionable British-English messages in `PolicyCreationError` (409 duplicate, invalid category, malformed XML, 403 privileges, 401 unauthorised)
- [ ] Show the specific reason per row in `OperationResultView`
- [ ] Pre-flight duplicate-name check surfaced in the confirmation step (rename/deselect, don't collect 409s)
- [ ] Widen "already deployed" detection — match the Installomator script by **id** as well as name; flag resolved-name collisions — F4
- [ ] Decide on the 10 dead `knownOverrides` keys (prune, or retain with a comment) — state which and why
- [ ] Verified: a selection including `omnissahorizonclient`, `mysqlworkbenchce`, `python` either succeeds or reports an accurate per-item reason
- [~] Verified: deploying into a category whose name contains `&` succeeds (the exact case that failed on 2026-08-03) — macOS build green; **live re-test outstanding.** The tenant's categories have since been renamed to use "and", so reproducing needs a throwaway category named e.g. "Test & Verify" on a non-production tenant
- [~] Verified: creating a category named with `&` from the New Category field in this sheet succeeds, and renaming one from the dashboard succeeds — same outstanding live test
- [ ] **Real Jamf message recorded in the progress log** for anything still failing (drives Phase 4)

### Phase 2 — Self Service icon in the create flow
- [ ] Spike: does `POST /JSSResource/policies/id/0` accept `<self_service_icon><id>` at create time?
- [ ] Route chosen and documented (create-with-icon, or create-then-assign via `updatePolicySelfService`)
- [ ] Icon step in `DeploymentConfigSheet`: none (default) / upload local image / reuse existing Jamf icon
- [ ] Reuse `SelfServiceIconPickerView` + `IconBrowserView` as-is — F10
- [ ] Local upload via `NSOpenPanel` (`.png`/`.gif`/`.jpeg`), mirroring `PolicySelfServiceEditorView`
- [ ] Uploaded **once per run**, icon id reused for every policy in the batch
- [ ] Fallback path (if create-then-assign) stays inside the throttled loop with its own per-item result
- [ ] Chosen icon previewed in the sheet summary box
- [ ] Verified: a two-label batch shows the icon on both policies in Jamf **and** in Self Service
- [ ] Verified: "no icon" run is byte-for-byte the behaviour of today
- [ ] *(Optional)* per-label icon override

### Phase 3 — Show the username in the computer scope picker
- [ ] Row shows assigned user: `userAndLocation.realname` / `username`, fallback `general.lastLoggedInUsernameBinary`, clear "No assigned user" state
- [ ] Serial still visible; row legible at the current 150 pt list height
- [ ] `filteredComputers` search matches username, real name and serial (not just computer name)
- [ ] Accessibility label reads computer name + user; not colour-dependent
- [ ] Verified: searching a username selects the right Mac

### Phase 4 — Label variant & version pinning
**4.1 — Detect and explain variance (do this regardless):**
- [ ] Fetch `fragments/labels/<label>.sh` on demand; cache per label for the session — F8
- [ ] Informational panel: arch-aware ("picks Apple Silicon or Intel automatically on each Mac — no action needed"), always-latest, `type`, `expectedTeamID`, `blockingProcesses`
- [ ] Degrades quietly when GitHub is unreachable; never blocks a deploy

**4.2 — Advanced overrides (opt-in, per label):**
- [ ] Up to five `key=value` overrides written to `parameter7`–`parameter11` — F6
- [ ] Strict validation: `key=value` shape, key allow-list, no whitespace/newlines, `downloadURL` must be `https://`
- [ ] XML-escaped before interpolation
- [ ] Live preview of the exact parameter strings to be written
- [ ] Default "Let Installomator decide (recommended)" — no overrides
- [ ] Prominent warnings: pinned `downloadURL` goes stale; a pinned architecture installs the wrong binary on the other architecture
- [ ] No "Silicon / Intel" toggle offered as a normal option; no vendor-page scraping in the app — F1, F7
- [ ] Arch-split recipe (two policies + arch smart groups) documented in the overview and README
- [ ] Verified: `mysqlworkbenchce` explains it handles both architectures automatically
- [ ] Verified: `python` deploys pinned to a chosen version and installs exactly that version on a test Mac

### Phase 5 — Polish, docs and consistency pass
- [ ] Liquid Glass design pass over the new `DeploymentConfigSheet` steps (icon, scope rows, variant panel)
- [ ] Sheet sizing re-checked (currently fixed 750 × 620) or made to scroll properly with the added steps
- [ ] Loading / empty / error states for the label-source fetch
- [ ] `JamfCommander/README.md` — Packages / Installomator Manager section updated
- [ ] `docs/JAMF_API_REFERENCE.md` — icon endpoint at create time, `parameter7`–`parameter11` overrides
- [ ] Verified: no functional regressions, macOS build green

## Cross-cutting acceptance criteria
- [ ] No label fails with an opaque error; every failure names an actionable cause
- [ ] No raw Jamf error body, token or secret printed, logged or exported
- [ ] Every interpolated value in Classic XML goes through `xmlEscape`
- [ ] Creation stays throttled (batch + inter-item delay); one failure never aborts the batch
- [ ] Safe defaults: no arch pin, no version pin, no icon unless the admin opts in
- [ ] British English throughout; `SharedUI` / Liquid Glass reused; accessibility labels on new controls
- [ ] `xcodebuild -scheme JamfCommander -destination "platform=macOS" build` green at the end of every phase
- [ ] Nothing committed or pushed

## Added during the overhaul

_(Record genuinely new scope discovered while implementing, with a one-line reason. Nothing yet.)_

## Progress log

- **2026-08-03** — Pre-work review of the Packages module. Diagnosed the reported "Add to Jamf" failures:
  the architecture branch in `mysqlworkbenchce` is resolved on-device at install time and is **not** the
  cause (F1). Verified against the live upstream repo: duplicate `omnissahorizonclient` label line (F2),
  unescaped XML in `createInstallomatorPolicyAsync` (F3), narrow deployed-policy detection (F4), hidden
  error detail plus a raw-body `print()` (F5). Confirmed Installomator re-evaluates `key=value` arguments
  after the label case block, making version pinning implementable via `parameter7`–`parameter11` (F6),
  while the app itself cannot resolve pinned URLs (F7). Confirmed per-label fragments are fetchable (F8).
  Ruled out display-name collisions and reserved entries (F9). Wrote
  `docs/PACKAGES_OVERHAUL_PROMPT.md` and this overview. No code changed.
- **2026-08-03** — **F3 confirmed as the actual root cause by the user.** The target category name
  contained `&`; renaming it to use "and" made every affected label deploy successfully. Treated as an
  app defect (a `&` in a Jamf category name is legal), not a usage error. Follow-up found the same raw
  interpolation in `createCategory(name:)` and `updateCategory(id:newName:)`
  (`JamfAPIService+Dashboard.swift:61`, `:67`) — and the **New Category** field inside
  `DeploymentConfigSheet` calls `createCategory`, so the Add-to-Jamf window contained two unescaped write
  paths, not one. Phase 1 checklist and the brief updated accordingly; the escaping fix is now the first
  item of work.
- **2026-08-03** — **F3 escaping fix landed** (pulled forward out of Phase 1 at the user's request).
  `createInstallomatorPolicyAsync` now escapes the policy name, label, category name and Self Service
  display name; `createCategory` / `updateCategory` escape their names. Escaping is a no-op for names
  without `& < > " '`, so the XML for every existing category is byte-identical — the change cannot break
  a case that currently works, and `xmlEscape` replaces `&` first so entities aren't double-escaped.
  Swept all Classic-XML writes: no raw interpolation remains.
  `xcodebuild -scheme JamfCommander -destination "platform=macOS" build` ⇒ **BUILD SUCCEEDED**.
  Deliberately left for the rest of Phase 1: the raw-error-body `print()` at `+Packages.swift:~229`
  (invariant 4) and the failure-message mapping — not touched here to keep the diff to the escaping fix.

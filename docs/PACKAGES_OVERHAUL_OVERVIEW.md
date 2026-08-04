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
| F11 | Computer display logic is duplicated. The realname → username fallback is written **three different ways inside `ComputersDashboardView` alone** (`:34` search predicate, `:272` `userDisplayName`, `:333` `sortRealName`), and again in `ComputerExportService` and `JamfAPIService+Dashboard`. Four of the five files consuming `ComputerInventoryRecord` derive display values independently. | Phase 3 consolidates onto the model + a shared row view, rather than adding a fourth copy in the scope picker. |
| F12 | **Reusing `ComputersDashboardView.computerTable` in the scope picker was considered and rejected.** Its column minimums total ~910 pt vs ~510 pt available (750 pt sheet − 220 pt category pane); the scope list is 150 pt tall so a `Table` header + rows leaves ~4 visible rows; and `Table(selection:)` uses standard list selection (a plain click *replaces* the selection) whereas the picker tap-toggles with a checkbox, which is correct for multi-machine scoping. | Share the derivation and the row content, not the `Table`. `SelfServiceIconPickerView` is reusable as-is only because it is already a self-contained picker. |

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
- **Computer display is shared via the model + a `SharedUI` row view, not by extracting the Table**
  (F11, F12). Derivation goes on `ComputerInventoryRecord`; presentation goes in
  `SharedUI/ComputerIdentityRow.swift`; the scope picker keeps its tap-to-toggle checkbox list. The
  Computers-module refactor must be behaviour-preserving, and if it starts growing, the username display
  ships standalone instead — that is the deliverable, the refactor is only the means.

## Progress

**Current status:** **All five phases are code complete.** Phase 5 finished the design pass (the new sheet
blocks now use the same `liquidGlassRect` treatment as `InfoSection` on the policy screens), made the
sheet resizable because six steps no longer fit 750 × 620, gave the sheet's own load failure a real
error state, and brought the docs in line with the code — including correcting a stale warning in three
places that still claimed the XML-escaping bug was unfixed. Commits: Phase 1 `2bebedb`, Phase 2
`0447469`, Phase 3 `796f651`, label naming + Phase 4.1 `66e3862`, Phase 4.2 `ab663fa`; Phase 5 is
uncommitted.

**What remains is verification, not code.** Nothing in this overhaul has been exercised against a Jamf
tenant — every "Verified:" line that needs one is still open, most importantly the `&`-category re-test,
an icon-enabled batch, and installing a pinned Python version on a test Mac.

Earlier phases — Phase 1 = `2bebedb`, Phase 2 = `0447469`.
Phase 2 adds a Self Service icon step to the deployment sheet — none (default), upload a local image, or
reuse an existing Jamf icon via the unchanged `SelfServiceIconPickerView` — uploaded once per run, with
only the icon id reaching the batch, and attached to each new policy by a narrow
`assignPolicyIcon(policyID:iconID:)` PUT inside the existing throttled loop. The create-time spike could
not be run (no tenant access), so the proven create-then-attach route was taken; see the Phase 2 checklist
for the reasoning and the one deviation from the brief. The per-label icon override was deliberately not
built. **Nothing in either phase has been exercised against a Jamf tenant.** Phases 3–5 not started.

Phase 1 detail — every code deliverable is implemented and the macOS build
is green. Labels are de-duplicated; the raw-error-body `print()` is gone; `PolicyCreationError` now maps
Jamf responses to actionable British-English messages shown per row in `OperationResultView`; a pre-flight
duplicate-name check warns in the sheet **and** in a new confirmation dialog before anything is written;
deployed-policy detection now matches the Installomator script by id as well as by name and flags
name-collision suspects as "Possibly Deployed". The dead `knownOverrides` keys were **kept** (reason
below). **Live verification against a tenant is the only thing outstanding for Phase 1** — nothing in it
has been exercised against Jamf yet, including the `&`-in-a-category-name case. Phases 2–5 not started.
Phase 3 remains re-scoped as a shared-component refactor (3.1 model derivation → 3.2
`SharedUI/ComputerIdentityRow` → 3.3 scope picker) — see F11/F12.
**Last updated:** 2026-08-04 (Phase 5 — all phases complete).

### Phase 1 — Fix and harden policy creation (the actual bug)
- [x] De-duplicate labels in `fetchInstallomatorLabelsFromGitHub()` (stable order, case-insensitive; log the drop) — F2
- [x] `xmlEscape` `policyName`, `label`, `categoryName`, Self Service display name in `createInstallomatorPolicyAsync` — F3 **(confirmed root cause — done ahead of the rest of Phase 1, 2026-08-03)**
- [x] `xmlEscape` `createCategory(name:)` and `updateCategory(id:newName:)` (`+Dashboard.swift:62`, `:68`) — the New Category field in this same sheet uses `createCategory` — F3
- [x] Sweep for any remaining raw interpolation into Classic XML — clean; every `<name>`/`<parameter*>`/Self Service text element now interpolates an escaped variable
- [x] Remove the raw-error-body `print()`; no bodies logged anywhere — F5. The body is now reduced to a
      `JamfRejectionHint` enum in memory and discarded; the only log is a status-code-only line
- [x] Map Jamf responses to actionable British-English messages in `PolicyCreationError` (409 duplicate,
      rejected category, malformed request, 401, 403, 404, 429, 5xx, network failure). The status code is
      authoritative except for 400/409, where Jamf reuses one code for different problems and the body
      hint disambiguates
- [x] Show the specific reason per row in `OperationResultView` — creation now throws only
      `PolicyCreationError`, and the row wraps the sentence instead of truncating a monospaced fragment
- [x] Pre-flight duplicate-name check surfaced in the confirmation step (rename/deselect, don't collect
      409s) — `fetchPolicyNames()` + an amber banner in the sheet + the collision count repeated in the
      new confirmation dialog. Uses **exact** name matching so it never cries wolf
- [x] Widen "already deployed" detection — match the Installomator script by **id** as well as name; flag
      resolved-name collisions — F4. Ids come from `fetchInstallomatorScriptIDs()` plus the script last
      deployed with (`@AppStorage("installomatorScriptID")`); a loose name match adds a third
      "Possibly Deployed" state that stays selectable
- [x] Decide on the 10 dead `knownOverrides` keys (prune, or retain with a comment) — **kept**, with a
      comment saying why: the Deployed list formats names from each policy's own `parameter4`, so a
      policy created against a since-retired label still needs a readable name. A miss is a free
      dictionary lookup that falls through to the heuristic, so retaining them costs nothing
- [ ] Verified: a selection including `omnissahorizonclient`, `mysqlworkbenchce`, `python` either succeeds or reports an accurate per-item reason — **not run** (needs a tenant)
- [~] Verified: deploying into a category whose name contains `&` succeeds (the exact case that failed on 2026-08-03) — macOS build green; **live re-test outstanding.** The tenant's categories have since been renamed to use "and", so reproducing needs a throwaway category named e.g. "Test & Verify" on a non-production tenant
- [~] Verified: creating a category named with `&` from the New Category field in this sheet succeeds, and renaming one from the dashboard succeeds — same outstanding live test
- [ ] **Real Jamf message recorded in the progress log** for anything still failing (drives Phase 4)

### Phase 2 — Self Service icon in the create flow
- [ ] ~~Spike: does `POST /JSSResource/policies/id/0` accept `<self_service_icon><id>` at create time?~~
      **Not performed — no tenant access from the implementation session, and the configured instance is
      production.** Rather than guess an unproven create-time payload (invariant 2) or risk Jamf silently
      ignoring it and showing iconless policies as a clean success, the create-then-attach route was taken.
      Left open: if you ever spike it and Jamf does accept the element at create time, the attach PUT can be
      folded into the POST and halve the write volume.
- [x] Route chosen and documented — **create, then attach**, but via a new narrow
      `assignPolicyIcon(policyID:iconID:)` rather than `updatePolicySelfService(id:settings:)`.
      **Deviation from the brief, deliberately:** `updatePolicySelfService` re-states the *whole*
      `self_service` section, so calling it after creation would need every field reproduced exactly —
      including a category **id** the create flow only carries by name — and would write
      `<self_service_categories/>`, clearing the Self Service category, if that were got wrong. The new
      method writes only `<self_service><self_service_icon><id>…`, relying on the same Classic
      partial-section merge that `applyClonedGeneral` and `movePolicy` already prove. The icon id is an
      `Int`, so no dynamic string is interpolated.
- [x] Icon step in `DeploymentConfigSheet`: none (default) / upload local image / reuse existing Jamf icon —
      placed inside step 4 "Self Service Options", where it belongs, so the existing step numbering is
      untouched
- [x] Reuse `SelfServiceIconPickerView` + `IconBrowserView` as-is — F10. Presented unchanged; it is already
      a self-contained picker with its own search, "Show All" scan and paginated browser
- [x] Local upload via `NSOpenPanel` (`.png`/`.gif`/`.jpeg`), mirroring `PolicySelfServiceEditorView` —
      including its precedent that the library upload is inert (no policy, no device) and so isn't itself
      gated by a confirmation; attaching is what sits behind the confirmation
- [x] Uploaded **once per run**, icon id reused for every policy in the batch — guaranteed structurally:
      the upload happens in the sheet before the batch starts, and only `InstallomatorDeploymentPlan.iconID`
      reaches the loop
- [x] Attach stays inside the throttled loop with its own per-item result — one extra PUT per policy, then
      the existing 0.5 s gap. A failed attach reports "Policy created (ID n), but the Self Service icon
      could not be attached" rather than a clean success, following the convention `clonePolicy` uses
- [x] Chosen icon previewed in the sheet — 48 pt preview beside the buttons and an 18 pt thumbnail in the
      summary box's new "Icon:" row
- [ ] Verified: a two-label batch shows the icon on both policies in Jamf **and** in Self Service — **not run**
- [ ] Verified: "no icon" run is byte-for-byte the behaviour of today — **not run.** By construction it is:
      the create XML is untouched and a `nil` icon id short-circuits before any second request
- [x] ~~*(Optional)* per-label icon override~~ **Not built, deliberately.** The brief gates it on the batch
      case being solid first, and the batch case cannot be called solid until it has run against a tenant.

### Phase 3 — Shared computer display + username in the scope picker

**F11 was an overcount — correcting it here.** Only `ComputersDashboardView` actually duplicated the
realname → username fallback (three times, as recorded). `ComputerExportService` and
`BasicComputerRecord` emit `username` and `realname` as **separate raw fields** and derive no fallback at
all, and `ComputerInspectorView` shows them as two separate rows. So there were three copies in one file,
not five across five — which is why the refactor stayed genuinely mechanical.

**3.1 — Model-level derivation (behaviour-preserving):**
- [x] `ComputerInventoryRecord`: `displayName`, `assignedUserDisplayName` (realname → username → `lastLoggedInUsernameBinary` → nil), `assignedUserEmail`, `isManaged`, `matches(_ searchText:)` — F11. A file-private `presentValue` helper treats Jamf's `""` and a missing field as the same thing, which the three old variants disagreed on
- [x] `sort*` extension moved from `ComputersDashboardView.swift` to `Models/ComputerModels.swift`; `sortRealName` expressed via `assignedUserDisplayName` so there is one fallback rule. `sortName` deliberately keeps its `?? ""` fallback (an unnamed record should sort first, not under "U") — that is a sort key, not a display value
- [x] `ComputersDashboardView` refactored to use them; local `userDisplayName` and inline predicate deleted (342 → 286 lines)
- [x] **CSV export byte-identical — guaranteed by construction, not by inspection alone:** `ComputerExportService` was not touched, and it never derived a display name, so no column can have changed
- [ ] Verified by hand: every column still sorts, both filter-chip counts unchanged, search still matches name/serial/user/email — **not run** (needs a tenant)
- [x] **Three intended behaviour changes, recorded rather than glossed over:** (a) the display and sort now fall back to `lastLoggedInUsernameBinary`, as the brief specifies, so a Mac with no assigned user shows its last logged-in user instead of "—"; (b) a blank-string `realname` no longer masks a real `username` in search (the old predicate used `??`, which only falls back on nil); (c) a whitespace-only query now matches everything instead of matching every name containing a space

**3.2 — Shared row content:**
- [x] `SharedUI/ComputerIdentityRow.swift` — device icon (tinted by managed state) + name + assigned user, optional serial, sized for the 150 pt list
- [x] ~~a **compact** variant~~ **Only the dense form was built.** A second, roomier layout would have had no caller, and shipping an unused variant is dead code. The file's three views are `ComputerDeviceLabel` (icon + name), `ComputerUserLabel` (user + email) and `ComputerIdentityRow`, which composes the first with the assigned user — so each piece exists exactly once
- [x] Accessibility label reads computer name + assigned user; not colour-dependent (the icon tint is always paired with the badge in the table and with text in the picker)
- [x] Used by the dashboard's Device and User cells **and** the scope picker row
- [x] `statusBadge` left alone (Managed/Unmanaged ≠ `JamfItemStatus`); generalising it stayed out of scope

**3.3 — Scope picker:**
- [x] Tap-to-toggle checkbox list and "N selected / Clear" retained — F12
- [x] Row body swapped for `ComputerIdentityRow`, with a clear "No assigned user" state
- [x] `DeploymentConfigSheet.filteredComputers` uses `matches(_:)`; placeholder now "Search by name, serial, user or email…"
- [x] Added while in there: an **empty state** for the computer list (it previously showed a blank box when a search matched nothing, unlike the group picker beside it, which already had one), and the row exposed to VoiceOver as one selectable element with an `.isSelected` trait instead of an unlabelled tick image beside some text
- [ ] Verified by hand: searching a username finds the right Mac, and each row shows who the machine belongs to — **not run** (needs a tenant)

### Phase 4 — Label variant & version pinning
**4.1 — Detect and explain variance (do this regardless):**
- [x] Fetch `fragments/labels/<label>.sh` on demand; cache per label for the session — F8. New
      `Services/JamfAPIService+InstallomatorLabels.swift` holds the model, an `actor`-based session
      cache and the parser. Unauthenticated GET — the Jamf token is never sent to GitHub
- [x] Informational panel: arch-aware, always-latest, `type`, `expectedTeamID`, `blockingProcesses` —
      `Modules/Packages/LabelVariantPanel.swift`, reached from **any** package card's context menu via
      "Explain This Label…". Placed there rather than in the deployment sheet: it applies to deployed
      labels too (which is where the original confusion arose), and the sheet is already dense at 750 × 620
- [x] Degrades quietly when GitHub is unreachable; never blocks a deploy — the panel has loading,
      loaded and failed states, says outright that deployment is unaffected, and offers a retry
- [x] **Parser verified against real fragments using the shipping code** (not a copy): `mysqlworkbenchce`
      → arch-aware, dmg, team `VB5E2TV963`, resolves version at run time; `python` → arch-aware,
      blocking `IDLE, Python, Launcher`; `googlechrome` and `firefox` → correctly **not** arch-aware;
      `suitestudio` → arch-aware with no version check. This is the evidence F1 predicted, now visible
      in the app
- [x] Verified: `mysqlworkbenchce` explains it handles both architectures automatically ← **the original
      question in the brief, answered**

**4.2 — Advanced overrides (opt-in, per label):**
- [x] Up to five `key=value` overrides written to `parameter7`–`parameter11` — F6
- [x] Strict validation: key allow-list, no whitespace in values, `downloadURL` must be `https://`, no
      duplicate keys, at most five, version strings restricted to characters safe in both a policy name
      and a single shell argument
- [x] XML-escaped before interpolation — a pinned URL can legitimately contain `&`
- [x] Live preview of the exact parameter strings to be written, per version
- [x] Default "Let Installomator decide (recommended)" — no overrides. Verified that this produces one
      unpinned variant with no extra parameters, i.e. byte-identical XML to before pinning existed
- [x] Prominent warnings: pinned `downloadURL` goes stale; a pinned architecture installs the wrong binary
      on the other architecture
- [x] No "Silicon / Intel" toggle offered as a normal option; no vendor-page scraping in the app — F1, F7
- [x] Arch-split recipe (two policies + arch smart groups) — stated in the pinning section's warning; the
      README wording is Phase 5's job

**4.2 — added at the user's request (2026-08-03): one label, many versions, one pass**
- [x] The sheet expands a single label into **one policy per version**, all sharing the category, script,
      icon and scope from the same window — the user's actual ask. `{version}` in the name template and in
      any override value is substituted per version, so the URL pattern is typed once
- [x] **Restricted to single-label runs, deliberately:** a pinned Python URL is meaningless for Firefox.
      With more than one label selected the section explains why it is unavailable rather than hiding
- [x] Everything downstream reads one expanded list (`plannedPolicies`), so the duplicate-name pre-flight,
      the review list, the footer count and the confirmation can never disagree about how many policies
      a run creates
- [x] Guard found while verifying: pinning several versions with no `{version}` in the name template would
      create identical names and Jamf would reject all but the first. That is now a blocking validation
      message rather than a batch of 409s
- [x] The fan-out reuses the same per-policy 0.5 s pacing, so a four-version run is throttled exactly like
      a four-label one
- [ ] ~~Offer a list of *available* versions to choose from (e.g. "latest 3.12")~~ **Not possible, and not
      attempted.** The only source of which versions exist and where they live is the vendor's site, which
      the label scrapes on the Mac at install time (F7). Replicating that would mean per-vendor scraping
      logic for 1,224 labels that silently rots, and Python publishes no stable per-series URL. The
      administrator supplies the versions; the app validates, expands and previews.
- [x] **Verified with the shipping validation/expansion code** (`swiftc` against
      `Models/InstallomatorOverrides.swift`): the python case expands `3.11.9, 3.12.7, 3.13.1` — including
      de-duplicating a repeat — into three correctly-named policies with the right `parameter7`–`parameter9`
      strings; all nine validation rules fire on cue; a missing `{version}` leaves no trailing space in the
      name; and repeated faults are reported once
- [x] **Verified on a real tenant and a real Mac (2026-08-04) — with `golang` rather than `python`.**
      Three versions pinned in one run (1.24.13, 1.25.12, 1.26.5) → three policies, 3 successful /
      0 failed, each carrying the right `appNewVersion=` and `darwin-arm64` `downloadURL` in
      parameter7/8, all sharing one category, script, icon and scope. Installing the latest and then
      1.24.13 left `/usr/local/go/bin/go version` reporting **1.24.13** — the pin beat the label's
      own vendor scrape, which is the whole point of the feature. The name-collision guard also
      earned itself: it blocked the run until `{version}` was added to the template.
      Note Go installs to a single `/usr/local/go`, so pinned versions **replace** one another rather
      than coexisting — the policies are a version switcher, not parallel installs.

### Phase 5 — Polish, docs and consistency pass
- [x] Liquid Glass design pass over the new `DeploymentConfigSheet` steps — the summary box, pinning
      editor, pinning preview, single-label note and both scope lists now use `.liquidGlassRect(...)`,
      matching `InfoSection` (radius 12) on the policy-overhaul screens instead of ad-hoc
      `controlBackgroundColor` fills. The pinning block keeps a thin amber edge to mark it as the
      advanced path, rather than tinting the whole panel
- [x] Sheet sizing re-checked — six steps no longer fit a fixed 750 × 620. Now opens at 880 × 760 and is
      **resizable** (min 780 × 620), with the right column still scrolling
- [x] Loading / empty / error states for the label-source fetch — `LabelVariantPanel` has all three plus
      a retry, and states outright that a failure leaves deployment unaffected (done in 4.1)
- [x] **The deployment sheet's own load failure now has an error state** — previously it printed and left
      an empty sheet with a permanently disabled Deploy button and no explanation. This was logged during
      Phase 1 and deferred here; it is fixed, with Try Again / Cancel and no error body in the log
- [x] `JamfCommander/README.md` — Packages / Installomator Manager section rewritten: icons, version
      pinning with a worked Python example, name review, Explain This Label, Possibly Deployed, the
      pre-flight duplicate check, and the three limitations that are by design
- [x] `docs/JAMF_API_REFERENCE.md` — `parameter7`–`parameter11` overrides, the icon endpoints and the
      narrow `assignPolicyIcon` PUT, created-id read-back, the 400/409 body-classification rule, label
      de-duplication, the `fragments/labels/` fetch, and the Create/Update Policies privilege split
- [x] **Stale guidance corrected in three places** — root `CLAUDE.md`, `.claude/rules/services-and-networking.md`
      and `docs/JAMF_API_REFERENCE.md` all still warned that `createCategory` and
      `createInstallomatorPolicyAsync` interpolate raw XML. Phase 1 fixed both; a stale "don't trust this
      code" note is worse than none
- [x] Verified: macOS build green, no warnings

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

- [x] **The Dashboard's category editor no longer fails silently** (raised by the user 2026-08-04, after
      trying to rename a category back to one containing `&` and finding it "wouldn't let me save").
      `DashboardView.saveCategory()` caught the error, `print`ed it and left the sheet open with nothing
      said — the same silent-failure defect fixed in the deployment sheet's New Category field during
      Phase 1, in the one other place that writes a category. It now shows the reason. **This was not a
      regression from the overhaul** — `DashboardView.swift` was untouched by every phase; the underlying
      write bug was the unescaped `&` that Phase 1 (`ab47453`) fixed, and the missing error state is why
      it looked like the app was refusing to save.

- [x] **Explicit confirmation before creating policies** (Phase 1). The sheet's "Deploy Policies" button
      fired straight at the tenant with no confirmation, which `.claude/rules/swiftui-views.md` requires
      for production writes. Now routes through `CommanderConfirmation`, stating the count, category and
      scope — and repeating any name collisions.
- [x] **The New Category field no longer fakes success** (Phase 1). `createCategory()` used `try?`, so a
      rejected write closed the field and showed nothing — indistinguishable from success, which breaks
      invariant 1. It now keeps the field open with an inline error. Directly relevant because this is the
      second write path in the very window F3 broke.
- [x] **`OperationResultView` error rows wrap as prose** (Phase 1) — dropped `.fontDesign(.monospaced)`
      and added `fixedSize` so a full sentence is readable. Shared component, so this affects every
      module's results sheet; deliberate, since they all pass sentences.
- [ ] **`DeploymentConfigSheet.loadData()` still swallows a total load failure** — it prints and leaves an
      empty sheet with no error state. Out of scope for Phase 1; folded into the Phase 5 states pass.
- [x] **Label display names are properly segmented** (raised by the user on 2026-08-03 after seeing a
      created policy called "Install Mysqlworkbenchce"). `InstallomatorLabelFormatter` gained a
      `knownTokens` table and an all-or-nothing splitter: a lowercase label is only re-spelt if it
      decomposes **entirely** into at least two known product words, otherwise it falls through to the
      old heuristic untouched. `mysqlworkbenchce` → "MySQL Workbench CE", `omnissahorizonclient` →
      "Omnissa Horizon Client", `adobereaderdc` → "Adobe Reader DC".
      **Verified by running the shipping formatter over all 1,224 upstream labels:** 27 names improve,
      nothing else changes, and deliberately-excluded short tokens keep "keynote" from becoming
      "Key Note". Repeat that check before extending the table — the method is recorded in the code comment.
- [x] **"Review policy names" in the deployment sheet** (same report). A collapsed disclosure under the
      name-template step lists every policy name the run will create, marking the ones still spelt as one
      unbroken word (317 of 1,224 labels — the honest rate, since the app can only tidy what it
      recognises). The template preview also now uses the first real selected app instead of a
      hard-coded "Google Chrome".
- [ ] **Per-label name editing** — the review list surfaces an awkward name but the admin can still only
      change the *template*, not one app's name. The remedy today is to deselect it or rename the policy in
      Jamf afterwards. Worth doing if the flag proves noisy in practice.
- [x] **`InstallomatorDeploymentPlan` replaces the 6-argument `onConfirm` callback** (Phase 2). The icon id
      would otherwise have been a 7th positional argument, and Phase 4's overrides more again. One call site,
      mechanical change; Phase 4 now just adds a field.
- [x] **`parseIDFromXMLResponse` made non-private in `+Cloning.swift`** (Phase 2) so the Installomator create
      path can read the new policy id back instead of duplicating the regex.
- [x] **Dashboard refresh observer no longer reloads mid-batch** (Phase 2) — the icon attach PUTs bump the
      refresh token, so an icon-enabled batch would otherwise trigger a full policy re-scan while still
      running. Guarded on `isCreatingPolicies`/`isLoading`.
- [ ] **Fold the icon into the create POST if a spike allows it** — would halve the write volume for
      icon-enabled batches. Needs `POST /JSSResource/policies/id/0` confirmed to honour
      `<self_service_icon><id>`; until then the two-request route stands.
- [ ] **Caveat on `@AppStorage("installomatorScriptID")`** — if an administrator once deploys with the
      wrong script, that id sticks and its other policies may be read as Installomator deployments.
      Affects categorisation only, and is overwritten by the next correct deploy. Revisit if it bites.

## Progress log

- **2026-08-04** — **Phase 5 complete; the overhaul is code complete.** Design pass: the summary box,
  pinning editor, pinning preview, single-label note and both scope lists moved off ad-hoc
  `controlBackgroundColor` fills onto `.liquidGlassRect(...)`, matching the radius-12 treatment
  `InfoSection` gives the policy-overhaul screens; the pinning block keeps a thin amber edge so the
  advanced path still reads as such without tinting the whole panel. Sizing: six steps do not fit a fixed
  750 × 620, so the sheet now opens at 880 × 760 and is resizable down to 780 × 620. Fixed the deferred
  gap from Phase 1 — a total load failure in the deployment sheet left an empty pane with a permanently
  disabled Deploy button; it now shows a real error with Try Again / Cancel, and logs no error body.
  Docs: the README's Packages section was rewritten around what the module actually does now (icons,
  version pinning with a worked Python example, name review, Explain This Label, Possibly Deployed, the
  pre-flight duplicate check) plus the three limitations that are by design; `JAMF_API_REFERENCE.md`
  gained `parameter7`–`parameter11`, the icon endpoints and narrow `assignPolicyIcon` PUT, created-id
  read-back, the 400/409 body-classification rule, label de-duplication, the `fragments/labels/` fetch,
  and the Create/Update Policies privilege split. Also corrected stale guidance in **three** places —
  root `CLAUDE.md`, `.claude/rules/services-and-networking.md` and the API reference all still warned
  that `createCategory` and `createInstallomatorPolicyAsync` interpolate raw XML, which Phase 1 fixed.
  `xcodebuild -scheme JamfCommander -destination "platform=macOS" build` ⇒ **BUILD SUCCEEDED**, no warnings.
  **The overhaul now stands or falls on tenant verification, which has never been run.**

- **2026-08-03** — **Phase 4.2 complete, extended at the user's request.** They asked whether the sheet
  could offer a *choice* of versions for a label like `python` — latest of the 3.12 series, or individual
  releases — picking several and having one window create a policy per version. The first half is not
  possible and was not faked: only the vendor's site knows which versions exist and where they live, the
  label scrapes it on the Mac at install time (F7), and Python publishes no stable per-series URL. The
  second half is now built. A single-label run can list versions, give one override pattern containing
  `{version}`, and get one policy per version — named by version, all sharing the category, script, icon
  and scope. `parameter7`–`parameter11` carry the resolved overrides, XML-escaped.
  Restricted to single-label runs on purpose: a pinned Python URL is meaningless for Firefox, and the
  section says so rather than hiding. Everything downstream reads one expanded `plannedPolicies` list, so
  the duplicate-name pre-flight, the review list, the footer count and the confirmation cannot disagree.
  Verification found a real trap: pinning several versions without `{version}` in the name template would
  have created identical names and collected 409s — now a blocking message. Verified by running the
  shipping `InstallomatorOverrides` code: the python case expands three versions (de-duplicating a repeat)
  into correctly-named policies with the right parameter strings, all nine validation rules fire, an unused
  `{version}` leaves no trailing space, and repeated faults are reported once. The default path produces one
  unpinned variant with no extra parameters — byte-identical to before pinning existed.
  `xcodebuild -scheme JamfCommander -destination "platform=macOS" build` ⇒ **BUILD SUCCEEDED**.
  **Still open:** the brief's own acceptance test — deploying pinned `python` and confirming that exact
  version installs on a test Mac — needs a tenant and a Mac.

- **2026-08-03** — **Label naming fixed, and Phase 4.1 complete.** The user deployed
  `mysqlworkbenchce` successfully and reported the resulting policy was called "Install
  Mysqlworkbenchce" — asking for a real fix if one existed, or a "check this name" flag if not. Both
  were possible. `InstallomatorLabelFormatter` now tries an all-or-nothing token split before falling
  back to the camelCase heuristic, giving "MySQL Workbench CE"; the rule only rewrites a label that
  decomposes *entirely* into ≥2 known product words, which is what keeps it safe. Measured by running
  the shipping formatter over all 1,224 upstream labels: **27 names improve and nothing else moves.**
  Short generic tokens are excluded on purpose so "keynote" can't become "Key Note" — confirmed. The
  sheet also gained a collapsed "Review policy names" list flagging names that are still one unbroken
  word, plus a template preview that uses a real selected app.
  **Phase 4.1** then landed the label-source explainer: `JamfAPIService+InstallomatorLabels.swift`
  (model + `actor` session cache + parser, unauthenticated so no Jamf token reaches GitHub) and
  `LabelVariantPanel.swift`, opened from any package card's context menu. Verified with the shipping
  parser against five real fragments — `mysqlworkbenchce` and `python` report arch-aware and
  always-latest, `googlechrome` and `firefox` correctly report **not** arch-aware, `suitestudio`
  reports arch-aware with no version check. F1 is now something the app explains rather than something
  a reader has to be told.
  `xcodebuild -scheme JamfCommander -destination "platform=macOS" build` ⇒ **BUILD SUCCEEDED**.
  **4.2 (the `parameter7`–`parameter11` overrides) not started.** Note: the existing
  "Install Mysqlworkbenchce" policy keeps its name — the fix only affects newly created policies.
- **2026-08-03** — **Phase 3 code complete (3.1 → 3.2 → 3.3 in one pass; the build was green at each
  sub-phase boundary).** First finding: **F11 overcounted.** Reading the consumers showed
  `ComputerExportService`, `BasicComputerRecord` and `ComputerInspectorView` all emit `username` and
  `realname` as separate raw fields and derive no fallback — the duplication was three variants inside
  `ComputersDashboardView` alone. That made the refactor genuinely mechanical and meant the CSV-export
  check was satisfied by *not touching* the exporter rather than by re-verifying it: no column it writes
  can have changed. 3.1 put `displayName`, `assignedUserDisplayName`, `assignedUserEmail`, `isManaged`
  and `matches(_:)` on `ComputerInventoryRecord` behind a `presentValue` helper that finally treats
  Jamf's `""` and a missing field alike, and moved the `sort*` extension across with `sortRealName`
  expressed via `assignedUserDisplayName`. 3.2 added `SharedUI/ComputerIdentityRow.swift` as three views —
  `ComputerDeviceLabel`, `ComputerUserLabel` and the composed `ComputerIdentityRow` — so each piece exists
  once; the brief's "compact variant" became the *only* variant, because a roomier one would have had no
  caller. 3.3 swapped the picker row onto it, moved the search to `matches(_:)`, and added the empty state
  the computer list was missing plus a proper VoiceOver element for the row toggle.
  `ComputersDashboardView` went 342 → 286 lines.
  `xcodebuild -scheme JamfCommander -destination "platform=macOS" build` ⇒ **BUILD SUCCEEDED**, no warnings.
  **Not run against a tenant:** both hand-verification lines are open. Three deliberate behaviour changes
  are listed under 3.1 — the `lastLoggedInUsernameBinary` fallback the brief asked for, a blank `realname`
  no longer masking a username in search, and whitespace-only queries now matching everything.
- **2026-08-03** — **Phase 2 code complete.** The deployment sheet gained a Self Service icon step inside
  step 4: preview + "Upload Image…" / "Reuse Existing…" / "Remove", with `SelfServiceIconPickerView`
  presented unchanged and the `NSOpenPanel` upload mirroring `PolicySelfServiceEditorView` (including its
  precedent that an icon-library upload is inert and so needs no confirmation of its own). The 6-argument
  `onConfirm` callback was replaced by a single `InstallomatorDeploymentPlan` value — the icon id would have
  been a 7th positional `Bool`/`Int?` otherwise, and Phase 4's overrides would add more still.
  **Route decision:** the create-time spike could not be run (no tenant access, and the configured instance
  is production), so rather than guess an unproven payload the icon is attached after creation. Built on
  three existing proofs rather than anything new: `parseIDFromXMLResponse` (un-privated, already used by
  `clonePolicy` to read a created id back), the partial-section Classic PUT that `applyClonedGeneral` and
  `movePolicy` rely on, and the `<self_service_icon><id>` shape `updatePolicySelfService` already writes.
  `createInstallomatorPolicyAsync` now returns `Int?` — the new policy id, or `nil` if unreadable, which is
  reported as "created but the icon could not be attached" and never as a failed creation.
  Also guarded the dashboard's `refreshCoordinator` observer against reloading mid-batch: the attach PUTs
  now bump the refresh token, and a duplicate full policy scan would compete with the batch for Jamf's
  rate limit — which is the very thing the coordinator's debounce exists to avoid.
  `xcodebuild -scheme JamfCommander -destination "platform=macOS" build` ⇒ **BUILD SUCCEEDED**, no warnings.
  **Not run against a tenant:** both Phase 2 "Verified:" lines are open, and the create-time spike remains
  the one cheap follow-up that could halve the write volume.
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
- **2026-08-03** — **Phase 1 code complete.** Remaining items landed in one pass:
  `fetchInstallomatorLabelsFromGitHub()` de-duplicates case-insensitively in first-seen order and logs the
  count dropped (F2). The raw-error-body `print()` is gone — `creationFailure(status:body:…)` reduces the
  body to a private `JamfRejectionHint` in memory and discards it, leaving only a status-code-only
  developer line (F5, invariant 4). `PolicyCreationError` was rewritten from two cases to ten actionable
  ones, and `createInstallomatorPolicyAsync` now throws only that type (URLSession errors are wrapped as
  `.networkFailure`), so the per-row reason in `OperationResultView` is always our own copy.
  `fetchInstallomatorPolicies` became `fetchInstallomatorPolicies(knownScriptIDs:)` returning an
  `InstallomatorScan` (deployed policies **plus** every policy name), matching the script by id or name
  (F4); ids come from the new `fetchInstallomatorScriptIDs()` unioned with the script last deployed with.
  A new `PolicyNameMatching` helper in `PackageModels` provides two deliberately different strengths —
  `exactKey` for the pre-flight prediction (so it can't cry wolf) and `appKey`, which drops a leading
  "install ", for the new "Possibly Deployed" hint. The sheet gained `pendingItems`, a `fetchPolicyNames()`
  pre-flight, an amber collision banner, and a `CommanderConfirmation` step before any write.
  `xcodebuild -scheme JamfCommander -destination "platform=macOS" build` ⇒ **BUILD SUCCEEDED**, no warnings.
  **Nothing was run against a Jamf tenant** — every "Verified:" line in Phase 1 is still open, including
  the `&`-category case and the real-Jamf-message capture that Phase 4 depends on.
- **2026-08-03** — Phase 3 redesigned after reviewing `ComputersDashboardView`. The user proposed
  extracting `computerTable` into a shared component for the scope picker; measured and **rejected** —
  ~910 pt of column minimums vs ~510 pt available, 150 pt list height, and `Table` selection semantics
  are wrong for multi-machine scoping (F12). Found the stronger case instead: the realname → username
  fallback exists in three different forms in that one file plus two services (F11). Phase 3 is now
  3.1 model-level derivation → 3.2 `SharedUI/ComputerIdentityRow` → 3.3 scope picker, with an explicit
  bail-out if the Computers-module refactor grows. Brief and this overview updated; no code changed.

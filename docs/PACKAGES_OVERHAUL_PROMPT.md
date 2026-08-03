# Packages / Installomator Manager Overhaul — Brief and Delivery Record

> **This started life as an implementation brief and has been updated to match what was actually
> built (2026-08-04).** The context, findings and guardrails below still hold and are why the work
> looks the way it does. The "What was built" section replaces the original phase instructions and
> records every deviation from the plan, with the reason.
>
> **Live status lives in `docs/PACKAGES_OVERHAUL_OVERVIEW.md`** — the tick-by-tick checklist and dated
> progress log. This file is the narrative; that one is the state.
>
> **All five phases are code complete and none of it has been run against a Jamf tenant.** The
> outstanding verification is listed at the end and is the only thing standing between this and done.

## Context & goal

The Packages module (`Modules/Packages/`) is an **Installomator policy manager**: it diffs deployed Jamf
policies that run an Installomator script (label in `parameter4`) against the upstream `Labels.txt`, and
creates Self Service install policies for selected labels via `createInstallomatorPolicyAsync`.

Four things needed doing. All four were delivered, plus two more raised by the user while the work was
under way (label display names, and creating one policy per pinned version):

1. **Fix "Add to Jamf" failures.** Some labels failed on creation. The causes are diagnosed below —
   they were *not* what they first appeared to be. ⇒ Phase 1.
2. **Self Service icon in the create flow.** Attach an icon to the policies being created, reusing the
   icon infrastructure the policy overhaul already built. ⇒ Phase 2.
3. **Show the username in the computer scope picker.** It showed computer name + serial only. ⇒ Phase 3.
4. **Label variant / version control** — the `mysqlworkbenchce` (arm64 vs Intel) and `python` (many
   versions) cases. No naive "Silicon or Intel" picker was built, for the reason in "Findings". ⇒ Phase 4.

## Findings from the pre-work review (verified — build on these, don't re-derive)

Verified against the live upstream Installomator repo and this codebase on 3 August 2026.

### The architecture branch is a red herring

The `mysqlworkbenchce` label branches on `$(arch)`:

```sh
if [[ $(arch) == "arm64" ]]; then   downloadURL="…-macos-arm64.dmg"
elif [[ $(arch) == "i386" ]]; then  downloadURL="…-macos-x86_64.dmg"
fi
```

`$(arch)` is evaluated **on the target Mac at install time**, not by JamfCommander. The app only writes
the label string into `parameter4`; it never resolves a download URL. So:

- A two-architecture label **cannot** fail policy *creation* for that reason. 114 of the 1,224 upstream
  labels contain an arch conditional; if this were the cause, ~114 labels would fail.
- Today's behaviour is already **correct per device** — each Mac gets its own architecture.
- Forcing one architecture for everyone would actively **break mixed fleets**. Any arch override must be
  opt-in, clearly warned, and never the default.
- `Labels.txt` contains exactly **one** line for `mysqlworkbenchce` (line 735) and **one** for `python`
  (line 869). The app is not seeing "two versions" of anything.

### What actually breaks policy creation

Confirmed by inspection of `JamfAPIService+Packages.swift` and analysis of the upstream label list:

1. **Duplicate line in `Labels.txt`.** The file has 1,225 lines but 1,224 unique labels —
   `omnissahorizonclient` appears twice. `fetchInstallomatorLabelsFromGitHub()` does not de-duplicate,
   so within one deploy run the second POST hits **HTTP 409** and is reported as a failure.
2. **No XML escaping — CONFIRMED as the cause of the reported failure.** `createInstallomatorPolicyAsync`
   interpolates `policyName`, `label` and `categoryName` **raw** into the Classic XML body. A category
   name or name template containing `&`, `<`, `>`, `"` or `'` produces malformed XML that Jamf rejects.
   The user reproduced and confirmed this on 3 August 2026: deploying into a category whose name contained
   `&` failed for every label; renaming the category to use "and" made it work. **A category name
   containing `&` is entirely legal in Jamf — this is an app defect, not a usage error, and must be fixed
   rather than worked around.**

   The same raw interpolation exists in **`createCategory(name:)` and `updateCategory(id:newName:)`**
   (`JamfAPIService+Dashboard.swift:61` and `:67`). That matters here because the **New Category** field
   *inside `DeploymentConfigSheet` itself* calls `createCategory` — so creating "Utilities & Tools" from
   the Add-to-Jamf window fails the same way, and the dashboard's category rename shares the defect.
   Root `CLAUDE.md` already calls these methods out as a known bad pattern not to copy — this is the
   phase that fixes all three.
3. **Invisible existing policies → 409.** "Deployed" is detected *only* via a policy whose script name
   contains "installomator" and whose `parameter4` is non-empty. A policy that installs the same app but
   was made by hand, uses a differently-named script, or stores the label elsewhere is invisible, so the
   label shows as **Available** and creation 409s on the duplicate name.
4. **The real reason is hidden from the user.** Failures surface as `error.localizedDescription`.
   `PolicyCreationError.serverError` embeds the raw Jamf response body, and line ~221 `print()`s that body
   — which violates invariant 4 (never print API error bodies). The user cannot currently see *why* a
   label failed, which is why this was misdiagnosed as an architecture problem.

Ruled out by measurement, so don't chase them: **display-name collisions** (0 across all 1,224 labels)
and **reserved/non-deployable entries** (`version`, `longversion`, `valuesfromarguments`, `broken*` —
none present in `Labels.txt`).

Cosmetic: 10 keys in `InstallomatorLabelFormatter.knownOverrides` no longer match any upstream label —
`adobeacrobatreader`, `adobecreativecloud`, `bravebrowser`, `cleanmymac`, `googleearth7pro`,
`jamfprotect`, `microsoftteamsclassic`, `rectanglepro`, `sublimetext4`, `trello`.

### Version/variant pinning *is* possible — via Installomator argument overrides

`Installomator.sh` re-evaluates `key=value` arguments **after** the label `case` statement
(`# MARK: reading arguments again`, ~line 12732 of 13,111):

```sh
for argument in "${argumentsArray[@]}"; do eval $argument; done
```

So a `key=value` passed as a script parameter **overrides** whatever the label computed. Jamf policy
scripts expose `parameter4`–`parameter11` (all eight are already modelled in `PolicyModels.swift` and
`ScriptModels.swift`). The create flow currently uses 4 = label, 5 = `DEBUG=0`, 6 = `NOTIFY=silent`,
leaving **`parameter7`–`parameter11` free** for overrides.

Critically, **JamfCommander cannot compute the pinned URL itself** — the labels derive it by scraping
vendor pages in shell at run time (MySQL scrapes `dev.mysql.com`; python scrapes `python.org`). The app
must not try to replicate that. So pinning is an **admin-supplied override**, not something the app
resolves. For python that means the admin supplies e.g.:

```text
appNewVersion=3.11.9
archiveName=python-3.11.9-macos11.pkg
downloadURL=https://www.python.org/ftp/python/3.11.9/python-3.11.9-macos11.pkg
packageID=org.python.Python.PythonFramework-3.11
```

Per-label source **is** cheaply readable for *informational* purposes — verified HTTP 200 at
`https://raw.githubusercontent.com/Installomator/Installomator/main/fragments/labels/<label>.sh`
(705 bytes for `mysqlworkbenchce`). Use this to *detect and explain* variance, not to resolve URLs.

### What already exists and must be reused, not rebuilt

- **Icons:** `JamfAPIService+Icons.swift` (`uploadIcon(imageData:filename:mimeType:)` →
  `POST /api/v1/icon`; `fetchIconURL(id:)`; `downloadIconData(from:)` with host-guarded token),
  `SelfServiceIcon` in `PolicyEditingModels.swift`, `IconImageCache`, `SelfServiceIconPickerView`
  (reuse an existing Jamf icon), `IconBrowserView` (paginated grid). `PolicySelfServiceEditorView`
  already has the local-upload flow (`NSOpenPanel`, `.png`/`.gif`/`.jpeg`) — copy that pattern.
- **Username data:** `fetchComputers()` already requests `section=USER_AND_LOCATION`, and
  `ComputerInventoryRecord.userAndLocation` carries `username`, `realname`, `email`. No API change is
  needed for phase 3 — it is a display + search change only.
- **Computer display logic already exists in `ComputersDashboardView`** — and is duplicated. The
  realname → username fallback is written **three different ways in that one file** (`:34` in the search
  predicate, `:272` in `userDisplayName`, `:333` in `sortRealName`). Phase 3 consolidates this — see the
  design decision recorded there.

  **Corrected while doing Phase 3:** the original claim that `ComputerExportService` and
  `JamfAPIService+Dashboard` also derived display values, and that "four of the five files" duplicated
  the logic, was wrong. Both of those emit `username` and `realname` as **separate raw fields** with no
  fallback, and `ComputerInspectorView` shows them as two separate rows. The duplication was three
  variants inside `ComputersDashboardView` alone. That kept the refactor mechanical — and made the
  "CSV export must stay byte-identical" check provable by simply not touching the exporter.

  **Do not extract `ComputersDashboardView.computerTable` for reuse in the scope picker.** It was
  considered and rejected: (a) its column minimums total ~910 pt but the scope picker has ~510 pt of
  width (750 pt sheet − 220 pt category pane); (b) the scope list is 150 pt tall, so a `Table` header
  plus rows leaves ~4 visible rows; (c) `Table(selection:)` uses standard list selection — a plain click
  *replaces* the selection — whereas the scope picker deliberately tap-toggles with a checkbox, which is
  correct for building a multi-machine scope and is what `scopeConfig.selectedComputerIDs` expects.
  `SelfServiceIconPickerView` is reusable as-is because it is already a self-contained *picker*;
  `computerTable` is a dashboard surface with sorting, context menus and double-click-to-inspect.
- **XML safety:** `JamfAPIService.xmlEscape(_:)` (`JamfAPIService.swift:332`).

## Guardrails (already documented — do not restate, just follow)

Follow the repo's existing instructions; they are authoritative:

- Root `CLAUDE.md` — the non-negotiable invariants.
- `.claude/rules/services-and-networking.md`, `swiftui-views.md`, `models-and-decoding.md`,
  `design-system.md`.
- `docs/PROJECT_OVERVIEW.md`, `docs/JAMF_API_REFERENCE.md`, and the maintainer `JamfCommander/README.md`.

The ones that bite this feature hardest, as a reminder only:

- **Every creation writes to a live production Jamf tenant** and the resulting policy installs software on
  real Macs. Gate behind explicit confirmation, report real per-item outcomes (`OperationResultView`),
  never fake success. Test against a **non-production** tenant.
- **XML-escape every interpolated value** via `JamfAPIService.xmlEscape(_:)` — including labels,
  override strings, category names and templates.
- **Respect rate limits** — keep the existing 0.5 s inter-item delay and batching in any new loop.
- **Never log tokens or raw API error bodies.**
- **British English** throughout; reuse `SharedUI` and the Liquid Glass helpers.
- **Do not commit or push.** Leave the working tree for review.

## What was built

Five phases, each committed separately and each leaving the app building. Commits: Phase 1 `2bebedb`,
Phase 2 `0447469`, Phase 3 `796f651`, label naming + Phase 4.1 `66e3862`, Phase 4.2 `ab663fa`,
Phase 5 uncommitted at the time of writing.

Verification note that applies to everything below: there is no test target, so "verified" means one of
two things, and the difference is stated each time — either `xcodebuild -scheme JamfCommander
-destination "platform=macOS" build` succeeded, or the shipping code was compiled standalone with
`swiftc` and run against real data. **No part of this overhaul has been exercised against a Jamf tenant.**

### Phase 1 — Fix and harden policy creation

Delivered as briefed:

- `fetchInstallomatorLabelsFromGitHub()` de-duplicates case-insensitively in first-seen order and logs
  the count dropped (F2).
- `createInstallomatorPolicyAsync`, `createCategory` and `updateCategory` route every interpolated value
  through `xmlEscape` (F3 — the confirmed root cause). A sweep found no other raw interpolation.
- The raw-error-body `print()` is gone. `creationFailure(status:body:…)` reduces the body to a private
  `JamfRejectionHint` in memory and discards it; the only log line is the status code (F5, invariant 4).
- `PolicyCreationError` went from two cases to ten actionable ones, and creation now throws only that
  type, so the per-row reason in `OperationResultView` is always our own copy.
- Pre-flight duplicate-name check via a new `fetchPolicyNames()`, surfaced as an amber banner in the
  sheet and repeated in the confirmation.
- Deployed-policy detection widened: `fetchInstallomatorPolicies(knownScriptIDs:)` matches the script by
  **id or name** (F4), ids coming from `fetchInstallomatorScriptIDs()` unioned with the script last
  deployed with. A looser name match adds a third **Possibly Deployed** state that stays selectable.

Deviations and decisions:

- **The 10 dead `knownOverrides` keys were kept, not pruned.** The Deployed list formats names from each
  policy's own `parameter4`, so a policy created against a since-retired label still needs a readable
  name. A miss is a free dictionary lookup that falls through to the heuristic.
- **Added, not briefed:** policy creation had no confirmation step at all, which
  `.claude/rules/swiftui-views.md` requires for production writes. It now goes through
  `CommanderConfirmation`.
- **Added, not briefed:** the New Category field in the same sheet used `try?`, so a rejected write
  closed the field and showed nothing — indistinguishable from success, which breaks invariant 1.

### Phase 2 — Self Service icon in the create flow

Delivered: an icon step inside "Self Service Options" — none (default), upload a local image, or reuse
an existing Jamf icon via `SelfServiceIconPickerView` presented unchanged. The upload happens once in
the sheet before the batch, so only the icon **id** reaches the loop; re-uploading per label is
structurally impossible. Attaching is one PUT per policy inside the existing throttled loop.

Deviations:

- **The create-time spike was never run.** No tenant access, and the configured instance is production.
  Rather than guess an unproven payload — where Jamf silently ignoring the element would show iconless
  policies as a clean success — the icon is attached after creation. Folding it into the create POST
  remains a cheap optimisation if the spike is ever done; it would halve the write volume.
- **The brief said to fall back via `updatePolicySelfService`. A narrower
  `assignPolicyIcon(policyID:iconID:)` was written instead.** `updatePolicySelfService` re-states the
  *whole* `self_service` section, so using it post-create would need every field reproduced exactly —
  including a category **id** the create flow only carries by name — and would write
  `<self_service_categories/>`, silently clearing the Self Service category, if that were got wrong.
  The new method writes only `<self_service><self_service_icon><id>…`, relying on the same Classic
  partial-section merge that `applyClonedGeneral` and `movePolicy` already prove.
- **The per-label icon override was not built.** The brief gates it on the batch case being solid, and
  the batch case cannot be called solid until it has run against a tenant.
- A failed attach reports "Policy created (ID n), but the Self Service icon could not be attached"
  rather than a clean success, following the convention `clonePolicy` already uses.

### Phase 3 — Shared computer display + username in the scope picker

Delivered in three sub-phases, building green at each boundary:

- **3.1** — `displayName`, `assignedUserDisplayName`, `assignedUserEmail`, `isManaged` and `matches(_:)`
  on `ComputerInventoryRecord`, behind a `presentValue` helper that treats Jamf's `""` and a missing
  field alike. The `sort*` extension moved across with `sortRealName` expressed via
  `assignedUserDisplayName`. `ComputersDashboardView` went 342 → 286 lines.
- **3.2** — `SharedUI/ComputerIdentityRow.swift`.
- **3.3** — the scope picker row rebuilt on it, search moved to `matches(_:)`.

Deviations:

- **The "compact variant" became the only variant.** A second, roomier layout would have had no caller,
  and shipping an unused layout is dead code. The file is three views — `ComputerDeviceLabel`,
  `ComputerUserLabel` and the composed `ComputerIdentityRow` — so each piece exists exactly once.
- **"This must change no behaviour" was not quite achievable, and three changes are recorded rather
  than glossed over:** the display and sort now fall back to `lastLoggedInUsernameBinary` (which the
  brief itself specified); a blank-string `realname` no longer masks a real `username` in search, because
  the old predicate used `??`, which only falls back on nil; and a whitespace-only query now matches
  everything rather than every name containing a space.
- **Added, not briefed:** an empty state for the scope picker's computer list (it showed a blank box when
  a search matched nothing, unlike the group picker beside it), and the row exposed to VoiceOver as one
  selectable element with an `.isSelected` trait.

### Label display names — raised by the user mid-overhaul, not in the original brief

A created policy came out called **"Install Mysqlworkbenchce"**. The brief had no item for this.

`InstallomatorLabelFormatter` now tries an all-or-nothing token split before the camelCase heuristic: a
lowercase label is re-spelt only if it decomposes **entirely** into at least two known product words,
otherwise it falls through untouched. That rule is what makes it safe. `mysqlworkbenchce` → "MySQL
Workbench CE", `omnissahorizonclient` → "Omnissa Horizon Client", `adobereaderdc` → "Adobe Reader DC".

**Verified by running the shipping formatter over all 1,224 upstream labels: 27 names improve and
nothing else moves.** Short generic tokens ("key", "note", "one", "box") are excluded on purpose so
"keynote" cannot become "Key Note" — confirmed. Repeat that measurement before extending the table; the
method is recorded in the code comment.

Because no token table will ever cover 1,224 labels, the deployment sheet also gained a **Review policy
names** list marking names still spelt as one unbroken word (317 of 1,224 — the honest rate). Per-label
name editing was **not** built: the admin can still only change the template. Worth revisiting if the
flag proves noisy.

### Phase 4 — Label variant & version pinning

**4.1 — detect and explain variance.** `Services/JamfAPIService+InstallomatorLabels.swift` fetches
`fragments/labels/<label>.sh`, parses it and caches per label for the session behind an `actor`; the
request is unauthenticated, so the Jamf token never reaches GitHub.
`Modules/Packages/LabelVariantPanel.swift` explains, in plain English, whether the label handles both
architectures and which version will land, plus `type`, `expectedTeamID` and `blockingProcesses`.

- **Placement deviates from the brief**, which said "in the sheet or inspector". It is reached from any
  package card's context menu ("Explain This Label…") because it applies to already-deployed labels
  too — which is where the original confusion arose — and the sheet was already dense.
- **Verified with the shipping parser against five real fragments:** `mysqlworkbenchce` and `python`
  report arch-aware and always-latest; `googlechrome` and `firefox` correctly report **not** arch-aware;
  `suitestudio` reports arch-aware with no version check. F1 is now something the app explains.

**4.2 — advanced overrides.** Up to five validated `key=value` overrides written to
`parameter7`–`parameter11`, XML-escaped, with a live preview and "Let Installomator decide" as the
default. Validation covers an allow-list of variables, `https://`-only `downloadURL`, no whitespace in
values, no duplicate keys, and version strings restricted to characters safe in both a policy name and
a shell argument.

**Extended at the user's request: one label, many versions, one pass.** They asked whether the sheet
could offer a *choice* of versions for a label like `python` and create a policy for each.

- **The "offer a choice" half is not possible and was not faked.** Only the vendor's site knows which
  versions exist and where they live; the label reads it on the Mac at install time (F7). Replicating
  that means per-vendor scraping logic for 1,224 labels that silently rots, and Python publishes no
  stable per-series URL, so "latest 3.12" has nothing to point at.
- **The rest is built.** A single-label run lists versions, gives one override pattern containing
  `{version}`, and gets one policy per version — named by version, all sharing the category, script,
  icon and scope.
- Restricted to single-label runs on purpose: a pinned Python URL is meaningless for Firefox, and the
  section says so rather than hiding.
- Everything downstream reads one expanded `plannedPolicies` list, so the duplicate-name pre-flight, the
  review list, the footer count and the confirmation cannot disagree.
- **A trap found while verifying:** pinning several versions with no `{version}` in the name template
  would create identical names and collect 409s. That is now a blocking validation message.
- **Verified with the shipping validation code:** three versions expand (de-duplicating a repeat) into
  correctly-named policies with the right parameter strings; all nine validation rules fire; an unused
  `{version}` leaves no trailing space; repeated faults are reported once; and the default path produces
  one unpinned variant with no extra parameters.
- The architecture-split recipe (two policies, each scoped to an architecture-based smart group) is
  stated in the pinning warning and the README, as a documented recipe rather than a code feature.

### Phase 5 — Polish, docs and consistency pass

- The summary box, pinning editor, pinning preview, single-label note and both scope lists moved off
  ad-hoc `controlBackgroundColor` fills onto `.liquidGlassRect(...)`, matching the radius-12 treatment
  `InfoSection` gives the policy-overhaul screens. The pinning block keeps a thin amber edge.
- The sheet no longer fits a fixed 750 × 620 with six steps: it opens at 880 × 760 and is resizable down
  to 780 × 620.
- The deployment sheet's own load failure got a real error state — it previously left an empty pane with
  a permanently disabled Deploy button and no explanation.
- `JamfCommander/README.md` and `docs/JAMF_API_REFERENCE.md` brought in line with the code.
- **Stale guidance corrected in three places.** Root `CLAUDE.md`,
  `.claude/rules/services-and-networking.md` and the API reference all still warned that
  `createCategory` and `createInstallomatorPolicyAsync` interpolate raw XML — the very bug Phase 1
  fixed. A stale "don't trust this code" note is worse than none.
- **Added after Phase 5, prompted by the user:** the Dashboard's category editor had the same
  silent-failure defect as the deployment sheet's New Category field — `saveCategory()` printed and left
  the sheet open with no message, which reads as "it won't let me save". It now shows the reason.

## What the original brief asked for and did not get

- **A create-time icon spike** (Phase 2) — needs a tenant.
- **A per-label icon override** (Phase 2, explicitly optional) — gated on the batch case proving itself.
- **A list of available versions to choose from** (Phase 4, added by the user) — impossible without
  vendor-page scraping; see above.
- **Per-label policy name editing** — not asked for, but the natural next step if the "check this name"
  flag proves noisy.

## Outstanding verification — the real remaining risk

Nothing here has touched a Jamf tenant. Against a **non-production** tenant, in rough priority order:

1. **The `&` category case** — the original bug. Create a category named e.g. "Test & Verify" from the
   Dashboard *and* from the deployment sheet's New Category field, rename one to contain `&`, and deploy
   a label into it. All three paths should now succeed; before Phase 1 they produced malformed XML.
2. **An icon-enabled batch of two labels** — the only path that writes twice per policy. Confirm the icon
   appears on both policies in the console and in Self Service, and that the icon library gained exactly
   **one** entry.
3. **A pinned version installing on a test Mac** — the brief's own acceptance test for 4.2. Deploy
   `python` pinned to a specific version and confirm that exact version lands.
4. A selection including `omnissahorizonclient`, `mysqlworkbenchce` and `python` — each should either
   succeed or report an accurate, specific reason. **Record any real Jamf message in the overview's
   progress log.**
5. The Computers table after the Phase 3 refactor: every column still sorts, both filter-chip counts
   unchanged, and a CSV export identical to a previous one (expected: it is, by construction).

# Implementation Prompt — Packages / Installomator Manager Overhaul

> Hand this to Claude Code in the JamfCommander repo. It is a multi-phase brief. **Work in phases,
> stop at the end of each phase, and leave the app building and manually testable before stopping**
> (see "How to work" below).
>
> **Live status lives in `docs/PACKAGES_OVERHAUL_OVERVIEW.md`.** That file is the running checklist and
> progress log; keep it updated as you go. Read it at the start of a session to see what's already done.

## Context & goal

The Packages module (`Modules/Packages/`) is an **Installomator policy manager**: it diffs deployed Jamf
policies that run an Installomator script (label in `parameter4`) against the upstream `Labels.txt`, and
creates Self Service install policies for selected labels via `createInstallomatorPolicyAsync`.

Four things need doing:

1. **Fix "Add to Jamf" failures.** Some labels fail on creation. The causes are diagnosed below —
   they are *not* what they first appear to be, so read "Findings" before writing code.
2. **Self Service icon in the create flow.** Let the admin attach an icon to the policies being created,
   reusing the icon infrastructure the policy overhaul already built.
3. **Show the username in the computer scope picker.** It currently shows computer name + serial only.
4. **Label variant / version control** — the `mysqlworkbenchce` (arm64 vs Intel) and `python` (many
   versions) cases. See "Findings" for what is and isn't real here; do **not** build a naive
   "Silicon or Intel" picker.

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
  predicate, `:272` in `userDisplayName`, `:333` in `sortRealName`), and again in
  `Services/Exports/ComputerExportService.swift` and `JamfAPIService+Dashboard.swift`. Four of the five
  files that consume `ComputerInventoryRecord` derive display values independently. Phase 3 consolidates
  this — see the design decision recorded there.

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

## Phases

Each phase must compile, keep existing features working, and end with manual test steps. There is **no
test target**, so "tested" = `xcodebuild -scheme JamfCommander -destination "platform=macOS" build`
succeeds + the manual checks pass against a non-production tenant.

Phase 1 comes first deliberately: it fixes the failures the user is actually hitting and makes the real
Jamf error visible, so the later phases are built on evidence rather than a guess.

### Phase 1 — Fix and harden policy creation (the actual bug)

- **De-duplicate the label list** in `fetchInstallomatorLabelsFromGitHub()` (stable order, case-insensitive
  key). Log the count dropped.
- **XML-escape** `policyName`, `label`, `categoryName` and the Self Service display name in
  `createInstallomatorPolicyAsync` via `JamfAPIService.xmlEscape(_:)`. **This is the confirmed root cause
  of the reported failure — do it first and verify it before anything else in this phase.**
- **XML-escape `createCategory(name:)` and `updateCategory(id:newName:)`** too
  (`JamfAPIService+Dashboard.swift:61`, `:67`) — the New Category field inside `DeploymentConfigSheet`
  calls `createCategory`, so the same window has a second unescaped write path. Sweep for any other raw
  interpolation into Classic XML while you are in there.
- **Make failures legible.** Replace the raw-body `print()` with nothing (or a scrubbed, non-body
  developer log). Map common Jamf responses to actionable British-English messages in
  `PolicyCreationError` — at minimum: duplicate name (409), missing/invalid category, malformed XML,
  insufficient privileges (403), unauthorised (401). Show that message per row in `OperationResultView`.
- **Pre-flight duplicate check.** Before the batch, fetch existing policy names once and warn in the
  confirmation step which of the selected labels would collide, so the admin can rename or deselect
  instead of collecting 409s.
- **Widen "already deployed" detection** so a label already installed by an existing policy is not offered
  as Available: match on the Installomator script by **id** (the script chosen in the sheet) as well as by
  name, and treat a name collision with the resolved policy name as "possibly deployed" in the UI.
- **Prune the dead `knownOverrides` keys** listed above, or keep them with a one-line comment saying they
  are retained for older tenants — your call, but state which and why.
- **Done when:** deploying a selection that includes `omnissahorizonclient`, `mysqlworkbenchce` and
  `python` either succeeds or reports an accurate, specific reason per item; a category named with an `&`
  no longer breaks the run; no raw error body is printed. **Record the real Jamf message observed for any
  label that still fails in the overview's progress log** — that evidence drives Phase 4.

### Phase 2 — Self Service icon in the create flow

- Add an icon step to `DeploymentConfigSheet`: **no icon** (default), **upload a local image**, or
  **reuse an existing Jamf icon** (present `SelfServiceIconPickerView` / `IconBrowserView` as-is).
- **Upload once per run, reuse the id** for every policy in the batch — never re-upload per label.
- **Spike first, then build:** confirm whether `POST /JSSResource/policies/id/0` accepts
  `<self_service_icon><id>…</id></self_service_icon>` at create time. If it does not, fall back to
  create-then-assign using the existing `updatePolicySelfService` path, and keep that second call inside
  the throttled loop with its own per-item result. Document which route Jamf actually accepted.
- Decide and state the scope: one icon for the whole batch is the baseline. A **per-label icon override**
  is a nice-to-have — only add it if the batch case is solid first.
- Show a preview of the chosen icon in the sheet's summary box.
- **Done when:** a batch of two labels is created with a chosen icon and the icon is visible on both
  policies in the Jamf console and in Self Service; and a run with "no icon" is unchanged from today.

### Phase 3 — Shared computer display + username in the scope picker

No API change needed. Rather than duplicating the dashboard's display logic in the scope picker, pull the
**derivation onto the model** and the **row content into `SharedUI/`**, then have both surfaces use them.
Read the "do not extract `computerTable`" note in the Findings section before starting.

**3.1 — Model-level derivation (behaviour-preserving refactor)**
- Add computed properties to `ComputerInventoryRecord` in `Models/ComputerModels.swift`:
  `displayName`, `assignedUserDisplayName` (realname → username → `general.lastLoggedInUsernameBinary` →
  nil), `assignedUserEmail`, `isManaged`, and `matches(_ searchText: String) -> Bool` (name, serial,
  user, email).
- Move the `sort*` extension out of `ComputersDashboardView.swift` into `Models/ComputerModels.swift`,
  and express `sortRealName` in terms of `assignedUserDisplayName` so there is **one** fallback rule.
- Refactor `ComputersDashboardView` to use them — delete its local `userDisplayName` and inline
  predicate. This must change **no behaviour**.
- **Done when:** the Computers table still sorts on every column, both filter chips still show the same
  counts, search still matches name/serial/user/email, and CSV export is byte-identical to before.

**3.2 — Shared row content**
- Add `SharedUI/ComputerIdentityRow.swift`: device icon (`DeviceSymbols.iconName(for:)`, tinted by
  managed state) + computer name + assigned user, with optional serial/email and a **compact** variant
  for the 150 pt scope list. Accessibility label reads computer name + assigned user.
- Use it for the dashboard's Device and User cells **and** the scope picker row.
- Leave `ComputersDashboardView.statusBadge` alone — it reads Managed/Unmanaged, whereas
  `SharedUI/StatusBadge` is bound to `JamfItemStatus` (Scoped/Unscoped/…). Generalising that is
  optional and out of scope unless it falls out naturally.
- **Done when:** the dashboard rows look unchanged and the same component renders in the scope picker.

**3.3 — Scope picker**
- Keep the existing tap-to-toggle checkbox list and the "N selected / Clear" affordance; swap the row
  body for `ComputerIdentityRow` (compact) so the assigned user shows, with a clear "No assigned user"
  state.
- Replace `DeploymentConfigSheet.filteredComputers`' name-only predicate with `matches(_:)` so searching
  a username or serial works, and update the field's placeholder copy accordingly.
- **Done when:** searching a username finds the right Mac, and each row shows who the machine belongs to.

**Caveat:** 3.1 and 3.2 modify the **Computers** module, which is otherwise out of scope for this
overhaul. Keep the diff strictly mechanical, verify the dashboard by hand before moving on, and if the
refactor starts growing, stop and do 3.3 standalone instead — the username display is the deliverable,
the refactor is the means.

### Phase 4 — Label variant & version pinning (the `mysqlworkbenchce` / `python` ask)

Build this **only** on the Phase 1 evidence, and read the Findings section again first.

- **Detect and explain variance (do this part regardless).** On demand for a selected label, fetch
  `fragments/labels/<label>.sh` and show an informational panel in the sheet or inspector: whether the
  label branches on `$(arch)` ("picks Apple Silicon or Intel automatically on each Mac — no action
  needed"), whether it resolves `appNewVersion` at run time ("always installs the latest version"), plus
  the `type`, `expectedTeamID` and `blockingProcesses`. Cache per label for the session. This alone
  resolves the original confusion and is the highest-value part of this phase.
- **Advanced overrides (opt-in, per label).** Let the admin add up to five `key=value` Installomator
  overrides written to `parameter7`–`parameter11`, e.g. `appNewVersion=…`, `downloadURL=…`,
  `archiveName=…`, `packageID=…`. Requirements:
  - Validate strictly: `key=value` shape, key from an allow-list of documented Installomator variables,
    no whitespace/newlines, `downloadURL` must be `https://`. XML-escape before interpolation.
  - Live preview of the exact parameter strings that will be written.
  - Default is **no overrides** — "Let Installomator decide (recommended)".
  - Prominent warning that a pinned `downloadURL` goes stale and stops installing when the vendor moves
    the file, and that a pinned architecture will install the wrong binary on the other architecture.
- **Do not** offer a "Silicon / Intel" toggle as a normal option, and do not attempt to scrape vendor pages
  to resolve URLs — that logic belongs in Installomator on the device.
- **Document the correct pattern for a genuine architecture split** (in the overview and the README):
  two policies, each scoped to an architecture-based smart group. Offer it as a documented recipe, not a
  code feature, unless the user asks for it.
- **Done when:** selecting `mysqlworkbenchce` explains it handles both architectures automatically;
  and `python` can be deployed pinned to a chosen version via validated overrides, verified installing
  that exact version on a test Mac.

### Phase 5 — Polish, docs and consistency pass

- Design pass over the new `DeploymentConfigSheet` steps (icon, scope rows, variant panel) using the
  Liquid Glass helpers, consistent with the policy-overhaul screens. The sheet is currently a fixed
  750 × 620; re-check it still fits with the new steps, or make it scroll properly.
- Loading, empty and error states for the label-source fetch (GitHub may be unreachable) — the informational
  panel must degrade quietly, never block a deploy.
- Update `JamfCommander/README.md` (Packages / Installomator Manager section) and
  `docs/JAMF_API_REFERENCE.md` (icon endpoint used at create time, `parameter7`–`parameter11` overrides).
- **Done when:** the module looks consistent with the rest of the app, and the docs match what the code does.

## Cross-cutting acceptance criteria

- No label fails with an opaque error; every failure names an actionable cause.
- No raw Jamf error body, token or secret is printed, logged or exported.
- Every interpolated value in Classic XML goes through `xmlEscape`.
- Creation stays throttled (batch + inter-item delay); one failure never aborts the batch.
- Defaults are safe: no architecture pin, no version pin, no icon — today's behaviour unless the admin
  opts in.
- All new copy is British English; UI reuses existing `SharedUI` / Liquid Glass components; accessibility
  labels on new controls.
- App builds at the end of every phase; nothing committed or pushed.

## How to work

- One phase at a time. At the end of each, give the phase-complete summary required by `CLAUDE.md`
  (what changed, files, commands run, how to test, checks, safe-to-commit, skills consulted) and
  **stop for review**.
- **Always update `docs/PACKAGES_OVERHAUL_OVERVIEW.md` before you stop** — tick the completed items
  (`- [ ]` → `- [x]`), set "Current status" and "Last updated", append a dated line to the Progress log,
  and add newly-discovered scope under "Added during the overhaul". If a phase is split into sub-phases,
  update the overview at the end of *each* sub-phase.
- Prefer new focused files (e.g. `JamfAPIService+InstallomatorLabels.swift` for label-source parsing,
  a `LabelVariantPanel` view) over enlarging `DeploymentConfigSheet`, which is already ~615 lines.
- If a spike shows an endpoint, XML shape or override behaviour differs from the notes above, **surface
  that and adjust** rather than guessing — and correct this document.

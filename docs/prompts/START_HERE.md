# Start here — a new session on this project

**Current as of 22 September 2026, app version 9.0.**

Hand this to a fresh Claude Code session in the JamfCommander repository. Read the files below in
order before writing any code. None of it is optional.

**The app is called Commander.** "Jamf" was removed from its own name on 22 September 2026 — it is a
trademark the app has no claim on, and a public release could not carry it. *Jamf's* names stay
wherever they are correct: Jamf Pro, Jamf Account, "your Jamf instance". **The repository, the target,
the scheme and the bundle identifier are all still `JamfCommander`** and are deliberately unchanged,
so the build command below is not a mistake. `Shared/AppIdentity.swift` reads the name from the
bundle, and its header lists what a further rename has to touch.

`CLAUDE.md` already points a new session here, so this should happen on its own. To be explicit, the
maintainer's opening message is kept in **`docs/prompts/NEW_SESSION_PROMPT.md`**, ready to copy — it
is this:

```
Before doing anything, read docs/prompts/START_HERE.md and follow it: the reading order,
what each module does, and the things that will catch you out. Then read CLAUDE.md's safety
invariants and treat them as binding — this app writes to a live production Jamf instance.

Confirm you have read both by telling me, in one line each: which two sidebar labels do not
match their folder names, and why a cancelled request must not be retried.

Then wait. I will tell you what we are working on.
```

The two questions are there because they cannot be answered from the code alone in a few seconds —
they are only in the documents. An answer that is wrong or vague means the reading did not happen, and
you have found that out before any code was written rather than afterwards.

---

## 1. Read these, in this order

| # | File | Why |
| --- | --- | --- |
| 1 | `CLAUDE.md` (repo root) | **The six safety invariants.** Read first, treat as binding. Every write this app makes lands on a live enterprise Jamf instance. |
| 2 | `.claude/rules/architecture.md` | Folder map, the Dashboard → Card → Inspector module pattern, data flow. |
| 3 | `JamfCommander/README.md` | What the app does, module by module, from a user's point of view. Authoritative for *feature behaviour*. |
| 4 | `docs/PROJECT_OVERVIEW.md` | The same ground in narrative form, with the internals. |
| 5 | `docs/JAMF_API_REFERENCE.md` | Exact endpoints, token flow, throttling, XML write and clone shapes. **The only sanctioned source for an endpoint besides Jamf's own documentation.** |
| 6 | `docs/README.md` | How `docs/` is organised and what to write where. |
| 7 | `docs/roadmap/` | Where the maintainer wants this to go. |

`.claude/rules/` also holds path-scoped rules that load when you open a matching file —
`services-and-networking.md`, `models-and-decoding.md`, `swiftui-views.md`, `design-system.md`,
`auth-and-credentials.md`, `exports.md` and `docs-workflow.md`. Do not fight them.

## 2. What this app is

A native SwiftUI macOS app (macOS 26+, single target, **no test target**) for bulk-managing a **live
production Jamf Pro instance**. It reads and writes Configuration Profiles, Computers, Scripts,
Policies, Packages, Blueprints and Categories across two different Jamf APIs.

**It deletes things.** Bulk delete, bulk scope changes, bulk category moves, policy creation. None of
that is theoretical — it has been run against a production tenant.

## 3. The modules, and what each actually does

The sidebar label and the folder name do not always match. Both are listed.

| Sidebar | Folder | What it does |
| --- | --- | --- |
| Dashboard | `Modules/Dashboard/` | Clickable counts, category manager, device status, Export All (six CSVs) |
| Policies | `Modules/Policies/` | List, inspect, bulk move / clone / scope / settings, delete |
| Profiles | `Modules/Profiles/` | Configuration profiles; scope is derived, not stored |
| Blueprints | `Modules/Blueprints/` | **Different API, different credentials** — see below |
| Computers | `Modules/Computers/` | Inventory, `api/v3/computers-inventory` |
| Packages | `Modules/AddPackage/` | Jamf's package library, custom uploads, package → policy usage |
| Scripts | `Modules/Scripts/` | List, inspect, move category, delete |
| Installomator | `Modules/Packages/` | Installs from ~1,287 labels read from **GitHub**, not Jamf |
| Unused | `Modules/Redundant/` | Audit: disabled or unscoped policies, unscoped profiles, unattached packages |

Two name mismatches are deliberate and documented in the code: `Modules/Packages/` is the module
labelled **Installomator**, and `Modules/Redundant/` is the one labelled **Unused** (renamed because
"redundant" reads as *duplicated for resilience* to an infrastructure audience).

## 4. The things that will catch you out

- **Two APIs.** Classic (`JSSResource/…`, XML for writes) and Pro (`api/v{n}/…`, JSON). The version
  varies per resource — computers are v3, not v1. Match what the resource already uses.
- **Blueprints is a third thing.** The Platform API Gateway, credentials created in Jamf Account
  rather than Jamf Pro, region-locked. A Jamf Pro API client cannot reach it.
- **Escape every dynamic value in Classic XML** with `JamfAPIService.xmlEscape(_:)`. A category named
  "Utilities & Tools" once broke an entire deployment run.
- **Never log or display a credential, a token, or an error object from a request.** An `NSError` from
  URLSession carries the full request URL, and with it the instance URL. Log the object's id instead.
- **Bulk work is throttled on purpose** — batches of 10 with 0.5s gaps for reads, 5 for writes. Do not
  remove it to make something faster.
- **A cancelled request must not be retried.** Leaving a module cancels its in-flight work; retrying
  that is waste, and it used to fill the console with one failure per policy.
- **Several actions read every policy in the tenant** (the Unused audit, the Packages Deployed tab,
  Export All). Tens of seconds on a real instance. Never trigger one on a keystroke or on module open.
- **Never invent an endpoint or a payload shape.** If it is not in `docs/JAMF_API_REFERENCE.md` or
  already proven in the code, confirm it against Jamf's documentation first. Where a Pro API update is
  needed, read the record, change one key and send the whole object back — see `moveScript`.
- **A module header has less room than it looks.** Measure the detail pane against the window's own
  **960pt** minimum, not that minus the sidebar: `NavigationSplitView` collapses the sidebar before
  the window gets that narrow and hands the whole width to the pane. Installomator's header
  (`PackagesDashboardView.headerView`) needs **910.5pt** — a 184pt title, a 140pt group picker, a
  420pt view picker and an 86.5pt Refresh button — so it fits by about 50pt. Add a fifth segment to
  that picker, or give a button a text label, and it will not. Packages was moved into the window
  toolbar once for exactly this reason and has since been moved back with content-sized controls;
  the arithmetic is in the comment on `AddPackageView.header`. Measure with a real
  `NSSegmentedControl`, do not estimate — glyph widths are not what you expect.

## 5. How to work here

- **Build:** `xcodebuild -scheme JamfCommander -destination "platform=macOS" build`
- **Tests:** there are none, and there is no test target. Do not claim tests ran.
- Work in phases; leave the project building after each; report what was actually *verified* against
  what merely compiled.
- **Do not commit or push unless asked.** End a unit of work by offering the maintainer the choice of
  committing himself with a short or a full message.
- British English everywhere — UI copy, comments, commit messages.

## 6. Before you build a new idea

Read `docs/README.md` and `.claude/rules/docs-workflow.md`. In short: a new idea becomes a
`docs/roadmap/` entry, **not** immediate code. A handover and a prompt are written from that entry on
the day work starts, never in advance.

Open roadmap entries: `docs/roadmap/CACHING.md`, `docs/roadmap/SCRIPT_USAGE.md`,
`docs/roadmap/MULTIPLE_ENVIRONMENTS.md`, `docs/roadmap/POLICY_NAME_SUGGESTIONS.md`,
`docs/roadmap/PROFILE_TO_BLUEPRINT.md`, `docs/roadmap/SHEET_NAVIGATION.md`.

**The next session's work is written up in `docs/prompts/PROFILE_TO_BLUEPRINT_PROMPT.md`**, over
`docs/roadmap/PROFILE_TO_BLUEPRINT.md` — telling an administrator which of their configuration
profiles Apple now expects to be declarations. The maintainer calls it a game changer; the prompt
frames the first session as a **spike, not a build**, because the mapping the feature rests on does
not exist anywhere yet. That prompt also lists what else is open.

`docs/roadmap/SCRIPT_USAGE.md` is **not wanted** — the maintainer said on 22 September 2026 that it is
not a useful feature. It is kept only until he says to delete it; do not offer it as next work.

Seven handovers exist in `docs/handovers/`:

- **Sheet navigation** — **two of four done, 20 September 2026.** Settings and the Installomator
  deployment window are converted and confirmed on screen; `BlueprintEditorSheet` and
  `PackageUploadPage` remain. Its handover records every layout trap the first two hit, so a third
  should be much cheaper.
- **PDF export** — **built and confirmed on screen, 20 September 2026.** Export a page, or the whole
  guide, from the guide's toolbar. Its handover is mostly a list of **three things a `CGPDFContext`
  gets wrong** that are invisible on screen — read it before touching any rendering that ends up in a
  document.
- **Caching** — **built, 20 September 2026.** A session cache over every Jamf Pro read, keyed by
  instance URL, cleared by Refresh and by any write, with a "Read … ago" stamp and a Live/Cached
  switch in Settings. Its handover has the proven/unproven table; `docs/roadmap/CACHING.md` has been
  trimmed to the five things still undone.
- **Dashboard** — **built and confirmed on screen, 22 September 2026.** Device Status now reads real
  check-in data. Worth reading for what it replaced rather than for what it is: the section
  fabricated a green "Active" badge on every row and had no date in the record at all. It is the
  clearest example in this project of a false report that does not look like an error.

- **Help overhaul** — **complete**, 19 September 2026. Twenty pages and fourteen figures, each
  figure instantiating the view its module actually uses. Its proven/unproven table is current, and
  the unproven column is the longer one. Two open questions remain, both the maintainer's calls.
- **Sidebar restructure** — written *before* its work began, which is what the rule above now
  forbids. **Re-verify its code facts against the repository before acting on it**; the sidebar has
  moved since.
- **Blueprints** — has its own proven/unproven table. Read that table before trusting any write.

## 7. What is proven against the live tenant

"It builds" is not "it works". These have actually run:

- **Script category moves and script delete** — `moveScript` is read-modify-write against
  `PUT api/v1/scripts/{id}`; the script's contents survive.
- **The Blueprints writes** that `BLUEPRINTS_HANDOVER.md` once listed as unexercised.
- **The session cache collapsing repeat estate scans** (20 September 2026). On a 249-policy tenant,
  opening the Dashboard and then Installomator printed **one** `[Packages] Estate scan:` line where
  it used to print two — the second being a duplicate implementation of the same scan, since
  deleted. Most of the rest of the cache is unproven; see its handover's right-hand column.
- **`.jamfconfig` export and import** (19 September 2026). An export carries the real instance URL
  and the real app version — it hardcoded `1.0.0` until that date — and importing a file written
  before Blueprints existed leaves existing Platform API credentials in place rather than blanking
  them. That merge rule lives in `SettingsTransfer.importConfiguration(mergingInto:)` and is the part
  worth re-checking if you touch it.

- **Parts of the help guide** (19 September 2026). Search was run for "403", "unscoped", "client
  secret" and a term that matches nothing; keyboard paging works; the guide opens as its own window;
  and the maintainer confirmed on screen that the search panel and the window both behave. The eight
  pages the guide started with were read end to end.

- **The guide's PDF export** (20 September 2026). The exported *Privileges* page is black on white
  and stamped with the app's name and version — it read "Jamf Commander 9.0" that day and reads
  "Commander 9.0" since the rename — the save panel writes where the reader chooses, and the app's own
  glass surfaces survived the change that made the figures render. Measured as well as seen: 291
  blocks across all 20 topics render with the same contrast on paper as on screen, and all 14 figures
  render identically across separate processes. Nobody has *printed* it.

- **The Dashboard's Device Status** (22 September 2026). It used to draw a hard-coded green "Active"
  on every row of an unsorted twenty, under a heading reading "Recent Check-ins", with no date in the
  record at all — a Mac last seen in June sat in that list marked Active. It now reads
  `lastContactTime`, which Jamf was already returning in a section the Dashboard already fetched.
  Confirmed on screen by the maintainer, and by 19 checks of the arithmetic. See
  `docs/handovers/DASHBOARD_HANDOVER.md`.

Still open, and it is most of the guide — but **split it in two, because the halves have different
answers**:

- **The pages render correctly.** Proven on 20 September 2026, as a by-product of the PDF export:
  every block of all twenty pages draws with the same contrast on paper as on screen, every figure
  draws its content and draws it identically across separate processes, and every figure id resolves
  to a real view.
- **Whether they *say the right thing* is unverified**, for the twelve pages and fourteen figures
  added after 19 September 2026. Nobody has read them against the app. Two figures were found wrong
  exactly this way — by the maintainer, on screen, not by any of the scripts that confirmed they
  rendered. A figure can draw perfectly and still show a control that no longer exists.

So a rendering check is not a correctness check, and no amount of the first substitutes for the
second. Treat the right-hand column of `docs/handovers/HELP_OVERHAUL_HANDOVER.md` as the real state.


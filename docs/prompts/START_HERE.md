# Start here — a new session on this project

**Current as of 19 September 2026, app version 8.5.**

Hand this to a fresh Claude Code session in the JamfCommander repository. Read the files below in
order before writing any code. None of it is optional.

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

Open roadmap entries: `docs/roadmap/CACHING.md`, `docs/roadmap/SCRIPT_USAGE.md`.

Handovers exist for the sidebar restructure and the Help overhaul in `docs/handovers/`. Both were
written *before* their work began, which is what the rule above now forbids — **re-verify their code
facts against the repository before acting on them.**

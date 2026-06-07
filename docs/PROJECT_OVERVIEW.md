# JamfCommander — Project Overview

> Deep, read-on-demand reference. The root `CLAUDE.md` summarises this; `.claude/rules/*` hold the
> durable "musts"/"must-nots". This file is the orientation document for a new contributor or a future
> Claude session.
>
> There is also a maintainer-authored **`JamfCommander/README.md`** that describes the app from a
> **user/feature** angle (every module, workflow, required Jamf privileges, limitations). This document
> is the **internal/architecture** companion to it — read the README for "what it does", read here for
> "how it's built". If you change behaviour, keep both consistent.

## 1. What it is and who it's for

JamfCommander is a native **SwiftUI macOS app** used by **Jamf Pro administrators** (at Zellis) to
manage a Jamf Pro MDM tenant in bulk from the desktop, faster than the Jamf web console allows. It is
an internal admin tool — not an App Store consumer product.

It connects to a **live, production** Jamf Pro instance (default `https://zellis.jamfcloud.com`) and can:

- **List & inspect** Configuration Profiles, Computers (inventory), Scripts, Policies, and Packages.
- **Bulk-edit** profiles/policies: move to a category, change/clear scope, delete.
- **Clone** policies and profiles (created disabled and scope-stripped for safety).
- **Create Installomator install policies** for apps (Self Service), discovering available labels from
  the Installomator GitHub `Labels.txt`.
- **Manage categories** (create/rename/delete).
- **Export** policies, profiles, scripts, and computers to CSV (basic and detailed/rate-limited).
- **Share connection settings** between admins via `.jamfconfig` files.

Because every write affects real enterprise Macs, **safety and correctness dominate** — see the
invariants in the root `CLAUDE.md`.

## 2. Platform & toolchain

- **OS target:** macOS 26.0+ (`MACOSX_DEPLOYMENT_TARGET = 26.1`).
- **Language:** Swift 5.0; SwiftUI; Combine (`ObservableObject`).
- **Project:** `JamfCommander.xcodeproj`, single target & scheme `JamfCommander`,
  bundle id `com.marcoliff.JamfCommander`, marketing version 5.1, team `9RE9AKHMY9`.
- **Security posture:** App Sandbox **on**, Hardened Runtime **on** (via build settings; no standalone
  `.entitlements` file — Xcode-managed). The app requires outgoing network access to reach Jamf.
- **App icon:** Icon Composer `.icon` bundle (`JamfCommander.icon/`), the macOS 26 icon format.
- **Tests:** none — there is no test target or test scheme.

## 3. Build / run / test workflow

```bash
# List schemes
xcodebuild -list -project JamfCommander.xcodeproj

# Build (matches .claude/settings.local.json allow-list)
xcodebuild -scheme JamfCommander -destination "platform=macOS" build
```

Day-to-day, open `JamfCommander.xcodeproj` in **Xcode 26** and Run (⌘R). To exercise anything beyond
the UI you need real Jamf API credentials (client ID/secret for an API role with the relevant
read/write privileges) entered via the in-app Settings sheet.

## 4. Architecture

Single-target SwiftUI app with a deliberately simple shape:

- **Entry:** `JamfCommanderApp` → `ContentView` in a `WindowGroup`.
- **Root:** `ContentView` owns the one `JamfAPIService` (`@StateObject`), gates on login, runs
  auto-login, and manually switches the detail pane by `AppModule`. There is **no router/coordinator**.
- **Service layer:** `JamfAPIService` (+ `+Dashboard`, `+Packages`, `+Cloning`, `+UserLocation`
  extensions) is the only thing that talks to Jamf. `SettingsService` handles `.jamfconfig`.
  `ExportService` coordinates CSV/ZIP export.
- **Feature modules:** `Modules/<Feature>/` each follow a **Dashboard → Card → Inspector** triad.
- **Reusable UI:** `SharedUI/` (Liquid Glass helpers, status badges, filter bar, inspector shell,
  confirmation/result views, JSON viewer).
- **Models:** `Models/` — `Codable` value types mirroring the Jamf API JSON, one file per domain.

See `.claude/rules/architecture.md` for the precise folder map and the module pattern.

### Data flow (typical read → action cycle)

1. `ContentView.task` auto-logs-in if stored credentials exist → `authenticate()` →
   `refreshAllData()`.
2. A module Dashboard calls `await api.fetch…()`, stores results in `@State`, renders, and offers
   filtering/selection.
3. List endpoints are **hydrated**: fetch a basic list, then fetch per-item detail in throttled batches
   (groups of ~10, 0.5s between batches, 3× backoff retry, capped `TaskGroup` concurrency).
4. A bulk action is **confirmed** (`CommanderConfirmation`), executed via `api.…`, and its real
   per-item outcome shown in `OperationResultView`, then the list refreshes.

## 5. Feature modules

- **Dashboard** — fleet landing view; computer overview with email-domain grouping; loading screen.
- **Profiles** — `osxconfigurationprofiles` (Classic). List + scope/category bulk actions + inspector
  with raw JSON; scope can be set to all computers, cleared, or targeted at computer groups.
- **Computers** — `computers-inventory` (Pro, **v3**). Table-style list (no `CardView`; that file was
  removed) + inspector (general/hardware/OS/profiles/scripts/policies/user & location). Building and
  Department IDs from `userAndLocation` are resolved to names via `+UserLocation`
  (`fetchBuildings`/`fetchDepartments`).
- **Policies** — `policies` (Classic). List (hydrated for category/enabled), move category, delete,
  clone, raw JSON. Moving a policy keeps its **Self Service category in sync**, and a bulk
  **"Match Self Service"** action realigns policies whose two categories have drifted.
- **Scripts** — `api/v1/scripts` (Pro). List + inspector (contents/category) + delete.
- **Packages** — Installomator-centric: discovers deployed Installomator policies and the available
  label set from GitHub, then creates Self Service install policies (`DeploymentConfigSheet`,
  `PackageModels.InstallomatorLabelFormatter`).
- **Cloning** — `CloneConfigSheet` + `JamfAPIService+Cloning` (regex XML surgery).
- **Export** — `ExportProgressSheet` + `ExportService`/`Services/Exports/*`. Per-domain CSV plus an
  "Export All" that bundles every CSV into a single timestamped **ZIP** (`exportAllDataToZip`).

## 6. Key types / entities

- `JamfAPIService` — API client (auth, fetch, write, generic helpers, error enums).
- `AppModule` — the navigable sections enum (drives the sidebar and the `ContentView` switch).
- `ConfigProfile`, `Policy`, `ScriptRecord`, `ComputerInventoryRecord`, `Category`, `ComputerGroup`
  (now carries smart/static + member count, decoded defensively), `ScopeInfo`/`ProfileDetail` — domain
  models.
- `JamfLookupItem` / `JamfBuildingsResponse` / `JamfDepartmentsResponse` (in `+UserLocation`) — id→name
  lookups for Buildings and Departments.
- `JamfItemStatus` — shared status enum (Scoped/Unscoped/Pending/Failed/Unknown) with colour + icon.
- `InstallomatorItem` / `InstallomatorLabelFormatter` — package label model + display-name mapping.
- `JamfConfiguration` (in `SettingsService`) — the `.jamfconfig` payload.

## 7. External services

- **Jamf Pro API** — both Classic (`JSSResource/…`, XML writes) and Pro (`api/v{n}/…`, JSON). OAuth
  client-credentials token from `/api/v1/oauth/token`. The Pro version varies by resource: computer
  inventory is **v3** (`api/v3/computers-inventory`); scripts, buildings, departments, and
  computer-groups are **v1**. Buildings/Departments (`api/v1/buildings`, `api/v1/departments`) resolve
  the IDs in `userAndLocation` to names. Full endpoint list in `docs/JAMF_API_REFERENCE.md`.
- **Installomator GitHub** — fetches `https://raw.githubusercontent.com/Installomator/Installomator/main/Labels.txt`
  to populate the available-apps list (read-only, unauthenticated).

## 8. Security & correctness notes (and improvement areas)

These are real characteristics of the current code. Respect them; flag before changing.

- **Live tenant by default.** The app points at whatever instance is configured (Zellis production by
  default); treat all writes as live. The README's disclaimer recommends testing bulk actions against a
  **non-production** Jamf tenant first — follow that.
- **Credential storage.** Client ID/secret/URL live in `UserDefaults` (`@AppStorage`) in clear; the
  `.jamfconfig` export is base64 (obfuscation, not encryption). The token is in memory only. The
  documented hardening path is the **Keychain** (see `.claude/rules/auth-and-credentials.md`).
- **XML injection / breakage.** Classic write bodies are string-interpolated. Cloning escapes via
  `xmlEscape`; `createCategory` and `createInstallomatorPolicyAsync` currently do **not** — escape new
  call sites.
- **Regex XML manipulation** in cloning is fragile; verify against real payloads when touched.
- **Logging.** Some `print()` calls emit API error bodies — don't extend that; never log secrets/tokens.
- **Rate limiting** is deliberate and must be preserved for any bulk operation.

## 9. Conventions cheat-sheet

- British English everywhere user-facing (and in comments/identifiers): "Uncategorised", "Initialise",
  "cancelled".
- `async/await` + `URLSession`; `Codable` models; `Result`/typed `enum` errors.
- `MARK:` section comments; modular files; split large views into subviews.
- SF Symbols + semantic/asset colours; Liquid Glass via the `SharedUI` helpers.
- Git: never commit/push or rewrite history unless explicitly asked.

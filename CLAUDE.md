# JamfCommander

JamfCommander is a native **SwiftUI macOS app** for Jamf Pro administrators. It is a bulk-management
"commander" over a **live, production Jamf Pro MDM instance**: it lists, inspects, and performs
administrative and destructive operations on Configuration Profiles, Computers, Scripts, Policies,
Packages, and Categories — delete, move category, change scope, clone, create Installomator install
policies, and CSV export. It authenticates with OAuth client-credentials and talks to both the Jamf
**Classic API** (`JSSResource/…`, XML for writes) and the **Pro API** (`api/v1/…`, JSON).

## First, if this is a new session

Read **`docs/prompts/START_HERE.md`** before writing any code. (The maintainer's own opening message
lives in `docs/prompts/NEW_SESSION_PROMPT.md`.) It is the orientation for this
project: what to read and in what order, what each module does, which sidebar labels do not match
their folder names, and the things that will catch you out. It takes a couple of minutes and it is
shorter than the mistakes it prevents.

## Non-negotiable safety invariants (ALWAYS apply)

These govern every change. Never relax them to make a feature easier.

1. **Every write hits real production devices.** Deletes, scope changes, category moves, clones, and
   policy creation affect a live enterprise Jamf instance (default `https://zellis.jamfcloud.com`) and
   the Macs it manages. The app talks to whatever instance is configured — prefer testing destructive
   flows against a non-production tenant (the project `JamfCommander/README.md` advises this). Treat any
   new write/delete path as high-risk: it MUST be behind an explicit user confirmation (see
   `CommanderConfirmation` / `OperationResultView`) and must report real outcomes, never fake success.
2. **Never invent or guess Jamf endpoints, XML shapes, or parameters.** Only use endpoints and payload
   structures already proven in the codebase or confirmed against Jamf documentation. A wrong endpoint
   or malformed XML can silently corrupt production objects.
3. **Always XML-escape user/dynamic values** interpolated into Classic-API XML bodies (`&`, `<`, `>`,
   `"`, `'`). Use the static `JamfAPIService.xmlEscape(_:)` helper (or the `+Cloning` equivalent).
   Unescaped names break requests and risk injection — a category named "Utilities & Tools" once
   failed every label in a deployment run. Every Classic write now escapes; keep it that way.
4. **Credentials and tokens are secrets.** The Jamf client ID, client secret, instance URL, and bearer
   token must never be logged, printed, written to exported files in clear, shown in UI, or committed.
   Avoid `print()`-ing API error bodies, which may contain sensitive data.
5. **Respect Jamf rate limits.** Bulk operations MUST keep the existing throttling (batches, delays,
   capped concurrency, bounded retry/backoff). Do not fan out unbounded concurrent requests.
6. **Sandbox/signing/entitlements are high-risk.** App Sandbox and Hardened Runtime are enabled via
   build settings. Do not change sandbox, entitlements, signing, bundle id, or team without being asked.

## Language, locale, and tone

- **British English** for all user-facing copy, comments, and identifiers (e.g. "Uncategorised",
  "Initialise", "cancelled"). Match the existing spelling — do not Americanise.
- Tone is **professional, calm, enterprise-appropriate**. Error messages must be clear and actionable
  without exposing tokens, internal IDs, or stack traces.

## Build / run / test

- **Build:** `xcodebuild -scheme JamfCommander -destination "platform=macOS" build`
- **List schemes:** `xcodebuild -list -project JamfCommander.xcodeproj`
- **Run:** open `JamfCommander.xcodeproj` in Xcode 26 and Run (⌘R), or build then launch the `.app`.
- **Tests:** none — there is **no test target or test scheme**. Do not claim tests ran.
- **Target:** macOS 26.0+ (`MACOSX_DEPLOYMENT_TARGET = 26.1`), Swift 5.0, single target/scheme
  `JamfCommander`, bundle id `com.marcoliff.JamfCommander`.

## Architecture (high level)

- `ContentView` is the root. It owns a single `JamfAPIService` (`@StateObject`) and switches between
  feature modules via an `AppModule` enum inside a `NavigationSplitView` — there is no router/coordinator.
- `JamfAPIService` is one `ObservableObject` split across extensions (`+Dashboard`, `+Packages`,
  `+Cloning`, `+UserLocation`). It centralises auth, fetching, and all writes.
- Each feature lives in `Modules/<Feature>/` and follows a **Dashboard → Card → Inspector** triad.
- Reusable UI is in `SharedUI/`; per-domain models in `Models/`; CSV export logic in `Services/Exports/`.

See `.claude/rules/architecture.md` for the full folder map and data flow, and
`docs/PROJECT_OVERVIEW.md` for the end-to-end reference.

## Universal coding standards (inferred from the code)

- Match the existing style: `MARK:` section comments, `async/await` + `URLSession`, `Codable` models,
  `Result`/typed `enum` errors (`APIError`, `PolicyCreationError`, `SettingsError`).
- Networking goes through `JamfAPIService`; keep it out of views. Views take the service via
  `@ObservedObject`/`@StateObject` and own only view state.
- Prefer safe optionals (`guard let`, `if let`, `??`) over force-unwraps. Mark cross-actor model types
  `Sendable` as the existing models do.
- Cover **loading, empty, success, error, and (where relevant) not-connected** UI states.
- Use SF Symbols and semantic/asset colours; apply the Liquid Glass helpers rather than ad-hoc materials.
- Keep files modular; split oversized views into focused subviews. Read a file before editing it.
- Remove dead code/imports you introduce. Don't add documentation files unless asked.

## Git

- **Do not commit or push unless explicitly asked.** Do not reset, rebase, force-push, or discard
  uncommitted work. Use focused diffs and preserve existing behaviour unless the task requires changing it.

## Where things live

- **Always-loaded rules:** `.claude/rules/architecture.md` (folder map + module pattern + data flow)
  and `.claude/rules/docs-workflow.md` (how an idea becomes a roadmap entry, then a handover and a
  prompt). Note `.claude/` is gitignored, so those two travel only with a copy of the folder —
  the conventions they describe are also written down in the tracked `docs/README.md`.
- **Path-scoped rules** (load when you open a matching file): `services-and-networking.md` (Services),
  `models-and-decoding.md` (Models), `swiftui-views.md` (Modules/Views/Auth/Core),
  `design-system.md` (SharedUI), `auth-and-credentials.md` (Auth + SettingsService), `exports.md` (export code).
- **Read-on-demand docs:** `docs/PROJECT_OVERVIEW.md` (whole-project reference),
  `docs/JAMF_API_REFERENCE.md` (exact endpoints, token flow, throttling, XML write/clone patterns).
- **How `docs/` is organised:** `docs/README.md`. Four kinds of document with different lifespans —
  read it before adding one, and follow it:
  - `docs/roadmap/` — **intent**. One file per idea the maintainer wants built, and why. Durable;
    it describes a goal rather than code. **Any new idea or feature request goes here first.**
  - `docs/handovers/` — **state**. Where a piece of work stands, and crucially what is *proven against
    the live tenant* versus what has only ever compiled. Perishable.
  - `docs/prompts/` — **instructions** for starting a session on one piece of work.
  A handover and a prompt are written from a roadmap entry **at the moment work starts**, never in
  advance: one written months early describes a codebase that has since moved, and the reader cannot
  tell which parts have gone stale.
- **Project README:** `JamfCommander/README.md` — the maintainer-authored end-user/feature & usage
  reference (modules, workflows, privileges, limitations). Treat it as authoritative for *feature*
  behaviour; the `docs/` files cover internals/architecture. Keep them consistent if you change either.

# Helpdesk Access — Brief

> One file rather than a brief plus a live overview: this is a day's work, not a five-phase overhaul,
> so the checklist lives at the bottom. Tick it as you go.
>
> **Read "The boundary is the Jamf role" first.** It determines how little code this needs.

## Context & goal

JamfCommander is about to be shared with the helpdesk / EUC team. They should be able to:

- **Deploy Installomator install policies** — the Packages module exactly as it works today.
- **View** policies, computers and profiles.
- **Not** delete, move, clone, rescope or edit anything.
- Preferably not see the Scripts module at all.

They will use their **own** Jamf API client, not the maintainer's.

## The boundary is the Jamf role, not the app

The enforcement that matters is the **Jamf Pro API role** attached to the helpdesk OAuth client. Jamf
checks every request server-side, so a restricted key cannot exceed its privileges regardless of what
the app's UI offers, what someone types into the settings sheet, or what they do to the binary.

Two consequences, and they shape everything below:

1. **Shipping the app unchanged with a restricted key is already safe.** It is merely *unpleasant* —
   controls appear to work and then fail with a 403.
2. **So this work is about honesty, not security.** The app's job is to stop offering what the key
   cannot do. Treat any UI gating as a courtesy; never as the thing keeping production safe.

**Build the Jamf role first and test the app against it before writing any code.** That alone gets a
safe helpdesk build; the code below just makes it pleasant.

## Verified findings (from a sweep of the codebase — don't re-derive)

| # | Finding | Consequence |
|---|---------|-------------|
| H1 | **The Computers module makes no write calls at all** — every `api.` call in `Modules/Computers/` is a fetch. | It is already read-only. Nothing to gate. |
| H2 | **The Scripts module has no write UI.** `deleteScript(id:)` exists in `JamfAPIService` but is wired to no view. | Scripts is already read-only, so hiding it is a *preference*, not a protection. Cheap to do (one enum case), but don't mistake it for a safety measure. |
| H3 | The write surfaces are exactly: `Views/ActionPanelView.swift`, `Views/SingleActionBar.swift`, `Views/SingleProfileActionBar.swift`, `Modules/Cloning/CloneConfigSheet.swift`, `Modules/Policies/PolicyEditorView.swift`, `Modules/Policies/PolicySelfServiceEditorView.swift`, `Modules/Profiles/ProfileDashboardView.swift`, `Modules/Policies/PoliciesDashboardView.swift` (context-menu delete/move), `Modules/Dashboard/DashboardView.swift` (categories), `SharedUI/CategorySelectionSheet.swift`, and the Packages deployment flow. | A finite, known list. Gating is mechanical, not exploratory. |
| H4 | **Attaching a Self Service icon needs `Update Policies`, not `Create Policies`** (`assignPolicyIcon`, added in the packages overhaul — see `docs/JAMF_API_REFERENCE.md`). | A Create-only helpdesk role will create policies successfully and then fail **every** icon attach, reporting "Policy created (ID n), but the Self Service icon could not be attached". Either grant Update Policies or tell the team icons are unavailable. |
| H5 | The deployment sheet reads **categories, scripts, computers, computer groups and all policy names** before it can be used (`DeploymentConfigSheet.loadData`). | The role needs **Read Scripts** even though the Scripts *module* is hidden — hiding a module does not remove the privilege its features depend on. Same for computers and groups. |
| H6 | `AppModule` is a plain enum in `Core/SidebarView.swift` (`dashboard`, `policies`, `profiles`, `computers`, `packages`, `scripts`) and `ContentView` switches on it. | Hiding a module is a filtered `allCases`, not a refactor. |
| H7 | `genericFetch` / `genericRequest` already throw `APIError.httpError(code)`, and `PolicyCreationError` already distinguishes 401 / 403 with actionable copy. | The "your key can't do this" plumbing partly exists. Reuse it rather than inventing a second error path. |
| H8 | Credentials live in `@AppStorage` — plain `UserDefaults` — and `.jamfconfig` export is obfuscated, **not** encrypted (see the project README and `auth-and-credentials.md`). | Both get materially worse once several people hold the app. See "Before you distribute". |

## The Jamf role recipe (do this first)

Create an API Role for the helpdesk and attach it to a new API Client. Grant **read** on everything the
app reads, and only the writes the Packages flow needs.

**Read:** Categories · Scripts · Computers (computer inventory) · Smart Computer Groups ·
Static Computer Groups · Policies · macOS Configuration Profiles · Buildings · Departments

**Write — only these:**
- **Create Policies** — required for the Packages deploy flow.
- **Update Policies** — only if you want Self Service icons to attach (H4).
- **Create Categories** — only if the helpdesk should be able to add a category from the deployment
  sheet. Omit it and that button will fail; the rest of the sheet still works.

**Deliberately withheld:** Delete Policies · Update/Delete macOS Configuration Profiles ·
Update/Delete Categories · Delete Scripts · anything to do with computers.

> Confirm the exact privilege names in the Jamf console rather than trusting this list verbatim — they
> vary slightly by Jamf version, and inventing one is worse than looking it up.

**Test the role before writing code:** point the app at the helpdesk client and walk through the
Packages deploy. Everything below is about the experience, not whether it is safe.

## Spike before building — can the app ask the key what it can do?

**Unverified, and the plan must not assume it.** Candidate: `GET /api/v1/auth`, which returns the
authenticated context. What it returns for an **OAuth API client** (as opposed to a user account) on
this Jamf version has **not** been confirmed, and root `CLAUDE.md` invariant 2 forbids building on an
unverified endpoint.

Spike it first — one authenticated GET, read the response shape:

- **If it reports the client's privileges** → resolve capabilities from it. One request, declarative,
  adapts to any key.
- **If it does not** → fall back to **probing reads**: one cheap GET per module at login, using
  endpoints the app already calls. A 403 or 401 means no read access, so hide that module. Six
  requests, no new endpoints, no guesswork.

**Writes cannot be probed** — you cannot test-create a policy to see whether you're allowed. So write
capability comes from the auth endpoint if it works, and otherwise is *assumed available and reported
honestly when it fails* (H7). Do **not** invent a "test write".

Record which route Jamf actually supported in this file.

## Guardrails

The repo's existing rules stand — root `CLAUDE.md`, `.claude/rules/*`, `docs/JAMF_API_REFERENCE.md`.
The ones that bite this work:

- **Never present UI gating as security.** The Jamf role is the boundary; the app is being polite.
- **Never fake a capability.** If the key cannot do something, say so — don't disable a control
  silently with no explanation, and don't show success that didn't happen (invariant 1).
- **Never log or display the client secret, the token, or a raw API error body** (invariant 4).
- A failed capability check must **degrade to showing more, not less**: if detection itself fails, do
  not lock the user out of a module they may well have access to — let them try and report the real
  error. Locking someone out because a probe timed out is worse than a 403 they can understand.
- British English; reuse `SharedUI`; accessibility labels on anything new.
- Build after each phase: `xcodebuild -scheme JamfCommander -destination "platform=macOS" build`.
- Don't commit or push unless asked.

## Phases

### Phase A — Capability detection

- [ ] Spike `GET /api/v1/auth` with a real client; record the response shape (no secrets in the notes)
- [ ] `Models/JamfCapabilities.swift` — a `Sendable` value type: `canReadPolicies`,
      `canCreatePolicies`, `canUpdatePolicies`, `canDeletePolicies`, `canReadProfiles`,
      `canWriteProfiles`, `canReadComputers`, `canReadScripts`, `canWriteCategories`, …
- [ ] A permissive `.unknown` default so a detection failure never locks anyone out
- [ ] `JamfAPIService+Capabilities.swift` — resolve once after `authenticate(...)`; auth endpoint if the
      spike succeeded, else the read probe. Published on the service so views can read it
- [ ] Probe path respects the existing throttling conventions; a probe failure degrades, never throws

### Phase B — Sidebar

- [ ] `SidebarView` shows only modules the key can read, plus a preference to hide Scripts (H2)
- [ ] `ContentView` handles the current module vanishing (fall back to Dashboard)
- [ ] Verified: a full-privilege key sees exactly today's sidebar

### Phase C — Read-only surfaces

- [ ] Hide the bulk action bar and single-item action bar in Policies and Profiles when the key cannot
      write them (H3) — selection still works for inspection
- [ ] Remove delete/move from the policy and profile context menus; keep Inspect
- [ ] Dashboard: hide New Category / edit / delete when categories aren't writable
- [ ] Packages keeps "Add to Jamf". If `canUpdatePolicies` is false, the icon step explains icons are
      unavailable with this key rather than failing per policy (H4)
- [ ] Verified: nothing offered that the key will refuse; nothing hidden that it would allow

### Phase D — Honest failures

- [ ] A 403 mid-session reads as "this API client isn't permitted to …", reusing the
      `PolicyCreationError` copy pattern rather than a second error vocabulary (H7)
- [ ] Modules the key can't read show a clear denied state, not an empty list
- [ ] Verified against the real helpdesk client end to end: deploy a label, confirm the read-only
      modules, confirm no control 403s unexpectedly

## Before you distribute

Not blockers, but they get worse the moment more than one person holds the app (H8):

- [ ] **Move credentials to the Keychain.** A key that can create policies sitting in plaintext
      `UserDefaults` on several machines is a different risk from one on the maintainer's own Mac.
      Contained change; worth doing as part of this work.
- [ ] **Decide how the helpdesk gets its credentials.** `.jamfconfig` is obfuscated, not encrypted, so
      distributing one is effectively distributing a plaintext secret. Prefer each person entering the
      client id and secret once, or ship the config through a channel you'd trust with a password.
- [ ] Confirm the archived maintainer build and the helpdesk build can't be confused for one another.

## Notes

_(Record the spike result and anything that contradicts the findings above.)_

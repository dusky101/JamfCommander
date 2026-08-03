# Jamf API reference (as used by JamfCommander)

> Read-on-demand reference of the **exact** Jamf endpoints, the token flow, the throttling strategy,
> and the XML write/clone patterns this app relies on. Durable rules live in
> `.claude/rules/services-and-networking.md`. Endpoints here are the ones proven in the codebase — do
> not invent new ones (root `CLAUDE.md`, invariant 2).

## Authentication

- **Token:** `POST {baseURL}/api/v1/oauth/token`
  - `Content-Type: application/x-www-form-urlencoded`
  - body: `grant_type=client_credentials&client_id=…&client_secret=…`
  - response JSON: `{ "access_token": "…" }` → stored in `JamfAPIService.token` (memory only).
- `baseURL` is the instance URL with a trailing slash trimmed (e.g. `https://your.jamfcloud.com`).
- All subsequent requests send `Authorization: Bearer {token}`.

## Two API families

| Family | Path prefix | Format | Used for |
|---|---|---|---|
| **Classic** | `JSSResource/…` | JSON or XML reads; **XML writes** | profiles, policies, categories, computer groups (fallback) |
| **Pro** | `api/v{n}/…` | JSON | OAuth token, scripts, computer inventory, buildings, departments, computer-groups |

**The Pro API version is not uniform — match the resource, don't assume `v1`:**
`api/v1/oauth/token`, `api/v1/scripts`, `api/v1/buildings`, `api/v1/departments`,
`api/v1/computer-groups`, but `api/v3/computers-inventory` (list **and** detail).

Classic write semantics: `POST …/id/0` creates, `PUT …/id/{id}` updates, `DELETE …/id/{id}` removes.
Write bodies are `Content-Type: application/xml`.

## Endpoints in use

### Configuration Profiles (Classic)
- List: `GET JSSResource/osxconfigurationprofiles` → `os_x_configuration_profiles[]` (id, name only).
- Detail (scope/category): `GET JSSResource/osxconfigurationprofiles/id/{id}`.
- Raw JSON (inspector): same path with `Accept: application/json`, pretty-printed.
- Delete: `DELETE JSSResource/osxconfigurationprofiles/id/{id}`.
- Move category: `PUT …/id/{id}` with `<os_x_configuration_profile><general><category><id>…</id></category></general></os_x_configuration_profile>`.
- Scope — all computers / remove / groups: `PUT …/id/{id}` with a `<scope>` body
  (`<all_computers>true|false</all_computers>`, `<computer_groups><computer_group><id>…</id></computer_group>…</computer_groups>`).

### Policies (Classic)
- List: `GET JSSResource/policies` → `policies[]` (id, name).
- Detail: `GET JSSResource/policies/id/{id}` → general (id/name/category/enabled), scope, scripts.
- Raw JSON: `GET JSSResource/policies/id/{id}` with `Accept: application/json`.
- Delete: `DELETE JSSResource/policies/id/{id}`.
- Move category: `PUT …/id/{id}` with a `<policy>` body that sets **both**
  `<general><category><id>…</id></category></general>` **and**
  `<self_service><self_service_categories><category><id>…</id><name>…</name>…</category></self_service_categories></self_service>`
  so the admin-console category and the Self Service category stay in sync (`movePolicy`). Escape the
  category name.
- Match Self Service only: `PUT …/id/{id}` with just the `<self_service><self_service_categories>` block
  (`setPolicySelfServiceCategory`) — realigns a drifted Self Service category without moving the policy.
- Create (Installomator install policy): `POST JSSResource/policies/id/0` with a `<policy>` body
  (general + scope + `<self_service>` + `<scripts><script>` with `parameter4=label`,
  `parameter5=DEBUG=0`, `parameter6=NOTIFY=silent`, plus optional overrides in
  `parameter7`–`parameter11`). The response carries the new policy's id — read it back with
  `parseIDFromXMLResponse(data:elementName:)`, the same helper `clonePolicy` uses.
  Failures are classified by `PolicyCreationError`: the status code is authoritative except for
  **400/409**, where Jamf reuses one code for different problems and the body is inspected in memory
  for a marker (duplicate / category / parse) and then **discarded** — never logged (invariant 4).
- **Installomator argument overrides (`parameter7`–`parameter11`).** `Installomator.sh` re-evaluates its
  `key=value` arguments *after* the label's `case` block, so a `key=value` passed as a script parameter
  overrides what the label computed. Parameters 4–6 are taken, leaving five. Used for version pinning:
  e.g. `appNewVersion=3.11.9`, `downloadURL=https://…`, `archiveName=…`, `packageID=…`.
  Values are validated (allow-listed variable, `https://` for `downloadURL`, no whitespace) and
  XML-escaped before interpolation — a pinned URL can legitimately contain `&`.
  See `Models/InstallomatorOverrides.swift`; the app never resolves a download URL itself.
- Attach a Self Service icon: `PUT JSSResource/policies/id/{id}` with **only**
  `<policy><self_service><self_service_icon><id>…</id></self_service_icon></self_service></policy>`
  (`assignPolicyIcon`). Classic merges the sections supplied, so the policy's other Self Service
  settings are untouched — deliberately narrower than `updatePolicySelfService`, which re-states the
  whole section and would clear `self_service_categories`. Needs **Update Policies**.
  Whether `POST …/id/0` honours `<self_service_icon>` at create time has **not** been tested; until it
  is, creation and icon assignment stay two requests.

### Categories (Classic)
- List: `GET JSSResource/categories` → `categories[]`.
- Create: `POST JSSResource/categories/id/0` with `<category><name>…</name><priority>9</priority></category>`.
- Rename: `PUT JSSResource/categories/id/{id}` with `<category><name>…</name></category>`.
- Delete: `DELETE JSSResource/categories/id/{id}`.

### Computer Groups (Pro, with Classic fallback)
- List: `GET api/v1/computer-groups`, falling back to `GET JSSResource/computergroups` on failure
  (`fetchComputerGroups`). The `ComputerGroupResponse` decoder tolerates a bare array or any of
  `results`/`groups`/`computerGroups`/`computer_groups`; `ComputerGroup` accepts an `Int` or `String`
  `id` and optional smart/static + member-count fields. Used for scope targeting.

### Buildings & Departments (Pro)
- Buildings: `GET api/v1/buildings?page-size=2000` → `results[]` of `{ id, name }`.
- Departments: `GET api/v1/departments?page-size=2000` → `results[]` of `{ id, name }`.
- `+UserLocation` returns these as `[id: name]` dictionaries to resolve the IDs in a computer's
  `userAndLocation` for the list, inspector, and CSV export.

### Scripts (Pro)
- List: `GET api/v1/scripts?page-size=2000&sort=name:asc` → `results[]`.
- Delete: `DELETE api/v1/scripts/{id}`.

### Computers (Pro — v3)
- Dashboard list: `GET api/v3/computers-inventory?section=GENERAL&section=USER_AND_LOCATION&page-size=2000`.
- Full list: `GET api/v3/computers-inventory?section=GENERAL&section=HARDWARE&section=USER_AND_LOCATION&page-size=2000`.
- Detail: `GET api/v3/computers-inventory/{id}?section=GENERAL&section=HARDWARE&section=OPERATING_SYSTEM&section=CONFIGURATION_PROFILES&section=USER_AND_LOCATION`.

### Installomator labels (external, GitHub — read-only)
- `GET https://raw.githubusercontent.com/Installomator/Installomator/main/Labels.txt`
  — parse non-empty, non-`#`, single-token lines as labels. **De-duplicate case-insensitively**: the
  file is not guaranteed unique (`omnissahorizonclient` currently appears twice), and a repeat would
  be offered twice and 409 on the second POST.
- `GET …/Installomator/main/fragments/labels/{label}.sh` — one label's own source, fetched on demand to
  *explain* it (arch-aware, version resolved at run time, `type`, `expectedTeamID`,
  `blockingProcesses`). Cached per label for the session. Informational only: it must never block a
  deployment, and it is **unauthenticated** — the Jamf bearer token is never sent to GitHub.

### Self Service icons (Pro)
- Upload: `POST api/v1/icon`, `multipart/form-data`, part name `file` → `{ id, url }`. Adds the image
  to the icon library only; attaching it to a policy is the separate Classic PUT above. Requires only a
  valid token.
- Resolve URL: `GET api/v1/icon/{id}` → `{ id, url }`. Download for preview:
  `GET api/v1/icon/download/{id}`, or the returned URL — the bearer token is attached **only** when the
  host matches the configured Jamf instance, never to a CDN.
- In the Installomator create flow the image is uploaded **once per run** and the resulting id is reused
  for every policy in the batch.

## Throttling strategy (preserve this)

Bulk "hydration" (fetching detail for every item in a list) must pace itself or Jamf throttles/fails:

- Split items into **batches of ~10** (`stride` + slices).
- Within a batch, run details concurrently in a `withTaskGroup` (bounded by batch size).
- Between batches, `Task.sleep` ~**0.5s**.
- Per-item: retry up to **3×** with exponential backoff (**0.5s, 1s, 2s**); on final failure, degrade
  (skip or return the basic record) rather than failing the whole operation.

Canonical implementations: `fetchPolicies`, `fetchProfiles` (`fetchProfiles` uses a single capped
`TaskGroup`), and `fetchInstallomatorPolicies`.

## XML write & clone patterns

- **Escape dynamic values** for `& < > " '` before interpolating into XML. Use the static
  `JamfAPIService.xmlEscape(_:)` (there is also a private copy in `JamfAPIService+Cloning.swift`).
  **Every Classic write now escapes**, including `createCategory`, `updateCategory` and
  `createInstallomatorPolicyAsync` — a category named "Utilities & Tools" produced malformed XML and
  failed every label in a run until this was fixed. Keep it that way for any new write.
- **Cloning** (`+Cloning`) fetches the full resource XML (`Accept: application/xml`) and rewrites it with
  `NSRegularExpression` (`.dotMatchesLineSeparators`):
  - Replace the **category ID first**, then the **name** (first `<general>…<name>…</name>` match).
  - Force `enabled=false` and, when requested, strip scope/triggers/frequency/self-service, so clones
    land **inert** and safe.
  - New ID is parsed from the POST response (`<id>(\d+)</id>`).
  - Regex edits are fragile — validate against a real exported payload before changing a pattern.

## Required Jamf privileges (operational note)

The API role/client used must have read **and** the relevant write/delete privileges for the objects
above (profiles, policies, categories, scripts, computer inventory, computer groups). Missing privileges
surface as `requestFailed` (non-2xx) — handle as a clear error, never as silent success.

Worth calling out for the Installomator flow: creating a policy needs **Create Policies**, and attaching
its Self Service icon afterwards needs **Update Policies**. A client with the first but not the second
creates the policy and then fails the icon — reported per item as "created, but the icon could not be
attached", never as a clean success. The icon endpoints themselves need only a valid token.

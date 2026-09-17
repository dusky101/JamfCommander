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
- Delete: `DELETE JSSResource/policies/id/{id}`. The Packages module's bulk removal
  (`deleteInstallomatorPolicies(_:)`) runs these in **batches of 5 with a 0.5s gap**, returning one
  `OperationResult` per policy; a refusal is reported with an actionable reason and never carries the
  response body. Needs **Delete Policies**.
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
- **Edit a deployed Installomator policy** (`updateInstallomatorPolicy(id:edit:)`): one
  `PUT …/id/{id}` carrying only the sections being changed — `<general>` (name / enabled / category),
  `<self_service>` (display name on rename, `feature_on_main_page`, `self_service_categories`,
  `self_service_icon`), `<scope>` and `<scripts>`. Classic **merges** the sections supplied, so an
  omitted section is genuinely untouched. Two consequences worth keeping:
  - `<scripts>` is **not** merged — supplying it replaces the whole list. The policy is therefore
    re-read immediately before the write and **every** script is sent back, with only the Installomator
    entry's parameters rewritten. parameter7–11 are always written (empty where unused) so clearing a
    version pin actually clears it.
  - Scope on an *edit* must be a full replacement, so both `<computers/>` and `<computer_groups/>` are
    always written — `DeploymentScopeConfig.toScopeXML()` (built for creation) would leave the old
    targets in place. Exclusions/limitations are deliberately not written.
  Clearing a policy's category is **not** supported: no shape for it has been verified, so the editor
  refuses it rather than guessing. Needs **Update Policies**.
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

### Packages (Pro) — custom package upload

Used by the **Add PKG** flow (`JamfAPIService+PackageUpload`). Confirmed against Jamf's API reference,
not inferred. Three steps, in order:

1. `POST api/v1/packages` (JSON) — creates the package **record**, returns `{ id, href }` (the id has
   been seen as both string and number; decode either). Required body fields: `packageName`,
   `fileName`, `categoryId` (**a string**), `priority`, `fillUserTemplate`, `rebootRequired`,
   `osInstall`, `suppressUpdates`, `suppressFromDock`, `suppressEula`, `suppressRegistration`.
   Optional: `info`, `notes`, `osRequirements`, hash fields. Privilege: **Create Packages**.
   HTTP 409 means the display name is already taken — package names must be unique.
2. `POST api/v1/packages/{id}/upload` — `multipart/form-data`, part name **`file`**. 201 on success,
   404 when the record (or, on an older Jamf Pro, the endpoint) is absent — the app reports 404/405
   as "this Jamf Pro does not offer the upload endpoint". Privileges: **Read Packages** +
   **Update Packages**.
   The body is assembled as a **temporary file on disk** and sent with `upload(for:fromFile:)`: a
   package is routinely a gigabyte or more, so the in-memory multipart used for icons is not an
   option. A dedicated `URLSession` carries a 5-minute *inactivity* timeout and a 6-hour resource
   timeout; progress comes from `URLSessionTaskDelegate.didSendBodyData`. The temporary file is
   removed on every exit path.
3. `POST JSSResource/policies/id/0` (Classic XML) — the install policy, identical in shape to the
   Installomator create except that `<scripts>` is replaced by
   `<package_configuration><packages><package><id>…</id><name>…</name><action>Install</action>`.
   Failures use the same `PolicyCreationError` classifier as the Installomator path.

Supporting reads: `GET api/v1/packages?page-size=2000&sort=packageName:asc` — one decoder
(`JamfPackage` in `+PackageLibrary`) serves both the pre-flight duplicate-name check and the
**Uploaded** tab; only documented fields are modelled (`id`, `packageName`, `fileName`, `categoryId`,
`info`, `notes`, `manifestFileName`, `cloudTransferStatus` — the endpoint returns no size). Privilege
**Read Packages**. There is **no** package → policy lookup in Jamf, so the **Deployed** tab's
`fetchPackagePolicyUsage()` lists policies and hydrates each one to read
`package_configuration.packages[].id`, using the standard throttle (batches of 10, 0.5s gaps, 3
attempts); it is run lazily, once per library load and `GET api/v1/jamf-pro-version` (to explain a missing endpoint).
`DELETE api/v1/packages/{id}` exists and is used **only** to clear up a record this app just created
and could not upload to — never as a general package-removal feature.

**Nothing is rolled back automatically.** If the upload or the policy fails after the record exists,
the outcome is reported as far as it got ("package created, upload failed"), so the cheap half can be
retried without pushing the file again.

### Computers (Pro — v3)
- Dashboard list: `GET api/v3/computers-inventory?section=GENERAL&section=USER_AND_LOCATION&page-size=2000`.
- Full list: `GET api/v3/computers-inventory?section=GENERAL&section=HARDWARE&section=USER_AND_LOCATION&page-size=2000`.
- Detail: `GET api/v3/computers-inventory/{id}?section=GENERAL&section=HARDWARE&section=OPERATING_SYSTEM&section=CONFIGURATION_PROFILES&section=USER_AND_LOCATION`.

### Installomator labels (external, GitHub — read-only)
- `GET https://raw.githubusercontent.com/Installomator/Installomator/main/Labels.txt`
  — parse non-empty, non-`#`, single-token lines as labels. **De-duplicate case-insensitively**: the
  file is not guaranteed unique (`omnissahorizonclient` currently appears twice), and a repeat would
  be offered twice and 409 on the second POST. Fetched with
  `cachePolicy = .reloadIgnoringLocalCacheData`: this list also decides whether a *deployed* policy's
  label still exists upstream (the **Missing** state), so a cached copy could report a withdrawn label
  as healthy. An empty/failed read marks nothing as missing.
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

### Blueprints (Platform API Gateway) — a THIRD API, separate credentials

Blueprints are **not** served by the Jamf Pro instance. They sit behind the Platform API Gateway,
which is a different host, a different credential and a different permission model. A Jamf Pro API
client cannot call it, and Jamf Pro privileges do not grant its capabilities.

- **Credential:** an integration created in **Jamf Account** (not Jamf Pro), scope level
  **platform environment**. Capabilities are `{capability}:{action}` — this app needs
  `blueprints:read`, `blueprints:create`, `blueprints:update`, `blueprints:delete`,
  `blueprints:deploy` and `device-groups:read`.
- **Host:** `https://{region}.api.jamfcloud.com`, where region is `us`, `eu` or `apac`.
  **Tokens are region-locked** — request the token from the same host you call.
- **Token:** `POST {host}/auth/token`, `application/x-www-form-urlencoded`, body
  `grant_type=client_credentials&client_id=…&client_secret=…`. Returns `access_token` with
  `expires_in` of **900 seconds**; `refresh_expires_in` is 0, so re-request rather than refresh.
- **Every request** carries `Authorization: Bearer …` and `X-Environment-Id: {environment UUID}`.
  (`X-Tenant-Id` is for tenant-scoped product APIs and is *not* used here.)
- **403 means one of three things** — missing capability, wrong scope level, or an unrecognised
  version segment in the path. A typo in `v1` returns 403, not 404.

| Operation | Call |
| --- | --- |
| List | `GET blueprints/v1/blueprints?page=&page-size=&sort=&search=` → `{ results, totalCount }` |
| Create | `POST blueprints/v1/blueprints` → 201 |
| Get | `GET blueprints/v1/blueprints/{id}` → 200 / 404 |
| Update | `PATCH blueprints/v1/blueprints/{id}` → 204 |
| Delete | `DELETE blueprints/v1/blueprints/{id}` → 204 / 404 |
| Deploy | `POST blueprints/v1/blueprints/{id}/deploy` → 202 / 404 / 409 |
| Undeploy | `POST blueprints/v1/blueprints/{id}/undeploy` → 202 / 404 |
| Device groups | `GET device-groups/v1/device-groups?page=&page-size=&sort=&filter=` |

**Traps, all load-bearing:**

- **PATCH requires `Content-Type: application/merge-patch+json`.** Plain `application/json` is
  answered with 415. Merge-patch semantics mean any key you omit is left unchanged on the server.
- **PATCH rejects `divisionId`** with 400 `DIVISION_ASSIGNMENT_NOT_ALLOWED`, whether it holds a
  value or null. A blueprint already assigned to a division cannot be updated at all — 409
  `DIVISION_PATCH_NOT_ALLOWED`. `BlueprintPayload` strips `divisionId` for this reason.
- **No `sort` parameter is sent for blueprints.** The reference does not state which fields that
  endpoint accepts, and an unrecognised one risks rejection, so results are sorted by name locally.
- **Deploy and undeploy answer 202** — the server starts the work and completes it afterwards.
  Never report these as finished; re-read `deploymentState` instead.
- **`scope.deviceGroups` is documented as required with at least one entry**, and holds **platform
  device group UUIDs** — not the numeric Jamf Pro computer group IDs used everywhere else in this
  app. The two are not interchangeable.
- **Component `configuration` objects are free-form** — any Apple payload key is legal. Never
  round-trip a blueprint through a strict Swift model; `BlueprintPayload` validates and passes
  through.

Request body for create:

```json
{
  "name": "string, required, 1-200 chars",
  "description": "string or null",
  "scope": { "deviceGroups": ["<group uuid>"] },
  "steps": [
    {
      "name": "string or null",
      "components": [ { "identifier": "com.jamf.ddm...", "configuration": { } } ],
      "activationPredicate": "string or null"
    }
  ]
}
```

`steps` holds 0–10 entries; each step's `components` holds 1–100.

### Wrapping raw DDM output into a blueprint

A raw Apple declaration is carried by component **`com.jamf.ddm-strict`**. This identifier is **not
in the enum published in the API reference** — it was recovered from a real deployed blueprint in the
tenant, and confirmed by creating one through this app. Do not change it on a guess.

```json
"components": [{
  "identifier": "com.jamf.ddm-strict",
  "configuration": {
    "declarations": [
      {
        "kind": "CONFIGURATION",
        "channelType": "SYSTEM",
        "type": "com.apple.configuration.extensible-sso",
        "payload": { }
      }
    ]
  }
}]
```

- `kind` — `ASSET` for a `com.apple.asset.*` type, `CONFIGURATION` otherwise.
- `channelType` — `SYSTEM` (device-wide) or `USER`.
- `Identifier` and `ServerToken` from an Apple declaration are **dropped**; Jamf generates both and a
  real deployed blueprint carries neither.
- Jamf renders the result as its own native component — an extensible-sso declaration showed as
  "Extensible Sso / Configuration" — **even when that component is absent from the blueprint
  builder's library**. This route therefore reaches component types the UI does not offer.

The Jamf DDM app exports two different shapes and both are handled in `BlueprintPayload`:
a **full declaration** (self-describing, carrying `Type` and `Payload`), and a **bare payload**
(settings only, where the declaration type must be supplied — note extensible-sso's payload has its
own `Type` key holding `"Redirect"`, which is a payload key, not a declaration type).

**Verified live (17 Sep 2026, Production (EU), region `eu`):** token, list, get, device groups, and
**create** — including a blueprint built by wrapping raw DDM output.
**Not yet exercised against the tenant:** update, delete, deploy, undeploy, blueprint-components.

Code: `Services/PlatformAPISession.swift` (token + request building),
`Services/JamfAPIService+Blueprints.swift` (operations), `Models/BlueprintPayload.swift`
(validation), `Models/BlueprintModels.swift` (shapes).

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
above (profiles, policies, categories, scripts, computer inventory, computer groups, and — for the
custom package upload — **Create Packages**, **Read Packages** and **Update Packages**). Missing privileges
surface as `requestFailed` (non-2xx) — handle as a clear error, never as silent success.

Worth calling out for the Installomator flow: creating a policy needs **Create Policies**, and attaching
its Self Service icon afterwards needs **Update Policies**. A client with the first but not the second
creates the policy and then fails the icon — reported per item as "created, but the icon could not be
attached", never as a clean success. The icon endpoints themselves need only a valid token.

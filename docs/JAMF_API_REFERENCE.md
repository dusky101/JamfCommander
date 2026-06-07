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
| **Classic** | `JSSResource/…` | JSON or XML reads; **XML writes** | profiles, policies, categories, computer groups |
| **Pro (v1)** | `api/v1/…` | JSON | scripts, computer inventory, OAuth token |

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
- Move category: `PUT …/id/{id}` with `<policy><general><category><id>…</id></category></general></policy>`.
- Create (Installomator install policy): `POST JSSResource/policies/id/0` with a `<policy>` body
  (general + scope + `<self_service>` + `<scripts><script>` with `parameter4=label`,
  `parameter5=DEBUG=0`, `parameter6=NOTIFY=silent`). HTTP **409** ⇒ duplicate name (`PolicyCreationError.conflict`).

### Categories (Classic)
- List: `GET JSSResource/categories` → `categories[]`.
- Create: `POST JSSResource/categories/id/0` with `<category><name>…</name><priority>9</priority></category>`.
- Rename: `PUT JSSResource/categories/id/{id}` with `<category><name>…</name></category>`.
- Delete: `DELETE JSSResource/categories/id/{id}`.

### Computer Groups (Classic)
- List: `GET JSSResource/computergroups` → `computer_groups[]` (used for scope targeting).

### Scripts (Pro)
- List: `GET api/v1/scripts?page-size=2000&sort=name:asc` → `results[]`.
- Delete: `DELETE api/v1/scripts/{id}`.

### Computers (Pro)
- Dashboard list: `GET api/v1/computers-inventory?section=GENERAL&section=USER_AND_LOCATION&page-size=2000`.
- Full list: `GET api/v1/computers-inventory?section=GENERAL&section=HARDWARE&page-size=2000`.
- Detail: `GET api/v1/computers-inventory/{id}?section=GENERAL&section=HARDWARE&section=OPERATING_SYSTEM&section=CONFIGURATION_PROFILES&section=USER_AND_LOCATION`.

### Installomator labels (external, GitHub — read-only)
- `GET https://raw.githubusercontent.com/Installomator/Installomator/main/Labels.txt`
  — parse non-empty, non-`#`, single-token lines as labels.

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

- **Escape dynamic values** for `& < > " '` before interpolating into XML. Use `xmlEscape(_:)` in
  `JamfAPIService+Cloning.swift`. New write paths must escape; `createCategory` /
  `createInstallomatorPolicyAsync` currently don't — fix when touched, don't copy.
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

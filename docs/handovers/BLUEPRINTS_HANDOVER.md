# Handover — Blueprints module (Platform API)

**State at handover:** 17 September 2026, app version 8.2 (build 3), all work committed on `main`.
The module is built, shipped and partly proven against the live tenant.

Read this before touching anything in `Modules/Blueprints/`, `Services/PlatformAPISession.swift`,
`Services/JamfAPIService+Blueprints.swift`, `Models/BlueprintModels.swift` or
`Models/BlueprintPayload.swift`.

---

## What was built

A **Blueprints** module (sidebar, under Profiles) for Jamf's declarative device management
blueprints, served by the **Platform API Gateway** — a different API from the Jamf Pro Classic/Pro
APIs every other module uses.

- List, search, inspect (full definition as JSON)
- Create from pasted JSON or an uploaded `.json` file, with name/description fields
- **Wrap raw DDM output** from the Jamf DDM app into a blueprint (the module's whole point)
- Edit via merge-patch, Delete, Deploy, Undeploy — all behind `CommanderConfirmation`
- Device-group scope picker, or unscoped
- Component catalogue browser

## Verified against the live tenant — and what is NOT

Tested against **Production (EU)**, region `eu`, on 17 September 2026.

| Proven working | Never exercised |
| --- | --- |
| `POST /auth/token` | `PATCH /blueprints/v1/blueprints/{id}` (Edit) |
| `GET /blueprints/v1/blueprints` | `DELETE /blueprints/v1/blueprints/{id}` |
| `GET /blueprints/v1/blueprints/{id}` | `POST .../{id}/deploy` |
| `GET /device-groups/v1/device-groups` | `POST .../{id}/undeploy` |
| `POST /blueprints/v1/blueprints` (create, incl. DDM wrap) | `GET /blueprints/v1/blueprint-components` |

**Do not claim the right-hand column works.** It compiles and reads correctly; it has never run.
The maintainer has a **Sandbox (EU)** platform environment — changing only the Environment ID in
Settings points the whole module at it, which is the right way to exercise those four writes.

## The hard-won facts

None of the following is guessable from the API reference. Root `CLAUDE.md` invariant 2 forbids
inventing endpoints or payload shapes, so treat these as the record.

**Credentials are a second, separate set.** The Platform API needs an integration created in **Jamf
Account** (not Jamf Pro), scoped to a **platform environment**, with capabilities
`blueprints:read/create/update/delete/deploy` and `device-groups:read`. A Jamf Pro API client cannot
reach this API at all. Three UUIDs are easy to confuse: environment ID, client ID, and the Jamf Pro
tenant ID (the latter is unused here). Stored under the `platform*` `@AppStorage` keys, read by
`PlatformCredentialsStore`.

**Tokens are region-locked** and last 900 seconds. Request them from the same `{region}` host you
call. Region is `eu` for this tenant.

**`PATCH` requires `Content-Type: application/merge-patch+json`** — plain `application/json` gets a
415. Merge-patch semantics: any key omitted is left unchanged server-side. It rejects `divisionId`
with a 400, and returns 409 for a blueprint already assigned to a division; `BlueprintPayload`
strips `divisionId` for this reason.

**Raw DDM declarations go in via component `com.jamf.ddm-strict`**, which is **not in the identifier
enum published in the API reference**. It was recovered from a real deployed blueprint in the tenant.

```json
"components": [{
  "identifier": "com.jamf.ddm-strict",
  "configuration": { "declarations": [
    { "kind": "CONFIGURATION", "channelType": "SYSTEM",
      "type": "com.apple.configuration.extensible-sso", "payload": { } } ] } }]
```

`kind` is `ASSET` for `com.apple.asset.*`, `CONFIGURATION` otherwise. `channelType` is `SYSTEM` or
`USER`. An Apple declaration's `Identifier` and `ServerToken` are **dropped** — Jamf generates both.
Jamf renders the result as its own native component (an extensible-sso declaration showed as
"Extensible Sso / Configuration") **even when that component is absent from the blueprint builder's
Components library**, so this route reaches component types the UI does not offer.

**The Jamf DDM app exports two different shapes** and both are handled: a *full declaration*
(self-describing, has `Type` beginning `com.apple.` plus `Payload`), and a *bare payload* (settings
only — the user must supply the declaration type). Watch out: extensible-sso's payload has its own
`Type` key holding `"Redirect"`, which is a payload key and **not** a declaration type.

**Other traps:** deploy and undeploy answer **202** — the server finishes the work afterwards, so
never report them as completed. No `sort` parameter is sent for blueprints (the reference does not
say which fields it accepts). The component catalogue path is `blueprint-components`, not
`components`. `scope.deviceGroups` is documented as required with at least one entry, and holds
**platform device group UUIDs**, not the numeric Jamf Pro computer group IDs used elsewhere in this
app. A 403 from the gateway means one of three things: missing capability, wrong scope level, or an
unrecognised version segment in the path.

## Where things live

```
Models/BlueprintModels.swift        Blueprint, device groups, components, PlatformRegion
Models/BlueprintPayload.swift       Validation, scope, DDM declaration detection + wrapping
Services/PlatformAPISession.swift   Token (actor), request building, PlatformAPIError
Services/JamfAPIService+Blueprints.swift   All operations
Modules/Blueprints/                 Dashboard, Card, Inspector, EditorSheet, ScopePicker,
                                    ComponentsSheet
Auth/ConfigurationView.swift        Both credential sets + Test Connection
Services/SettingsService.swift      .jamfconfig now carries the platform credentials too
```

`docs/JAMF_API_REFERENCE.md` has the full endpoint reference with the same verified/unverified
marking. `JamfCommander/README.md` documents the module from a user's perspective.

## Outstanding work, roughly in priority order

1. **Exercise the four untested writes** — Edit, Delete, Deploy, Undeploy — against Sandbox (EU)
   first. Edit is the highest risk: merge-patch's content type is the likeliest thing to be subtly
   wrong, and it fails with a 415.
2. **The component browser has never been run.** Its decoder guesses at field names
   (`identifier`/`id`, `name`/`displayName`/`title`) because Jamf does not publish that response's
   schema. There is a "Raw List Response" button to show the untouched JSON — use it to correct the
   decoder, then remove the guesswork.
3. **`docs/cleanup.md`** — an app-wide UI clash audit, already written as a multi-phase brief with
   **two confirmed defects** in it (the `InspectorShell` ZStack header, and fixed `.frame(width:)`
   on `HSplitView` children). Both were found by the maintainer in testing, not by the build.
4. **A GUI DDM builder** — the maintainer's stated "would be great" for a future session: build
   declarations in-app rather than pasting JSON, like the Jamf DDM app. `GET blueprint-components`
   and `GET blueprint-components/{identifier}` give the catalogue and per-component schema to
   generate forms from. This is a substantial piece of work and deserves its own brief.
5. **`{{DEVICEREGISTRATION}}` is unverified inside a blueprint.** Classic configuration profiles
   substitute that variable; whether DDM declarations do is untested. Flagged in the maintainer's
   own `platform-sso-blueprint-reference.md`.

## Working notes

- The maintainer tests against a **live production MDM**. Every write reaches real Macs.
- Layout bugs will not be caught by `xcodebuild`. This session shipped two that the maintainer found
  by eye. If a change affects layout, either verify it visually or say plainly that you have not.
- Commit Ceremony after every phase; the maintainer commits himself and has never asked for a push.

# Apple Business Manager API reference (as used by JamfCommander)

> Read-on-demand reference of the **exact** Apple Business Manager endpoints, the assertion and token
> flow, the pacing strategy, and the payload shapes this app relies on. Durable rules live in
> `.claude/rules/services-and-networking.md`. Everything here was verified against the live Zellis
> tenant — do not invent endpoints or parameters (root `CLAUDE.md`, invariant 2).
>
> **This is a second, entirely separate API from Jamf.** It shares no client, no helpers and no
> credentials with `JamfAPIService`. See `docs/JAMF_API_REFERENCE.md` for that one.

## Why this exists

Jamf Pro only surfaces purchase and warranty data with a GSX connection. Zellis has none, and GSX
access is difficult to obtain outside the US. Apple Business Manager began exposing AppleCare and
warranty data via its API in November 2025, which removes that dependency.

**ABM and Jamf are complementary and neither is sufficient alone.** ABM knows model, capacity, colour,
order number, purchase source and warranty dates. It does **not** know which user has the device, its
hostname, OS version or compliance state. Jamf knows the user and everything operational, and nothing
about purchase or warranty.

**The join key is the serial number**, which in ABM is also the resource ID.

## Read-only, permanently

**Every request this app builds is a GET.** An ABM API account has **no granular permissions** — there
is no read-only scope. The same key that reads warranty data can reassign and release devices. The
read-only discipline exists only in `ABMAPIService`, which is the sole place ABM requests are
constructed. **Do not add a write path.**

## Authentication

Three steps. Each of the traps below fails as a bare `{"error": "invalid_client"}` with no further
detail, so a mistake in any of them is indistinguishable from the others.

### 1. Credentials

Created by an administrator in ABM under **Preferences → API**:

- **Client ID**, format `BUSINESSAPI.<uuid>`
- **Key ID**, a bare UUID
- A **private key** download — EC P-256, issued once

Apple issues the key in **SEC1** form (`-----BEGIN EC PRIVATE KEY-----`), **not** PKCS#8. Python JWT
libraries need `openssl pkcs8 -topk8` first; `ABMPrivateKey` does the conversion in code so no
administrator ever runs openssl.

### 2. Client assertion (ES256 JWT) — `ABMClientAssertion`

```
Header:  { "alg": "ES256", "kid": "<Key ID>" }
Payload: { "sub": "<Client ID>", "iss": "<Client ID>",
           "aud": "https://account.apple.com/auth/oauth2/v2/token",
           "iat": <unix now>, "exp": <unix now + 900>, "jti": "<uuid>" }
```

`iss` and `sub` are **both** the Client ID. Apple's sample code names a `team_id` variable and assigns
the Client ID to it, which is misleading — ABM has no separate team identifier.

> **TRAP 1 — the `aud` claim contains `/v2/`, the POST URL does not.**
> `aud` = `…/auth/oauth2/**v2**/token`, POST to `…/auth/oauth2/token`. This is genuinely how the
> service behaves. Do not "correct" one to match the other.

> **TRAP 2 — the JWS signature must be `rawRepresentation`, never `derRepresentation`.**
> JWS ES256 requires 64 raw bytes, `r ‖ s`. `P256.Signing.ECDSASignature.rawRepresentation` is exactly
> that; `.derRepresentation` is ASN.1-wrapped and is rejected.

> **TRAP 3 — do not hash the input first.**
> `P256.Signing.PrivateKey.signature(for:)` computes the SHA-256 digest internally. Pre-hashing
> produces a valid signature over the wrong data, which also fails opaquely.

Apple permits an `exp` up to 180 days out. **Never use it.** An assertion is a bearer credential
granting full access to the organisation; this app generates a fresh 15-minute one per token request
and never writes one to disk.

### 3. Token exchange

```
POST https://account.apple.com/auth/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
client_id=<Client ID>
client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer
client_assertion=<the JWT>
scope=business.api
```

Returns `access_token`, `token_type`, `expires_in` (3600), `scope`. Cached in memory with its expiry,
refreshed 5 minutes ahead or on any 401, **never persisted**. Concurrent requests coalesce onto one
exchange so a bulk fetch does not open one per task.

## Endpoints in use

All against `https://api-business.apple.com/v1`.

| Purpose | Method and path |
|---|---|
| List MDM servers | `GET /v1/mdmServers` |
| Serials assigned to an MDM server | `GET /v1/mdmServers/{id}/relationships/devices` |
| All device records with attributes | `GET /v1/orgDevices` |
| Single device | `GET /v1/orgDevices/{serial}` |
| Warranty and AppleCare | `GET /v1/orgDevices/{serial}/appleCareCoverage` |

> **TRAP 4 — `/v1/mdmServers/{id}/devices` does not exist.** It returns:
> ```json
> {"errors":[{"status":"403","code":"FORBIDDEN_ERROR",
>  "detail":"The relationship 'devices' does not allow 'GET_RELATED'.
>            Allowed operation is: GET_RELATIONSHIP"}]}
> ```
> Use `/relationships/devices`, which returns **identifiers only** — no model, no order number, no
> warranty. Attributes must come from `/orgDevices` and be joined locally on serial.

**Single-resource shapes are unverified.** Every payload confirmed against the tenant came from a
collection endpoint, which wraps results in `data`. `fetchDeviceAttributes` therefore tries the wrapped
shape first and an unwrapped object second.

## Pagination

Cursor-based, not offset-based.

- `?limit=` accepts up to 1000. **999 is the value proven against the tenant** — use it.
- Response carries `meta.paging.nextCursor` when more pages exist; pass it back as `?cursor=`.
- **The absence of `nextCursor` is the terminator.** Do not compare the returned count against the
  limit.

## Rate limiting and pacing (preserve this)

Apple publishes no rate limit for this API. The only measured safe figure is from the proof-of-concept
extract: **153 sequential requests 150ms apart, never throttled**.

Two shapes were tried and abandoned:

- **Per-device attributes** (`/orgDevices/{serial}` for each) doubles the volume to ~306 requests.
- **Three devices concurrently** — six requests, roughly seven per second — was throttled after about
  a minute and returned a third of the fleet, with an exponential backoff that turned the run into a
  crawl.

`ABMAPIService+Fleet.fetchFleet` therefore runs in three stages:

1. `GET /mdmServers/{id}/relationships/devices` — the membership list, and **the scope for everything
   after it**.
2. `GET /orgDevices` paged — attributes for the whole organisation, filtered to that membership as it
   decodes. Devices managed elsewhere are discarded at the filter: never decoded into a record, never
   cached, never shown or exported.
3. `GET /orgDevices/{serial}/appleCareCoverage` per in-scope Mac, **150ms apart**. There is no bulk
   warranty endpoint.

That is ~155 requests at the proven rate, finishing in about a minute for 153 Macs.

Retries: 429 honours `Retry-After` (clamped 1–60s) with 8 attempts; 5xx backs off exponentially with 4;
transport failures retry with 4; a 401 refreshes the token once. Backoff is jittered and capped at 10s —
without jitter, concurrent requests that trip the same limit wake together and trip it again.

## Known Apple-side fault: HTTP/2 and `transfer-encoding`

`api-business.apple.com` intermittently returns `transfer-encoding: chunked` on an HTTP/2 connection.
**RFC 9113 forbids connection-specific header fields in HTTP/2.** CFNetwork correctly rejects the frame
and drops the connection, which surfaces as:

```
HTTP/2 error encountered on Connection 3 (Code -531): Invalid HTTP header field was received:
frame type: 1, stream: 37, name: [transfer-encoding], value: [chunked]
Task <…> finished with error [-1005] "The network connection was lost."
```

This is why the Python proof of concept never saw it — `requests` speaks HTTP/1.1, where chunked
framing is legal.

Mitigations in place, both of which must stay:

- **Transport failures retry.** Without this, each occurrence loses a device outright. This is what
  turned a run returning 34 of 153 into one returning 153.
- `Accept-Encoding: identity` on every request, to encourage a buffered response with a
  `Content-Length`. It reduces but does not eliminate the fault.

Worth an Apple Feedback report; every ABM API consumer on Apple platforms will hit it.

## Payload shapes

Model `Decodable` types against these, not against Apple's documentation samples — the attribute set
has changed since launch. Everything is optional: Apple omits fields rather than sending nulls.

### MDM server

```json
{
  "type": "mdmServers",
  "id": "C8F02BFBF40C4A53B99E72EA9076EDFE",
  "attributes": {
    "defaultProductFamilies": ["MAC"],
    "serverType": "MDM",
    "serverName": "Zellis Jamf Pro",
    "createdDateTime": "2026-01-10T14:48:11.911Z",
    "lastConnectedDateTime": "2026-08-12T15:06:32.974Z",
    "status": "ACTIVE"
  }
}
```

The `devices` relationship exposes only `self` and `include` — no `related`. That absence is the signal
that `GET_RELATED` is unavailable (trap 4).

### Device — reseller purchase

```json
{
  "type": "orgDevices",
  "id": "M79F6W44VV",
  "attributes": {
    "productFamily": "Mac",
    "serialNumber": "M79F6W44VV",
    "deviceModel": "MacBook Pro (16-inch, M5 Pro)",
    "productType": "Mac17,8",
    "deviceCapacity": "1TB",
    "color": "SPACE BLACK",
    "partNumber": "MGEC4B/A",
    "orderNumber": "PONUK1873405",
    "orderDateTime": "2026-03-30T05:00:00Z",
    "purchaseSourceType": "RESELLER",
    "purchaseSourceId": "395E9D0",
    "addedToOrgDateTime": "2026-03-31T10:03:35.108Z",
    "releasedFromOrgDateTime": null,
    "status": "ASSIGNED"
  }
}
```

### AppleCare coverage

```json
{
  "data": [{
    "type": "appleCareCoverage",
    "id": "MXP9G6CNWW",
    "attributes": {
      "description": "Limited Warranty",
      "startDateTime": "2026-01-15T00:00:00Z",
      "endDateTime": "2027-01-14T00:00:00Z",
      "status": "ACTIVE",
      "agreementNumber": null,
      "isRenewable": false,
      "isCanceled": false,
      "paymentType": "NONE",
      "contractCancelDateTime": null
    }
  }]
}
```

An expired device returns an `INACTIVE` record rather than an empty array. **Handle the empty array
anyway** — it occurs, and it means something different from a failed request.

> **TRAP 5 — timestamp formats are inconsistent between fields.** `addedToOrgDateTime` carries
> fractional seconds; `orderDateTime` and the coverage dates do not. A single `ISO8601DateFormatter`
> fails on one or the other, which shows up as fields that are intermittently and inexplicably blank.
> `ABMDate` tries both.

## Derived values

### Purchase date — `ABMDeviceRecord.purchase`

`orderDateTime` is only trustworthy for some devices:

| `purchaseSourceType` | Meaning of `orderDateTime` | Trust |
|---|---|---|
| `RESELLER` | Genuine reseller order date | Yes |
| `APPLE` | Genuine Apple order date | Yes |
| `MANUALLY_ADDED` | When someone added the device via Configurator | **No** |

For `MANUALLY_ADDED` devices the order date is fabricated from the add operation — one sampled device
was "ordered" on 16 January having been added on the 15th. The warranty start is used instead, which
reflects activation and is a sound proxy.

Resolution order: trustworthy order date → warranty start → date added to ABM → unknown. **The source
is always carried alongside the date** (`ABMPurchaseDateSource`) and shown in the UI and the export.
Presenting an inferred date identically to a known one would be misleading, and this data informs
finance and refresh planning.

Note a further subtlety: on the reseller device above, `orderDateTime` is 30 March but the warranty
starts 19 April — the PO date versus activation, three weeks apart. The order date is preferred because
it is what finance recognises.

### Coverage selection — `ABMDeviceRecord.selectedCoverage`

Coverage is an **array**. Zellis holds only Limited Warranties, but devices with two records do occur
in this tenant, and other tenants show AppleCare contracts alongside. Selection:

1. Prefer records with `status == "ACTIVE"`, taking the latest `endDateTime`.
2. Otherwise the latest record of any status, so the UI can show when cover lapsed.
3. An empty array is represented distinctly from "expired".

Compare `endDateTime` as parsed `Date`s, not strings — see trap 5.

### Lifecycle date

Not an Apple concept and not held by Jamf. Calculated as purchase date plus a configurable interval
(`abmLifecycleYears`, default 4). `Calendar` clamps 29 February to the 28th.

## Caching (mandatory, not an optimisation)

One warranty request per device with no bulk endpoint means a full refresh cannot run on view
appearance. `ABMCache` (an actor) persists a snapshot to Application Support with a **7-day** lifetime,
tagged with the MDM server it was scoped to; a snapshot for a different server is discarded rather than
shown. `ABMFleetStore` is what views read.

**The Computers table must never trigger a request per row.**

The cache holds asset data — serials, models, order numbers — and **never** a credential. Those belong
in `KeychainStore`.

## Error states to keep distinct

Collapsing any pair of these reports a data gap as a fact about the hardware:

| State | Meaning |
|---|---|
| Not configured | No ABM credentials — hide the ABM UI entirely |
| Not in ABM | Serial absent from ABM — an asset management gap worth investigating |
| No coverage record | In ABM, empty coverage array — normal for an older machine |
| Expired | Coverage record, `INACTIVE` |
| Active | Coverage record, `ACTIVE` |
| Unavailable | The coverage request failed — nothing is known either way |

## Verified aggregates (Zellis tenant, 13 August 2026)

Useful as a regression check. The app's refresh summary reproduced the Python extract exactly:

- MDM server `C8F02BFBF40C4A53B99E72EA9076EDFE` returns **153** serials.
- 153 Macs retrieved, **10** out of warranty, **7** with no warranty record, **42** with an inferred
  purchase date, **0** with no purchase date.
- Purchase source splits 90 `RESELLER` / 42 `MANUALLY_ADDED` among the 132 in Jamf, matching the
  date-source split exactly.
- Jamf holds 132 of those 153; the remaining 21 are assigned in ABM but not enrolled
  (`ABMUnmatchedSheet`).

| Serial | Expectation |
|---|---|
| `MXP9G6CNWW` | `MANUALLY_ADDED`. Purchase 2026-01-15 from warranty start, **not** the 2026-01-16 order date. Warranty ends 2027-01-14, `ACTIVE`. |
| `M79F6W44VV` | `RESELLER`. Purchase 2026-03-30 from `orderDateTime`. Order `PONUK1873405`. Warranty 2026-04-19 → 2027-04-18, `ACTIVE`. |
| `C02DR4J3Q6LT` | Out of warranty. Ended 2021-12-03, `INACTIVE`. Lifecycle long past. |

## Credential handling

- Client ID, Key ID and the private key live in the **Keychain** (`KeychainStore.Key.abm…`), never in
  `UserDefaults`.
- The private key is deliberately **not** a `@Published` property — `hasABMPrivateKey` is published
  instead, and the PEM is read only to sign an assertion. Never bind it to a control, log it, or write
  it to an exported file.
- The MDM server identifier (`abmMDMServerId`) and lifecycle interval (`abmLifecycleYears`) are
  non-secret settings in `@AppStorage`.

See `.claude/rules/auth-and-credentials.md` for the full rules.

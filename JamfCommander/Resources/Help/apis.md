# Which APIs this app uses

Written for whoever has to approve this app before it is pointed at a production tenant. Jamf
Commander talks to **three Jamf APIs and one public file**, and nothing else.

Everything it does, it does with credentials you create and can revoke. It has no server of its own,
sends nothing to the author, and holds no data outside your Mac.

## 1. The Jamf Pro Classic API

`https://yourcompany.jamfcloud.com/JSSResource/…`

The older of Jamf Pro’s two APIs, and the one that still serves configuration profiles, policies and
package records in the detail this app needs. Reads come back as JSON; **writes are sent as XML**.

Used for: listing and inspecting policies and profiles, moving them between categories, changing
scope, cloning, and deleting.

## 2. The Jamf Pro API

`https://yourcompany.jamfcloud.com/api/v{n}/…`

The current API. JSON in both directions. The version number is **per resource**, not per app —
computer inventory is `v3` while most others are `v1` — so there is no single version to allow.

Used for: computer inventory, scripts, categories, package upload, Self Service icons, and the
OAuth token itself.

Both of these use the **same credential**: the API Client you create in Jamf Pro, described in
*Creating the API client in Jamf Pro*, with the privileges in *Privileges*.

> **Note:** Authentication is OAuth client credentials. The app exchanges the client ID and secret
> for a bearer token, holds that token **in memory for the session only**, and never writes it to
> disk.

## 3. The Platform API Gateway

`https://{region}.api.jamfcloud.com` — where region is `us`, `eu` or `apac`.

A different host, a different credential and a different permission model. It serves **Blueprints**
and the device groups they are scoped to.

A Jamf Pro API client cannot reach it at all, whatever privileges you give it: this needs an
integration created in **Jamf Account**, granted capabilities rather than Jamf Pro privileges. See
*Creating the Blueprints integration*.

Used only by the Blueprints module. If you are not using Blueprints, do not create this credential
and the module will simply say it is not configured.

> **Warning:** Platform API tokens are **region-locked**. A token issued for one region is refused by
> another, so the region must match where your instances are hosted or every call fails with a 401.

## 4. Installomator’s label list, from GitHub

`https://raw.githubusercontent.com/` and `https://api.github.com/` — unauthenticated, read-only,
and outbound only.

The Installomator module reads the list of application labels, and the per-label explanations, from
the Installomator project’s public repository. The Dashboard additionally asks GitHub when that
label list last changed, so the Installomator tile can show the date. Those are the only requests
this app makes to anything that is not Jamf, and neither sends anything about your tenant.

If your network blocks them, the Installomator module says so and the rest of the app is unaffected.

> **Note:** The date lookup is rate limited by GitHub to 60 requests an hour per address, shared
> across everything on your network that asks unauthenticated. If it is refused, the Dashboard tile
> shows the label count without a date and nothing else changes.

## For a firewall or proxy allowlist

- `yourcompany.jamfcloud.com` — your own Jamf Pro instance, whatever its hostname is
- `us.api.jamfcloud.com`, `eu.api.jamfcloud.com` or `apac.api.jamfcloud.com` — only if you use
  Blueprints, and only your own region
- `raw.githubusercontent.com` and `api.github.com` — only if you use the Installomator module

All outbound, all HTTPS. The app listens on nothing.

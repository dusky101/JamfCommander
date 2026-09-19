# Getting connected

Jamf Commander signs in to your Jamf Pro tenant with OAuth client credentials — an API Client created
in Jamf, not your own admin login. You need three things:

- The Jamf instance URL, for example `https://yourcompany.jamfcloud.com`
- A Client ID
- A Client Secret

Enter them under **Settings → Jamf Connections** in the sidebar, then choose **Initialise
Connection**. Once saved, the app reconnects automatically each launch.

*Creating the API client in Jamf* covers making the client, and *Privileges* covers what to grant it.

> **Note:** The bearer token is held in memory for the session only and is never written to disk.

## Settings has two tabs

- **General** — how the app behaves. Currently the hover explanations on the sidebar, and the control
  that brings them all back once you have dismissed them.
- **Jamf Connections** — the credentials above, the separate Blueprints integration, and importing or
  exporting a settings file.

## Blueprints needs different credentials

The Blueprints module does **not** use the API client above. Blueprints are served by Jamf’s Platform
API Gateway, which is a different host with its own integration, created in **Jamf Account** rather
than in Jamf Pro. A Jamf Pro API client cannot reach it, whatever privileges you give it.

Its settings live under **Settings → Jamf Connections → Platform API — Blueprints**, and there is a
**Test Connection** button there that proves the credentials, the region and the environment ID in
one go. Until those are filled in, the Blueprints module says so and offers a button straight to
Settings.

> **Warning:** Platform API tokens are region-locked. A token issued for one region is refused by
> another, so the region must match where your instances are actually hosted or every call fails with
> a 401.

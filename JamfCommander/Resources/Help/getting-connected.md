# Getting connected

Jamf Commander signs in to your Jamf Pro tenant with OAuth client credentials — an API Client created
in Jamf, not your own admin login. You need three things:

- The Jamf instance URL, for example `https://yourcompany.jamfcloud.com`
- A Client ID
- A Client Secret

Enter them under **Settings → Jamf Connections** in the sidebar.

```figure
connection-settings
```

The instance URL (**1**) is your Jamf Pro address and nothing more — no `/JSSResource`, no trailing
path. The client ID (**2**) and secret (**3**) come from the API client you create in Jamf Pro.
Then choose **Initialise Connection** (**4**). Once saved, the app reconnects automatically each
launch.

*Creating the API client in Jamf* covers making the client, and *Privileges* covers what to grant it.

> **Note:** The bearer token is held in memory for the session only and is never written to disk.

## Settings has two tabs

- **General** — how the app behaves. Currently the hover explanations on the sidebar, and the control
  that brings them all back once you have dismissed them.
- **Jamf Connections** — the credentials above, the separate Blueprints integration, and importing or
  exporting a settings file.

## Blueprints needs different credentials

The Blueprints module does **not** use the API client above, and no amount of Jamf Pro privileges
will make it. Blueprints are served by Jamf’s Platform API Gateway: a different host, with its own
integration created in **Jamf Account** rather than in Jamf Pro.

Its settings live under **Settings → Jamf Connections → Platform API — Blueprints**, and there is a
**Test Connection** button there that proves the credentials, the region and the environment ID in
one go.

*Creating the Blueprints integration* is the whole of it, start to finish. Skip that page if you are
not using Blueprints — nothing else in the app needs these credentials.

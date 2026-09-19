# If something fails

- **Refused (401)** — the session expired. Reconnect from Settings.
- **Not permitted (403)** — the API role is missing a privilege. Add it in Jamf and reconnect. For
  the Blueprints module a 403 can also mean the integration's scope level is wrong, rather than a
  missing capability.
- **Name already exists (409)** — Jamf requires unique policy and package names. Change the name
  template, or deselect that item.
- **No labels in Installomator** — GitHub could not be reached, or no Installomator script exists in
  Jamf. See *Before using Installomator*.
- **Blueprints says it is not configured** — the Platform API integration has not been filled in.
  It is separate from the Jamf Pro API client; see *Getting connected*.

> **Note:** Actions that change Jamf always ask for confirmation first and then report the real
> outcome for each item. If something failed, the results sheet says why — nothing is reported as
> successful unless Jamf confirmed it.

## Something looks like it has hung

Several actions read **every policy in the tenant**: the Unused audit, the Packages **Deployed** tab,
and Export All. Jamf offers no way to ask "which policies use this package", so the only way to
answer it is to read them all. On a large instance that is tens of seconds.

The app shows progress while it does this rather than pretending to be finished, but it is the most
common reason for thinking it has stopped responding.

Bulk operations are also deliberately paced — small batches with gaps between them — so that a large
run does not trip Jamf's rate limiting and start failing part-way through. That pacing is why they
are not faster, and removing it would make them less reliable rather than quicker.

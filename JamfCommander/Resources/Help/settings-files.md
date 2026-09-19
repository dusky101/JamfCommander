# Sharing your settings

**Settings → Jamf Connections → Export** writes a `.jamfconfig` file so the same connection can be
set up on another Mac without retyping it. **Import** reads one back in and fills the fields.

A `.jamfconfig` file contains:

- Jamf instance URL
- Client ID
- Client Secret
- The Blueprints integration — region, environment ID, client ID and secret — when one is configured
- Export date, app version, and a file signature

> **Warning:** These files are Base64 encoded for light obfuscation — they are **not encrypted**. A
> `.jamfconfig` file is a secret: treat it exactly as you would the client secret itself, and only
> move it through channels you would trust with a password. Never email one, and never commit one to
> source control.

## Importing over an existing setup

An import replaces the Jamf Pro credentials outright. The Blueprints values are treated more
carefully: a file written before this app had Blueprints carries none, and importing it leaves
whatever you already have in place rather than blanking a working integration.

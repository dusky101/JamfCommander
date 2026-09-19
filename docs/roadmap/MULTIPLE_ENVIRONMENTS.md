# Roadmap — multiple Jamf environments

## What

Hold the settings for more than one Jamf tenant, and switch between them from inside the app.

In the maintainer's words: *"I would love to be able to save multiple Jamf environments. So for
instance I have the settings for Zellis which I currently have and then an option to add another Jamf
instance, with different API settings, and so on, so that MSPs could have the config for the
companies they look after at a touch of a button instead of having to log into multiple webpages."*

So: a named list of environments rather than one set of credentials, and a way to change which one is
live without going through Settings and pasting a different client secret each time.

## Why

Today the app holds exactly one tenant. `jamfInstanceURL`, `clientId` and `clientSecret` are single
`@AppStorage` keys, and the four Platform API keys beside them are the same. Working against a second
tenant means overwriting the first — or keeping a `.jamfconfig` per customer and importing the right
one each time, which is the workaround the export feature accidentally became.

Two audiences want this for different reasons:

- **An MSP** manages several customers' Jamf instances. Every task means picking the right one, and
  the cost of picking wrong is a bulk change landing on somebody else's fleet.
- **This maintainer** has Production and Sandbox. The project's own advice — in `JamfCommander/README.md`
  and invariant 1 — is to rehearse destructive flows on a non-production tenant first. That advice is
  followed less often than it should be precisely because switching is tedious.

The safety argument is the stronger one. An app whose next action might be a bulk delete should make
"which tenant am I pointed at" impossible to get wrong, and right now the only answer on screen is a
URL in Settings.

## What it touches

Wider than it first looks, because "the current credentials" is assumed nearly everywhere.

- **Storage.** Eleven views read `@AppStorage("jamfInstanceURL")` directly, plus `clientId`,
  `clientSecret`, and the four `PlatformCredentialsStore` keys. All of that becomes "the selected
  environment's value". The natural shape is a list of environment records plus a selected id, behind
  an accessor, rather than scattering lookups through the views.
- **`JamfAPIService`.** One `@StateObject` in `ContentView` holds the token in memory. Switching
  environment must drop that token and everything fetched with it.
- **Every module's state.** Each dashboard holds its results in `@State`. Switching tenant while a
  module is open must not leave one tenant's policies on screen under another tenant's name.
- **`PlatformAPISession`.** Already notices a credentials change and re-requests its token
  (`PlatformCredentials: Equatable`); worth reading before designing the Jamf Pro equivalent, because
  the problem is the same one.
- **`.jamfconfig`.** Import and export currently carry one environment. They would need to carry one
  named environment, or several — and a file written by the current build must keep importing.
- **The UI.** An environment picker somewhere permanent, and the name visible while working.

## Known traps

**1. The selected environment must be obvious at all times, not just in Settings.** This is the whole
safety case. A picker buried in a sheet, with nothing on screen during a bulk delete, would make the
app more dangerous than the single-tenant version it replaces — somebody who previously *knew* there
was only one tenant would now be guessing. Whatever is built must name the live environment somewhere
that is always visible, and ideally make Production visually distinct from Sandbox.

**2. Secrets multiply.** One client secret in `UserDefaults` in clear is already the known weak point
(`.claude/rules/auth-and-credentials.md`); a dozen customers' secrets in clear is a different
proposition, and an MSP's threat model is not this maintainer's. This is the change that turns
"move to the Keychain" from an improvement into a prerequisite. Decide that deliberately rather than
shipping the list first and hardening later.

**3. Nothing in flight may cross environments.** Every module runs throttled batch work — the Unused
audit and the package scan read every policy in the tenant and take tens of seconds. A switch part-way
through must cancel that work and discard its results, not let them land against the new tenant. Note
the existing rule that a cancelled request is never retried (`JamfAPIService.swift`), which this
depends on rather than changes.

**4. Caching, if it happens, must be keyed by environment.** `docs/roadmap/CACHING.md` already records
this trap for the same reason. The two features share the failure: showing one tenant's data while
connected to another. If both are built, they are one design decision, not two.

**5. Per-environment Platform API credentials.** Blueprints uses a separate integration created in
Jamf Account, region-locked, with its own environment ID. An MSP's customers would each have their
own, so these travel with the environment rather than sitting beside it. A tenant with no Platform
integration is normal and must not read as an error.

## Open questions

1. **How many, realistically?** A handful, or dozens? A picker suits five; a searchable list suits
   fifty, and the difference changes the UI rather than the storage.
2. **Keychain now, or a list in `UserDefaults` first?** See trap 2. This is the decision that sets the
   size of the work.
3. **What does an environment record hold** beyond the credentials — a display name, a colour or badge,
   a "this is production" flag that changes how confirmations read?
4. **Does switching require re-authenticating**, or does the app hold a token per environment? Holding
   several live tokens is faster and is more credential surface in memory at once.
5. **What happens to `.jamfconfig`?** One file per environment, or one file carrying several? Either
   way an existing single-environment file must still import.
6. **Should destructive actions name the environment in their confirmation?** `CommanderConfirmation`
   already states the instance for some flows. With several configured, arguably every one should.

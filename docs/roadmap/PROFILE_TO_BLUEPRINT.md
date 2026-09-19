# Roadmap — recommend which profiles should become blueprints

## What

In the Profiles module, say which configuration profiles have a declarative equivalent and ought to
move to Blueprints.

In the maintainer's words: *"a section in the profiles section that recommends which ones should be
moved to blueprints"*.

So: an administrator looking at 152 profiles is told which of them Apple now expects to be
declarations, and which are fine where they are.

## Why

Apple is moving management from the configuration profile to declarative device management. A
profile is pushed and hoped for; a declaration is a state the device maintains and reports back on.
Payload by payload, Apple keeps publishing declarative replacements, and the profile equivalents keep
becoming the older way of doing the same thing.

Nobody has a list of which of *their own* profiles that applies to. Jamf Pro does not offer one. The
only way to find out today is to read every profile, know the declaration catalogue by heart, and
cross-reference the two by hand — for 152 profiles, on a catalogue that changes every autumn.

**This app is unusually placed to answer it**, and that is the whole case for building it here rather
than anywhere else. It already reads every configuration profile in the tenant *and* creates
blueprints. Nothing else in a Jamf administrator's toolkit has both halves open at once. The Blueprints
module currently starts from a blank editor, which assumes you already know what you want to build;
this is the question that comes before that one.

It also has a second, quieter use: **finding the ones that have already moved.** A blueprint that
duplicates a profile still deployed to the same Macs is a real misconfiguration, and the same
comparison surfaces it.

## What it touches

- **`Modules/Profiles/`** — wherever the recommendation is surfaced: the dashboard rows, the
  inspector, or a view of its own.
- **The profile payload, which nothing currently parses.** `ProfileDetail` models only `general` and
  `scope`. The full record does already come back — `JamfAPIService.fetchProfileJSON(id:)` fetches it
  and the inspector renders it as raw JSON — so the data is in hand; reading the payload types out of
  it is new work.
- **A mapping from profile payload type to declaration type.** This does not exist anywhere in the
  codebase and is the substance of the feature. See the traps.
- **`Modules/Blueprints/`**, if the recommendation goes as far as offering to draft the blueprint.
- **`Modules/Computers/`**, if OS versions are taken into account — the fleet's OS spread is already
  fetched there, but the Profiles module has no access to it today and there is no shared cache
  (see `CACHING.md`).

## Known traps

- **The mapping is the feature, and it goes stale on a fixed schedule.** Apple adds declaration
  types every OS release. A table compiled into the app is out of date the week after WWDC, and an
  out-of-date recommendation is worse than none — it will confidently tell somebody there is no
  equivalent when there has been one for a year. Jamf's own DDM Explorer reads its catalogue from
  data files in a repository rather than hardcoding it, for exactly this reason. The app already
  reads a published list off `raw.githubusercontent.com` for Installomator, so the pattern and the
  network path both exist.

- **"Has an equivalent" is not "should move".** A declaration often supports fewer keys than the
  profile payload it replaces, and usually needs a newer macOS than some of the fleet runs. A
  recommendation that ignores either would tell an administrator to break working management. What
  the recommendation is allowed to claim matters more than how it is displayed.

- **It must never migrate anything by itself.** A migration is a delete and a create, both
  irreversible, against production. Worse, a blueprint is created **undeployed** — so a naive
  "migrate this" that removed the profile and created the blueprint would leave those Macs managed by
  neither until somebody noticed.

- **Scope does not carry across.** A profile is scoped to Jamf computer groups, buildings and
  departments; a blueprint is scoped to **platform** device groups from a different API entirely.
  Even a careful hand migration is not a like-for-like scope copy, and anything that implies
  otherwise is misleading. See `BLUEPRINTS_HANDOVER.md`.

- **Not every payload may be readable.** Whether the Classic API returns a usable payload for
  *every* profile — signed and encrypted ones in particular — is unverified. A profile whose payload
  cannot be read must be reported as "cannot tell", never as "no equivalent found", for the same
  reason the Unused audit treats an unreadable scope as scoped.

- **Read-every-profile is already a slow path in this app.** Hydrating profiles is throttled on
  purpose. Whatever this becomes must not add a second full pass, and must not run on module open or
  on a keystroke.

## Open questions

1. **Where does it live?** A badge on each row, a column, a filter alongside the existing ones, or a
   separate view that lists only the candidates? The last of those is closest to the maintainer's
   phrasing ("a section in the profiles section") but it is the one guess in this entry.
2. **Advice only, or a draft?** Does it stop at "this could be a blueprint", or does it hand you the
   declaration JSON to review in the Blueprints editor?
3. **Where does the catalogue come from?** Hand-maintained in the repository, read from a published
   source, or derived from what the Platform API itself will accept?
4. **How much does OS version count?** Including it makes the advice trustworthy and couples Profiles
   to data the Computers module fetches. Excluding it is simpler and less safe.
5. **Does it also flag the reverse** — a blueprint and a profile doing the same job to the same Macs?
6. **Mobile devices.** The declarative story is further along on iOS than on macOS, and this app is
   Macs only. If mobile ever lands, does this feature grow to cover it, or was it always a macOS
   profile question?

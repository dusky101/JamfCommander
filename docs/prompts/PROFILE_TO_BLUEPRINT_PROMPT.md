# Prompt — Profiles → Blueprints recommendations

**Written 22 September 2026, against app version 9.0.** The code facts below were checked that day;
re-check anything you are about to rely on.

The maintainer's view of this one, in his words: **"this profile to blueprint is a game changer"**.
Treat that as the reason it is worth doing properly rather than quickly.

---

## Hand the session this

```
Read docs/prompts/START_HERE.md and follow it, then read CLAUDE.md's safety invariants and
treat them as binding. This app writes to a live production Jamf instance.

Then read these, in this order:
  docs/roadmap/PROFILE_TO_BLUEPRINT.md    — the intent, the traps, and six open questions
  docs/handovers/BLUEPRINTS_HANDOVER.md   — what is actually proven about the Blueprints half
  docs/prompts/PROFILE_TO_BLUEPRINT_PROMPT.md — this file: the code facts and the session's shape

The goal: in the Profiles module, tell an administrator which of their configuration
profiles Apple now expects to be declarations, and which are fine where they are.

**Do not write the feature in this session.** Write the spike described below, get an
answer, and bring me a recommendation. The roadmap entry says the mapping IS the feature,
and it does not exist anywhere in the codebase — so the first question is not how to
display it, it is whether the data to build it on exists at all.

Phase 1, and possibly the whole session: find out where the catalogue comes from.

A payload-to-declaration table compiled into this app is stale the week after WWDC, and a
stale recommendation is worse than none — it will confidently tell somebody there is no
declarative equivalent when there has been one for a year. So a hand-authored table in
Swift is not an acceptable answer, however quick.

The candidate is Apple's own published device-management schema — the data DDM Explorer
reads, in Apple's `device-management` repository on GitHub. **I have not verified it.**
Find out, and answer these:

  - Is there a machine-readable list of declaration types, and of profile payload types?
  - Does it carry per-key OS availability? That decides whether the advice can say
    "should move" rather than only "has an equivalent" — see the roadmap's second trap.
  - Can a payload → declaration mapping be DERIVED from it, or does somebody still have
    to author the correspondence by hand? If the latter, how much of it, and where does
    it live so it can be updated without shipping a build?
  - Is it licensed and stable enough to depend on?

The app already has the pattern and the network path for exactly this: it reads the
Installomator label list off raw.githubusercontent.com unauthenticated. See
JamfAPIService+InstallomatorLabels.swift — copy that shape, including its failure
behaviour. Nothing about this feature may require the Jamf credentials.

If the answer is no — no usable published catalogue — say so plainly and stop. That is a
successful session: it saves a feature that would lie every autumn. Put the finding in
the roadmap entry and leave it there.

If the answer is yes, bring me the four decisions the roadmap lists as open questions 1
to 4, with a recommendation on each, and THEN we scope the build.

Build after every phase. There is no test target — do not claim tests ran. I run the app
myself, so do not launch it; tell me what to look at. Hand me any file you produce.
```

## Code facts, checked 22 September 2026

Save the session from re-deriving these.

- **Nothing parses a profile's payload.** `ProfileDetail` (`Models/JamfModels.swift:132`) models
  `general`, `scope` and `scopeTargets` — and nothing else. The payload is not modelled anywhere.
- **The data is already in hand.** `JamfAPIService.fetchProfileJSON(id:)`
  (`Services/JamfAPIService.swift:546`) fetches the full record and the inspector renders it as raw
  JSON. So the payload arrives today and is thrown away, the same way `lastContactTime` was before
  22 September — check what the response actually contains before designing around a guess.
- **The published-list pattern exists.** `Services/JamfAPIService+InstallomatorLabels.swift` is an
  unauthenticated GET to `raw.githubusercontent.com`, with its own failure handling and no Jamf
  credentials involved. That is the shape a catalogue read should copy.
- **Reading every profile is already a slow, throttled path.** Batches of 10 with 0.5s gaps and three
  attempts, and `fetchProfiles` will not cache a list with holes in it. That throttling is load
  bearing — it was added on 20 September after an unbounded fan-out over 152 profiles made the Unused
  count wander between 120 and 133. **Do not add a second full pass over the profiles.**
- **`ConfigProfile.scopeIsKnown` exists for a reason** worth copying here: the Unused audit refuses to
  judge a profile whose scope it could not read, rather than treating unread as unscoped. A profile
  whose payload cannot be read must report **"cannot tell"**, never "no equivalent found".
- **Blueprints is a different API with different credentials** — the Platform API Gateway, region
  locked, configured in Jamf Account rather than Jamf Pro. A Jamf Pro API client cannot reach it. So
  the recommendation must still work for somebody who has never configured Blueprints at all, or the
  feature is invisible to most of its audience.
- **Blueprint scope is not profile scope.** A profile targets Jamf computer groups, buildings and
  departments; a blueprint targets **platform** device groups from that other API. There is no
  like-for-like copy, and anything implying otherwise misleads.

## Hard constraints

- **It must never migrate anything.** A migration is a delete and a create, both irreversible,
  against production — and a blueprint is created **undeployed**, so a naive "migrate this" would
  leave those Macs managed by neither until somebody noticed. Advice, or at most a draft the
  administrator reviews and deploys themselves.
- **"Has an equivalent" is not "should move".** A declaration often supports fewer keys than the
  payload it replaces and usually needs a newer macOS than some of the fleet runs. What the
  recommendation is *allowed to claim* matters more than where it is displayed.
- **Never invent an endpoint or a payload shape** — invariant 2. That applies to Apple's schema as
  much as to Jamf's: read it, do not assume its shape from memory.
- Nothing may run on module open or on a keystroke. Several actions in this app already read the
  whole tenant and take tens of seconds.

## Why there is no handover yet

`docs-workflow.md` asks for a handover alongside the prompt. There is deliberately none: a handover
records **what is proven against the live tenant versus what merely compiles**, and nothing is built.
Write `docs/handovers/PROFILE_TO_BLUEPRINT_HANDOVER.md` when the spike concludes, because that is the
first moment there is any state to hand over — starting with whether the catalogue exists.

## If he would rather do something else

- **`docs/roadmap/APP_STORE.md`** — three concrete code items, of which moving the client secret out
  of `UserDefaults` into the Keychain is the one worth doing whether or not the store ever happens.
- **`docs/roadmap/SHEET_NAVIGATION.md`** — two conversions left, `BlueprintEditorSheet` and
  `PackageUploadPage`. The most shovel-ready thing on the board; its handover records every trap the
  first two hit.
- **The four loose ends at the foot of `docs/handovers/DASHBOARD_HANDOVER.md`**, starting with the
  duplicate ISO-8601 parser.
- **Not `SCRIPT_USAGE.md`.** The maintainer said on 22 September 2026 that it is not a useful
  feature. Do not suggest it; the entry should probably be deleted.

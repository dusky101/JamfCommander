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

**Build the smallest honest version first, and stop there for review.** The roadmap entry
says the mapping IS the feature — that was written before anybody read Apple's schema, and
it is now only half true. Apple states the deprecation itself, so the first useful answer
needs no mapping. Do that one, show me, and we will scope the rest from what it finds.

Phase 1: the smallest true thing, which needs no mapping at all.

**The catalogue question is answered.** Apple publishes its own MDM and DDM schema at
github.com/apple/device-management — MIT licensed, Apple-maintained, no pull requests
accepted, branch `release`. Verified 22 September 2026 by reading it:

  - `mdm/profiles/<payloadtype>.yaml` is filed BY PAYLOAD TYPE. A profile in the tenant
    matches by direct lookup — e.g. com.apple.mobiledevice.passwordpolicy.yaml. It carries
    `payload.supportedOS.macOS.deprecated: '27.0'` where Apple has deprecated it, and
    `introduced` where it has not.
  - `declarative/declarations/configurations/*.yaml` each carry a `declarationtype`
    (com.apple.configuration.passcode.settings), `payload.supportedOS.macOS.introduced`,
    and — this is the valuable part — a `supportedOS` on INDIVIDUAL `payloadkeys`.
  - Raw files fetch from raw.githubusercontent.com, unauthenticated, exactly like the
    Installomator label list this app already reads.

So do NOT start with a payload-to-declaration mapping. Start with the one thing Apple
states outright:

    "37 of your 152 profiles use a payload Apple deprecated in macOS 27.0."

Read each profile's PayloadType, look up the file of that name, read one key. Entirely
mechanical, no editorial judgement, no table to go stale — and already the answer nothing
else in a Jamf administrator's toolkit will give them. Get that on screen and correct
before anything cleverer.

What is genuinely still open, for later phases and for me to decide:

  - **Pairing a deprecated payload to the declaration that replaces it.** Apple does not
    state the correspondence. The deprecation flag narrows it from "every payload" to "the
    deprecated ones", and the names are close (passwordpolicy → passcode.settings) with
    overlapping key names to corroborate against (forcePIN → RequirePasscode). Propose how,
    and how confident it can honestly claim to be, before building it.
  - **The OS floor.** Per-key `supportedOS` is what lets the advice say the replacement
    needs macOS 13.1 and four Macs do not run it. That couples Profiles to fleet OS data
    the Computers module fetches and Profiles cannot reach today. Worth it, but it is a
    second phase, not the first.
  - Where it is surfaced (roadmap question 1), and whether it ever drafts a declaration
    (question 2). Bring me a recommendation; do not guess.

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
Write `docs/handovers/PROFILE_TO_BLUEPRINT_HANDOVER.md` when phase 1 lands, because that is the first
moment there is any state to hand over. Its first proven row is already written for it: **Apple's
schema carries per-OS deprecation on profile payloads and per-key OS availability on declarations —
read on 22 September 2026, not assumed.**

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

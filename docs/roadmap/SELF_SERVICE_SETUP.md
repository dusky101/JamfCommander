# Roadmap — let the app set up its own API role

## What

In Settings, the administrator supplies a **starter API client** that can only manage API roles and
integrations. The app uses it once to create the role and client it actually needs, stores those, and
the starter key is never seen again.

In the maintainer's words: *"the user adds this api setup key. and then the app goes off and creates a
new api setup specifically for the app."*

The starter client he has already made carries exactly six privileges:

```
Create API Integrations    Read API Integrations    Update API Integrations
Create API Roles           Read API Roles           Update API Roles
```

**Blueprints stays manual.** Its integration is created in Jamf Account, on a different API with
different credentials, and nothing in Jamf Pro can create it.

A second, smaller feature falls out of the same endpoint work and is described at the end:
**Check my privileges**, for anybody who sets the role up by hand.

## Why

Setup is the hardest part of this app by a distance. The guide spends four pages on it — *Which APIs
this app uses*, *Creating the API client in Jamf Pro*, *Privileges*, *Getting connected* — and the
*Privileges* page alone asks an administrator to tick around thirty boxes across nine object types,
correctly, before anything works at all. Get one wrong and the failure arrives later as a 403 in one
module, which is what the whole *If something fails* page is about.

This replaces that with one paste.

## The security question, and why it is not the blocker it first looks like

Worth recording in full, because the first answer given to this idea was **wrong** and somebody will
reach for it again.

The objection raised was that a key able to create API roles is a privilege-escalation primitive: it
can mint a role with privileges the app's own role does not have — FileVault recovery key access,
remote wipe, user account management — and is therefore more dangerous than the credential the app
uses today. That much is true in raw capability.

**It does not follow that the idea is bad**, for three reasons the maintainer gave:

1. **The app's own role is already enormous.** Delete on Policies, Profiles, Packages, Scripts and
   Categories across a whole tenant. Anybody who can drive this app can already destroy the estate.
2. **The human doing the setup already has that authority.** They are a Jamf administrator with a
   console account that can do all of it and more. The starter key grants the *person* nothing new.
3. **It is used once.** A capability that exists for the length of a setup flow is not the same risk
   as one granted permanently.

The objection also confused two different things: the privileges the app asks a **security team to
approve** (the Privileges page) versus a key the administrator **temporarily supplies from their own
authority**. The security team still approves the role the app ends up with. Nothing about this asks
them to approve role creation.

### The one rule that makes it safe

What *is* real is narrow, and it is about this app specifically rather than about the idea:
credentials currently live in `UserDefaults` — a plaintext plist in the container — and `.jamfconfig`
exports are base64-obfuscated and explicitly not encrypted. So:

> **The starter key lives in memory for the duration of setup. It is never written to disk, never
> placed in `UserDefaults`, never included in a `.jamfconfig` export, and is discarded the moment the
> created client has authenticated successfully.**

Not negotiable, and not a hardship — it falls out of the flow naturally. With it, the difference
between this and what the app already holds is transient and small.

It would also be worth doing `docs/roadmap/APP_STORE.md`'s Keychain item first or alongside. Minting a
credential into a plaintext plist is a worse look than storing one that was pasted there.

## What it touches

- **`Auth/ConfigurationView.swift`** and the Jamf Pro credentials section — where the starter key is
  entered and the flow is driven from.
- **A new `JamfAPIService` extension** for the role and integration endpoints. It does not belong in
  any existing one: `+Dashboard` and the rest are about tenant objects, this is about the app's own
  access.
- **`Services/SettingsTransfer.swift`** — to guarantee the starter key cannot reach an export. That
  file already owns what an export *means*, including the merge rules, so the exclusion belongs there
  rather than at the call site.
- **The guide.** `api-client.md` becomes "do this, or paste a starter key and let the app do it", and
  `privileges.md` gains whatever privilege "Check my privileges" needs. Four pages of setup getting
  shorter is part of the value.

## Known traps

- **A client secret is returned once and cannot be retrieved again.** So the sequence must be: create
  the role → create the integration → generate credentials → store them → **authenticate with them to
  prove they work** — and if any step after generation fails, the tenant is left holding an
  integration whose secret nobody has. That needs a real recovery path, not a thrown error: at
  minimum, name the orphaned integration on screen so the administrator can delete it in Jamf.

- **Privilege names are exact strings.** "Update Policies" and its thirty siblings must match Jamf's
  vocabulary precisely, and a typo yields a role that silently lacks a privilege — surfacing weeks
  later as a 403 in one module. Jamf exposes an endpoint listing valid privilege names; **validate
  against it rather than trusting a hardcoded array**, and report any name the tenant does not
  recognise instead of creating a role with a hole in it.

- **Re-running it.** Version 10 will need a privilege version 9 did not. Always creating means a
  tenant accumulating `Commander`, `Commander 2`, `Commander 3` with nobody knowing which is live.
  Find the existing role by name and **update** it; only create when there is none.

- **The starter key's own privileges are not the app's.** A starter key can create a role but cannot
  read a policy. So the app cannot validate the tenant, list anything, or fall back to normal
  operation while holding only the starter key — the setup flow has to be genuinely separate from
  the connected state, not the login screen with different credentials.

- **It must not become the only way in.** Plenty of administrators will not be given a role-creating
  key, or will refuse to use one. The hand-built path stays first-class, and the guide keeps its
  instructions.

- **Creating an API role is a write against production.** Invariant 1 applies: it needs an explicit
  confirmation showing exactly what will be created and with which privileges, and it must report the
  real outcome rather than assuming success.

## Open questions

1. **Does the app delete the starter integration afterwards?** It could, with `Update`/`Delete` on
   integrations — leaving the tenant clean. Against: deleting something the administrator made, on
   their behalf, is a surprise, and they may want to reuse it on the next Mac.
2. **Does it show the created secret to the administrator?** They may want it for their own records,
   and they cannot get it from Jamf afterwards. Against: it then needs to be displayed somewhere, and
   invariant 4 says a secret is never shown in the UI.
3. **What is the created role called?** It has to be found again by name on a later run, so the name
   is effectively an identifier. `Commander` collides with a hand-made one.
4. **Which privileges does it grant?** Everything on the Privileges page, or only what the modules the
   administrator intends to use need? The second is better least-privilege and much more UI.
5. **Does an existing hand-made role get adopted rather than replaced**, if one is found?

---

# Sibling — "Check my privileges"

## What

A button in Settings, beside the Jamf Pro credentials: read the role attached to the credential the
app is **already** using, compare it against what each module needs, and list what is missing.

> *Missing `Update Policies` — Installomator deployment will create policies but every Self Service
> icon will fail to attach.*

## Why

This is the smaller, safer half of the idea above, and it earns its place independently.

Every hand-built role is a chance to miss a checkbox, and the symptom is a 403 in one module, weeks
later, with nothing tying it back to the setup. The guide has a whole page about what refusals mean
precisely because this happens. Turning *"why did this fail"* into *"your role is missing this exact
privilege, and here is what stops working"* removes the most common support problem the app has.

It needs no escalation — only `Read API Roles` on the app's own role — and it is useful to somebody
who never touches the starter-key flow at all.

**It is also the honest fallback** if the flow above is judged too much: the app cannot set the role
up for you, but it can tell you precisely where yours is wrong.

## What it touches

- The same role-reading endpoint work as the flow above, which is why they belong in one entry.
- `privileges.md`, which gains `Read API Roles` — and a note that without it the check itself cannot
  run, which is its own small irony to word carefully.
- A **map from privilege to consequence**. The interesting part: not "you lack Update Policies" but
  what that costs, per module. That mapping already exists in prose on the Privileges page and would
  need to become data.

## Known traps

- **Read API Roles may not be grantable to a role that can read itself** — unverified, and the whole
  feature rests on it.
- **A privilege the check does not know about must be reported as unknown, not as absent.** Same rule
  as `ConfigProfile.scopeIsKnown` and the Unused audit: never present an unread state as a negative
  finding.
- **Do not run it on Settings opening.** It is a button.

## Verify before building either of these

Against Jamf's documentation, not from memory — invariant 2:

- The endpoint shapes for creating and updating an API role and an API integration.
- How client credentials are generated, and whether they can ever be regenerated.
- The endpoint that lists valid privilege names.
- Whether a role can read its own definition, and what privilege that needs.

# Installomator

An Installomator policy manager. It does not upload package files — it creates and maintains the Jamf
policies that run the Installomator script, each one installing a named application.

It works by comparing two lists: the policies already in your tenant that run an Installomator script
with a label in parameter 4, and the labels Installomator currently publishes.

Before any of this works, the Installomator script has to exist in Jamf — see *Before using
Installomator*.

```figure
label-states
```

## What you can do

- **See labels four ways** — deployed, missing, available, or all.
- **Search** by application display name or by raw Installomator label, and group the list
  alphabetically or by Jamf category.
- **Create policies** for the labels you select, choosing category, script, a name template, Self
  Service options and icon, scope, and optionally a pinned version.
- **Edit a deployed policy in place**, including the label it installs.
- **Remove deployed policies** from Jamf.
- **Explain This Label** on any row — what that label will actually do on a Mac.

## The four states on a row

- **Deployed** — a policy runs an Installomator script with this label in parameter 4. The script is
  matched by name *or* by ID, so one that has been renamed is still recognised once you have deployed
  with it at least once.
- **Possibly Deployed** — the application appears to be installed by some other policy, which is
  named on the row. It stays selectable, because the match is a hint rather than a certainty.
- **Available** — published by Installomator, not deployed here.
- **Missing** — deployed here, and **no longer published by Installomator**.

## Missing is the one to act on

Labels are withdrawn upstream from time to time, and the Jamf policy created against one outlives it.
The policy still runs; Installomator simply no longer recognises the label, so it **fails on every
Mac it reaches**, quietly, for as long as it is left in place.

The **Missing** view is exactly that list. Edit the policy to point at a current label, or remove it.

## Creating policies

Select the labels you want and the **deployment sheet** opens. Its six sections are numbered on
screen, and the figure below uses the same numbers.

```figure
installomator-deploy
```

- **1 — Category.** Where the policies are filed. You can create a new one here without leaving
  the sheet.
- **2 — Script.** The Installomator script in your Jamf instance. A script whose name contains
  “Installomator” is pre-selected; if yours is called something else, pick it once and the app
  remembers it.
- **3 — Name template.** `Install {appName}` gives *Install Google Chrome*. `{version}` is
  available once you are pinning versions (**6a**). The preview under the field shows a real name
  before anything is created.
- **4 — Self Service.** Whether the policy appears, and under which category. The icon is uploaded
  once per run and attached to every policy the run creates.
- **5 — Scope.** All computers, specific Macs, or computer groups. The computer list can be
  searched by name, serial, user or email.
- **6 — Version pinning.** Leave it on *Let Installomator decide* unless you have a reason not to;
  see below.

> **Note:** Attaching a Self Service icon needs **Update Policies**, not just Create Policies. With
> Create alone every policy is created and every icon attach fails — and the results sheet says so,
> per policy.

## Pinning a version

By default Installomator installs whatever the vendor currently publishes, which is the point of it.
Pinning is for when you need a specific version — a compatibility freeze, or a staged rollout.

```figure
version-pinning
```

- **6a — Versions.** One policy is created for **each** version you list. Three versions means
  three policies.
- **6b — Overrides.** Installomator variables, with `{version}` substituted into each one. This is
  how a pinned `downloadURL` gets the right version in it.
- **6c — What will be created.** The exact policy names, before you commit to them. Read this.
- **6d — The warning, which is not boilerplate.** A pinned download URL stops working the moment
  the vendor moves or removes that file, and the policy then fails on every Mac it reaches — exactly
  like a **Missing** label, but with no flag to tell you. Pinning an architecture-specific URL is
  worse: it installs the wrong binary on the other architecture. For a genuine split, create one
  policy per architecture and scope each to an architecture-based smart group.

Pinning is available on single-label runs only.

## The labels come from GitHub, not from Jamf

Installomator’s label list is read from the Installomator project’s public repository, fresh on every
refresh rather than from a cached copy — so what you see is what Installomator publishes now, not
what it published the last time the app ran.

This module therefore needs outbound access to `raw.githubusercontent.com`, and the Dashboard tile
asks `api.github.com` when that list last changed. If GitHub cannot be
reached the module says so and marks **nothing** as missing, which is the safe way round: a network
failure must never be read as “these labels have been withdrawn”.

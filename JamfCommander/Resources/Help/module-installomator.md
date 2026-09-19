# Installomator

An Installomator policy manager. It does not upload package files — it creates and maintains the Jamf
policies that run the Installomator script, each one installing a named application.

It works by comparing two lists: the policies already in your tenant that run an Installomator script
with a label in parameter 4, and the labels Installomator currently publishes.

Before any of this works, the Installomator script has to exist in Jamf — see *Before using
Installomator*.

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

## The labels come from GitHub, not from Jamf

Installomator’s label list is read from the Installomator project’s public repository, fresh on every
refresh rather than from a cached copy — so what you see is what Installomator publishes now, not
what it published the last time the app ran.

This module therefore needs outbound access to `raw.githubusercontent.com`, and the Dashboard tile
asks `api.github.com` when that list last changed. If GitHub cannot be
reached the module says so and marks **nothing** as missing, which is the safe way round: a network
failure must never be read as “these labels have been withdrawn”.

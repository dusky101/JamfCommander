# Unused

An audit of things that look like they do nothing, and the means to tidy them up. It sits at the
bottom of the sidebar because it is housekeeping rather than somewhere you work day to day.

## What it lists

- **Policies** that are disabled, or that have nothing scoped to them. Policies that install through
  Installomator are marked as such, since the software they install has no package in the library and
  would otherwise look like an anomaly.
- **Profiles** that have nothing scoped to them. Configuration profiles have no enabled state in
  Jamf, so “not enabled” never applies to one.
- **Packages** in Jamf’s library that no policy installs.

Every row gives the reason it was listed. Alongside the usual category filter there is a row of
reason filters — All, Not enabled, Not scoped, Not attached — and a Select All button.

```figure
unused-reasons
```

## What you can do about it

The three actions are ordered by how easily each can be undone, and that order is deliberate.

```figure
unused-actions
```

- **a — Move to Category** is the primary action, because it is the one you can undo by hand. It
  files the selection under a category — one called “Unused”, say — and changes nothing else. They
  stay enabled, stay scoped, and keep running.
- **b — Disable** applies to policies only, and only to ones currently enabled. They stay in Jamf
  with scope and payload intact but stop running. Reversible from the *Policies* module.
- **c — Delete** is permanent, confirmed separately and named by count.

**Export** writes the currently filtered list to CSV — a record to circulate before anything is
acted on.

Packages are **reported only**. Removing a package record is done in Jamf.

## What “not scoped” means here

Nothing is targeted: no computers, no computer groups, no buildings, no departments.

Exclusions and limitations **narrow** a scope rather than create one, so a policy that excludes a
group but targets nobody is still unscoped. And a scope that cannot be read at all is treated as
**scoped** — the audit errs towards leaving things alone.

> **Warning:** “Unused” is what this app can see, not a certainty. A policy scoped to nobody may be
> run by a trigger, and a disabled policy may be disabled on purpose and waiting. Read the reason on
> each row before acting, and prefer **Move to Category** over **Delete**.

## Why it takes a moment

The audit reads every policy, every profile and every package in the tenant — there is no shortcut
Jamf can offer for the question it asks. It runs when the module is opened and when **Refresh** is
pressed, not after every action, which is why the list updates in place once something is moved,
disabled or deleted.

If any of those reads fails the audit reports an error rather than showing a partial list. An empty
section would otherwise read as “nothing of this kind is unused” when it really meant “this could not
be checked”.

# What each section does

A tour of the sidebar, in the order it appears.

## Dashboard

Fleet totals at a glance, each one clickable — a count opens its module. A total that could not be
read shows — rather than 0, so a failed read never reads as an empty tenant.

Also here: category management (create, rename, delete), device check-ins grouped by email domain,
and **Export All**, which writes every CSV into a single ZIP.

## Policies

Every policy, grouped by category. Search by name or ID, filter by category, inspect one in detail,
and act on a selection: move category, change scope, clone, or delete. Selecting several swaps the
filter bar for the bulk action panel.

Moving a policy keeps its Self Service category in step with its admin-console category, and there is
a bulk action to realign policies whose two have drifted apart.

## Profiles

The same pattern for macOS configuration profiles — inspect, move category, change scope, clone,
delete and export.

> **Note:** A profile's Scoped or Unscoped badge is worked out from its scope, not read from a field.
> Jamf configuration profiles have no enabled/disabled flag at all, so "not enabled" never applies to
> one.

## Blueprints

Declarative device management blueprints. List, inspect, create, edit, deploy, undeploy and delete.

Blueprints are served by a different API with different credentials — see *Getting connected*. Deploy
and undeploy are *started* by the server and finish afterwards, so the app reports them as requested
rather than completed; the deployment state in the list is what confirms the outcome.

## Computers

The managed Mac fleet. Search by name, serial, assigned user or email; filter to managed devices;
inspect hardware, OS, profiles, scripts, policies and User & Location; export to CSV. Read-only.

## Packages

Jamf's own package library, and uploading software Installomator has no label for. Three tabs:

- **New** — drop a `.pkg`, `.mpkg`, `.dmg` or `.zip` onto the page, fill in the details, and the app
  creates the package record, uploads the file with progress, and creates the install policy. Each
  step is reported separately, and nothing is rolled back behind your back.
- **Uploaded** — every package in this Jamf instance.
- **Deployed** — only the packages a policy actually installs, with the policy named on the row.

The Deployed answer requires reading every policy, so it runs once, lazily, the first time you open a
library tab — never for the New tab alone. While it runs, rows read "Checking…" rather than
pretending a package is unused.

## Scripts

The scripts in your tenant, grouped by category. Inspect metadata, parameters and source; move a
script to another category; delete one; export to CSV.

> **Note:** Scripts carry no scope and no enabled state in Jamf — they are run by whichever policies
> reference them — so no status is shown for them. Showing which policies run a script is planned.

## Installomator

An Installomator policy manager. It compares the policies already deployed against the upstream label
list, then creates Self Service install policies for the labels you select, with a category, script,
icon, scope and optional version pinning.

A deployed policy whose label has since been **withdrawn upstream** is flagged **Missing** in amber.
The policy still runs, but Installomator no longer recognises the label, so it fails on every Mac it
reaches. Missing rows are the clean-up list: edit the policy to point at a current label, or remove
it. "Explain This Label" on any row describes what that label will actually do on a Mac.

## Unused

An audit of objects that look like they do nothing, with the means to tidy them up. It lists policies
that are disabled or scoped to nobody, profiles with no scope, and packages no policy installs. Every
row gives its reason.

**Move to Category** is the primary action because it can be undone by hand — it files things under a
category without changing whether they run. **Disable** applies to policies only and is reversible
from the Policies module. **Delete** is permanent and confirmed separately. Packages are reported
only; removing a package record is done in Jamf.

> **Note:** "Not scoped" means nothing is targeted — no computers, groups, buildings or departments.
> Exclusions and limitations narrow a scope rather than create one, so they do not count as targets.
> A scope that cannot be read at all is treated as scoped, so the audit errs towards leaving things
> alone.

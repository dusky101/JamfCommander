# Privileges

These cover everything the app currently does. Reduce them to match the work you plan to do.

- **Computers** — Read. Fleet lists, inspectors and CSV export.
- **Computer Groups** — Read. Smart and static groups, used for deployment scope.
- **Buildings, Departments** — Read. Resolves IDs to names in User & Location and in exports.
- **Scripts** — Read, Update, Delete. Listing and inspecting scripts, moving one to another category,
  and deleting one. Read is also required by the Installomator module even if you never open Scripts.
- **Categories** — Read, Create, Update, Delete. Category management on the Dashboard, and creating a
  category from a deployment sheet.
- **macOS Configuration Profiles** — Read, Update, Create, Delete. Profile actions: move category,
  change scope, clone, delete.
- **Policies** — Read, Update, Create, Delete. Policy actions and Installomator deployment.
- **Packages** — Read, Create, Update. Required by the Packages module to upload a package and file
  it in Jamf.

> **Note:** Attaching a Self Service icon to a policy needs **Update Policies**, not just Create
> Policies. With Create alone, policies are created successfully and every icon attach fails — the
> results sheet says so, per policy, rather than reporting a clean success.

## Blueprints is separate

Blueprints does not use this role at all. Its integration is created in Jamf Account and granted
capabilities rather than Jamf Pro privileges: `blueprints:read`, `create`, `update`, `delete` and
`deploy`, plus `device-groups:read`. See *Getting connected*.

## What a missing privilege looks like

A refusal, not a silent failure. Jamf answers **403**, and the app reports that item as failed with
the reason. Nothing is ever counted as successful unless Jamf confirmed it.

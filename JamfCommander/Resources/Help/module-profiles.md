# Profiles

macOS configuration profiles, grouped by category, with the same shape of bulk actions as *Policies*.

## What you can do

- **Find** a profile by name or ID, or filter to a category.
- **Select** one, several with ⌘-click, or a run with ⇧-click.
- **Inspect** a profile’s scope and its raw source.
- **Move to a category.**
- **Change scope** — set the selection to All Computers, or remove all scope from it.
- **Clone** into a category you choose, optionally stripping the scope so the copy is not deployed
  the moment it exists.
- **Delete**, behind a confirmation.
- **Export** detailed profile data to CSV.

## Scoped or Unscoped is worked out, not read

Jamf does not store a “scoped” flag on a configuration profile, so the badge on each row is derived
from the profile’s actual scope every time the list is built.

```figure
status-badges
```

That has one consequence worth holding on to: **a configuration profile has no enabled or disabled
state at all**. Policies do; profiles do not. If you are looking for a way to switch a profile off
without unscoping it, there isn’t one — in this app or in Jamf.

> **Note:** A profile whose scope could not be read is treated as **scoped**. The app errs towards
> leaving things alone rather than towards reporting something as unused.

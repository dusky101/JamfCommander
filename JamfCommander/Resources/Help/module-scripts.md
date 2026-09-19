# Scripts

Every script in your tenant, grouped by category.

## What you can do

- **Search** by script name, and filter by category. There is a chip for uncategorised scripts.
- **Inspect** a script — its metadata, its parameter labels, and its full source.
- **Move** a script to another category, one at a time or in bulk.
- **Delete**, confirmed by count and reported per script.
- **Export** to CSV.

```figure
script-parameters
```

## Scripts have no status, and that is not an omission

A script in Jamf carries no scope and no enabled state. It is not targeted at anything and it does
not run on its own — it runs because a *policy* references it.

So no status badge is shown on a script. Earlier versions of this app showed one, hardcoded green,
which said the same untrue thing about every row.

> **Warning:** The app cannot yet tell you which policies run a given script, so it cannot warn you
> that the one you are about to delete is still in use. Deleting a script a policy references breaks
> that policy. Check in Jamf before deleting anything you did not create. Showing script usage is
> planned — see *What is coming*.

## “NONE” is a real category name

Jamf returns the literal string `NONE` as a script’s category when it has none. The app shows those
as uncategorised rather than inventing a category called NONE, and the filter bar has a chip for
them.

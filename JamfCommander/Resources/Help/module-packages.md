# Packages

Jamf’s own package library, and a way to upload software yourself when Installomator has no label for
it. Three tabs:

- **New** — the upload flow.
- **Uploaded** — every package this Jamf instance holds, searchable and grouped A–Z or by category.
- **Deployed** — only the packages a policy actually installs, with the policy named on the row.

```figure
package-tabs
```

## Uploading a package

Drop a `.pkg`, `.mpkg`, `.dmg` or `.zip` onto the page, or choose it, fill in the details, and the
app runs three steps and reports each one separately:

1. **Creates the package record** in Jamf — display name, file name, category, priority, restart
   requirement, and optional info and notes. Everything else is created switched off and can be
   changed on the package in Jamf afterwards.
2. **Uploads the file** to that record, with a progress bar and a Cancel button.
3. **Creates the install policy** — name, category, Self Service options, icon and scope, exactly as
   the Installomator flow does. It is created enabled and offered in Self Service; turn it off if you
   only wanted the package filed in Jamf.

Package names must be unique in Jamf, so the display name is checked against the library **before**
the file is sent rather than after. The policy name is checked too, but only warns — a rejected
policy still leaves the package safely uploaded.

## Nothing is rolled back behind your back

If a step fails, the results say exactly where it stopped and what exists: a record with no file
attached, and its ID; or a package uploaded with only the policy left to create. You are never told a
three-step job succeeded when two steps did.

Cancelling is the one exception. The empty record the app has just created is removed, and the
results say whether that removal succeeded.

> **Warning:** The upload is prepared on disk first, so while it runs the Mac needs roughly as much
> free space again as the package is big.

## “Checking…” means it is reading every policy

Jamf offers no way to ask *which policies use this package*, so the only way to answer it is to read
every policy in the tenant.

That scan runs **once, lazily** — the first time you open **Uploaded** or **Deployed**, and never for
the **New** tab alone, so coming here to upload something stays instant. While it runs, rows read
**Checking…** rather than pretending a package is unused, and the Deployed count shows an ellipsis
until the answer is real. **Refresh** re-reads both the library and the scan.

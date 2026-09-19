# Computers

The managed Mac fleet, read from Jamf’s computer inventory. This module is **read-only** — nothing in
it writes to your tenant.

```figure
computer-row
```

## What you can do

- **Search** by computer name, serial number, assigned user or email address.
- **Filter** to managed devices only, or show everything Jamf holds a record for.
- **Inspect** a computer: hardware and OS, FileVault state, IP address, last contact, and remote
  management status; the configuration profiles installed on it; the scripts available to it; its
  policies; and its User & Location record.
- **Copy a serial number** from the row’s context menu.
- **Export** the visible list to CSV.

## Buildings and departments are resolved to names

Jamf returns a building and a department on a computer record as numeric IDs. The app looks those up
and shows the names, in the inspector and in the CSV export, so an export is readable by somebody who
does not have the ID list in front of them.

That lookup needs **Read** on Buildings and Departments. Without it the record still loads; the two
fields simply show nothing.

> **Note:** This module covers Macs only. Jamf Commander does not manage iPhones or iPads today — see
> *What is coming*.

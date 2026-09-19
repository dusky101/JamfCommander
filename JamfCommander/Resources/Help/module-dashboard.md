# Dashboard

Where you land once the app has connected. Eight tiles count what your tenant holds, and each one is
a button: clicking a tile opens that module.

Six of them are simple totals — computers, policies, profiles, blueprints, packages and scripts. The
other two answer a question rather than count a list:

- **Installomator** counts the labels Installomator currently publishes — the ones available to
  deploy — and says how long ago that list last changed upstream, the same age GitHub shows against
  the file. A list that has not moved in months is the thing worth noticing. Hover the tile for the
  exact date.
- **Unused** counts what the Unused audit would list: policies and profiles that look like they do
  nothing, and packages no policy installs.

## What you can do

- **Open a module** by clicking its total.
- **Manage categories** — create one, rename one, or delete one. Categories are what almost every
  bulk action in this app files things under, so this is where you make the ones you are about to
  move things into.
- **See recent check-ins**, grouped by the email domain of each Mac’s assigned user. On a tenant
  that manages more than one company’s devices, that grouping is the quickest read of who has been
  online.
- **Export All** — writes six CSVs into a single ZIP: computers, policies, profiles, scripts,
  packages and the Unused audit.

## A tile showing a dash has not read as zero

A total that could not be read shows **—**, never `0`. The difference matters: a zero says *your
tenant holds none of these*, and a dash says *this could not be checked*. If a tile shows a dash, the
usual cause is a missing privilege on the API role — see *Privileges*.

## The last two tiles arrive late, on purpose

The Unused count cannot be read from a list: working it out means reading **every policy in the
tenant**, which is the most expensive thing this app does. So those two tiles are filled in *after*
the rest of the Dashboard is already on screen — they spin while they work, and the totals, the
categories and Device Status are usable throughout.

A spinner means still working. A dash means the read failed. They are deliberately not the same.

When the Unused answer arrives the tile counts up to it and settles. Every number on the way is
between where the tile was and the figure Jamf returned — there is no count climbing while the scan
runs, because until it comes back nobody knows the total.

Leaving the Dashboard before they finish cancels them, which is the right outcome; they are read
again next time you come back.

> **Note:** **Export All** reads every policy too, because several of the exports need detail the
> list endpoints do not return. On a large instance that is tens of seconds. It shows progress while
> it works.

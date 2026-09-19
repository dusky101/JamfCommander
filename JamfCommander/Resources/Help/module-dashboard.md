# Dashboard

Where you land once the app has connected. Six tiles count what your tenant holds — computers,
policies, profiles, blueprints, packages and scripts — and each one is a button: clicking a tile
opens that module.

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

> **Note:** **Export All** reads every policy in the tenant, because several of the exports need
> detail the list endpoints do not return. On a large instance that is tens of seconds. It shows
> progress while it works.

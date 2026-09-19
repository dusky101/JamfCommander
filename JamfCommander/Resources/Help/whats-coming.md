# What is coming

What this app cannot do today, and what is intended next.

> **Note:** These are intentions, not commitments. They are recorded here because knowing what a tool
> deliberately does not do yet is more useful than discovering it halfway through a job. Nothing on
> this page has a date.

## Mobile devices

Jamf Commander manages **Macs only**. iPhones and iPads enrolled in the same tenant are not listed,
not counted on the Dashboard, and not covered by any of the bulk actions.

That is the largest single gap, and extending the app to mobile devices is the intention. It is not a
small change: mobile devices are a different set of Jamf endpoints, a different inventory shape, and
a different set of privileges, and every module that says “computer” today would have to say which
kind of device it means.

## Remembering what it has already read

Every module fetches from scratch each time you open it. On a tenant of a few hundred policies that
is the single biggest source of waiting in the app, and the reason there is a loading overlay at all.

The intention is a cache per kind of object, where making a change marks only the affected kinds as
stale. Adding a package would refresh packages and policies; it would leave profiles, computers,
blueprints and scripts alone.

## Which policies run a script

The *Scripts* module cannot yet answer the only question anybody asks of a script they are about to
delete: **is anything using this?**

The intention is to show, for each script, the policies that actually run it — and to let a search
find a script by the policy that uses it, the way Jamf Pro’s own search does. Until then, check in
Jamf before deleting a script you did not create.

## More than one Jamf environment

The app holds exactly one tenant’s settings. Working against a second means overwriting the first, or
keeping a `.jamfconfig` file per customer and importing the right one each time — which is what the
export feature has quietly become.

The intention is a named list of environments and a way to switch between them from inside the app,
without going through Settings and pasting a different client secret each time. Managed service
providers are the obvious case; so is anyone with a test tenant beside their production one.

## Saving this guide as a PDF

So that a page can be handed to somebody who does not have the app — the *Privileges* page to a
security team before anyone creates the API role, or the setup pages to a customer. Today the only
way is a screenshot.

## Things that are deliberate, not missing

Some absences are decisions rather than gaps:

- **There is no graphical editor for blueprints.** Definitions are authored in the Jamf DDM app or by
  hand and brought in as JSON, and shown back verbatim, because a field-by-field editor would quietly
  drop payload keys it did not recognise.
- **Packages found by the Unused audit are reported, never removed.** Deleting a package record is
  done in Jamf.
- **Bulk operations are paced on purpose**, in small batches with gaps between them, so a large run
  does not trip Jamf’s rate limiting and start failing part-way through.

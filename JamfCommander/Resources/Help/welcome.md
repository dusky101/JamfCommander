# Welcome to Jamf Commander

Jamf Commander is a native Mac app for Jamf Pro administrators. It lists, inspects and bulk-edits the
things you would otherwise click through one at a time in the Jamf web console: configuration
profiles, policies, scripts, packages, computers and categories.

It is an administrative tool, not a viewer. It moves objects between categories, changes what they
are scoped to, clones them, creates install policies, and deletes them — against whichever Jamf
instance you have configured.

> **Important:** Every write lands on a real tenant and the Macs it manages. Deletion is permanent
> from this app's point of view. Rehearse a bulk action against a non-production instance before you
> run it against the one your fleet is enrolled in.

## Using this guide

This guide ships inside the app, so it always matches the version you are running. There is nothing
to find online and nothing to keep in step.

- The list on the left is the whole index, grouped into sections.
- The **search** box matches titles, summaries and the full text of every page, so you can look for
  the words you would actually type — *403*, *unscoped*, *client secret* — rather than guessing a
  heading.
- **⌘?** opens this guide from anywhere, and it is in the sidebar footer beside Settings.

## Where to start

- **Setting the app up for the first time?** Read *Getting connected*, then *Creating the API client
  in Jamf* and *Privileges*, in that order.
- **Setting it up for a colleague?** *Sharing your settings* covers moving a connection to another
  Mac, and what that file contains.
- **Want the lie of the land?** *What each section does* is a tour of the sidebar.

## A note on what this is

Jamf Commander is not affiliated with Jamf. It uses the documented Jamf Pro APIs with credentials you
create yourself, and it can only do what the API role you grant it allows.

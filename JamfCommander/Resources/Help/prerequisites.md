# Prerequisites

Two of the nine modules need something that exists outside Jamf Commander. Nothing on this page is
needed to connect the app, and nothing on it is needed for the other seven modules — skip it if you
are not using Installomator or Blueprints.

## Installomator — a script inside your Jamf instance

### What it is

Installomator is an open-source shell script, maintained by the Mac admin community.
Give it a short label such as `googlechrome` and it works out where that vendor publishes the current
version, downloads it, checks it is signed by the developer it expects, and installs it. There are
over a thousand labels.

The point of it is that you stop hosting and re-uploading installers. The Mac fetches the current
version from the vendor at the moment it runs, so a policy written once keeps installing the latest
release without anybody repackaging anything.

### Why this app needs it

The Installomator module does not upload package files. It creates and
maintains the Jamf **policies that run the Installomator script**, each one passing a label in
parameter 4. If the script is not in your Jamf instance, the deployment sheet has nothing to select
and no policies can be created.

### Where to get it

The Installomator project publishes releases at
[https://github.com/Installomator/Installomator](https://github.com/Installomator/Installomator).
Download the current release and add `Installomator.sh` to Jamf as a script.

*Before using Installomator*, the next page in this section, has the exact steps — including the
parameter labels to set.

> **Note:** The module also reads Installomator’s published label list directly from GitHub, so it
> needs outbound access to `raw.githubusercontent.com`, and to `api.github.com` for the date on the
> Dashboard tile. That is a separate thing from having the script in Jamf, and you need both.

## DDM Explorer — an app on your own Mac

### What it is

DDM Explorer is a free Mac app from Jamf. It browses Apple’s published declaration
types — what each one is for, which operating systems support it, which channels it can be scoped to
— and it has an editor that builds a declaration key by key while showing you the resulting JSON in
real time.

Declarative device management is Apple’s successor to the configuration profile: instead of pushing a
payload and hoping it applied, you declare the state you want and the device maintains it and reports
back. A **blueprint** is how Jamf packages those declarations for delivery.

### Why this app needs it

Jamf Commander has **no graphical blueprint builder**. Blueprints are
authored as JSON and brought here — you build the declaration in DDM Explorer, copy the payload, and
paste it into the Blueprints editor, which wraps it into a complete blueprint for you.

You can write the JSON by hand instead. DDM Explorer simply saves you from guessing at a declaration’s
key structure, which is the part that is easy to get wrong and tedious to debug.

### Where to get it

Free on the Mac App Store —
[https://apps.apple.com/app/id6754861743](https://apps.apple.com/app/id6754861743). The source is
published at
[https://github.com/Jamf-Concepts/ddm-explorer](https://github.com/Jamf-Concepts/ddm-explorer).

> **Note:** DDM Explorer is installed on **your** Mac, as an authoring tool. It is not something you
> deploy to the devices you manage, and it has nothing to do with the app’s connection to Jamf.

## Blueprints also needs a second credential

Separately from DDM Explorer, the Blueprints module cannot reach Jamf at all on the API client you
created in Jamf Pro. It needs its own integration, made in Jamf Account — see *Creating the
Blueprints integration*.

## Everything else needs nothing but the API client

Dashboard, Policies, Profiles, Computers, Packages, Scripts and Unused work on the Jamf Pro API
client alone. If you are not deploying software through Installomator and not using declarative
device management, you can ignore this page entirely.

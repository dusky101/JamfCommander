# Welcome to Jamf Commander

```figure
app-identity
```

## Before you start

Two of the nine modules need something that lives outside this app: the **Installomator** script in
your Jamf instance, and **DDM Explorer** on your Mac for authoring blueprints. Neither is needed to
connect, and neither is needed for the other seven.

*Prerequisites* says what each one is, why it is needed, and where to get it, and *Before using
Installomator* has the exact steps for the script.

Setting the app up for the first time? *Getting connected*, then *Creating the API client in Jamf
Pro*, then *Privileges*, in that order.

## Using this guide

```figure
help-index
```

- **Search** is the fast way in. Click it, or press **⌘F**, and type what you would say out loud —
  the error code Jamf gave you, the word on a badge, the field you are filling in. Arrow keys move
  through the results, Return opens one.
- **The index** is grouped into three sections, closed until you open one. **Using the app** has a
  page for every item in the sidebar, in the order they appear there:
```figure
sidebar
```

- **⌘?** opens this guide from anywhere, and it is in the sidebar footer beside Settings.
- **Export as PDF**, in the window’s toolbar, saves the page you are reading — or the whole guide —
  for somebody who does not have the app. Hand the *Privileges* page to a security team before
  anyone creates the API role. Choose the paper size there if you are sending it somewhere that
  does not use yours. Every page carries the app version and the date it was exported, because a
  PDF is a copy: it stops being true when the app moves on, and this guide does not.

The illustrations are drawn with the app’s own code, so they show what you are actually running and
cannot go stale.

> **Important:** Every write this app makes lands on a real tenant and the Macs it manages. Deletion
> is permanent from this app’s point of view. Rehearse a bulk action against a non-production
> instance before you run it against the one your fleet is enrolled in.

Jamf Commander is not affiliated with Jamf. It uses the documented Jamf Pro APIs with credentials you
create yourself, and it can only do what the API role you grant it allows.

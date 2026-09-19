# Policies

Every policy in the tenant, grouped by category. This is the module most of the bulk work happens
in: the actions here are the ones that would otherwise be a long afternoon of clicking through the
Jamf web console one policy at a time.

```figure
bulk-actions
```

## What you can do

- **Find** a policy by name or ID, or filter the list down to a single category. Category groups
  expand and collapse.
- **Select** one policy, several with ⌘-click, or a run of them with ⇧-click. Selecting anything
  swaps the filter bar for the bulk action panel.
- **Inspect** a policy — its scope, its settings, and its raw source.
- **Move to a category**, one policy or a hundred.
- **Change scope** — set the selection to All Computers, target specific computers or computer
  groups, or remove scope entirely.
- **Clone** into a category you choose.
- **Delete**, behind a confirmation that names the count.
- **Export** the detailed policy data to CSV.

## Clones are created switched off

A clone is named `Copy of [Original Name]` and is **disabled**, always: a copy that started running
the moment it was made would be a copy you had not finished configuring.

```figure
clone-options
```

Four more things can be stripped on the way — scope (**a**), triggers (**b**), the frequency
(**c**) and Self Service (**d**). Each is there for the same reason as the disabled state: a clone
is a starting point, not a deployment.

Turn the clone on in Jamf, or in this module, when you are satisfied with it.

## Two categories, kept in step

A policy in Jamf has an admin-console category and, if it is offered in Self Service, a Self Service
category as well. They can drift apart, and when they do the policy appears under one name to you and
another to your users.

Moving a policy here updates both. There is also a bulk action that realigns policies whose two
categories have already drifted.

> **Warning:** Everything in this module writes to the live tenant, and delete is permanent from this
> app’s point of view. Every action asks for confirmation first and then reports the real outcome for
> each policy — nothing is counted as successful unless Jamf confirmed it.

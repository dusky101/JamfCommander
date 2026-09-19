# Handover — Help overhaul

**State at handover:** 19 September 2026, app version 8.5. `Modules/Help/HelpView.swift` is 281 lines
and has not kept pace with the app. Three modules shipped since it was written are absent from it.

Read this before touching `Modules/Help/HelpView.swift`.

---

## What exists today

One scrolling document in a sheet, reachable from the sidebar footer and from ⌘? (the Help menu item
is replaced in `JamfCommanderApp.swift`, because the app has no help book). Seven `InfoSection`s:

1. Getting connected
2. Creating the API client in Jamf
3. Privileges for full administrative use
4. Before using Packages: add the Installomator script
5. Exporting and importing settings
6. What each section does
7. If something fails

`HelpPresenter.shared` is the singleton that opens it. `InfoSection` (`SharedUI/InfoSection.swift`) is
the section container; `HelpView` has private `bullet` and numbered-step helpers.

The single-document shape was a deliberate early choice — an administrator setting the app up for the
first time reads it top to bottom once. That reasoning still holds for *setup*. It no longer holds for
*reference*, which is most of what the file now needs to carry.

## Why it needs work

**It is out of date.** Written before Blueprints, the Unused audit, and the split of Packages into two
modules. Section 4 still says "Before using Packages", which is now the Installomator module.

**Module names changed underneath it.** The sidebar now reads Installomator (was Packages) and
Packages (was Add PKG), and the audit reads **Unused** while the code says `redundant`. Help copy must
use what the sidebar says, not what the folders say. That drift is documented in
`docs/prompts/SIDEBAR_RESTRUCTURE_HANDOVER.md`.

**The sidebar is about to be restructured**, and may gain groups and a Devices module. Help that
describes the sidebar item by item will need rewriting again unless it is organised so a module's
entry can be added without touching the rest.

## What the overhaul should cover

### Connecting, and sharing that connection

The maintainer named this specifically. It is currently thin, and it is the part a *second* person on
the team hits first.

- The Jamf Pro API client: created in Jamf Pro, `client_credentials` grant, which privileges for which
  modules. Section 3 has a privilege list — check it against what the app now calls.
- The **Platform API** integration for Blueprints is a genuinely different thing: created in Jamf
  Account rather than Jamf Pro, scoped to a platform environment, region-locked, and a Jamf Pro client
  **cannot** reach it. This trips people up and deserves its own explanation, not a footnote.
- **Sharing with team members** via the `.jamfconfig` import/export in Settings → Jamf Connections.
  Both credential sets are included in an export. That has an obvious implication the help must state
  plainly: **the file contains secrets**. How it should and should not be passed around is help copy,
  not a security policy, but it has to be said.
- Settings is now two tabs (General, Jamf Connections). Help should say where things are.

### What each module shows

One entry per module, in sidebar order. Each should answer: what it lists, what you can do to it, and
the one thing that surprises people. Candidates for that last part, all currently living only in code
comments or in this handover set:

| Module | The thing worth saying |
| --- | --- |
| Dashboard | Counts are clickable; a count that could not be read shows — rather than 0 |
| Policies | Bulk actions appear on selection; a single selection gets a different bar |
| Profiles | Scoped/Unscoped is derived from scope, not stored by Jamf |
| Blueprints | Different API, different credentials; reads are proven, several writes are not — see `BLUEPRINTS_HANDOVER.md` |
| Computers | Inventory read, v3 endpoint |
| Packages | The Jamf package library plus custom uploads; the Deployed tab needs a full policy scan |
| Scripts | Read and delete only |
| Installomator | Labels come from GitHub, not Jamf; a **Missing** label means the policy still runs but cannot succeed |
| Unused | What "not scoped" means, and that packages are report-only |

### Operational truths that belong in help, not just in comments

- Several actions read **every policy** in the tenant (the Unused audit, the Packages Deployed tab,
  Export All). On a large instance that is tens of seconds. People assume the app has hung.
- Bulk operations are throttled deliberately — batches with gaps — and that is why they are not faster.
- Export All now writes six CSVs, including the Unused audit.
- Deletes are permanent from the app's point of view. The README says so; help should too.

## Constraints

- **British English**, calm and professional, matching the rest of the app.
- **Never put a credential, token or instance URL in help copy**, including as an example. Use
  obviously fake placeholders.
- Reuse `InfoSection`; do not invent a second section style.
- Keep it reachable from both the sidebar footer and ⌘?.
- The sheet is a fixed size — check long sections scroll rather than overflow, the bug class that has
  already bitten several views in this app.

## Open questions

1. **One document, or navigable sections?** At this length a sidebar or tab strip inside the sheet
   starts to earn its place, and the read-top-to-bottom argument only covers the first three sections.
   If it becomes navigable, setup should still be a single readable run.
2. **Does help move out of a sheet?** A sheet cannot be left open beside the thing it describes, which
   is exactly what reference material is for. A separate window would let somebody keep it open while
   they work. Bigger change; worth deciding before restructuring the content.
3. **Per-module help.** The Installomator sidebar row already carries a dismissible hint
   (`SidebarHint`, resettable from Settings → General). If that pattern spreads, help and hints must
   not drift apart — decide which is the source of truth.
4. **Does help need to say the app is unofficial?** It is not affiliated with Jamf and it performs
   destructive operations against production. The README carries a disclaimer; help may need one too.

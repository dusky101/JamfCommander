# Roadmap — windows instead of sheets

## What

Turn the app's larger sheets into **windows**, with a sidebar-and-detail shape instead of one long
scrolling column.

In the maintainer's words: *"in the installomator DeploymentConfigSheet we can have sections on the
left to add details on the right"*, and then, having seen the guide converted: *"so thats the setup
we need to use. use windows instead of sheets for the popover windows. like the blueprint setup and
so on."*

Two changes, and the first is the one that carries the second.

## Why a window, not a sheet

This was settled by doing it to the help guide on 19 September 2026, and the difference was larger
than expected. A sheet has **no title bar** — no traffic lights, no title, no sidebar toggle — so its
content begins flush against the top edge and reads as cramped. The maintainer diagnosed it himself
before anyone proposed it: *"why don't i have the red green and yellow buttons and the minimise side
bar like ssmacos then … mine seems squashed up"*.

And a sheet is **modal**. It cannot be left open beside the thing it describes, and it cannot be put
aside while you go and look something up. For the deployment sheet that is not theoretical: creating
Installomator policies is exactly the job where you want the *Privileges* page or the Jamf console
open next to you.

A window also deletes machinery rather than adding it. The guide needed a whole
`HostWindowSizeReader` to size itself, because a sheet cannot read its container; as a window that
went away and `.defaultSize` replaced it.

## Why a sidebar, not a scroll

`DeploymentConfigSheet` is the clearest case, and it is the one he named. It has **six numbered
sections** — the sheet literally labels them "1. Select Target Category" through "6. Version Pinning
(Advanced)" — stacked in a single scroll. Numbering them was the right instinct and it is also the
tell: a form that has to number its own sections so you can find your way back up it is a form that
wants navigation.

Three things follow from that shape today:

- **You cannot see where you are.** Scope is section 5; to check what you set there while editing the
  name template you scroll away and back.
- **Version pinning is buried.** It is section 6, below the fold, and it is the part with the
  warning that matters most — a pinned URL stops working the moment the vendor moves the file.
- **The sheet cannot be illustrated.** The help guide has no figure for the deployment sheet or for
  version pinning, which are the two pages that most need one, because the sheet is one view with
  its state wired in through bindings and there is nothing a figure can borrow. See
  `HELP_OVERHAUL_HANDOVER.md`, phase D.

That last point is the second payoff and it is worth stating plainly: **splitting the sheet into
section views is the same work as making it illustratable.**

## What it is *not*

**Not every sheet.** A confirmation prompt, a category picker, an icon chooser and a results summary
are better as they are: one job each, dismissed the moment it is done, and a window for any of them
would be a window the reader has to go and close. `CommanderConfirmation` in particular **must** stay
modal — it is the thing standing between a click and a bulk delete, and a confirmation you can click
away from is not one.

The rule that separates them: **does the reader need anything else while it is open?** If yes, a
window. If it is one decision and then it is gone, a sheet.

Worth recording so it is not re-derived: the idea first arrived as "every view uses navigation view …
maybe we do everything to use nav split view like ssmacos". Two parts of that were not so — the help
guide already used `NavigationSplitView`, and the reference app uses split views in ten files while
still presenting `.sheet(` in twelve. What actually made the difference was the **window**, and the
text column being left-aligned.

## Roughly what it touches

Candidates, in the order the value falls off:

1. **`Auth/ConfigurationView.swift`** — already a tab picker over `SettingsGeneralSection`,
   `SettingsJamfProSection`, `SettingsPlatformSection`, `SettingsTransferSection`, each in its own
   file. The cheapest conversion, the lowest risk, and the natural rehearsal.
2. **`Modules/Packages/DeploymentConfigSheet.swift`** — six sections, already numbered. The case,
   and the highest risk: it creates policies on a live tenant.
3. **`Modules/Blueprints/BlueprintEditorSheet.swift`** — the maintainer named it: editor, scope and
   the DDM wrap panel, and the one place you most want the Jamf DDM app open beside you.
4. **`Modules/AddPackage/PackageUploadPage.swift`** — the upload has the same three-step shape, and
   an upload runs long enough that being trapped in a modal matters.

Each needs a `Window(id:)` in `JamfCommanderApp`, an `openWindow(id:)` at its entry point, and its
presenter reduced to carrying a request rather than an `isPresented` flag — exactly the shape the
help guide now has, which is the worked example to copy.

Not candidates: `CommanderConfirmation`, `OperationResultView`, `CategorySelectionSheet`,
`ScopeTargetPicker`.

## Known traps

- **`DeploymentConfigSheet` creates policies on a live tenant.** This is a layout change that must
  not become a behaviour change. Whatever is built has to produce byte-identical requests, and the
  safest route is to move the section *views* without touching the state they read and write.
- **Sections must take values, not bindings, to be reusable by the guide.** A section that takes
  `@Binding` can be composed by the sheet but not by a figure. The pattern already exists in
  `SharedUI/ActionBarComponents.swift` — `ActionBarColumn`, `SoftIconLabel` — which is why the
  action-bar figures could be grounded when the rest could not.
- **A window that presents sheets is fine; a sheet that presents sheets is where it got awkward.**
  The deployment sheet already presents a category picker and an icon chooser. As a window those
  become ordinary sheets on it, which is better than what happens today. The guide's search panel
  went the other way for a related reason — it was a sheet on a sheet and could not be dismissed by
  clicking away, so it became an overlay.

- ~~**State outlives the window now.**~~ **Decided, 20 September 2026: start clean each time, and
  warn before closing.** A half-filled deployment window does *not* come back as it was — but
  closing one that has work in it asks first, saying plainly that what has been entered will be
  lost. A window that silently discarded a part-configured deployment would be worse than either
  option on its own.

  The maintainer's words: *"have a popover warning saying if you close this window now you will
  lose what you have added already. but yes, start clean each time"*. The warning fires **only when
  something was actually changed** — opening the window and shutting it closes silently, because a
  dialog on every close is one nobody reads.

  **This is not free, and whoever builds it should know that before starting.** SwiftUI has no
  `shouldClose` hook for a `Window` scene: `.onDisappear` fires after the decision is made, and
  `isDocumentEdited` only draws the dot in the close button, it does not prompt. Intercepting the
  close means reaching the `NSWindow` and installing a delegate — AppKit interop, in an app that
  currently has none of it outside the save and open panels. Settings did not need this, so the
  rehearsal did not surface it.
- **The window minimum is 960pt and the header arithmetic is tight** — see `START_HERE.md` §4. A
  sheet gaining a 200pt rail loses that from its detail pane; the six sections' content has to still
  fit at the smallest window the app allows.

## Open questions

1. **Rail, or tabs?** The numbered steps are a sequence, not peers. A rail implies free navigation; a
   stepper implies order. The sheet is currently neither, and it is genuinely used both ways —
   accepting every default and pressing Deploy, or going straight to scope.
2. **Does the "1 label selected / Deploy Policies" footer stay put** across all sections, or move
   into the last one?
3. ~~**Is `ConfigurationView` done first**~~ **Yes** — it is the only candidate where a mistake
   cannot reach a Mac.
4. **What happens to a window left open when the connection drops, or Settings is pointed at another
   tenant?** A deployment sheet holding a category list from the previous instance is the same class
   of problem as the cache in `CACHING.md`, and the two should be solved with one answer.
5. **How much does this owe the help guide?** If the sections end up taking values, four deleted
   figures can come back. If they keep bindings, they cannot. That should be a deliberate choice at
   the start rather than discovered at the end.

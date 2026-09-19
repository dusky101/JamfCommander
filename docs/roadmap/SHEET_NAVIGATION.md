# Roadmap — sheets that navigate

## What

Give the app's larger sheets a sidebar-and-detail shape instead of one long scrolling column.

In the maintainer's words: *"in the installomator DeploymentConfigSheet we can have sections on the
left to add details on the right. i think it will look a lot better."*

## Why

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

The idea arrived as "update all the popover windows … to use NavigationSplitView like ssmacos". That
premise does not hold and the entry should not carry it forward:

- **The help guide already uses `NavigationSplitView`** and has since it was built. What made the
  reference app's pages look better was left-aligning the text column and richer figures, both since
  fixed.
- **The reference app does not use split views for its sheets either.** It uses `NavigationSplitView`
  in ten files — the app shell, the home launcher, onboarding and help — and still has twelve files
  presenting `.sheet(`.

A confirmation prompt, a category picker and a results summary are better as they are. Converting
them would be churn against production-facing code for no reader benefit.

## Roughly what it touches

Candidates, in the order the value falls off:

1. **`Modules/Packages/DeploymentConfigSheet.swift`** — six sections, already numbered. The case.
2. **`Auth/ConfigurationView.swift`** — already a tab picker over `SettingsGeneralSection`,
   `SettingsJamfProSection`, `SettingsPlatformSection`, `SettingsTransferSection`. The sections are
   *already separate files*, so this is the cheapest conversion and the lowest risk: no write path
   runs through it beyond saving credentials.
3. **`Modules/AddPackage/PackageUploadPage.swift`** — the upload flow has the same three-step shape.
4. **`Modules/Blueprints/BlueprintEditorSheet.swift`** — editor, scope and the DDM wrap panel.

Not candidates: `CommanderConfirmation`, `OperationResultView`, `CategorySelectionSheet`,
`ScopeTargetPicker` — one job each, already the right size.

## Known traps

- **`DeploymentConfigSheet` creates policies on a live tenant.** This is a layout change that must
  not become a behaviour change. Whatever is built has to produce byte-identical requests, and the
  safest route is to move the section *views* without touching the state they read and write.
- **Sections must take values, not bindings, to be reusable by the guide.** A section that takes
  `@Binding` can be composed by the sheet but not by a figure. The pattern already exists in
  `SharedUI/ActionBarComponents.swift` — `ActionBarColumn`, `SoftIconLabel` — which is why the
  action-bar figures could be grounded when the rest could not.
- **A sheet inside a sheet is already in play.** The guide's search panel is presented from within
  the help sheet. It works, but a deployment sheet that itself presents a category picker and an icon
  chooser is two levels before this change and three after. Worth watching rather than assuming.
- **The window minimum is 960pt and the header arithmetic is tight** — see `START_HERE.md` §4. A
  sheet gaining a 200pt rail loses that from its detail pane; the six sections' content has to still
  fit at the smallest window the app allows.

## Open questions

1. **Rail, or tabs?** The numbered steps are a sequence, not peers. A rail implies free navigation; a
   stepper implies order. The sheet is currently neither, and it is genuinely used both ways —
   accepting every default and pressing Deploy, or going straight to scope.
2. **Does the "1 label selected / Deploy Policies" footer stay put** across all sections, or move
   into the last one?
3. **Is `ConfigurationView` done first** as the low-risk rehearsal? It is the only candidate where a
   mistake cannot reach a Mac.
4. **How much does this owe the help guide?** If the sections end up taking values, four deleted
   figures can come back. If they keep bindings, they cannot. That should be a deliberate choice at
   the start rather than discovered at the end.

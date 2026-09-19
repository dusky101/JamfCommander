# Handover — sheets that navigate

**State at handover:** 19 September 2026, app version 9.0. **Nothing is built.** Read
`docs/roadmap/SHEET_NAVIGATION.md` first for the intent; this file is what is true about the code.

---

## Correct the premise before you start

The idea reached the roadmap as *"every view uses navigation view … maybe we do everything to use nav
split view like ssmacos"*. Two parts of that are not so, and building on them would waste a session:

- **The help guide already uses `NavigationSplitView`.** It has since it was built. What made the
  reference app's pages look better was that its text column is **left-aligned** against a 640pt
  measure, not centred — fixed on 19 September 2026 — and that its figures are richer.
- **The reference app does not use split views for its sheets.** `NavigationSplitView` appears in ten
  of its files: the app shell, the home launcher, onboarding and help. It still presents `.sheet(` in
  twelve.

So this is **not** an app-wide container change. It is a shape change to two or three sheets that
have genuinely outgrown a single scrolling column.

## Proven — and what is NOT

| Established | Not established |
| --- | --- |
| `DeploymentConfigSheet` has six sections and numbers them itself | That a rail is better than the scroll — nobody has tried it |
| `ConfigurationView`'s sections are already four separate files | Whether the content fits at the 960pt window minimum with a rail |
| `ActionBarComponents.swift` proves the value-not-binding pattern works | Whether the sheet's sections can take values without a rewrite |
| The help guide's figures were deleted for exactly this reason | Whether any of it can be done without changing what is sent to Jamf |

## Do `ConfigurationView` first

It is the rehearsal, and the argument is not that it is easiest — it is that **a mistake there cannot
reach a Mac**. It already has a tab picker over `SettingsGeneralSection`, `SettingsJamfProSection`,
`SettingsPlatformSection` and `SettingsTransferSection`, each in its own file. Turning a picker into
a rail is close to a container swap, and it will surface every layout problem the deployment sheet
will hit — at the window minimum, with a footer, inside a sheet — while the worst outcome is a
mis-saved credential the user retypes.

Only then `DeploymentConfigSheet`.

## The rule for `DeploymentConfigSheet`

**It creates policies on a live tenant.** This is a layout change that must not become a behaviour
change.

- The requests it produces must be **byte-identical** before and after. Move the section *views*;
  do not touch the state they read and write, the XML they build, or the throttling.
- Verify against a non-production tenant before it goes near the real one. The project README says
  this and it applies with force here.
- The existing behaviour worth preserving deliberately: the policy-name preview, the "Review policy
  names" list, the icon uploaded once per run, and the version-pinning warning about architecture and
  moved download URLs. That warning is the single most load-bearing sentence in the sheet.

## Take values, not bindings — and get four figures back

This is the decision to make **at the start**, because it is expensive to retrofit.

A section that takes `@Binding` can be composed by the sheet and by nothing else. A section that
takes plain values plus callbacks can be composed by the sheet **and by the help guide**.

`SharedUI/ActionBarComponents.swift` is the proof this works: `ActionBarColumn` and `SoftIconLabel`
exist so the action bars share one look, and they are the only reason the guide's action-bar figures
could be grounded when the others could not. The card views — `PolicyCardView`, `PackageCardView`,
`RedundantRowView`, `StatCard` — are the same story: they take a model and no service, and the guide
instantiates them directly.

If the sheet's sections end up value-taking, these come back to the guide:

- `installomator-deploy` — the six steps, on *Installomator*
- `version-pinning` — 6a–6d, the page that most needs a picture
- `package-upload` — the three steps, on *Packages*
- `platform-settings` / `connection-settings` — on the two setup pages

They were written once and deleted on 19 September 2026 because they were hand-drawn and wrong. See
`HELP_OVERHAUL_HANDOVER.md`, phase D. **Do not re-draw them by hand.** The whole lesson of that phase
is that a figure must instantiate the real view, and the registry is in
`Modules/Help/HelpFigures.swift` with `FigureMarker` and `MarkedRow` still there, unused, waiting.

## Traps

- **The window minimum is 960pt**, and a module header already fits by about 50pt — see
  `START_HERE.md` §4 for the arithmetic and the warning not to estimate glyph widths. A sheet that
  gains a 200pt rail loses that from its detail pane at every window size.
- **Sheet inside a sheet is already in play.** The guide's search panel is presented from within the
  help sheet. `DeploymentConfigSheet` already presents a category picker and an icon chooser, so it
  is two levels now and three after. Watch it rather than assume.
- **Six sections are a sequence, not peers.** A rail implies free navigation. The sheet is genuinely
  used both ways — accept every default and press Deploy, or go straight to scope — so whichever is
  chosen, both paths must stay short. See open question 1 in the roadmap entry.
- **British English, and the existing copy is deliberate.** "Let Installomator decide (recommended)"
  and the pinning warning were written to be read under time pressure. Move them; do not improve
  them.

## Not candidates

`CommanderConfirmation`, `OperationResultView`, `CategorySelectionSheet`, `ScopeTargetPicker`. One
job each, already the right size. Converting them is churn against production-facing code for no
reader benefit.

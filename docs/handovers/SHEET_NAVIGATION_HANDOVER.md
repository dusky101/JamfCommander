# Handover — windows instead of sheets

**State at handover:** 20 September 2026, app version 9.0. **`ConfigurationView` is converted — the
rehearsal is done.** `DeploymentConfigSheet`, `BlueprintEditorSheet` and `PackageUploadPage` are
untouched. Read `docs/roadmap/SHEET_NAVIGATION.md` first for the intent; this file is what is true
about the code.

---

## There is a worked example. Copy it.

**The help guide was converted from a sheet to a window on 19 September 2026**, and that conversion
is the pattern for everything in this handover. Read it before writing anything:

- `JamfCommanderApp.swift` — `Window("Jamf Commander Guide", id: HelpWindowID)`, `.defaultSize`,
  `.restorationBehavior(.disabled)`, and `HelpWindowID` declared beside the scene.
- `SidebarView.swift` and the `CommandGroup(replacing: .help)` — both entry points call
  `openWindow(id:)`.
- `HelpPresenter` — reduced from an `isPresented` flag to carrying a deep-link request. The window's
  existence is no longer a piece of state some view owns.
- `HelpView` — lost its `onDismiss`, its Done button, and the whole `HostWindowSizeReader` that
  existed only because a sheet cannot read its container.

That last point is worth dwelling on: **the conversion deleted more code than it added.**

The scale of the change was larger than expected, and the maintainer's verdict afterwards was that
the guide "looks much better". The parts that made the difference were the title bar — traffic
lights, a title, the sidebar toggle — and no longer being modal.

## Proven — and what is NOT

| Established | Not established |
| --- | --- |
| The help guide's sheet-to-window conversion works, and deleted code | **Everything about the `ConfigurationView` conversion on screen** — it builds clean, nothing has been looked at |
| `DeploymentConfigSheet` has six sections and numbers them itself | Whether a half-filled deployment window should survive being closed |
| `ConfigurationView` is now a window with a four-item rail, and it compiles with no warnings | Whether the deployment sheet's content fits at the 960pt minimum with a rail |
| `ActionBarComponents.swift` proves the value-not-binding pattern works | Whether the sheet's sections can take values without a rewrite |
| The help guide's figures were deleted for exactly this reason | Whether any of it can be done without changing what is sent to Jamf |

## Two changes, not one

Each candidate needs **both**, and they are separable:

1. **Sheet → window.** A `Window(id:)` scene, `openWindow(id:)` at the entry point, the presenter
   reduced to a request. Mechanical, and the guide is the template.
2. **Scroll → sidebar.** The shape change. Only worth doing where the content has sections.

Do them in that order per candidate, and build between. A window that still scrolls is already an
improvement and is a safe place to stop.

## `ConfigurationView` — done, 20 September 2026

The rehearsal, converted. Six files, +210/−73.

**The scene.** `Window("Settings", id: SettingsWindowID)` beside the guide's, `.defaultSize(860×660)`,
`.restorationBehavior(.disabled)` so Settings left open does not reopen in front of the app.

**The presenter lost its flag.** `SettingsPresenter.isPresented` is gone; it carries
`requestedPage: SettingsPage?` and every caller opens the window itself — exactly what `HelpPresenter`
did. The request is cleared once honoured, so reopening Settings lands where the reader left off
rather than repeating the last deep link.

**Two tabs became four pages.** The sheet had a segmented picker over `General` and
`Jamf Connections`, and the second stacked three sections. As a rail each section file is one click:
General, Jamf Pro, Platform, Import & Export. That also let the deep links say what they mean — the
login screen's "Open Settings" lands on **Jamf Pro**, and Blueprints' on **Platform**, where both
used to land on a tab holding three sections.

**Six entry points**, all now `request(_:)` then `openWindow(id: SettingsWindowID)`: the ⌘, menu
item, the sidebar footer, two buttons on the login screen, and two in Blueprints.

**Blueprints lost a binding it should not have had.** It took `showConfigSheet: Binding<Bool>` — the
presenter's `isPresented`, threaded through `ContentView` — purely to reload when Settings closed. A
window has no such moment, so it now watches the Platform credentials themselves via a hashed token.
That is the better trigger regardless: it fires when something actually changed, rather than every
time Settings was opened and shut again. The hash is deliberate — a client secret has no business
sitting in view state as text.

**Settings owns its own `JamfAPIService`.** A `Window` scene cannot reach the one `ContentView`
holds. This is correct rather than a workaround, and it was checked rather than assumed:
`verifyPlatformConnection()` → `preparedPlatformSession()` reads `PlatformCredentialsStore.current()`
straight from `@AppStorage` and never touches `baseURL` or `token`. Nothing else in Settings calls
Jamf.

**No Done button.** A window closes the way windows close, and "Done" reads as "save" — which these
fields do not need, since every one is `@AppStorage` and stored as it is typed.

**Clear All moved rather than changed.** It showed under the `Jamf Connections` tab; it now shows
under the three credential pages when there is something to clear, and still empties both APIs
wherever it is pressed.

### What to look at

- ⌘, and the sidebar footer both open **one** window, and bring it forward if it is already open.
- The login screen's "Open Settings" lands on **Jamf Pro**; Blueprints' lands on **Platform**.
- Settings can be left open *beside* the app — that is the whole point, and the reason to prefer it
  for credentials is that creating a Jamf Pro API client means reading the Privileges page while you
  do it.
- **Platform → Test Connection still works.** It is the only part of Settings that calls Jamf, and it
  now runs through a service of its own.
- Entering Platform credentials should make the Blueprints module reload on its own.
- Close Settings and reopen it: it should land where you left it, not on General.

## Then `DeploymentConfigSheet`

The rehearsal above is what the pattern looks like in this codebase. The deployment sheet is the
case, and the risk: **it creates policies on a live tenant.**

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
- **A window presenting sheets is fine; a sheet presenting sheets was not.**
  `DeploymentConfigSheet` already presents a category picker and an icon chooser — two levels today,
  and as a window those become ordinary sheets on it, which is better. The guide hit the other side
  of this: its search panel was a sheet on a sheet and therefore could not be dismissed by clicking
  away, so it became an **overlay** with a backdrop that takes the click. If a converted window needs
  something Spotlight-like, that is the pattern, and it is in `HelpView.searchOverlay`.
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

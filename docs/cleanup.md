# Implementation Prompt — App-Wide UI Clash & Layout Cleanup

> Hand this to Claude Code in the JamfCommander repo. It is a multi-phase brief. **Work in phases,
> stop at the end of each phase, and leave the app building and manually testable before stopping.**
>
> This is a **presentation-only** pass. It must not change what any screen does, what any API call
> sends, or what any confirmation says.

## Context & goal

Every module in JamfCommander was built independently, and the layout has drifted. Controls overlap
each other, text runs underneath adjacent elements, fixed frames leave dead space, and long values
(UUIDs, long object names, long category names, long error messages) push views past what their
container reserves for them. The maintainer's words:

> "there are things overlapping and so on.. and that actually is currently throughout the app"

Go over the **complete UI of the app** and make sure nothing clashes. Concretely, at the end of this
work no screen should have:

- text or controls drawn on top of one another,
- text truncated in a way that hides information with no way to read it (no tooltip, no selection,
  no wrapping),
- bands of empty space caused by a fixed frame that outgrew its content,
- content clipped or unreachable at the app's **smallest usable window size**,
- a horizontal scrollbar caused by a row that cannot compress,
- a control whose hit area overlaps a neighbour's.

## Guardrails (already documented — do not restate, just follow)

The repo's existing instructions are authoritative:

- Root `CLAUDE.md` — the non-negotiable invariants.
- `.claude/rules/design-system.md`, `swiftui-views.md`, `architecture.md`.
- `docs/PROJECT_OVERVIEW.md` and the maintainer `JamfCommander/README.md`.

The ones that bite this work hardest, as a reminder only:

- **Reuse `SharedUI` rather than inventing new visual treatments.** Use the Liquid Glass helpers
  (`.liquidGlassRect(cornerRadius:)`, `.liquidGlassCapsule()`), `StatusBadge`, `InfoSection`,
  `FilterBar`, `InspectorShell`, `LoadingProgressView`.
- **British English** in every user-facing string you touch.
- **Semantic colours and SF Symbols only** — no hard-coded RGB except the existing gradients.
- **Never communicate state by colour alone**; pair with a symbol and text.
- **Do not commit or push.** Leave the working tree for the maintainer to review.
- **Do not restyle wholesale.** This is a clash-and-overflow fix, not a redesign. If a screen looks
  dated but nothing collides, leave it alone and note it instead.

## Confirmed defect — fix this first

**`SharedUI/InspectorShell.swift` lays its header out as a `ZStack`.** Three things are overlaid
with no width reserved for any of them:

1. left — a `VStack` of the section label and the `id` string,
2. centre — `headerText`, capped at `maxWidth: 250`,
3. right — the Close button.

When the `id` or the name is long they are drawn on top of each other. This was seen with a
blueprint UUID (`1c31ef25-7d6d-4c0e-bd0c-e2b543240f8e`) running underneath the centred title
"Software Update".

Every module still using `InspectorShell` inherits this. Today most of them pass short IDs such as
`#4`, so it only shows up with long values — but it is latent everywhere.

**Fix:** rebuild the header as a single `HStack` with a `Spacer`, so each element reserves its own
width. Give the identifier `.lineLimit(1)`, `.truncationMode(.middle)` and `.textSelection(.enabled)`
so a truncated UUID can still be copied. `Modules/Blueprints/BlueprintInspectorView.swift` already
uses that header shape and can be copied from.

Changing `InspectorShell` touches every inspector, so **check each one visually afterwards** —
Profiles, Policies, Computers, Packages — and do not let the fix regress the ones that look fine now.

## Areas to audit

Work through these. This list is where to look, **not** a list of known-broken screens — each needs
checking before anything is changed.

| Area | Files | What to check |
|---|---|---|
| Inspectors | `SharedUI/InspectorShell.swift`, `Modules/*/[A-Za-z]*InspectorView.swift` | The confirmed header defect; fixed 500×650 frames holding content that needs more width |
| Sheets | `Modules/Packages/DeploymentConfigSheet.swift`, `PackageEditSheet.swift`, `SharedUI/CategorySelectionSheet.swift`, `ScopeTargetPicker.swift` | Fixed frames vs content that grows; footer buttons pushed off the bottom |
| Dashboards | `Modules/*/[A-Za-z]*DashboardView.swift` | Row layouts at narrow widths; long object names against trailing badges and menus |
| Filter bar | `SharedUI/FilterBar.swift` | Chip wrapping, the 132pt chip-area cap, long category names |
| Action bar | `Views/ActionPanelView.swift` | Button row at the smallest window width |
| Results | `SharedUI/OperationResultView.swift` | Long error strings against the trailing category column |
| Settings | `Auth/ConfigurationView.swift` | Now scrolls; confirm the footer stays pinned and nothing clips |
| Sidebar | `Core/SidebarView.swift`, `Views/ContentView.swift` | 220pt minimum against the longest module name; status footer truncation |
| Dashboard | `Modules/Dashboard/` | Tile and grid behaviour when the detail pane is narrow |

## How to verify

Compile-checking is not enough — this is a visual defect class, so it needs eyes on it.

1. Build and run: `xcodebuild -scheme JamfCommander -destination "platform=macOS" build`, then launch
   the built `.app`.
2. Visit **every** sidebar module and open **every** sheet and inspector reachable from it.
3. Check each at three window sizes: the smallest the window allows, a typical ~1400×900, and
   full screen.
4. Check each with the longest real data you can find — the longest policy name, a category such as
   "Utilities & Tools", a full UUID, a multi-line API error.
5. Check light and dark appearance.
6. Check the accessibility text sizes; per `swiftui-views.md`, Dynamic Type is part of the
   implementation, not an afterthought.

If a screen cannot be reached without writing to the production tenant, **do not trigger the write**
to see it. Note it as unverified and say so in the phase summary.

## Suggested phases

1. `InspectorShell` header, plus a visual check of every inspector that uses it.
2. Sheets and modal frames.
3. Dashboards and row layouts at narrow widths.
4. Shared components — `FilterBar`, `ActionPanelView`, `OperationResultView`, `StatusBadge`.
5. Sidebar, root layout, and a final pass at the smallest window size.

End each phase with the standard PHASE COMPLETE summary and the Commit Ceremony question.

## Out of scope

- Redesigns, new visual language, colour-scheme changes.
- Behaviour changes of any kind, including what a confirmation says or what an API call sends.
- New features. If a screen needs a control it does not have, note it and move on.

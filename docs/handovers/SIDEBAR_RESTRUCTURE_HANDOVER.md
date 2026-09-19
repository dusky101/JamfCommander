# Handover — sidebar restructure

**State at handover:** 19 September 2026, app version 8.5. Everything under *What exists today* is
built and committed on `main`. Everything under *What is proposed* is a decision, not code.

Read this before touching `Core/SidebarView.swift`, `Views/ContentView.swift` or
`SharedUI/Animations/ModuleTransition.swift`.

---

## Why this is its own piece of work

The sidebar was a flat list of nine modules. Two have already been pulled out of it for structural
reasons, and the maintainer wants to group the rest — plus add a **Devices** module for mobile
devices, so every operation the app performs on computers can be performed on iOS/iPadOS too. That
addition is what forces the question: eight flat items is tolerable, ten is not.

## What exists today

```
Dashboard          ─┐
Policies            │
Profiles            │   the scrolling list — AppModule.navigationModules
Blueprints          │
Computers           │
Packages            │
Scripts            ─┘
───────────────────────  Divider
Installomator            pinned, framed both sides, with a subtitle
───────────────────────  Divider
                         40pt of air
Unused                   pinned, unframed and deliberately quieter (AppModule.redundant)
───────────────────────  Divider
Settings · Help          SidebarFooterRow
```

**On names.** The sidebar reads **Unused**; the code says `redundant` throughout (`AppModule.redundant`,
`Modules/Redundant/`, `RedundantItem`). The label changed because to an infrastructure audience
"redundant" most naturally means *duplicated for resilience*; the concept behind the code did not.
Installomator keeps its name and carries a subtitle instead — every generic alternative collides with
Jamf's own App Catalog / App Installers.

**Why Installomator is out of the list.** Every other module *mirrors* something that already exists
in the Jamf tenant. Installomator is the only one that brings something **in** from outside it — it
reads ~1,287 labels from the Installomator project on GitHub and offers ~1,200 applications Jamf has
never heard of. That is a difference of kind, not of size, and it is why sorting it into a group
never felt right. Redundant is the mirror image: it takes dead objects *out*. The two pinned zones
are "change the estate"; the list above them is "view the estate".

**Constraints the restructure must respect:**

- `AppModule`'s **declaration order is the visual order**. `navigationIndex` (in
  `SharedUI/Animations/ModuleTransition.swift`) reads `allCases.firstIndex(of:)` to decide which way
  the detail pane slides. Move a module in the sidebar and you must move its case, or the pane
  animates the wrong way.
- `AppModule.navigationModules` filters out `.installomator` and `.redundant`. Any new pinned or
  grouped entry has to be filtered out of it too, or it appears twice.
- `SidebarModuleRow` owns hover, press-bounce and the per-module accent colour
  (`AppModule.accentColour` → `SharedUI/ModulePalette.swift`). A group header is a **different kind
  of row** and should not reuse it.
- `SidebarHint` + `SidebarHintCard` give a row a dismissible hover explanation on a 650ms dwell,
  resettable from Settings → General. Only Installomator carries one. Group headers may want them.
- `ContentView` exposes `currentModule` as a computed `Binding<AppModule>` whose setter works out the
  transition direction. Children — the sidebar, the dashboard tiles — know nothing about transitions.
  **Keep it that way**; do not have the sidebar set a direction itself.

## What is proposed

The maintainer's grouping, in his words:

| Group | Modules |
| --- | --- |
| *(ungrouped)* | Dashboard |
| **Content** | Packages, Installomator |
| **Management** | Policies, Profiles, Blueprints |
| *(pinned, unchanged)* | Unused |

Plus **Devices** (mobile), not yet built, which needs a home in this scheme.

Note this **differs from Jamf Pro's own information architecture**, where Policies and Configuration
Profiles sit under *Content Management* and Packages and Scripts under *Settings → Computer
Management*. The maintainer's grouping inverts those two words. He is the Jamf expert and it is his
call — but whoever picks this up should ask once whether inverting Jamf's own vocabulary helps or
confuses an admin who moves between the two tools all day, because that was raised and not settled.

Also unsettled: whether to **adopt Jamf's terminology outright** — a "Computers" group containing
"Inventory", rather than a module called Computers. Attractive for transfer of learning, and it
scales when Devices arrives (Computers → Inventory, Devices → Inventory). Nobody has decided.

### Expanding sections, not submenus

Explicit requirement: clicking a group **pushes the rows below it down, in place**. Not a popover,
not an overlay, not a disclosure floating above the list. The list grows and shrinks.

In SwiftUI that is an `if expanded { … }` inside the list's `VStack` with an `.animation` on the
expansion state — the layout does the pushing for you. Two things to get right:

- The list lives in a `ScrollView` whose empty space is what creates the gap above the pinned zones.
  An expanded group must not fight that; test with every group open at a short window height.
- Group expansion should persist (`@AppStorage`), as `FilterBar`'s `filterBarCategoriesExpanded`
  already does. Somebody who works in Policies all day should not re-open Management every launch.

## Open questions, in the order they block work

1. **Where does Devices go?** It is the reason for grouping, and no group currently fits it. Answer
   this first; it may change the whole scheme.
2. **Group names.** "Content" and "Management" are the maintainer's, and they invert Jamf's usage of
   the same two words. Worth one deliberate conversation.
3. **Does Dashboard stay ungrouped?** It has no hue of its own in the palette precisely because it is
   an overview rather than a kind of object — that reasoning probably extends to grouping.
4. **Do group headers navigate, or only expand?** A header that does both is ambiguous; a header that
   only expands costs a click.
5. **Does Installomator stay pinned, or move into Content?** The maintainer's table puts it in
   Content. That reverses the inbound/outbound argument above, so it is a real decision with a reason
   on each side, not an oversight.

## Do not

- Do not reuse `ActionPanelView`'s or `SidebarModuleRow`'s chrome for group headers.
- Do not persist `currentModule`. It is `@State` and deliberately resets to Dashboard on launch.
- Do not add a dashboard tile for Installomator. Its count needs the full policy scan (~250 detail
  calls), which is exactly why the Packages tile counts the cheap library instead. Considered and
  rejected.

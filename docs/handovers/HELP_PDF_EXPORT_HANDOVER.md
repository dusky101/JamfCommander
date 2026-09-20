# Handover — help as a PDF

**State at handover:** 20 September 2026, app version 9.0. **Built, and confirmed on screen by the
maintainer.** The roadmap entry and the session prompt have been deleted; this file is what is left.

The feature: a toolbar item in the guide's window exports the page you are reading, or the whole
guide, as a PDF. Paper size is the Mac's own by default, overridable to A4 or US Letter in the same
popover and remembered between exports. Every page carries the app version and the export date.

---

## Proven — and what is NOT

| Established | Not established |
| --- | --- |
| **The body text is black.** Measured under an app forced dark, three ways: `.environment(\.colorScheme, .dark)` produced *no dark pixels at all* — the 19 September failure, reproduced — while `.light` produced `RGB(39,39,39)`, light-mode `labelColor` over white | How it behaves on a Mac whose default paper is neither A4 nor Letter. The code falls back to A4 only when the printing system reports something absurd; a B5 default would simply be used |
| `ImageRenderer` resolves `.primary`, `.secondary` **and** `Color(nsColor:)` against SwiftUI's `colorScheme`, not against `NSApp.effectiveAppearance`. That is the whole reason this route works where `NSHostingView` did not | Whether a very large export (many more topics than twenty) stays responsive. Twenty topics is 0.35s; nothing has been tried at ten times that |
| **No block in the guide loses contrast on paper.** All 291 blocks across all 20 topics rendered both to a bitmap and to a PDF and compared: none legible one way and not the other | That the pagination is *pleasant* everywhere. It is correct everywhere — nothing is split — but a topic's last block can land alone on an otherwise empty page |
| **The figures render deterministically.** All 14, four separate processes, identical ink coverage every run | Printing. It has been read on screen and rasterised; nobody has put it through a printer |
| The prose is real vector text — PDFKit extracts it verbatim, so a security team can search and copy from it | Any locale but this one. Dates are formatted `en_GB` deliberately; nothing else has been tried |
| The version stamp reads the real `MARKETING_VERSION` — the exported *Privileges* page says "Jamf Commander 9.0", confirmed on screen | |
| The save panel writes where the reader chooses, under the sandbox — confirmed on screen | |
| The app's own glass surfaces are unchanged by the `LiquidGlassModifier` restructure — Dashboard and Policies confirmed on screen | |

## Three things a `CGPDFContext` gets wrong

All three were invisible on screen and only appeared on paper. **This is the section worth reading
before touching the renderer**, because each one produced a document that looked plausible.

1. **A gradient's stops lose their alpha.** `AppBackground` is three tinted stops at 12–22% over a
   dark base; drawn into a PDF they paint opaque, turning the app's wash into a vivid purple band.
   Measured: the identical `ImageRenderer` gave `(0.16, 0.13, 0.23)` to a bitmap and
   `(0.31, 0.18, 0.66)` to a PDF. `.drawingGroup()` does not help.
   **Fix:** figures are placed as rendered *images*, which composites correctly. Prose stays vector.
2. **Alpha on a fill can turn the text on it white.** The callout's `tint.opacity(0.07)` background
   did exactly that — but only once the callout wrapped past two lines, which is why one page looked
   right and the next did not. A short callout was fine; a three-line one was white on pale blue.
   **Fix:** `HelpPDFTheme.onPaper(_:fraction:)` composites tints over white itself. **The print
   stylesheet now uses no alpha anywhere.** Keep it that way.
3. **The real `glassEffect` does not render reliably off screen.** The same figure came out complete
   in one process and an empty panel in the next, with no code change in between.
   **Fix:** `\.isDocumentRendering` in `SharedUI/LiquidGlassModifier.swift`. A view drawn into a
   document gets a flat panel of the same shape instead of asking for glass. This is the one part of
   the change that reaches **outside the guide** — it touches every glass surface in the app — so the
   flag defaults to `false` and only `HelpPDFFigure` sets it.

## How to check it again without launching the app

The whole app compiles headless, which is how everything above was measured:

```
find JamfCommander -name "*.swift" ! -name "JamfCommanderApp.swift" > sources.txt
xcrun swiftc -swift-version 5 -default-isolation MainActor \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -o harness $(cat sources.txt) shim.swift main.swift
```

`shim.swift` supplies the three window-id constants that live in `JamfCommanderApp.swift` (which
cannot be compiled, being `@main`). The flags match the target's `SWIFT_DEFAULT_ACTOR_ISOLATION` and
`SWIFT_APPROACHABLE_CONCURRENCY` settings; without them the app's own sources will not build.

A `main.swift` that reads `Resources/Help/*.md` from disk, parses with the real `HelpMarkdown` and
calls `HelpPDFExportService.pdfData(topics:page:)` gives a real PDF to inspect. **Do not trust the
version stamp in a harness build** — there is no Info.plist, so it prints "unknown".

The two checks worth keeping are the contrast sweep (render every block both ways; flag any that is
dark in a bitmap and light in a PDF) and the figure sweep run in several separate processes (flag any
figure whose ink coverage moves between runs).

## What it is made of

| File | What it holds |
| --- | --- |
| `Services/Exports/HelpPDFTheme.swift` | The print stylesheet. Fixed points, explicit ink, and `onWhite(_:)`, which darkens a module's hue until it clears WCAG AA on white — `ModulePalette` says of itself that several of its hues fail there |
| `Services/Exports/HelpPDFPage.swift` | Page geometry, and `HelpPDFPaper` (system / A4 / Letter) |
| `Services/Exports/HelpPDFBlockView.swift` | Each `HelpBlock`, set for print, plus the whole-guide cover |
| `Services/Exports/HelpPDFExportService.swift` | Atoms, measurement, pagination, drawing, the stamp |
| `Modules/Help/HelpExportButton.swift` | The toolbar item and its popover |
| `Services/ExportService.swift` | `savePDFToFile(data:defaultName:)` — the sibling of the CSV door |

**Pagination is the part to understand.** The document is flattened into *atoms*: the smallest pieces
that may not be split. A callout is one atom however long it is. A list is one atom **per item**, so a
break falls between items rather than through a sentence. A heading is kept with whatever follows it.
20 topics come to 35 pages; the reverted `NSPrintOperation` attempt made 40 and broke mid-callout.

## What is left undone

Small, and none of it blocking:

- **A topic's last block can sit alone on an otherwise empty page.** Correct — keeping it whole is
  the point — but it reads as a mistake. A modest overflow tolerance into the bottom margin would
  recover some cases; it would not have recovered the one that was seen (a callout ~14pt too tall).
- **The contents page carries no page numbers.** Every topic starts a fresh page and every page names
  the guide, so the list says what is inside rather than being navigated by. Real numbers would need
  a second pagination pass, and wrong ones would be worse than none.
- **Nobody has printed it.** It has been read and rasterised, not put on paper.

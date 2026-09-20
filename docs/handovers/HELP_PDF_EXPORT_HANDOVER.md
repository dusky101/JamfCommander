# Handover — help as a PDF

**State at handover:** 20 September 2026, app version 9.0. **Nothing is built**, and nothing is left
over: `HelpExport.swift` was removed on 19 September rather than left as a button that writes a blank
document. This starts from an empty file.

Read `docs/roadmap/HELP_PDF_EXPORT.md` first — it holds the intent and, more usefully, **the three
ways the first attempt failed**. This file is what is true about the code today.

---

## Proven — and what is NOT

| Established | Not established |
| --- | --- |
| `NSPrintOperation` does not work here. Three separate failures, all recorded in the roadmap entry | That `ImageRenderer` does work — it is a recommendation, not a finding |
| The guide's content model is already a list of typed blocks (`HelpBlock`) | Whether a block can be measured before it is drawn |
| The CSV and ZIP exports prove the compose-then-save shape this should copy | What a page of the guide costs to render, or how long 20 pages takes |
| The figures are real views, so they render like anything else | Whether a figure fits a page at all |

## What exists to build on

**The content.** `HelpLibrary.loadTopics()` returns 20 `HelpTopic`s, each with a Markdown body.
`HelpMarkdown.parse(_:)` turns a body into `[HelpBlock]`:

```swift
case heading(level: Int, text: String)
case paragraph(String)
case bulleted([String])
case numbered(start: Int, items: [String])
case code(language: String?, text: String)
case figure(id: String)
case callout(HelpCallout, [HelpBlock])
case divider
```

**That list is the whole reason this is tractable.** Pagination means measuring blocks and deciding
where to break; a flat array of typed blocks is exactly what you want to walk. `MarkdownView` already
renders them — the PDF renderer should share that vocabulary, not re-derive it.

**The figures** are in `HelpFigures.swift`, looked up by id. Each one instantiates the view its
module actually uses. `FigureMarker` and `MarkedRow` are there and currently unused — four figures
were deleted on 19 September because the views they needed could not be composed. **Do not re-draw a
figure by hand for the PDF**; see `HELP_OVERHAUL_HANDOVER.md`, phase D, for why that was the lesson.

**The save.** `ExportService.saveCSVToFile(content:defaultName:) -> Bool` is the door to copy: one
`NSSavePanel`, write, report. `exportAllDataToZip` does the same for a ZIP. **Compose in memory,
then one panel.** Both are in `Services/ExportService.swift`.

## The trap that cost the first attempt twice

**The app forces `.preferredColorScheme(.dark)`.** An `NSHostingView` made from that inherits the
dark *appearance*, and `.primary`, `.secondary` and every `Color(nsColor:)` resolve against the
appearance — not against SwiftUI's `colorScheme` environment value. Setting
`.environment(\.colorScheme, .light)` changes the value and not the appearance, which is how the
first attempt produced white text on a white page and looked correct in every preview.

**Prove the body text is black before building anything on top of it.** One page, one paragraph,
opened in Preview. The roadmap entry says this cost the first attempt twice, and it is the single
cheapest thing to check.

## The route to try, and why

`ImageRenderer` (macOS 13+) exposes `render { size, context in … }`, handing you a `CGContext`. A
`CGPDFContext` can be driven a page at a time through it, and the figures survive because they are
still SwiftUI views rather than pictures of views.

**Unproven.** Nobody has rendered a page of this guide. Treat the first spike as finding out whether
the approach works at all, not as the start of the feature.

## Pagination is the actual work

Not the PDF plumbing — the deciding where pages break. A callout or a numbered list cut in half is
worse than a page that ends early. The blocks are typed, so each kind can be measured and kept whole.

## Stamp every export

The guide's whole claim is that it matches the build. **A PDF is a copy that stops being true the
moment either moves**, so every export carries the app version and the date it was made.
`SettingsTransfer` already reads the real app version for `.jamfconfig` files — it hardcoded `1.0.0`
until 19 September 2026, which is the mistake not to repeat.

## Where it is invoked from

The guide is its own window (`HelpView`, `Window(id: HelpWindowID)`). A toolbar item there is the
obvious home for "Export this page" and "Export the whole guide". There is no export affordance in
the guide today.

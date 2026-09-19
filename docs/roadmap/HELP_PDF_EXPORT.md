# Roadmap — help as a PDF

## What

Save a help page, or the whole guide, as a PDF from inside the app.

## Why

The case is not that the reader wants a PDF — they have the guide open. It is **sending it to
somebody who cannot open the app**:

- Handing a security team the *Privileges* page to approve, before anyone creates the API role.
- An MSP giving a customer the setup pages for their own tenant.
- Attaching *Before using Installomator* to a change request.

Today the only way to do any of that is a screenshot or retyping it.

## Attempted 19 September 2026, and reverted

`HelpExport.swift` built the whole thing on `NSPrintOperation` with `jobDisposition = .save` — the
route the entry originally recommended, on the reasoning that macOS gives Save as PDF free from the
print system. **It produced unusable output twice and was removed rather than left as a button that
writes a blank document.** The code is in git history; the findings are more use than the code.

**What it got wrong, in order:**

1. **White text on a white page.** The app forces `.preferredColorScheme(.dark)`, so
   `NSApp.effectiveAppearance` is dark and an `NSHostingView` created from it inherits that.
   `.environment(\.colorScheme, .light)` sets SwiftUI's *value* but does not reach AppKit:
   `.primary`, `.secondary` and every `Color(nsColor:)` resolve against the **appearance**. Only the
   explicitly-tinted things printed — section headers, module colours, one red callout icon.
2. **Then nothing at all.** Setting `hosting.appearance = NSAppearance(named: .aqua)` fixed the
   colour resolution and the export came out **completely blank**, all forty pages. Not diagnosed.
3. **Forty pages for twenty topics**, with the content that did print falling at the bottom of
   otherwise empty pages. `NSPrintOperation` was paginating a single tall `NSHostingView` and
   breaking wherever the boundary landed.

**The lesson:** printing a live SwiftUI view hierarchy means fighting the appearance system, the
layout system and AppKit's pagination at once, and getting no useful diagnostics from any of them.

## The approach to take instead

In the maintainer's words: *"create a real pdf creator section. instead of using the apple exporter.
a file exporter like what is already setup for the export of csvs"*.

**Build the PDF, then write the file.** That is exactly the shape `ExportService` already has: every
CSV export composes its content in memory and hands it to `saveCSVToFile(content:defaultName:)`,
which runs an `NSSavePanel` and writes. `exportAllDataToZip` does the same for a ZIP. A PDF export
should produce `Data` and go through the same door — one place that asks where to save, writes, and
reports.

Two candidate renderers, both of which give control over page breaks rather than taking what AppKit
decides:

- **`ImageRenderer`** (SwiftUI, macOS 13+). Its `render { size, context in … }` hands you a
  `CGContext`, so a `CGPDFContext` can be driven a page at a time. Keeps the figures, because they
  are still views.
- **Core Graphics directly**, drawing text runs and rules. Loses the figures, and is a lot of work
  for a guide that is mostly prose.

`ImageRenderer` is the one to try. It also sidesteps the appearance problem, because the view is
rendered rather than hosted — but **verify that** rather than assume it.

**Pagination is the real work.** Measure each `HelpBlock`, decide whether it fits in the page
remaining, and start a new page if not. A callout or a numbered list cut in half is the failure this
must avoid, and it is what the first attempt could not control.

## Constraints that carry over

- **Every export carries the app version and the date.** The guide's whole claim is that it ships
  with the app and therefore matches the build. A PDF is a copy and stops being true the moment
  either moves; a page read six months later should say how old it is.
- **The page must be light.** Whatever renderer is used, prove the body text is black before
  building anything else on top of it. That is the trap that cost the first attempt.
- **`NSSavePanel` is what grants a sandboxed app permission to write** where the reader chose. Keep
  it, as the CSV path does.

# Roadmap — help as a PDF

## Built, 19 September 2026

`Modules/Help/HelpExport.swift`. The guide's toolbar has an **Export** menu: *Export This Page…* and
*Export the Whole Guide…*, each writing a PDF through `NSSavePanel` — which is also what gives a
sandboxed app permission to write where the reader chose.

The original case is met: a security team can be handed the *Privileges* page before anyone creates
the API role, and a customer the setup pages, without either needing the app.

Two decisions worth knowing:

- **Every export is stamped** with the app version and the date. The guide's whole claim is that it
  ships with the app and therefore matches the build; a PDF is a copy and stops being true the moment
  either moves. A page read six months later should say how old it is.
- **The document is forced to light appearance.** The app is locked to dark, and a dark-mode render
  would arrive as white text on a page that prints blank.

## What remains

**Pagination is `NSPrintOperation`'s.** It breaks wherever the page boundary falls, so a long callout,
a numbered list or a figure can be cut across two pages. This is the part the entry always said was
not cheap, and it is still not: fixing it means a renderer that measures each block and decides its
own breaks, rather than handing AppKit one tall view.

Whether that is worth building depends on how the exports are actually used. A page handed to a
security team is two or three sides; a whole-guide export is twenty-odd and will show the seams.

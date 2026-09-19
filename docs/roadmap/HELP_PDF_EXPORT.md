# Roadmap — help as a PDF

## What

Save a help page, or the whole guide, as a PDF from inside the app.

In the maintainer's words: *"maybe add a option to download individual sections as a pdf or the
complete help as a pdf?"*

## Why

The case is not "the reader wants a PDF" — they have the guide open. It is **sending it to somebody
who cannot open the app**:

- Handing a security team the *Privileges* page to approve, before anyone creates the API role.
- An MSP giving a customer the setup pages for their own tenant.
- Attaching *Before using Installomator* to a change request.

Today the only way to do any of that is a screenshot or retyping it.

## What it touches

- `Modules/Help/MarkdownView.swift` renders into a `ScrollView`, which does not paginate. A PDF needs
  either `NSPrintOperation` over an `NSHostingView`, or a second render path that lays blocks out
  page by page.
- `Modules/Help/HelpLibrary.swift` already loads every topic's body, so "the whole guide" is a
  concatenation, not a new fetch.
- File saving would follow `SettingsService` and `ExportService` — `NSSavePanel`, and the same
  reporting of what actually happened.

## Known traps

**1. macOS already does most of this for free.** Any printable view gets **Save as PDF** from the
standard print dialog. A **Print** command on the help window (⌘P) would deliver the feature by name
for a fraction of the work, and it would be the familiar route rather than a bespoke one. Try that
before building an exporter — if it is good enough, this entry is finished.

**2. Pagination is the whole job.** The hard part is not producing a PDF, it is producing one that is
not embarrassing: a callout split across a page break, a numbered list orphaned from its heading, a
code block cut in half. Whatever renders the PDF has to keep blocks whole, which the on-screen
renderer never has to think about.

**3. A PDF goes stale the moment it is sent.** The guide's stated advantage is that it ships with the
app and always matches the version running. A PDF is a copy that does not. It should carry the app
version and the date it was written, or somebody will be following setup instructions for a build
from a year ago.

**4. The content is already portable.** The pages are Markdown files in the bundle. Anyone who wants
a document can be handed one. Worth being clear about what the PDF adds over that — mostly layout
and the fact that a non-technical reader will open it.

## Open questions

1. **Is a Print command enough?** See trap 1. This decides whether the rest of this entry is needed
   at all.
2. **Per page, per section, or whole guide?** Three different pieces of work; the whole guide needs a
   contents page and the others do not.
3. **Does it need the app's look**, or is a plain readable document better for something that will be
   printed and emailed? The guide is designed against a dark background; that is wrong on paper.
4. **Where does it live** — a button on the help window, an item in the File menu, or both?

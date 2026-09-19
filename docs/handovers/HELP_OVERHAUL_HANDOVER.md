# Handover — Help overhaul

**State at handover:** 19 September 2026, app version 8.5. Phase 1 is **committed**, and the window
has now been opened once — see the table below for exactly how far that goes.

Read this before touching anything in `Modules/Help/` or `Resources/Help/`.

> This file replaces an earlier version written *before* the work started, which is what
> `.claude/rules/docs-workflow.md` now forbids. Everything below was checked against the code on the
> day it was written.

---

## What was built in phase 1

The single 281-line scrolling document in `Modules/Help/HelpView.swift` was replaced by a
**searchable index plus a rendered Markdown page**, modelled on the Help feature in the maintainer's
other app (`~/Codingapps/ssmacos/ssmacos/Features/Help`), which he pointed at as the target.

Content now lives in Markdown files, one per topic, so a wording fix is a text edit rather than a
code change, and the same text feeds both the page and the search index.

| File | Lines | What it is |
| --- | --- | --- |
| `Modules/Help/HelpSection.swift` | 38 | The three index sections and their symbols |
| `Modules/Help/HelpTopic.swift` | 58 | One page: id, title, section, summary, keywords, body |
| `Modules/Help/HelpMarkdown.swift` | 208 | Block-level Markdown parser → `[HelpBlock]` |
| `Modules/Help/HelpSearch.swift` | 98 | Ranked search; `groups(for:)` orders sections by relevance |
| `Modules/Help/HelpLibrary.swift` | 130 | The manifest, and the bundle loader |
| `Modules/Help/MarkdownView.swift` | 153 | Renders the blocks |
| `Modules/Help/HelpView.swift` | 184 | `NavigationSplitView`: index left, page right |
| `Resources/Help/*.md` | 8 files | The content |

`HelpPresenter.shared` still opens it, and gained `requestedTopic` plus `present(_:)` so a caller can
deep-link to a page. The existing callers (`SidebarView`, `JamfCommanderApp`) set `isPresented`
directly and are unchanged.

## Proven — and what is NOT

| Proven on screen | Never exercised |
| --- | --- |
| The window opens; the index draws all three sections | **Search has never been run** |
| Selecting a topic renders its page | Seven of the eight pages have not been read |
| Headings, paragraphs, bullets and callouts render | `HelpPresenter.present(_:)` — nothing calls it |
| `welcome.md` reads correctly end to end | The empty-search-result state |

Every page now parses with balanced inline emphasis, checked by compiling `HelpMarkdown.swift`
standalone and running it over all eight files. That proves the *parser*, not the *rendering*: a
block can parse perfectly and still look wrong.

The maintainer's verdict on first sight was "good but not great", with no specifics — so the layout
is unfinished, not broken. Read all eight pages and form your own view before changing anything.

### Found the first time the window was opened

`welcome.md` rendered with half of two bullets falling out of the list and appearing as loose
paragraphs after it, one of them showing a literal `*` where emphasis had been split.

The cause was the parser, not the content. The guide's pages are hard-wrapped, so a bullet routinely
spans several source lines; the list loop only continued while a line *began* with `- `, so the first
line became the item and the rest became a paragraph — taking half of any `*emphasis*` with it.
Markdown's lazy continuation. Fixed in `HelpMarkdown.consumeContinuations(of:lines:index:)`.

Worth knowing because it is the shape of bug to expect: **the parser has only ever seen eight
documents.** Phase 2 adds eleven more, written by somebody who will reasonably assume ordinary
Markdown works. Tables, nested lists and images are not supported at all — see Constraints.

## The bundling trap, confirmed by experiment

This target uses Xcode **synchronised folders** (`fileSystemSynchronizedGroups`, objectVersion 77),
so a new file in `Resources/Help/` is added to the target automatically — no `.pbxproj` edit.

But resources are **flattened**. `Resources/Help/welcome.md` is copied to
`Contents/Resources/welcome.md`, *not* into a `Help` folder. Verified by building a probe file and
looking in the bundle.

Two consequences:

1. `HelpLibrary.markdown(forResource:)` tries the `Help` subdirectory and then the bundle root. **The
   second lookup is the one that succeeds today.** Do not delete it as dead code.
2. **A help file's name must be unique across every resource in the app.** `JamfCommander/README.md`
   is already swept into the same flat directory, so `Resources/Help/README.md` would collide.

## What phase 2 has to do

Phase 1 deliberately ported the *existing* content and invented almost none, so that it is a pure
mechanism change and any difference on screen is a rendering bug rather than a rewrite. Phase 2 is
the content the maintainer actually asked for.

**1. Split `modules.md` into one topic per module.** It is currently a single page with nine `##`
headings — a faithful carry-over plus the modules that were missing, but not the shape he asked for
("a section/md file for each section"). Nine topics: Dashboard, Policies, Profiles, Blueprints,
Computers, Packages, Scripts, Installomator, Unused. Each should answer what it lists, what you can
do to it, and **the one thing that surprises people** — that last part is the value, and most of it
currently exists only in code comments.

**2. `apis.md` — what APIs the app uses now.** Asked for explicitly. Three of them, which is the
point: the Jamf **Classic** API (`JSSResource/…`, XML for writes), the Jamf **Pro** API
(`api/v{n}/…`, JSON, and the version varies per resource — computers are v3), and the **Platform API
Gateway** for Blueprints, with its own credentials and region lock. Plus the unauthenticated read of
Installomator's label list from GitHub. `docs/JAMF_API_REFERENCE.md` has all of it; write it for an
administrator deciding what to grant, not for a developer.

**3. `whats-coming.md` — future versions.** He named **mobile devices** specifically: the app is
computers-only today. Draw the rest from `docs/roadmap/`: per-domain caching (`CACHING.md`), showing
which policies run a script (`SCRIPT_USAGE.md`), and multiple Jamf environments
(`MULTIPLE_ENVIRONMENTS.md`). Say plainly that these are intentions, not commitments.

**4. Add the new topics to `HelpLibrary.topics`** with summaries and keywords. Keywords are the field
authored for search — the words an administrator types that the title does not contain.

## Constraints

- **British English**, calm and professional. Match the existing pages.
- **Never put a real credential, token or instance URL in help copy**, including as an example. Use
  obviously fake placeholders (`https://yourcompany.jamfcloud.com`).
- Callouts are `> **Note:**`, `> **Tip:**`, `> **Warning:**`, `> **Important:**` at the start of a
  blockquote. `HelpMarkdown.calloutTone(of:)` strips the marker; the view draws the icon and colour.
- The parser handles headings, paragraphs, `-`/`*` bullets, ordered lists, fenced code, blockquote
  callouts and `---`. It does **not** do tables, nested lists or images. Inline bold, italic, code
  spans and links work, because paragraphs go through `AttributedString(markdown:)`.
- Every page should open with `# Title` matching its `HelpTopic.title`, so the page and the index
  agree.

## Open questions

1. **Sheet or window?** Help is still a sheet, so it cannot be left open beside the thing it
   describes — which is what reference material is for. The reference app uses a separate `Window`
   scene. Deliberately not changed in phase 1: it affects both entry points (sidebar footer and ⌘?)
   and is a decision, not a detail.
2. **Figures.** The reference app renders live in-app diagrams from a ```figure``` fence, so the
   guide shows the real thing and cannot drift. ~300 lines plus one view per figure. Omitted from
   phase 1; `HelpBlock` has no `figure` case, so adding it means touching the parser.
3. **Deep links from the app.** `HelpPresenter.present(_:)` takes a topic id and nothing calls it
   yet. A "?" on each module's header would be the obvious use, and would overlap with the sidebar
   hover hints (`SidebarHint`) — decide which is the source of truth before both exist.
4. **Does help need the unofficial/disclaimer note?** `welcome.md` currently carries one paragraph
   saying the app is not affiliated with Jamf. Check that is the wording he wants.
5. **Print, and Save as PDF.** The maintainer asked for the guide to be saveable as a PDF — to hand
   the *Privileges* page to a security team, or the setup pages to a customer, without them needing
   the app. Full background and traps: `docs/roadmap/HELP_PDF_EXPORT.md`.

   **Try a Print command first.** macOS gives **Save as PDF** free from the standard print dialog,
   so `⌘P` on the help window may deliver the whole request for a fraction of a bespoke exporter.
   Ask him before building it — it is his call whether it belongs in phase 2 — and if he says yes,
   two things decide whether it is small or not:

   - `MarkdownView` renders into a `ScrollView`, which does not paginate. Printing an
     `NSHostingView` of the page is the cheap route; making sure a callout or a numbered list is not
     cut in half by a page break is the part that is not cheap.
   - The guide's stated advantage is that it ships with the app and always matches the build. A PDF
     is a copy that does not, so whatever is produced should carry the app version and the date.

# Handover — Help overhaul

**State at handover:** 19 September 2026, app version 8.5. Phase 1 is **committed**. **Phase 2a**
(layout and search) and **phase 2b** (the content) are both done. The overhaul is complete as
specified; what remains is the four open questions at the bottom, all of which are the maintainer's
calls.

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

| Proven on screen | Never seen on screen |
| --- | --- |
| The eight **phase 1** pages, read end to end at 900×900 and at 1500×1204 | **Every one of the thirteen pages phase 2b added** |
| Search run for "403", "unscoped", "client secret" and a miss | **Module colour on an index row and on a page's H1** |
| The empty-search-result state | The index at twenty topics — it was eight when it was last seen |
| Keyboard paging: Page Down and Home move the page | Whether a Markdown link renders as a clickable link |
| The sheet tracks the window it is presented on | `HelpPresenter.present(_:)` — nothing calls it |

**Read the right-hand column before trusting anything about phase 2b.** The maintainer asked that
this session stop launching the app — it costs him time and money — so phase 2b was verified by
other means and **not once looked at**. What *was* checked:

- It builds, and all twenty `.md` files reach `Contents/Resources/` with no name collision
  (`README.md` is the only other Markdown in that flat directory).
- Every topic in the manifest resolves to a file on disk, every file is in the manifest, and every
  page's `# Title` matches its `HelpTopic.title` exactly — checked by script, not by eye.
- All twenty pages were run through `HelpMarkdown` compiled standalone: every page opens with an
  H1, every paragraph and list item parses as inline Markdown, no unbalanced `**`, and none of the
  three unsupported shapes (tables, images, indented sub-bullets) appears anywhere.
- No straight quotes or apostrophes, and no American spellings, anywhere in the content.

Also unseen: the index rows' hover treatment — a link pointer, the module's colour as the wash on
a "Using the app" row and the neutral `.primary` wash elsewhere, and the 3pt nudge — copied from
`SidebarModuleRow`. And the section headers, which needed rebuilding from an `Image` and a `Text`
with their own styles because `.listStyle(.sidebar)` re-applies its treatment over a `Label` and
silently ignored the `.foregroundStyle(.primary)` phase 2a put on one.

None of that proves a *rendering*. A block can parse perfectly and still look wrong, which is the
lesson phase 1 already paid for once.

Every page now parses with balanced inline emphasis, checked by compiling `HelpMarkdown.swift`
standalone and running it over all eight files. That proves the *parser*, not the *rendering*: a
block can parse perfectly and still look wrong.

The maintainer's verdict on first sight was "good but not great", with no specifics. All eight pages
were then read on screen and the specifics turned out to be six things, fixed in phase 2a — see
below.

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

## What phase 2a fixed, and what it proved

Reading every page at two window sizes, and running the search, turned "good but not great" into a
list. All of the following were seen on screen before and after.

- **The sheet ignored the window.** `minWidth: 820, idealWidth: 980, maxWidth: .infinity` settles a
  sheet on its *minimum*: the guide drew at ~820×785pt whether the window was 1428pt wide or 1500,
  marooned in the middle with a third of the window empty. `.presentationSizing(.page)` was tried and
  only fixed the height. It now measures the window it is attached to — `HostWindowSizeReader` in
  `HelpView.swift` — and sizes to it. **The trap:** `window.sheetParent` is nil in
  `viewDidMoveToWindow`, so a first attempt measured the sheet's own window and never corrected;
  resolve the host one run-loop turn later.
- **Headings floated.** A uniform `VStack(spacing: 14)` gave 20pt over a heading and 14pt under it,
  so it belonged to neither section. Spacing is now per block — `HelpRhythm.swift`, a new file — and a
  heading gets 26pt over and 8pt under.
- **Lists were unscannable.** 6pt between items, and most items wrap, so the gap between two items
  matched the gap inside one. Now 10pt, with a shared 22pt marker column so bullets and numbers line
  up and wrapped lines hang under the text.
- **`note` callouts read as disabled** — `Color.secondary` drew a grey icon in a grey box. The four
  tones are now blue, green, orange, red, each with its own symbol and an accessibility label.
- **Search ranked the wrong page first**, in two separate ways. `groups(for:)` promoted every match
  in a section to sit beside that section's best match, so "403" put Welcome (score 1) above the
  troubleshooting page (score 6). Search now draws a **flat ranked list** with a result count;
  `groups(for:)` is for browsing only. Separately, `welcome.md` advertised *403*, *unscoped* and
  *client secret* as example searches, which put all three in its own searchable body and made it a
  false hit for the three terms it invited people to try. That sentence has been reworded.
- **Search did not move the page**, and the empty-result message was drawn *below* a full-height
  empty list, hundreds of points from the search box. The page now follows the best match when the
  open topic drops out of the results, and the message sits where the list would be.
- **The page could not be scrolled from the keyboard.** `.focusable()` alone is not enough on macOS —
  Page Down, the arrow keys and the space bar all did nothing. `HelpPage` now wires them against
  `onScrollGeometryChange` and `ScrollPosition`.

Also fixed: the guide had no title (the index column now carries one); `stethoscope` for the
Reference section became `book.closed`; straight quotes and apostrophes across all eight pages became
typographic ones; and `modules.md` said a failed Dashboard read "shows — rather than 0", which is not
a sentence.

## What phase 2b built

The guide went from eight topics to **twenty**, and the index now mirrors the sidebar.

**One topic per sidebar module.** `modules.md` — a single page with nine `##` headings — is deleted
and replaced by nine pages: `module-dashboard`, `-policies`, `-profiles`, `-blueprints`,
`-computers`, `-packages`, `-scripts`, `-installomator`, `-unused`, listed in **sidebar order**. Each
answers what it lists, what you can do to it, and the one thing that surprises people — the last of
which is the part that is worth anything, and most of it existed only in code comments and
`JamfCommander/README.md` before this.

They are named `module-…` on purpose. The bundle is flat (see the trap above), so `packages.md` or
`scripts.md` are exactly the names something else in the app might one day claim.

**Modules carry their colour into the guide.** `HelpTopic` gained `module: AppModule?`. When it is
set, the index row shows the module's SF Symbol in `AppModule.accentColour` and `MarkdownView` draws
the page's level-1 heading in the same colour with the same symbol. Headings *inside* a page stay
neutral — nine pages each a solid wall of one hue would be worse than no colour at all. The
maintainer asked for this directly: "each of the section headers should have the same colour as the
section in the app".

**The index section headers were the dimmest thing in the window** — `.secondary` at caption size,
quieter than the summaries under the rows they introduced. They are `.primary` and semibold now, with
the symbol left in the accent colour. Also his ask.

**`apis.md` — which APIs this app uses.** Written for whoever approves the app before it is pointed
at production, not for a developer: the Classic API, the Pro API (with the per-resource version
number spelled out), the Platform API Gateway, and the unauthenticated GitHub read, plus a short
allowlist section naming the three hostnames and saying everything is outbound HTTPS.

**`blueprints-integration.md` — a page of its own.** He said the guide "only glances on the account
section api settings needed". It now walks through creating the integration in **Jamf Account**:
scope level *platform environment*, the six capabilities, where the environment ID is hidden, and the
four fields in Settings. Four traps are called out — the region lock, the fact that a 403 here most
often means the scope level rather than a capability, that **Jamf integrations expire after six
months**, and that the values travel inside a `.jamfconfig`.

`getting-connected.md` and `privileges.md` stopped half-explaining Blueprints and now point at it.

**Two external links, both verified to resolve** on 19 September 2026 rather than guessed:

- `https://developer.jamf.com/platform-api/reference/getting-started-with-platform-api` — Jamf's own
  walkthrough of creating an integration; it is where the six-month expiry is documented.
- `https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/API_Roles_and_Clients` — the Jamf
  Pro screen `api-client.md` describes. The `-current` form is used deliberately; the
  version-numbered URLs rot.

  **Unverified:** whether a Markdown link renders as a clickable link in `Text(AttributedString)`
  here. Both are written with the full URL as the link *text* so they are readable and copyable
  either way, and page text is now `.textSelection(.enabled)` so a URL or a privilege name can be
  copied out.

**`whats-coming.md`.** Mobile devices first, because he named it: the app is Macs only. Then the
three open roadmap entries — caching, script usage, multiple environments — plus the PDF, and a
closing section separating what is *deliberate* from what is *missing*. Stated as intentions, with a
callout saying so and no dates.

**`api-client.md` is now "Creating the API client in Jamf Pro"**, because there is a second
credential-creation page beside it and "in Jamf" no longer distinguishes them.

**`prerequisites.md`**, added afterwards on the maintainer's ask: the two things that live outside
this app. Installomator — what the script is, why the module is useless without it in Jamf, and the
releases page — and **DDM Explorer**, the free Jamf app on the Mac App Store that builds a
declaration and hands you its JSON. The codebase only ever calls the latter "the Jamf DDM app";
DDM Explorer (`Jamf-Concepts/ddm-explorer`) is what that was taken to mean, confirmed against the
repository rather than assumed. Placed **second in Getting started**, straight after *Welcome*, with
a first line making clear neither is needed to connect the app or to use the other seven modules.

## Phase B — figures, and the index rebuild that preceded it

The maintainer's verdict on the nineteen-topic guide was that it was "too wordy" and "will turn
people away", set against SSMacOS's guide, and that what was missing was "actual images from the
app". Two phases answered it.

**The index stopped showing summaries while browsing.** Nineteen titles under three headings is a
list you take in at a glance; the same nineteen with a grey two-line summary under each is a wall of
secondary text. Summaries now appear only in search results, where you need them to judge a hit.
This was the single biggest cause of the wordiness, and it is what the reference app does.

**Sections collapse**, all but the one holding the page you are on — an index that showed no sign of
where you were would be worse than a long one. Headers took their own colours, kept clear of the
nine in `ModulePalette` so a module's colour still means that module.

**Search became a panel.** ⌘F or click, a large field, ranked results, arrows to move and Return to
open. As a field in the corner of the sidebar it was being ignored; the guide's whole case is that
you look things up.

**The welcome page lost about two thirds of its text** and gained the app icon, the version, and a
figure of the index. The maintainer asked for exactly that.

**Every module page now carries a figure**, plus `installomator-setup`. Prose-heavy pages —
`prerequisites`, `blueprints-integration`, `module-blueprints`, `module-dashboard` — were broken up
with level-3 headings rather than left as runs of bold-led paragraphs.

### Still not done

- **"Prerequisites in larger type"** was asked for and interpreted rather than implemented: the
  renderer has no lead-paragraph concept, so the section was given prominence by position instead.
  A `lead` block would be a small parser change if it is still wanted.
- **The search panel is a sheet presented from inside the help sheet.** It works, and the maintainer
  says it "works well", but sheet-on-sheet remains the thing most likely to behave oddly if the help
  window ever becomes a `Window` scene (open question 1).

## Phase C — annotated figures

The maintainer's note on phase B was that the figures were "random images from that page" rather
than design: what he wanted was figures that explain a **job**, with numbered markers the prose can
point at — "*see 2b*".

**`FigureMarker` and `MarkedRow`.** A figure carries small numbered capsules; the page refers to them
in bold — "the label goes in **2**". The text cannot render a badge inline (the parser has no custom
inline views and `AttributedString` carries no colour), so bold is the convention. It is consistent
across every annotated figure, which is what makes it readable.

**The Installomator deployment sheet's markers are not invented.** The sheet itself is labelled
"1. Select Target Category" through "6. Version Pinning", so the figure uses the app's own numbers
and a reader can match the picture to the screen without translating. Version pinning is broken out
as 6a–6d for the same reason.

Nine workflow figures were added: `connection-settings`, `platform-settings`, `installomator-deploy`,
`version-pinning`, `package-upload`, `clone-options`, `unused-actions`, `blueprint-editor`,
`computer-inspector`. Twenty figures now, across fourteen pages.

**The app icon is drawn chromeless.** `HelpFigures.chromelessIDs` lists figures with no card: a
bordered box around the app's own icon reads as a screenshot of something, when the point is that it
*is* the app. Everything else keeps the card.

**Tagline:** "Two hundred policies, one action." — proposed, not settled.

## Phase D — figures rebuilt from the real views

Phase C's figures were drawn by hand from README prose and memory. The maintainer opened the guide,
compared the bulk-action figure with `ActionPanelView`, and it was not close: the real panel is an
action name *above* a large soft button in equal-width columns on the elevated bar background; the
figure showed small tinted capsules with names beside them. **"Where is this coming from"** is the
right question and the answer was: from me, not from the code.

**The rule now, and it is not negotiable: a figure instantiates the view the module uses.**

That is possible because the card views take a model and nothing else — no service, no bindings:
`PolicyCardView(policy:categoryName:)`, `ProfileCardView`, `PackageCardView(item:isSelected:)`,
`BlueprintCardView`, `RedundantRowView(item:)`, `StatCard`. The action bars are built from
`ActionBarColumn` and `SoftIconLabel`, which are equally reusable, and `StatusBadge` takes only a
`JamfItemStatus`. Figures use `SoftIconLabel` rather than `SoftIconButton` because a figure must not
be clickable.

`BlueprintRowFigure` decodes its samples from JSON rather than constructing them, because `Blueprint`
has a custom `init(from:)`. That is better than a workaround: the figure's data goes through the same
decoding path a real blueprint does, so a change to the coding keys breaks the figure too.

**Nine figures were deleted rather than left wrong.** `clone-options`, `package-upload`,
`blueprint-editor`, `computer-inspector`, `computer-row`, `package-tabs`, `script-parameters`,
`connection-settings`, `platform-settings`, plus `installomator-deploy` and `version-pinning`. Each
illustrated a **sheet** — `DeploymentConfigSheet`, `PackageUploadPage`, `BlueprintEditorSheet`,
`SettingsPlatformSection` — and a sheet is one large view with its state wired in, not a set of
reusable pieces a figure can borrow. Drawing them by hand is how the last round went wrong.

The numbered `FigureMarker`s went with them. They only ever made sense pointing at parts of a real
reproduction; on an invented list they were pointing at things the guide had made up. `FigureMarker`
and `MarkedRow` remain in the file, unused, for whoever grounds the sheets.

### If the sheet figures are wanted

The honest route is to refactor each sheet the way the action bars already are: pull its sections out
as presentational views taking values rather than bindings, and let both the sheet and the figure use
them. That is real work in the modules, not in the guide, and it should be decided as such.

## Constraints

- **British English**, calm and professional. Match the existing pages.
- **Never put a real credential, token or instance URL in help copy**, including as an example. Use
  obviously fake placeholders (`https://yourcompany.jamfcloud.com`).
- Callouts are `> **Note:**`, `> **Tip:**`, `> **Warning:**`, `> **Important:**` at the start of a
  blockquote. `HelpMarkdown.calloutTone(of:)` strips the marker; the view draws the icon and colour.
- The parser handles headings, paragraphs, `-`/`*` bullets, ordered lists, fenced code, blockquote
  callouts and `---`. It does **not** do tables, nested lists or images. Inline bold, italic, code
  spans and links work, because paragraphs go through `AttributedString(markdown:)`.
- **What the unsupported shapes actually do.** Checked by compiling `HelpMarkdown.swift` standalone
  and running these through it. None of them fails loudly, which is what makes them dangerous:
  - An **indented sub-bullet is silently flattened into a sibling**. `- Top` / `  - Child` parses to
    one flat list. The hierarchy simply disappears; nothing on screen says so.
  - A **table becomes one run-on paragraph** — `| Column | Other | | --- | --- | | a | b |`, on
    screen, verbatim. Not graceful degradation. Worth knowing because *Privileges* is the page most
    naturally written as a table.
  - A **sub-bullet inside an ordered list splits it into three blocks** — `1.`/`2.`, then a
    full-width bullet list, then `3.`. The numbering correctly resumes at 3, but it looks broken.
- Every page should open with `# Title` matching its `HelpTopic.title`, so the page and the index
  agree.

## Open questions

1. ~~**Sheet or window?**~~ **Answered: window** (19 September 2026). The maintainer worked it out
   from the reference app's title bar: *"why don't i have the red green and yellow buttons and the
   minimise side bar like ssmacos then … mine seems squashed up"*. He was right about the cause. A
   sheet has no title bar, so the page began flush against the top edge; and a sheet cannot be left
   open beside the thing it describes, which is the whole point of reference material.

   `Window("Jamf Commander Guide", id: HelpWindowID)` in `JamfCommanderApp`, `.defaultSize(1100×900)`,
   `.restorationBehavior(.disabled)` so a guide left open does not reopen in front of the app next
   launch. Both entry points call `openWindow(id:)`. `HelpPresenter` lost `isPresented` and now only
   carries a deep-link request; `HostWindowSizeReader` and the sheet sizing went with it, because a
   window is sized by its scene and by the reader.

   **Previously:** still open, and still the maintainer's call. Help is a sheet, so it cannot
   be left open beside the thing it describes — which is what reference material is for. The
   reference app uses a separate `Window` scene. It affects both entry points (sidebar footer and
   ⌘?) and is a decision, not a detail. Phase 2a fixed the *size* complaint without touching this:
   the sheet now tracks the window. `HostWindowSizeReader` already falls back to `window` when there
   is no `sheetParent`, so it keeps working if this ever becomes a scene.
2. ~~**Figures.**~~ **Built** (19 September 2026). `HelpBlock` gained a `figure(id:)` case, a
   ```figure``` fence resolves to `HelpFigureView(id:)`, and `HelpFigures.swift` holds the registry
   and eleven figures. They are drawn from the app's own types — `AppModule.navigationModules` for
   the sidebar, `RedundantReason.allCases` with its own `icon`, `colour` and `explanation` for the
   Unused reasons, `PackageViewMode.allCases` for the Installomator views, `JamfItemStatus` for the
   badges — so adding a module or a reason updates the picture without anyone remembering to. The
   app icon and version come from `NSApplication` and the bundle.

   **Nothing in a figure may read the tenant.** They are presentational only: an illustration
   showing somebody's real policy names would be a privacy problem and a support problem at once.

   `HelpMarkdown.figureIDs(in:)` lists every id a page references. The scratch checker run over all
   twenty pages asserts each one resolves *and* that no registered figure is unused — a typo should
   be caught by whoever changes the content, not found by a reader. There is no test target, so that
   check is a script rather than a test; it is worth re-running after any content change.
3. **Deep links from the app.** `HelpPresenter.present(_:)` takes a topic id and nothing calls it
   yet. A "?" on each module's header would be the obvious use, and would overlap with the sidebar
   hover hints (`SidebarHint`) — decide which is the source of truth before both exist.
4. **Does help need the unofficial/disclaimer note?** `welcome.md` currently carries one paragraph
   saying the app is not affiliated with Jamf. Check that is the wording he wants.
5. **Print, and Save as PDF.** **Attempted and reverted** (19 September 2026). `HelpExport.swift`
   built it on `NSPrintOperation`; it printed white text on a white page, then — once the appearance
   was forced — printed nothing at all, over forty pages for twenty topics. It was **removed rather
   than shipped as a button that writes a blank document**, and the guide's welcome page no longer
   advertises it.

   `docs/roadmap/HELP_PDF_EXPORT.md` now carries the three failures, why printing a live SwiftUI
   hierarchy is the wrong approach, and the route to take instead: build the PDF as `Data` with
   `ImageRenderer` and write it through the same `NSSavePanel` door the CSV exports use. Phase 3 of
   `docs/prompts/CACHING_AND_SHEETS_PROMPT.md`.

   **Previously: asked and answered on 19 September 2026: not now.** The maintainer
   was offered a `⌘P` Print command in phase 2 and said to leave it and make the guide complete
   first. It stays a roadmap entry — `docs/roadmap/HELP_PDF_EXPORT.md` — and the background below is
   kept for whoever picks it up.

   macOS gives **Save as PDF** free from the standard print dialog, so `⌘P` on the help window may
   deliver the whole request for a fraction of a bespoke exporter. Two things decide whether it is
   small or not:

   - `HelpPage` renders into a `ScrollView`, which does not paginate. Printing an
     `NSHostingView` of the page is the cheap route; making sure a callout or a numbered list is not
     cut in half by a page break is the part that is not cheap.
   - The guide's stated advantage is that it ships with the app and always matches the build. A PDF
     is a copy that does not, so whatever is produced should carry the app version and the date.

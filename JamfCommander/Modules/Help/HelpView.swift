//
//  HelpView.swift
//  JamfCommander
//
//  In-app help: a searchable index on the left, the rendered page on the right.
//
//  Reachable from the sidebar footer and from the standard macOS Help menu (⌘?). It was a single
//  scrolling document, on the reasoning that an administrator setting the app up reads it top to
//  bottom once. That still holds for *setup*, but most of what help now has to carry is reference —
//  what a module lists, what a refusal means — and reference is looked up rather than read through.
//
//  Content lives in Markdown files in `Resources/Help/`, one per topic, listed in `HelpLibrary`.
//  Keeping the prose out of Swift means a wording fix is a text edit rather than a code change, and
//  the same text feeds the page and the search index, so search can never offer a page that says
//  something different.
//

import SwiftUI
import Combine

/// Lets the Help menu open the sheet that `ContentView` owns.
final class HelpPresenter: ObservableObject {
    static let shared = HelpPresenter()
    private init() {}

    @Published var isPresented = false
    /// The topic to open on. `nil` opens wherever the reader last was, or the first topic.
    @Published var requestedTopic: HelpTopic.ID?

    /// Open help at a particular page.
    func present(_ topic: HelpTopic.ID? = nil) {
        requestedTopic = topic
        isPresented = true
    }
}

struct HelpView: View {
    var onDismiss: () -> Void

    @ObservedObject private var presenter = HelpPresenter.shared

    /// Loaded once when help opens: the manifest with every body read from the bundle.
    @State private var topics: [HelpTopic] = []
    @State private var selectedTopicID: HelpTopic.ID?
    @State private var searchText = ""
    /// The content size of the window this sheet is attached to, once `HostWindowSizeReader` has it.
    @State private var hostSize: CGSize?
    /// Help opens ready to be searched. Without this the page takes first focus — it is focusable so
    /// that it can be scrolled from the keyboard — and opens wearing a focus ring.
    @FocusState private var searchFocused: Bool

    /// How large to draw the guide, given the window behind it. Generous, but always inside the
    /// window, and capped so it does not become an unreadably wide measure on a large display.
    private var sheetSize: CGSize {
        guard let hostSize else { return CGSize(width: 900, height: 700) }
        return CGSize(width: min(max(hostSize.width - 120, 820), 1400),
                      height: min(max(hostSize.height - 100, 520), 1100))
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var matches: [HelpTopic] {
        HelpSearch.filter(topics, query: searchText)
    }

    private var selectedTopic: HelpTopic? {
        topics.first { $0.id == selectedTopicID }
    }

    var body: some View {
        NavigationSplitView {
            index
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
        } detail: {
            page
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        // A sheet takes its size from its content's *ideal* size, not from the window it is
        // presented on: `maxWidth: .infinity` bought nothing here, and the guide settled on its
        // minimum — about 820×785pt — whether the window was 1428pt wide or 1500. Reference material
        // that refuses the room it is given is the main reason this read as unfinished.
        // `.presentationSizing(.page)` was tried first and only fixed the height, so the size is
        // measured from the window the sheet is attached to and applied directly.
        .background(HostWindowSizeReader { hostSize = $0 })
        .appBackground()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDismiss)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .task {
            // Reading a dozen files is cheap, but it is still file I/O on every open, so it happens
            // once here rather than in `body`.
            topics = HelpLibrary.loadTopics()
            selectInitialTopic()
            searchFocused = true
        }
        .onChange(of: presenter.requestedTopic) {
            guard let requested = presenter.requestedTopic else { return }
            searchText = ""
            selectedTopicID = requested
            presenter.requestedTopic = nil
        }
        // Searching used to leave the page alone, so typing "403" changed the list and nothing else:
        // the reader kept staring at whatever page they had open, scrolled wherever they had left
        // it, with no row highlighted because the selection was no longer in the results. Follow the
        // best match instead, and only when the current page has actually dropped out.
        .onChange(of: searchText) {
            followSearch()
        }
    }

    /// Open on the requested topic, or hold the reader's place, or start at the top of the index.
    private func selectInitialTopic() {
        if let requested = presenter.requestedTopic,
           topics.contains(where: { $0.id == requested }) {
            selectedTopicID = requested
            presenter.requestedTopic = nil
            return
        }
        if let current = selectedTopicID, topics.contains(where: { $0.id == current }) { return }
        selectedTopicID = topics.first?.id
    }

    /// Keep the page in step with the results: if the open topic still matches, leave it alone, so
    /// narrowing a search does not yank the reader off the page they were reading.
    private func followSearch() {
        let results = matches
        guard !results.isEmpty else { return }
        if let current = selectedTopicID, results.contains(where: { $0.id == current }) { return }
        selectedTopicID = results.first?.id
    }

    // MARK: - Index

    private var index: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()

            if matches.isEmpty {
                emptyResults
            } else {
                topicList
            }
        }
    }

    /// The sheet has no title bar of its own, so without this the guide opens as an anonymous panel
    /// whose only label is a Done button.
    private var header: some View {
        Text("Jamf Commander Guide")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var topicList: some View {
        List(selection: $selectedTopicID) {
            if isSearching {
                // Flat and ranked. Grouping results by section promoted weak matches to sit beside
                // the strong one in their section — see `HelpSearch.groups(for:)`.
                Section {
                    ForEach(matches) { topic in
                        row(for: topic)
                    }
                } header: {
                    Text(resultsSummary)
                }
            } else {
                ForEach(HelpSearch.groups(for: matches), id: \.section) { group in
                    Section {
                        ForEach(group.topics) { topic in
                            row(for: topic)
                        }
                    } header: {
                        sectionHeader(group.section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(for topic: HelpTopic) -> some View {
        HelpIndexRow(topic: topic,
                     isSelected: topic.id == selectedTopicID,
                     showsSection: isSearching)
            .tag(topic.id)
    }

    /// A section's header in the index.
    ///
    /// The default sidebar-header treatment draws this in `.secondary` at caption size, which made
    /// it the dimmest thing in the window — quieter than the summaries under every row it was meant
    /// to introduce.
    ///
    /// Built from an `Image` and a `Text` with their own styles rather than from a `Label` with one
    /// applied over it: `.listStyle(.sidebar)` re-applies its own header treatment to a `Label`, so
    /// a single `.foregroundStyle(.primary)` on the outside was simply ignored. `.textCase(nil)`
    /// stops the list uppercasing it for the same reason.
    private func sectionHeader(_ section: HelpSection) -> some View {
        HStack(spacing: 6) {
            Image(systemName: section.systemImage)
                .font(.caption)
                .foregroundStyle(.tint)
            Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary)
        }
        .textCase(nil)
        .padding(.top, 4)
    }

    private var resultsSummary: String {
        matches.count == 1 ? "1 result" : "\(matches.count) results"
    }

    /// An empty list under a search box reads as "help is broken" rather than "nothing matched".
    /// This sits where the list would be: the previous version drew it *below* the list, which still
    /// claimed the full height, so the message landed at the bottom of a tall empty column several
    /// hundred points from the search box the reader was looking at.
    private var emptyResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No topics match “\(searchText)”.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Try a shorter term, or the words you would see on screen.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search help", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel("Search help")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Page

    @ViewBuilder
    private var page: some View {
        if let topic = selectedTopic {
            HelpPage(topic: topic)
                // Re-scroll to the top on every topic change: without the id, moving from a long
                // page to a short one leaves the reader part-way down the new one.
                .id(topic.id)
        } else {
            ContentUnavailableView(
                "Choose a topic",
                systemImage: "questionmark.circle",
                description: Text("Pick a page from the index, or search for what you need.")
            )
        }
    }
}

// MARK: - Index row

/// One row in the help index.
///
/// Its own view because it owns hover state, and because it answers the same way the app's sidebar
/// does: the pointer becomes a link pointer, the row lights in a colour and nudges a little. A
/// module's row uses **that module's colour**, so finding Policies in the guide looks like finding
/// Policies in the sidebar; the setup and reference pages use the neutral wash the sidebar footer
/// uses for Settings and Help.
private struct HelpIndexRow: View {
    let topic: HelpTopic
    let isSelected: Bool
    /// While searching the row also names the section the page lives in — the grouping a flat
    /// result list gives up.
    let showsSection: Bool

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The module's colour, or the app's standard neutral hover.
    private var highlight: Color { topic.module?.accentColour ?? .primary }

    /// A selected row already wears the list's own highlight. Drawing a second one inside it reads
    /// as a box in a box, so hover only paints when the row is not the selected one.
    private var showsHoverFill: Bool { isHovering && !isSelected }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let module = topic.module {
                Image(systemName: module.icon)
                    .font(.caption)
                    .foregroundStyle(module.accentColour)
                    .frame(width: 16, alignment: .center)
                    // The title already says which module this is; the symbol would only repeat it.
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    // Only a module row recolours its title, and only on hover — the same trade the
                    // sidebar makes. A selected row keeps the list's own foreground so the text
                    // stays legible against the selection fill.
                    .foregroundStyle(showsHoverFill && topic.module != nil ? highlight : Color.primary)

                Text(showsSection ? "\(topic.section.title) · \(topic.summary)" : topic.summary)
                    .font(.caption)
                    // `.secondary` left this fainter than the summaries were worth: they are what
                    // tells you which of nineteen pages you want, and at that weight they read as
                    // disabled text rather than as the answer.
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlight.opacity(showsHoverFill ? 0.10 : 0))
        }
        .contentShape(Rectangle())
        .pointerStyle(.link)
        // A nudge rather than a scale: scaling a row this small softens its text.
        .offset(x: isHovering && !reduceMotion ? 3 : 0)
        .animation(.snappy(duration: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - The page

/// One rendered topic, scrollable from the keyboard as well as the trackpad.
///
/// Making the `ScrollView` focusable is not enough on macOS: with only `.focusable()`, Tab reached
/// the page and then Page Down, the arrow keys and the space bar all did nothing, so a long topic
/// could be read only by somebody with a trackpad. The keys are wired here against the live scroll
/// geometry instead.
private struct HelpPage: View {
    let topic: HelpTopic

    @State private var position = ScrollPosition(edge: .top)
    @State private var metrics = Metrics()

    /// What the scroll view currently reports: where it is, how much it shows, how much there is.
    private struct Metrics: Equatable {
        var offset: CGFloat = 0
        var viewport: CGFloat = 0
        var content: CGFloat = 0
    }

    /// A page-worth of movement keeps a couple of lines of overlap, so the reader does not have to
    /// find their place again after every keypress.
    private var pageStep: CGFloat { max(metrics.viewport * 0.9, 1) }
    private var lineStep: CGFloat { 60 }
    private var maxOffset: CGFloat { max(metrics.content - metrics.viewport, 0) }

    var body: some View {
        ScrollView {
            MarkdownView(blocks: HelpMarkdown.parse(topic.body), module: topic.module)
                // A reference page is read *and* copied from — a privilege name into a Jamf role, a
                // documentation URL into a browser — so the text has to be selectable.
                .textSelection(.enabled)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                // Room under the last block, so the page does not end flush against the bar.
                .padding(.bottom, 40)
                // A measure, not a margin. The guide is now as wide as the window, and body text set
                // the full width of a 1100pt pane runs to well over a hundred characters a line,
                // which is tiring to read and easy to lose your place in. 620 keeps a line near
                // ninety characters at `.callout`. Centred, because a column pinned to the left of a
                // pane this wide looks like a layout accident.
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: Metrics.self) { geometry in
            Metrics(offset: geometry.contentOffset.y,
                    viewport: geometry.containerSize.height,
                    content: geometry.contentSize.height)
        } action: { _, new in
            metrics = new
        }
        .focusable()
        .onKeyPress(.pageDown) { scroll(by: pageStep) }
        .onKeyPress(.space) { scroll(by: pageStep) }
        .onKeyPress(.pageUp) { scroll(by: -pageStep) }
        .onKeyPress(.downArrow) { scroll(by: lineStep) }
        .onKeyPress(.upArrow) { scroll(by: -lineStep) }
        .onKeyPress(.home) { jump(to: .top) }
        .onKeyPress(.end) { jump(to: .bottom) }
        .accessibilityLabel("\(topic.title) page")
    }

    private func scroll(by delta: CGFloat) -> KeyPress.Result {
        guard maxOffset > 0 else { return .ignored }
        position.scrollTo(y: min(max(metrics.offset + delta, 0), maxOffset))
        return .handled
    }

    private func jump(to edge: Edge) -> KeyPress.Result {
        position.scrollTo(edge: edge)
        return .handled
    }
}

// MARK: - Host window size

/// Reports the content size of the window a sheet is presented on, and again whenever it is resized.
///
/// A sheet cannot read its container from SwiftUI: it is sized from its own content's ideal size, so
/// `maxWidth: .infinity` and `.presentationSizing(.page)` both left the guide far narrower than the
/// window behind it. Reaching for the parent window is the only way to make the sheet track it.
private struct HostWindowSizeReader: NSViewRepresentable {
    var onChange: (CGSize) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ReaderView)?.onChange = onChange
    }

    final class ReaderView: NSView {
        var onChange: ((CGSize) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard window != nil else { return }
            // `sheetParent` is not set until the sheet has been attached, which happens *after* this
            // view reaches its window. Reading it here returns nil, the fallback then measures the
            // sheet's own window, and the guide sizes itself from its own placeholder size and never
            // corrects — so resolve the host on the next turn of the run loop instead.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // `sheetParent` while the guide is a sheet; `window` if it is ever given a scene of
                // its own, so this keeps working rather than silently reporting nothing.
                guard let host = self.window?.sheetParent ?? self.window else { return }
                self.attach(to: host)
            }
        }

        private func attach(to host: NSWindow) {
            report(host)
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: host,
                queue: .main
            ) { [weak self] notification in
                guard let host = notification.object as? NSWindow else { return }
                self?.report(host)
            }
        }

        private func report(_ host: NSWindow) {
            onChange?(host.contentLayoutRect.size)
        }

        private func stopObserving() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

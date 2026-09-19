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
    /// The content size of the window this sheet is attached to, once `HostWindowSizeReader` has it.
    @State private var hostSize: CGSize?
    /// Help opens ready to be searched. Without this the page takes first focus — it is focusable so
    /// that it can be scrolled from the keyboard — and opens wearing a focus ring.
    /// Which index sections are open. Everything starts closed except the section holding the page
    /// you land on — an index that showed no sign of where you are is disorienting, and one section
    /// open is not the wall of text the whole index was.
    @State private var openSections: Set<HelpSection> = []
    /// Whether the search panel is up. Search is a panel rather than a field in the index: as a
    /// field it sat in the corner being ignored, and the index underneath it was doing the work.
    @State private var isSearchPresented = false

    /// How large to draw the guide, given the window behind it. Generous, but always inside the
    /// window, and capped so it does not become an unreadably wide measure on a large display.
    private var sheetSize: CGSize {
        guard let hostSize else { return CGSize(width: 900, height: 700) }
        return CGSize(width: min(max(hostSize.width - 120, 820), 1400),
                      height: min(max(hostSize.height - 100, 520), 1100))
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
        }
        .onChange(of: presenter.requestedTopic) {
            guard let requested = presenter.requestedTopic else { return }
            selectedTopicID = requested
            revealSelectedSection()
            presenter.requestedTopic = nil
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
        revealSelectedSection()
    }

    /// Open the section holding the selected topic, leaving the rest closed.
    private func revealSelectedSection() {
        guard let section = selectedTopic?.section else { return }
        openSections.insert(section)
    }

    // MARK: - Index

    private var index: some View {
        VStack(spacing: 0) {
            header
            searchButton
            Divider()
            topicList
        }
        .sheet(isPresented: $isSearchPresented) {
            HelpSearchPanel(topics: topics) { chosen in
                selectedTopicID = chosen
                revealSelectedSection()
                isSearchPresented = false
            }
        }
    }

    /// Opens the search panel. A button, not a text field: a field here is a small grey box in a
    /// corner that people read as decoration, and this guide's whole case is that you look things up
    /// rather than read it through.
    private var searchButton: some View {
        Button {
            isSearchPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Search the guide")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("⌘F")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7),
                        in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .keyboardShortcut("f", modifiers: .command)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityLabel("Search the guide")
        .accessibilityHint("Opens the search panel")
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
            ForEach(HelpSearch.groups(for: topics), id: \.section) { group in
                Section {
                    if openSections.contains(group.section) {
                        ForEach(group.topics) { topic in
                            row(for: topic)
                        }
                    }
                } header: {
                    sectionHeader(group.section)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(for topic: HelpTopic) -> some View {
        HelpIndexRow(topic: topic,
                     isSelected: topic.id == selectedTopicID,
                     showsSummary: false)
            .tag(topic.id)
    }

    /// A section's header — and the control that opens it.
    ///
    /// Built from an `Image` and a `Text` with their own styles rather than from a `Label`:
    /// `.listStyle(.sidebar)` re-applies its own header treatment over a `Label`, so a single
    /// `.foregroundStyle` on the outside was simply ignored. `.textCase(nil)` stops the list
    /// uppercasing it for the same reason.
    private func sectionHeader(_ section: HelpSection) -> some View {
        let isOpen = openSections.contains(section)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isOpen { openSections.remove(section) } else { openSections.insert(section) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: section.systemImage)
                    .font(.caption)
                    .foregroundStyle(section.colour)
                Text(section.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(section.colour)
                Spacer(minLength: 0)
            }
            .textCase(nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityLabel(section.title)
        .accessibilityHint(isOpen ? "Collapses this section" : "Expands this section")
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
    /// Whether to draw the one-line summary under the title.
    ///
    /// Off while browsing, on in search results. Nineteen titles under three headings is a list you
    /// can take in at a glance; the same nineteen with a two-line grey summary under each is a wall
    /// of secondary text, and it was the single biggest reason the index read as wordy. In results
    /// the trade reverses — you need the summary to judge a hit — so it earns its space there.
    var showsSummary: Bool = false

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

                if showsSummary {
                    Text("\(topic.section.title) · \(topic.summary)")
                        .font(.caption)
                        // `.secondary` left this fainter than the summary is worth: in a result it
                        // is what tells you whether this is the page you want.
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(topic.title). \(topic.summary)")
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
        // Focusable for the keys, not for the ring. SwiftUI's generic focus treatment draws a blue
        // rectangle around the whole pane the moment you click into the page, which reads as "this
        // is selected" — it is not, it is just where the arrow keys go. No document scroll area on
        // macOS shows one: Preview, Mail's message body and Safari all take key input without it.
        .focusEffectDisabled()
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

// MARK: - Search

/// The guide's search, as a panel rather than a field in the index.
///
/// Modelled on Spotlight, and for the same reason: a search you summon takes the whole of your
/// attention, and a search box sitting in the corner of a sidebar does not. The index behind it is
/// for browsing — nineteen titles under three headings — and this is for the other way in, when you
/// already know the words you would type and want the page they are on.
///
/// Ranking is `HelpSearch`'s, unchanged: a flat list, best match first, because grouping results by
/// section promotes weak matches to sit beside strong ones.
private struct HelpSearchPanel: View {
    let topics: [HelpTopic]
    /// Called with the chosen topic's id. The caller owns selection and dismissal.
    var onChoose: (HelpTopic.ID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var highlighted: HelpTopic.ID?
    @FocusState private var fieldFocused: Bool

    private var results: [HelpTopic] {
        HelpSearch.filter(topics, query: query)
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider()
            body(for: results)
        }
        .frame(width: 620, height: 460)
        .appBackground()
        .onAppear { fieldFocused = true }
        // Arrow keys move the highlight without leaving the field, as Spotlight does — typing and
        // choosing are the same gesture.
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.return) { choose() }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private var field: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField("Search the guide", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($fieldFocused)
                .onSubmit { choose() }
                .accessibilityLabel("Search the guide")

            if !query.isEmpty {
                Button {
                    query = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func body(for results: [HelpTopic]) -> some View {
        if !isSearching {
            prompt
        } else if results.isEmpty {
            empty
        } else {
            list(results)
        }
    }

    private var prompt: some View {
        VStack(spacing: 10) {
            Text("Type what you would say out loud.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("The error code Jamf gave you, the word on a badge, the field you are filling in.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("No topics match “\(query)”.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Try a shorter term, or the words you would see on screen.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ results: [HelpTopic]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text(results.count == 1 ? "1 result" : "\(results.count) results")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    ForEach(results) { topic in
                        Button {
                            onChoose(topic.id)
                        } label: {
                            HelpIndexRow(topic: topic,
                                         isSelected: topic.id == highlighted,
                                         showsSummary: true)
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .id(topic.id)
                    }
                }
                .padding(.bottom, 10)
            }
            .onChange(of: highlighted) {
                guard let highlighted else { return }
                withAnimation(.snappy(duration: 0.15)) { proxy.scrollTo(highlighted, anchor: .center) }
            }
        }
        // A fresh query starts at the top, so Return always takes the best match rather than
        // whatever happened to be highlighted for the previous one.
        .onChange(of: query) { highlighted = results.first?.id }
        .onAppear { highlighted = results.first?.id }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let results = self.results
        guard !results.isEmpty else { return .ignored }
        let current = results.firstIndex { $0.id == highlighted } ?? 0
        let next = min(max(current + delta, 0), results.count - 1)
        highlighted = results[next].id
        return .handled
    }

    private func choose() -> KeyPress.Result {
        guard let highlighted else { return .ignored }
        onChoose(highlighted)
        return .handled
    }

    private func choose() {
        guard let highlighted else { return }
        onChoose(highlighted)
    }
}

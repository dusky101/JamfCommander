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

    private var matches: [HelpTopic] {
        HelpSearch.filter(topics, query: searchText)
    }

    private var selectedTopic: HelpTopic? {
        topics.first { $0.id == selectedTopicID }
    }

    var body: some View {
        NavigationSplitView {
            index
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        } detail: {
            page
        }
        .frame(minWidth: 820, idealWidth: 980, maxWidth: .infinity,
               minHeight: 560, idealHeight: 720, maxHeight: .infinity)
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
            searchText = ""
            selectedTopicID = requested
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
    }

    // MARK: - Index

    private var index: some View {
        VStack(spacing: 0) {
            searchField
            Divider()

            List(selection: $selectedTopicID) {
                ForEach(HelpSearch.groups(for: matches), id: \.section) { group in
                    Section {
                        ForEach(group.topics) { topic in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title)
                                    .font(.callout)
                                Text(topic.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                            .tag(topic.id)
                        }
                    } header: {
                        Label(group.section.title, systemImage: group.section.systemImage)
                    }
                }
            }
            .listStyle(.sidebar)

            if matches.isEmpty {
                // An empty list under a search box reads as "help is broken" rather than "nothing
                // matched", so it says which it is.
                Text("No topics match “\(searchText)”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search help", text: $searchText)
                .textFieldStyle(.plain)
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
            ScrollView {
                MarkdownView(blocks: HelpMarkdown.parse(topic.body))
                    .padding(24)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Re-scroll to the top on every topic change: without the id, moving from a long page to
            // a short one leaves the reader part-way down the new one.
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

//
//  HelpTopic.swift
//  JamfCommander
//
//  One page of the help guide: its identity, where it sits in the index, a one-line summary, the
//  extra search terms, and the bundled Markdown file holding its body. The body is filled in by
//  `HelpLibrary` when it loads the bundle, so search matches content as well as titles.
//
//  A pure value type, so `HelpSearch` can filter it off the main actor.
//

import Foundation

nonisolated struct HelpTopic: Identifiable, Sendable, Hashable {
    /// Stable slug: the list identity, the deep-link key, and the bundled file's base name unless
    /// `resource` overrides it.
    let id: String
    /// User-facing title. The topic's Markdown should open with the same `# Title` so the page and
    /// the index agree.
    let title: String
    /// Where the topic sits in the index.
    let section: HelpSection
    /// One line shown beneath the title in the index and in search results.
    let summary: String
    /// Terms to match in search that may not appear in the title or body — the words an
    /// administrator would actually type. "403", "token expired", "redundant" for the Unused audit.
    let keywords: [String]
    /// The bundled Markdown resource's base name, without extension. Defaults to `id`.
    let resource: String
    /// The raw Markdown body, filled by `HelpLibrary.loadTopics()`. Empty in the static manifest.
    var body: String

    init(id: String,
         title: String,
         section: HelpSection,
         summary: String,
         keywords: [String] = [],
         resource: String? = nil,
         body: String = "") {
        self.id = id
        self.title = title
        self.section = section
        self.summary = summary
        self.keywords = keywords
        self.resource = resource ?? id
        self.body = body
    }

    /// The lowercased text `HelpSearch` matches against. Including the body means search finds
    /// content rather than only headings, which is the whole point of a searchable guide.
    var searchableText: String {
        ([title, summary, section.title] + keywords + [body])
            .joined(separator: "\n")
            .lowercased()
    }
}

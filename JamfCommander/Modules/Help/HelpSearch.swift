//
//  HelpSearch.swift
//  JamfCommander
//
//  Case-insensitive search over the help index. A topic matches when its searchable text contains
//  *every* whitespace-separated term; an empty query returns every topic in manifest order.
//
//  Matches are then **ranked by where the terms were found** — title, keywords, summary, section,
//  body — because filtering alone puts the wrong page first. A term like "scope" appears in the body
//  of almost every module page, so without ranking the answer is whichever topic happens to come
//  first in the manifest rather than the one the page is about.
//
//  Pure and nonisolated.
//

import Foundation

nonisolated enum HelpSearch {

    /// Topics matching `query`, most relevant first. An empty query returns every topic in manifest
    /// order, which is section order, so browsing is unchanged.
    static func filter(_ topics: [HelpTopic], query: String) -> [HelpTopic] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return topics }

        // The manifest index is carried through as the tie-break: `sorted(by:)` is not guaranteed
        // stable, so without it equally relevant topics could come back in an order that changed
        // between runs.
        let matches = topics.enumerated().compactMap { index, topic -> (topic: HelpTopic, score: Int, index: Int)? in
            let haystack = topic.searchableText
            guard terms.allSatisfy({ haystack.contains($0) }) else { return nil }
            return (topic, relevance(of: topic, terms: terms), index)
        }

        return matches
            .sorted { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
            .map(\.topic)
    }

    /// How strong a match this topic is: for each term, the weight of the *best* field it appears
    /// in, summed.
    ///
    /// Summing per term rather than taking one best field means a topic matching every term in its
    /// title outranks one matching a single term in its title and the rest deep in its body. The
    /// floor is the body weight, because `filter` has already proved every term appears somewhere.
    private static func relevance(of topic: HelpTopic, terms: [String]) -> Int {
        let title = topic.title.lowercased()
        // Joined on a newline so a term cannot match across two adjacent keywords.
        let keywords = topic.keywords.joined(separator: "\n").lowercased()
        let summary = topic.summary.lowercased()
        let section = topic.section.title.lowercased()
        let exactKeywords = Set(topic.keywords.map { $0.lowercased() })

        return terms.reduce(0) { total, term in
            if title.contains(term) { return total + Weight.title }
            // An *exact* keyword outranks one that merely contains the term: the difference between
            // an author writing "403" because the page is about it and writing "403 on delete"
            // because the page mentions it once.
            if exactKeywords.contains(term) { return total + Weight.exactKeyword }
            if keywords.contains(term) { return total + Weight.keyword }
            if summary.contains(term) { return total + Weight.summary }
            if section.contains(term) { return total + Weight.section }
            return total + Weight.body
        }
    }

    /// The index grouped into its sections, in the order the topics arrive.
    ///
    /// This is the **browsing** index — the whole manifest, in manifest order. It is deliberately not
    /// used for search results any more.
    ///
    /// Grouping and ranking cannot both be honoured. A section's rank here is its best topic's rank,
    /// which sounds right and is not: every *other* match in that section is then promoted to sit
    /// beside it, regardless of its own score. Searching "403" ranked Welcome — a single incidental
    /// match in its body, score 1 — above the troubleshooting page that scored 6, purely because
    /// Welcome shares a section with the top hit. Search now draws a flat, ranked list instead, so
    /// the order on screen is the order `filter` computed.
    static func groups(for matches: [HelpTopic]) -> [(section: HelpSection, topics: [HelpTopic])] {
        var order: [HelpSection] = []
        var bySection: [HelpSection: [HelpTopic]] = [:]
        for topic in matches {
            if bySection[topic.section] == nil { order.append(topic.section) }
            bySection[topic.section, default: []].append(topic)
        }
        return order.map { (section: $0, topics: bySection[$0] ?? []) }
    }

    /// Field weights, strongest first.
    ///
    /// Keywords rank just below the title deliberately: they are hand-written for exactly this job —
    /// the words an administrator would type that the title does not contain ("401", "unscoped",
    /// "redundant"). Ranking them below the summary would waste the one field authored for search.
    private enum Weight {
        static let title = 8
        static let exactKeyword = 6
        static let keyword = 5
        static let summary = 3
        static let section = 2
        static let body = 1
    }
}

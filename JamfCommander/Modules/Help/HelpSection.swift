//
//  HelpSection.swift
//  JamfCommander
//
//  The sections of the in-app help guide, in display order. Each groups a set of `HelpTopic`s in the
//  index. A pure value type so the manifest and the search index can use it off the main actor.
//

import SwiftUI

/// A top-level grouping in the help index. The `rawValue` order is the order sections appear.
nonisolated enum HelpSection: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case gettingStarted
    case modules
    case reference

    var id: Int { rawValue }

    /// The section's title, shown as the index group header.
    var title: String {
        switch self {
        case .gettingStarted: return "Getting started"
        case .modules: return "Using the app"
        case .reference: return "Reference"
        }
    }

    /// An SF Symbol for the section header, matching the symbols the app uses for the same areas.
    var systemImage: String {
        switch self {
        case .gettingStarted: return "bolt.horizontal.circle"
        case .modules: return "square.grid.2x2"
        // Was `stethoscope`, which reads as diagnostics: right for "If something fails" alone, wrong
        // once this section also holds the API and roadmap pages.
        case .reference: return "book.closed"
        }
    }

    /// The section's own colour, used on its index header.
    ///
    /// Three hues kept clear of the nine in `ModulePalette`: a module's colour has to mean that
    /// module wherever it appears, so the sections borrow none of them. Deliberately not `.secondary`
    /// — as `.secondary` these headers were the dimmest thing in the window, quieter than the rows
    /// they introduce.
    var colour: Color {
        switch self {
        case .gettingStarted: return Color(red: 0.55, green: 0.60, blue: 1.000)
        case .modules: return Color(red: 0.45, green: 0.80, blue: 0.95)
        case .reference: return Color(red: 0.90, green: 0.75, blue: 0.45)
        }
    }

    static func < (lhs: HelpSection, rhs: HelpSection) -> Bool { lhs.rawValue < rhs.rawValue }
}

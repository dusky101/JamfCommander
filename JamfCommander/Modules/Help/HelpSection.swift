//
//  HelpSection.swift
//  JamfCommander
//
//  The sections of the in-app help guide, in display order. Each groups a set of `HelpTopic`s in the
//  index. A pure value type so the manifest and the search index can use it off the main actor.
//

import Foundation

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
        case .reference: return "stethoscope"
        }
    }

    static func < (lhs: HelpSection, rhs: HelpSection) -> Bool { lhs.rawValue < rhs.rawValue }
}

//
//  HelpRhythm.swift
//  JamfCommander
//
//  The vertical spacing between one help block and the next.
//
//  Phase 1 set a single `VStack(spacing: 14)` for every gap, plus 6pt above a heading — so a heading
//  had 20pt over it and 14pt under it. Read on screen, that is not enough of a difference: the
//  heading floats between two sections rather than starting one, and a nine-heading page reads as one
//  undifferentiated slab. A heading belongs to the text *below* it, so the space above it has to be
//  clearly larger than the space below.
//
//  Kept apart from `MarkdownView` because it is arithmetic, not layout: it can be reasoned about, and
//  changed, without reading a view.
//
//  Pure and nonisolated.
//

import Foundation

nonisolated enum HelpRhythm {

    /// The gap to leave above `block`, given the block before it. `nil` means `block` opens the page,
    /// where the page's own padding already provides the space.
    static func space(before block: HelpBlock, after previous: HelpBlock?) -> CGFloat {
        guard let previous else { return 0 }

        switch block {
        case .heading(let level, _):
            // The break that makes a section legible as a section.
            return level <= 2 ? 30 : 24

        case .bulleted, .numbered:
            // A list introduced by a line like "You need three things:" belongs to that line, so it
            // sits closer to it than two paragraphs sit to each other.
            if case .paragraph = previous { return 10 }
            return 18

        case .divider:
            return 26

        case .figure:
            // A figure is a block of its own, not an aside to the paragraph above it.
            return 18

        case .paragraph, .code, .callout:
            // First thing under a heading: close, because the heading introduces it.
            if case .heading = previous { return 10 }
            return 18
        }
    }
}

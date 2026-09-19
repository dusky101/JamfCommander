//
//  HelpMarkdown.swift
//  JamfCommander
//
//  A small block-level Markdown model and parser for the help guide.
//
//  SwiftUI's `AttributedString(markdown:)` renders *inline* styling only — bold, italic, links, code
//  spans — and collapses block structure: headings, lists, paragraphs and fenced code all merge into
//  one run. A guide needs blocks, so this parser splits a document into ordered `HelpBlock`s and
//  `MarkdownView` renders each with the right SwiftUI view, applying inline styling per paragraph.
//
//  One non-standard extension carries the guide's character: a blockquote beginning `> **Note:**`,
//  `**Tip:**`, `**Warning:**` or `**Important:**` becomes a coloured callout. That replaces the
//  `note(_:)` and `warning(_:)` helpers the old single-document help view carried, so the same two
//  tones survive the move to Markdown.
//
//  Pure and nonisolated.
//

import Foundation

/// A callout's tone, choosing its colour and icon. `note` is the neutral default.
nonisolated enum HelpCallout: String, Sendable, CaseIterable {
    case note, tip, warning, important
}

/// One block of a help page, in document order.
nonisolated enum HelpBlock: Sendable, Equatable {
    /// A heading, level 1–6. Level 1 is the page title.
    case heading(level: Int, text: String)
    /// A paragraph of inline Markdown, rendered as an `AttributedString`.
    case paragraph(String)
    /// An unordered list; each item is inline Markdown.
    case bulleted([String])
    /// An ordered list. `start` is the first item's number in the source, so a list interrupted by
    /// another block resumes at the right number instead of restarting at 1.
    case numbered(start: Int, items: [String])
    /// A fenced code block. `language` is the fence's info string, or `nil`.
    case code(language: String?, text: String)
    /// A coloured callout containing further blocks.
    case callout(HelpCallout, [HelpBlock])
    /// A horizontal rule.
    case divider
}

nonisolated enum HelpMarkdown {

    /// Parse a Markdown document into ordered blocks.
    static func parse(_ markdown: String) -> [HelpBlock] {
        parse(lines: normalisedLines(markdown))
    }

    /// Lines with endings normalised, so a CRLF document parses identically to an LF one.
    private static func normalisedLines(_ markdown: String) -> [String] {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    // MARK: - Line-based parsing

    private static func parse(lines: [String]) -> [HelpBlock] {
        var blocks: [HelpBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line — block separator.
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Fenced code.
            if let info = fenceInfo(trimmed) {
                index += 1
                var body: [String] = []
                while index < lines.count, !isFenceClose(lines[index]) {
                    body.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(language: info.isEmpty ? nil : info,
                                    text: body.joined(separator: "\n")))
                continue
            }

            // Blockquote — a callout, possibly spanning several lines.
            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let quotedLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quotedLine.hasPrefix(">") else { break }
                    quoted.append(String(quotedLine.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                let (tone, inner) = calloutTone(of: quoted)
                blocks.append(.callout(tone, parse(lines: inner)))
                continue
            }

            // Horizontal rule.
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
                index += 1
                continue
            }

            // Heading.
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix { $0 == "#" }.count
                if hashes <= 6 {
                    let text = trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: hashes, text: text))
                    index += 1
                    continue
                }
            }

            // Unordered list.
            if isBullet(trimmed) {
                var items: [String] = []
                while index < lines.count {
                    let item = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isBullet(item) else { break }
                    index += 1
                    items.append(consumeContinuations(
                        of: String(item.dropFirst(2)).trimmingCharacters(in: .whitespaces),
                        lines: lines, index: &index))
                }
                blocks.append(.bulleted(items))
                continue
            }

            // Ordered list.
            if let first = orderedNumber(trimmed) {
                var items: [String] = []
                while index < lines.count {
                    let item = lines[index].trimmingCharacters(in: .whitespaces)
                    guard orderedNumber(item) != nil,
                          let dot = item.firstIndex(of: ".") else { break }
                    index += 1
                    items.append(consumeContinuations(
                        of: String(item[item.index(after: dot)...])
                            .trimmingCharacters(in: .whitespaces),
                        lines: lines, index: &index))
                }
                blocks.append(.numbered(start: first, items: items))
                continue
            }

            // Paragraph — consume until a blank line or the start of another block.
            var paragraph: [String] = []
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                guard !next.isEmpty, !next.hasPrefix("#"), !next.hasPrefix(">"),
                      !isBullet(next), orderedNumber(next) == nil,
                      fenceInfo(next) == nil, next != "---" else { break }
                paragraph.append(next)
                index += 1
            }
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
            }
        }

        return blocks
    }

    // MARK: - Line classification

    /// The info string of an opening fence, or `nil` when the line is not a fence.
    private static func fenceInfo(_ line: String) -> String? {
        guard line.hasPrefix("```") else { return nil }
        return String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    private static func isFenceClose(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    /// A list item plus any wrapped lines belonging to it, advancing `index` past them.
    ///
    /// Markdown lets a list item span several source lines, and the guide's pages are hard-wrapped,
    /// so most multi-line bullets arrive that way. Without this the first line became the item and
    /// the remainder became a paragraph *after* the list — which also split any emphasis straddling
    /// the wrap, putting a literal asterisk on screen. Seen on `welcome.md` the first time the
    /// window was opened.
    private static func consumeContinuations(of item: String,
                                             lines: [String],
                                             index: inout Int) -> String {
        var text = item
        while index < lines.count, let continuation = listContinuation(lines[index]) {
            text += " " + continuation
            index += 1
        }
        return text
    }

    /// A wrapped line belonging to the list item above it, or `nil` when the line starts something
    /// new. A blank line ends the item, as it does in Markdown.
    private static func listContinuation(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !isBullet(trimmed),
              orderedNumber(trimmed) == nil,
              !trimmed.hasPrefix("#"),
              !trimmed.hasPrefix(">"),
              fenceInfo(trimmed) == nil,
              trimmed != "---", trimmed != "***", trimmed != "___" else { return nil }
        return trimmed
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ")
    }

    /// The number of an ordered-list line ("3. Enable the client" → 3), or `nil`.
    private static func orderedNumber(_ line: String) -> Int? {
        guard let dot = line.firstIndex(of: "."),
              dot > line.startIndex,
              line.index(after: dot) < line.endIndex,
              line[line.index(after: dot)] == " " else { return nil }
        return Int(line[line.startIndex..<dot])
    }

    /// A quoted block's tone, and the block with its `**Note:**` marker removed.
    ///
    /// The marker is stripped because the callout draws its own icon and colour; leaving it would
    /// say the same thing twice.
    private static func calloutTone(of lines: [String]) -> (HelpCallout, [String]) {
        guard var first = lines.first else { return (.note, lines) }
        for tone in HelpCallout.allCases {
            let marker = "**\(tone.rawValue.capitalized):**"
            guard first.hasPrefix(marker) else { continue }
            first = String(first.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return (tone, [first] + lines.dropFirst())
        }
        return (.note, lines)
    }
}

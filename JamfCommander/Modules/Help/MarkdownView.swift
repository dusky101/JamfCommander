//
//  MarkdownView.swift
//  JamfCommander
//
//  Renders the blocks `HelpMarkdown` produces, each with the SwiftUI view that suits it. Inline
//  styling — bold, italic, code spans, links — is applied per paragraph with
//  `AttributedString(markdown:)`, which handles inline Markdown well and block structure not at all.
//
//  Vertical spacing is not uniform: each block asks `HelpRhythm` how much room it needs above it, so
//  a heading opens a section instead of floating between two.
//

import SwiftUI

/// One help page: its parsed blocks, in order.
struct MarkdownView: View {
    let blocks: [HelpBlock]
    /// The module this page documents, when it documents one. Its colour and symbol dress the page's
    /// level-1 heading, so a module looks the same in the guide as it does in the sidebar.
    var module: AppModule?

    var body: some View {
        // Spacing is per block rather than per stack — see `HelpRhythm`.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                HelpBlockView(block: block, module: module)
                    .padding(.top, HelpRhythm.space(before: block,
                                                    after: index == 0 ? nil : blocks[index - 1]))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A single block. Recursive, because a callout contains blocks of its own.
private struct HelpBlockView: View {
    let block: HelpBlock
    /// Only the page's own title is dressed in the module's colour; headings inside the page stay
    /// neutral, or nine pages would each be a wall of one hue.
    var module: AppModule?

    /// The width reserved for a list marker. Bullets and numbers share it so an unordered list and an
    /// ordered one start their text on the same line, and a wrapped line hangs under the text rather
    /// than under the marker.
    private static let markerWidth: CGFloat = 22
    private static let markerGap: CGFloat = 8

    var body: some View {
        switch block {
        case .heading(let level, let text):
            if level == 1, let module {
                Label {
                    Text(text)
                } icon: {
                    Image(systemName: module.icon)
                }
                .font(headingFont(1))
                .fontWeight(.bold)
                .foregroundStyle(module.accentColour)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            } else {
                Text(text)
                    .font(headingFont(level))
                    .fontWeight(level <= 2 ? .bold : .semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }

        case .paragraph(let text):
            inline(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bulleted(let items):
            // 10pt between items, because most items in this guide wrap: at the old 6pt the gap
            // between two items was no larger than the gap inside one, and the list stopped reading
            // as a list.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow {
                        Text("•")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.tint)
                            .frame(width: Self.markerWidth, alignment: .trailing)
                    } content: {
                        inline(item)
                    }
                }
            }

        case .numbered(let start, let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    listRow {
                        Text("\(start + offset).")
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                            .frame(width: Self.markerWidth, alignment: .trailing)
                    } content: {
                        inline(item)
                    }
                }
            }

        case .code(_, let text):
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

        case .callout(let tone, let inner):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: tone.systemImage)
                    .foregroundStyle(tone.colour)
                    .font(.callout)
                    .accessibilityLabel(tone.accessibilityLabel)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(inner.enumerated()), id: \.offset) { index, block in
                        HelpBlockView(block: block, module: nil)
                            .padding(.top, HelpRhythm.space(before: block,
                                                            after: index == 0 ? nil : inner[index - 1]))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(tone.colour.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tone.colour.opacity(0.35), lineWidth: 1)
            )

        case .figure(let id):
            HelpFigureView(id: id)

        case .divider:
            Divider()
        }
    }

    /// A list row: a fixed-width marker, then the item's text.
    private func listRow<Marker: View>(@ViewBuilder marker: () -> Marker,
                                       @ViewBuilder content: () -> Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.markerGap) {
            marker()
            content()
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Inline Markdown as styled text. A document that will not parse is shown verbatim rather than
    /// dropped — a formatting slip should cost the styling, never the sentence.
    private func inline(_ markdown: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(markdown)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }
}

private extension HelpCallout {
    var systemImage: String {
        switch self {
        case .note: return "info.circle"
        case .tip: return "lightbulb"
        case .warning: return "exclamationmark.triangle.fill"
        case .important: return "exclamationmark.circle.fill"
        }
    }

    /// Four tones that stay apart from each other on the dark background. `note` was `.secondary`,
    /// which drew a grey box with a grey icon inside it — beside the orange and red ones it read as a
    /// disabled control rather than as information, and six of the eight pages open with one.
    var colour: Color {
        switch self {
        case .note: return .blue
        case .tip: return .green
        case .warning: return .orange
        case .important: return .red
        }
    }

    /// Spoken in place of the icon, so the tone survives for somebody who cannot see the colour.
    var accessibilityLabel: String {
        switch self {
        case .note: return "Note"
        case .tip: return "Tip"
        case .warning: return "Warning"
        case .important: return "Important"
        }
    }
}

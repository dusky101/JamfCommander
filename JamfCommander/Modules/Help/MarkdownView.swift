//
//  MarkdownView.swift
//  JamfCommander
//
//  Renders the blocks `HelpMarkdown` produces, each with the SwiftUI view that suits it. Inline
//  styling — bold, italic, code spans, links — is applied per paragraph with
//  `AttributedString(markdown:)`, which handles inline Markdown well and block structure not at all.
//

import SwiftUI

/// One help page: its parsed blocks, in order.
struct MarkdownView: View {
    let blocks: [HelpBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                HelpBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A single block. Recursive, because a callout contains blocks of its own.
private struct HelpBlockView: View {
    let block: HelpBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level))
                .fontWeight(level <= 2 ? .bold : .semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level == 1 ? 0 : 6)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            inline(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bulleted(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        inline(item)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }

        case .numbered(let start, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(start + offset).")
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                            .frame(width: 22, alignment: .trailing)
                        inline(item)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
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
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(inner.enumerated()), id: \.offset) { _, block in
                        HelpBlockView(block: block)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(tone.colour.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tone.colour.opacity(0.25), lineWidth: 1)
            )

        case .divider:
            Divider().padding(.vertical, 2)
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

    var colour: Color {
        switch self {
        case .note: return .secondary
        case .tip: return .blue
        case .warning: return .orange
        case .important: return .red
        }
    }
}

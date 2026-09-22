//
//  HelpPDFBlockView.swift
//  JamfCommander
//
//  How one `HelpBlock` is drawn on paper.
//
//  The screen renderer is `MarkdownView`; this is its counterpart for print, and the two share the
//  block vocabulary rather than the styling. They have to differ: the screen is dark, fluid and
//  follows the reader's text size; the page is white, fixed and will be printed. What they must not
//  differ on is *structure* — a callout is a callout, a numbered list resumes at the right number —
//  and that lives in `HelpMarkdown`, which both read.
//
//  Every colour here is explicit. Nothing in this file resolves against the colour scheme, with one
//  deliberate exception: a figure, which is forced *dark* so it looks like the app it illustrates.
//

import SwiftUI

// MARK: - Blocks

/// One block, set for print.
///
/// Not recursive by accident: a callout draws the blocks inside it with this same view, exactly as
/// `MarkdownView` does, so the two renderers cannot drift on what a callout may contain.
struct HelpPDFBlockView: View {
    let block: HelpBlock
    /// The module this page documents, when it documents one. Only the page's own title is dressed
    /// in its colour.
    var module: AppModule?
    /// The width this block is laid out in. Narrower inside a callout, which is inset.
    var width: CGFloat

    var body: some View {
        content
            .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch block {
        case .heading(let level, let text):
            if level == 1, let module {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: module.icon)
                        .font(HelpPDFTheme.heading(1))
                        // The module's own hue, darkened until it reads on paper. The title itself
                        // stays black: a coloured headline on white is decoration, and this document
                        // may well be printed in grey.
                        .foregroundStyle(HelpPDFTheme.onWhite(module.accentColour))
                    Text(text)
                        .font(HelpPDFTheme.heading(1))
                        .foregroundStyle(HelpPDFTheme.ink)
                }
                .frame(width: width, alignment: .leading)
            } else {
                Text(text)
                    .font(HelpPDFTheme.heading(level))
                    .foregroundStyle(HelpPDFTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: width, alignment: .leading)
            }

        case .paragraph(let text):
            HelpPDFText(text, width: width)

        case .bulleted(let items):
            // Reached only for a list drawn whole — inside a callout. In the run of a page, the
            // exporter splits a list into one atom per item so a page break can fall between two
            // items rather than through one. See `HelpPDFExportService.atoms(for:)`.
            VStack(alignment: .leading, spacing: HelpPDFListRow.spacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HelpPDFListRow(marker: .bullet, text: item, width: width)
                }
            }

        case .numbered(let start, let items):
            VStack(alignment: .leading, spacing: HelpPDFListRow.spacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    HelpPDFListRow(marker: .number(start + offset), text: item, width: width)
                }
            }

        case .code(_, let text):
            Text(text)
                .font(HelpPDFTheme.code)
                .foregroundStyle(HelpPDFTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width - 20, alignment: .leading)
                .padding(10)
                .background(HelpPDFTheme.codeGround)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(HelpPDFTheme.rule, lineWidth: 0.5)
                )

        case .callout(let tone, let inner):
            HelpPDFCallout(tone: tone, blocks: inner, width: width)

        case .figure(let id):
            HelpPDFFigure(id: id)

        case .divider:
            Rectangle()
                .fill(HelpPDFTheme.rule)
                .frame(width: width, height: 0.5)
        }
    }
}

// MARK: - Text

/// A paragraph, or a list item's text: inline Markdown set in the print body face.
///
/// A separate view because every piece of running text in the document needs the same three things —
/// the body font, the line spacing, and black ink — and a paragraph that missed one of them would be
/// invisible against the others only when printed.
struct HelpPDFText: View {
    private let attributed: AttributedString
    private let width: CGFloat

    init(_ markdown: String, width: CGFloat) {
        self.attributed = MarkdownView.inline(markdown, codeFont: HelpPDFTheme.code)
        self.width = width
    }

    var body: some View {
        Text(attributed)
            .font(HelpPDFTheme.body)
            .lineSpacing(HelpPDFTheme.bodyLineSpacing)
            .foregroundStyle(HelpPDFTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: .leading)
    }
}

// MARK: - Lists

/// One list item: its marker, then its text, with wrapped lines hanging under the text rather than
/// under the marker — the same arrangement the screen uses.
struct HelpPDFListRow: View {
    enum Marker {
        case bullet
        case number(Int)
    }

    /// The gap between two items in the same list. Smaller than on screen, where a list had to be
    /// told apart from surrounding prose at a glance; on the page the indent already does that.
    static let spacing: CGFloat = 5
    static let markerWidth: CGFloat = 16
    static let markerGap: CGFloat = 7

    let marker: Marker
    let text: String
    let width: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.markerGap) {
            markerText
                .font(HelpPDFTheme.bodyBold)
                .foregroundStyle(HelpPDFTheme.ink)
                .frame(width: Self.markerWidth, alignment: .trailing)
            HelpPDFText(text, width: width - Self.markerWidth - Self.markerGap)
        }
        .frame(width: width, alignment: .leading)
    }

    private var markerText: Text {
        switch marker {
        case .bullet: return Text("•")
        case .number(let value): return Text("\(value).")
        }
    }
}

// MARK: - Callouts

/// A callout, kept whole on one page.
///
/// The tone's hue is the screen's, darkened for paper. Losing the colour entirely would lose the
/// distinction between a note and a warning, which on a page about privileges and deletions is the
/// part most worth keeping — and the icon carries it as well, for a document that is printed in
/// grey or read by somebody who cannot see the hue.
struct HelpPDFCallout: View {
    let tone: HelpCallout
    let blocks: [HelpBlock]
    let width: CGFloat

    private static let padding: CGFloat = 10
    private static let iconWidth: CGFloat = 14
    private static let iconGap: CGFloat = 8

    private var innerWidth: CGFloat {
        width - Self.padding * 2 - Self.iconWidth - Self.iconGap
    }

    private var tint: Color { HelpPDFTheme.onWhite(tone.colour) }

    var body: some View {
        HStack(alignment: .top, spacing: Self.iconGap) {
            Image(systemName: tone.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: Self.iconWidth, alignment: .leading)
                .accessibilityLabel(tone.accessibilityLabel)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    HelpPDFBlockView(block: block, width: innerWidth)
                        .padding(.top, index == 0 ? 0 : HelpPDFTheme.space(before: block,
                                                                          after: blocks[index - 1]))
                }
            }
            .frame(width: innerWidth, alignment: .leading)
        }
        .padding(Self.padding)
        // After the padding, not before it: `innerWidth` has already had the padding taken out, so
        // constraining the padded view to anything less than the full column squeezes the text out
        // past its own box. It did, by exactly 20pt, until this said `width`.
        .frame(width: width, alignment: .leading)
        .background(HelpPDFTheme.onPaper(tint, fraction: 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(HelpPDFTheme.onPaper(tint, fraction: 0.45), lineWidth: 0.6)
        )
    }
}

// MARK: - Cover

/// The first page of a whole-guide export: what this is, which build it describes, and what is in it.
///
/// The sentence about staleness is the point of the page. The guide on screen cannot be out of date,
/// because it ships inside the app; a PDF of it can be, and will be, and the person reading it six
/// months later has no way to tell unless the document says so.
///
/// The contents list carries no page numbers. Every topic starts on a fresh page and every page
/// names the guide it came from, so the list is there to say what is inside rather than to be
/// navigated by — and numbers that were right would have to be recomputed by a second pagination
/// pass, while numbers that were wrong would be worse than none.
struct HelpPDFCover: View {
    let topics: [HelpTopic]
    let stamp: String
    let width: CGFloat

    private var sections: [(section: HelpSection, topics: [HelpTopic])] {
        HelpSection.allCases.compactMap { section in
            let members = topics.filter { $0.section == section }
            return members.isEmpty ? nil : (section, members)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AppIdentity.name)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(HelpPDFTheme.ink)
            Text("The complete guide")
                .font(.system(size: 15))
                .foregroundStyle(HelpPDFTheme.quietInk)
                .padding(.top, 4)

            Rectangle()
                .fill(HelpPDFTheme.rule)
                .frame(width: width, height: 0.5)
                .padding(.top, 18)

            Text(stamp)
                .font(HelpPDFTheme.body)
                .foregroundStyle(HelpPDFTheme.ink)
                .padding(.top, 14)

            Text("""
                 The guide ships inside the app, so on screen it always describes the build you are \
                 running. This is a copy of it. It stops being true the moment either the app or the \
                 guide moves on, so check the version above against the app before relying on it.
                 """)
                .font(HelpPDFTheme.body)
                .lineSpacing(HelpPDFTheme.bodyLineSpacing)
                .foregroundStyle(HelpPDFTheme.quietInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .leading)
                .padding(.top, 8)

            Text("Contents")
                .font(HelpPDFTheme.heading(2))
                .foregroundStyle(HelpPDFTheme.ink)
                .padding(.top, 28)

            ForEach(sections, id: \.section.id) { group in
                Text(group.section.title)
                    .font(HelpPDFTheme.bodyBold)
                    .foregroundStyle(HelpPDFTheme.quietInk)
                    .padding(.top, 16)

                ForEach(group.topics) { topic in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        if let module = topic.module {
                            Image(systemName: module.icon)
                                .font(.system(size: 9))
                                .foregroundStyle(HelpPDFTheme.onWhite(module.accentColour))
                                .frame(width: 12, alignment: .leading)
                        } else {
                            Color.clear.frame(width: 12, height: 1)
                        }
                        Text(topic.title)
                            .font(HelpPDFTheme.body)
                            .foregroundStyle(HelpPDFTheme.ink)
                    }
                    .padding(.top, 5)
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

// MARK: - Figures

/// A figure, drawn by the app's own view and kept in the app's own appearance.
///
/// The figures illustrate a dark application, and `ModulePalette` states that its hues are tuned for
/// that appearance. Rendering one light would show the reader a version of the app that does not
/// exist. So the whole panel is forced dark — the app's real backdrop behind the app's real view —
/// which has the second virtue of being *deterministic*: both the ink and the ground are set here,
/// so the white-on-white that sank the first attempt cannot arise, in either direction.
///
/// Laid out at `figureDesignWidth` and scaled by the exporter; see that constant for why.
struct HelpPDFFigure: View {
    let id: String

    var body: some View {
        HelpFigureView(id: id)
            .padding(18)
            .frame(width: HelpPDFTheme.figureDesignWidth - 36, alignment: .leading)
            // The app's real backdrop, unmodified.
            //
            // It survives only because the exporter places a figure as a rendered *image*: drawn
            // straight into a PDF context, `AppBackground`'s gradient loses the 12–22% alpha on its
            // stops and prints as a vivid purple band instead of a wash. Measured — the same
            // renderer gave (0.16, 0.13, 0.23) to a bitmap and (0.31, 0.18, 0.66) to a PDF. See
            // `HelpPDFExportService.Atom.rasterise`.
            .background(AppBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(white: 0.45), lineWidth: 1)
            )
            .environment(\.colorScheme, .dark)
            // Tells the shared Liquid Glass helper that this is going onto a page, so it draws a
            // flat panel instead of asking for an effect a document cannot carry — and, more to the
            // point, one that does not render reliably off screen. See `\.isDocumentRendering`.
            .environment(\.isDocumentRendering, true)
            // The paper behind the panel's rounded corners.
            //
            // The exporter places a figure as a JPEG, and a JPEG has no alpha: without an opaque
            // ground the corners would composite onto black and print as four dark notches. The page
            // is white, so painting it here is invisible and makes the image safe to compress.
            .background(Color.white)
    }
}

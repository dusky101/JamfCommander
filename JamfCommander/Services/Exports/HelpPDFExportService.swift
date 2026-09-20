//
//  HelpPDFExportService.swift
//  JamfCommander
//
//  Turns help topics into a PDF: compose the whole document in memory, then hand the bytes to one
//  save panel. The same shape every CSV export has — `ExportService.saveCSVToFile(content:)` is the
//  door, and `savePDFToFile(data:)` is its sibling.
//
//  ## Why this is not `NSPrintOperation`
//
//  It was, on 19 September 2026, and it failed three ways: white text on a white page, then a blank
//  document, then forty pages for twenty topics. The first two were the appearance system — an
//  `NSHostingView` inherits the *appearance*, and `.environment(\.colorScheme, .light)` does not
//  touch it. The third was pagination: AppKit was breaking one tall view wherever the page boundary
//  happened to land, through the middle of callouts and lists.
//
//  `ImageRenderer` answers both. It resolves semantic colours against SwiftUI's colour scheme rather
//  than the AppKit appearance — measured before any of this was written, by rendering the same
//  paragraph three ways under an application forced dark — and its `render { size, context in … }`
//  hands over a `CGContext`, so this file decides where every page break falls.
//
//  ## Pagination
//
//  The document is flattened into **atoms**: the smallest pieces that may not be split. A paragraph
//  is one. A callout is one, however much it contains, because a warning cut in half is worse than a
//  page that ends early. A list is one atom *per item*, so a long list breaks between items rather
//  than through a sentence. Each atom is measured, then placed; a heading is kept with whatever
//  follows it, so no section title is left stranded at the foot of a page.
//
//  Nothing here touches Jamf, and the guide's content is bundled text: an export makes no network
//  request and contains no tenant data, no instance URL and no credential.
//

import SwiftUI
import AppKit
import ImageIO

@MainActor
enum HelpPDFExportService {

    // MARK: - Public

    /// Compose a PDF of the given topics and ask the reader where to save it.
    ///
    /// Returns `false` when the reader cancels the panel, matching `saveCSVToFile`.
    @discardableResult
    static func export(topics: [HelpTopic], defaultName: String, paper: HelpPDFPaper) -> Bool {
        let data = pdfData(topics: topics, page: paper.page)
        guard !data.isEmpty else {
            ExportService.reportExportFailure(message: "The guide could not be rendered.")
            return false
        }
        return ExportService.savePDFToFile(data: data, defaultName: defaultName)
    }

    /// The finished document, as bytes.
    ///
    /// Separate from the saving so the composition can be exercised without a panel in front of it.
    /// `page` is not defaulted: a default argument is evaluated outside the actor, and resolving the
    /// system's paper size is main-actor work. The caller chooses the paper anyway.
    static func pdfData(topics: [HelpTopic],
                        page: HelpPDFPage,
                        stampedAt date: Date = Date()) -> Data {
        let stamp = Stamp(date: date)
        let atoms = atoms(for: topics, page: page, stamp: stamp)
        let measured = atoms.map { measure($0) }
        let pages = paginate(measured, page: page)
        return draw(pages, page: page, stamp: stamp)
    }

    /// The default file name for an export: the app, what was exported, and the date it was made.
    static func defaultFileName(for subject: String, on date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "yyyy-MM-dd"
        let slug = subject
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "JamfCommander_\(slug)_\(formatter.string(from: date)).pdf"
    }

    // MARK: - The stamp

    /// What every page carries: which build of the app wrote it, and when.
    ///
    /// The guide's whole claim is that it ships with the app and therefore describes the app. A PDF
    /// breaks that link the moment either moves, so a copy has to say how old it is — and it has to
    /// say so on **every** page, because a page is exactly what gets forwarded on its own.
    struct Stamp {
        let date: Date

        var version: String {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        }

        var text: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_GB")
            formatter.dateFormat = "d MMMM yyyy"
            return "Jamf Commander \(version) · exported \(formatter.string(from: date))"
        }
    }

    // MARK: - Atoms

    /// One indivisible piece of the flow.
    private struct Atom {
        let view: AnyView
        /// The gap this piece wants above it, when it is not the first thing on a page.
        let spaceAbove: CGFloat
        /// Whether a page break may fall immediately after it. `true` for a heading, which belongs
        /// to the text below it.
        let keepWithNext: Bool
        /// The width it is laid out at — wider than the column for a figure, which is then reduced.
        let layoutWidth: CGFloat
        /// How much the finished drawing is reduced when it is placed.
        let scale: CGFloat
        /// Whether this piece must open a page of its own. The cover does, and so does each topic
        /// in a whole-guide export: a page that begins mid-topic gives a reader nothing to orient
        /// by, and the guide's pages are the unit somebody forwards.
        var startsPage: Bool = false
        /// Whether to draw this piece as an image rather than straight into the PDF context.
        ///
        /// **Figures are, and prose is not.** A `CGPDFContext` does not reproduce everything
        /// `ImageRenderer` can draw: a gradient whose stops carry alpha comes out opaque, and the
        /// app's backdrop is exactly that. Rendering the same fourteen figures both ways and
        /// comparing them pixel by pixel put nine of them well outside any tolerance — the worst off
        /// by a mean of 55 levels per channel — while text, rules and flat translucent fills came
        /// back identical.
        ///
        /// So the figures are rasterised, at twice their placed size, and everything else stays
        /// vector. The trade is deliberate: a figure is an illustration of a screen, so a picture of
        /// it is honest, and the running text — the part somebody searches, copies a privilege name
        /// out of, or hands to a screen reader — loses nothing.
        var rasterise: Bool = false
    }

    /// Flatten every topic into the pieces a page is built from.
    ///
    /// A single topic is exported as itself — no cover, because the case this exists for is handing
    /// somebody one page. More than one gets a cover, because a sixty-page document with no front
    /// matter says nothing about what it is or how old it is until you are already inside it.
    private static func atoms(for topics: [HelpTopic], page: HelpPDFPage, stamp: Stamp) -> [Atom] {
        var atoms: [Atom] = []
        let isWholeGuide = topics.count > 1

        if isWholeGuide {
            atoms.append(Atom(view: AnyView(HelpPDFCover(topics: topics,
                                                         stamp: stamp.text,
                                                         width: page.contentWidth)),
                              spaceAbove: 0,
                              keepWithNext: false,
                              layoutWidth: page.contentWidth,
                              scale: 1,
                              startsPage: true))
        }

        for (topicIndex, topic) in topics.enumerated() {
            let blocks = HelpMarkdown.parse(topic.body)

            for (index, block) in blocks.enumerated() {
                let previous = index == 0 ? nil : blocks[index - 1]
                let opensTopic = index == 0
                // A topic that opens a page has the top margin above it, so its own gap is unused.
                let space = opensTopic && (isWholeGuide || topicIndex > 0)
                    ? 0
                    : HelpPDFTheme.space(before: block, after: previous)

                var blockAtoms = self.atoms(for: block,
                                            module: topic.module,
                                            spaceAbove: space,
                                            page: page)
                if opensTopic, isWholeGuide, !blockAtoms.isEmpty {
                    blockAtoms[0].startsPage = true
                }
                atoms.append(contentsOf: blockAtoms)
            }
        }

        return atoms
    }

    /// One block's atoms. Lists become one atom per item; everything else is a single atom.
    private static func atoms(for block: HelpBlock,
                              module: AppModule?,
                              spaceAbove: CGFloat,
                              page: HelpPDFPage) -> [Atom] {
        let width = page.contentWidth

        switch block {
        case .bulleted(let items):
            return items.enumerated().map { offset, item in
                Atom(view: AnyView(HelpPDFListRow(marker: .bullet, text: item, width: width)),
                     spaceAbove: offset == 0 ? spaceAbove : HelpPDFListRow.spacing,
                     keepWithNext: false,
                     layoutWidth: width,
                     scale: 1)
            }

        case .numbered(let start, let items):
            return items.enumerated().map { offset, item in
                Atom(view: AnyView(HelpPDFListRow(marker: .number(start + offset),
                                                  text: item, width: width)),
                     spaceAbove: offset == 0 ? spaceAbove : HelpPDFListRow.spacing,
                     keepWithNext: false,
                     layoutWidth: width,
                     scale: 1)
            }

        case .figure(let id):
            return [Atom(view: AnyView(HelpPDFFigure(id: id)),
                         spaceAbove: spaceAbove,
                         keepWithNext: false,
                         layoutWidth: HelpPDFTheme.figureDesignWidth,
                         scale: page.figureScale,
                         rasterise: true)]

        case .heading:
            return [Atom(view: AnyView(HelpPDFBlockView(block: block, module: module, width: width)),
                         spaceAbove: spaceAbove,
                         // A heading at the foot of a page, with its section on the next, is the
                         // one break that reads as a mistake rather than as a page ending.
                         keepWithNext: true,
                         layoutWidth: width,
                         scale: 1)]

        default:
            return [Atom(view: AnyView(HelpPDFBlockView(block: block, module: module, width: width)),
                         spaceAbove: spaceAbove,
                         keepWithNext: false,
                         layoutWidth: width,
                         scale: 1)]
        }
    }

    // MARK: - Measurement

    /// An atom that knows how much room it needs.
    private struct Measured {
        let renderer: ImageRenderer<AnyView>
        let atom: Atom
        /// The size it laid out at, before `atom.scale`. Points, not pixels, even when rasterised.
        let naturalSize: CGSize
        /// The finished drawing, for an atom that is placed as an image. See `Atom.rasterise`.
        let image: CGImage?

        /// The room it takes on the page.
        var height: CGFloat { naturalSize.height * atom.scale }
    }

    /// Lay an atom out and record its size.
    ///
    /// `render` computes the layout and then calls back; the drawing itself only happens when the
    /// callback's closure is invoked, which this deliberately does not do. Measuring therefore costs
    /// a layout pass, not a rasterisation.
    private static func measure(_ atom: Atom) -> Measured {
        let renderer = ImageRenderer(content: AnyView(
            atom.view
                // The line that the first attempt needed and did not have. `ImageRenderer` resolves
                // `.primary`, `.secondary` and `Color(nsColor:)` against this value rather than
                // against `NSApp.effectiveAppearance`, which is what makes a light page possible
                // inside an app locked to dark. Figures override it again, back to dark.
                .environment(\.colorScheme, .light)
        ))
        renderer.proposedSize = ProposedViewSize(width: atom.layoutWidth, height: nil)

        var measuredSize = CGSize.zero
        renderer.render { size, _ in measuredSize = size }

        var image: CGImage?
        if atom.rasterise {
            // Twice the size it lays out at. A figure lays out at 700pt and is placed at about
            // 467pt, so this lands near 215 dots per inch on the page — sharp in print, without
            // making an illustration the largest thing in the file.
            renderer.scale = 2
            image = renderer.cgImage.flatMap(compressed)
        }

        return Measured(renderer: renderer, atom: atom, naturalSize: measuredSize, image: image)
    }

    /// Re-encode a rendered figure as JPEG, so the PDF embeds it compressed.
    ///
    /// `CGPDFContext` passes a JPEG-backed image through as `DCTDecode` rather than re-encoding it,
    /// which is the difference between a guide that can be emailed and one that cannot: the same
    /// fourteen figures came to roughly 1MB each as raw pixels and a fraction of that this way.
    ///
    /// Quality is set high deliberately. These are pictures of an interface, all small text and hard
    /// edges, which is the content JPEG handles worst; the saving at 0.9 is most of the saving there
    /// is, and going lower starts to show around the lettering.
    ///
    /// If anything in the chain refuses, the uncompressed image is used — a large file beats a
    /// missing illustration.
    private static func compressed(_ image: CGImage) -> CGImage {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let jpeg = representation.representation(using: .jpeg,
                                                       properties: [.compressionFactor: 0.9]),
              let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return image
        }
        return decoded
    }

    // MARK: - Pagination

    /// An atom with its place on a page: how far down the content column it starts, and any further
    /// reduction needed to fit.
    private struct Placed {
        let measured: Measured
        let y: CGFloat
        /// Applied on top of the atom's own scale, for the rare piece taller than a whole page.
        let squeeze: CGFloat

        var scale: CGFloat { measured.atom.scale * squeeze }
        var height: CGFloat { measured.naturalSize.height * scale }
    }

    private static func paginate(_ atoms: [Measured], page: HelpPDFPage) -> [[Placed]] {
        let limit = page.contentHeight
        var pages: [[Placed]] = []
        var current: [Placed] = []
        var y: CGFloat = 0

        func closePage() {
            if !current.isEmpty { pages.append(current) }
            current = []
            y = 0
        }

        for (index, measured) in atoms.enumerated() {
            if measured.atom.startsPage { closePage() }
            let space = current.isEmpty ? 0 : measured.atom.spaceAbove

            // A single piece taller than the whole column cannot be broken — a figure, or a code
            // block of thirty lines. Reducing it keeps it whole and keeps it on one page, which is
            // the lesser of the two evils; clipping it would lose content silently.
            var squeeze: CGFloat = 1
            if measured.height > limit {
                squeeze = limit / measured.height
            }
            var height = measured.height * squeeze

            var needed = space + height
            // A heading has to fit with the first piece of what it introduces.
            if measured.atom.keepWithNext, index + 1 < atoms.count {
                let next = atoms[index + 1]
                needed += next.atom.spaceAbove + min(next.height, limit)
            }

            if !current.isEmpty, y + needed > limit {
                closePage()
                // Starting a page re-measures nothing, but the reduction is relative to the column
                // and the gap above disappears, so both are worked out again.
                if measured.height > limit {
                    squeeze = limit / measured.height
                    height = measured.height * squeeze
                }
                current.append(Placed(measured: measured, y: 0, squeeze: squeeze))
                y = height
                continue
            }

            current.append(Placed(measured: measured, y: y + space, squeeze: squeeze))
            y += space + height
        }

        closePage()
        return pages
    }

    // MARK: - Drawing

    private static func draw(_ pages: [[Placed]], page: HelpPDFPage, stamp: Stamp) -> Data {
        let data = NSMutableData()
        var mediaBox = page.mediaBox
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        for (index, placedAtoms) in pages.enumerated() {
            context.beginPDFPage(nil)

            // A PDF page has no ground of its own. Without this the document is transparent, which
            // most viewers show as white and some show as whatever is behind them.
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)

            for placed in placedAtoms {
                draw(placed, in: context, page: page)
            }

            drawFooter(stamp: stamp,
                       pageNumber: index + 1,
                       of: pages.count,
                       in: context,
                       page: page)

            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }

    /// Draw one placed atom.
    ///
    /// Core Graphics puts the origin at the bottom-left and the renderer paints its content upwards
    /// from there, so the translation is to the *bottom* of where the piece should sit. Scaling
    /// afterwards scales about that point, which is why the height it is offset by is the scaled one.
    private static func draw(_ placed: Placed, in context: CGContext, page: HelpPDFPage) {
        context.saveGState()
        context.translateBy(x: HelpPDFTheme.marginSide,
                            y: page.size.height - HelpPDFTheme.marginTop - placed.y - placed.height)
        if let image = placed.measured.image {
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(origin: .zero,
                                           size: CGSize(width: placed.measured.naturalSize.width * placed.scale,
                                                        height: placed.height)))
        } else {
            if placed.scale != 1 {
                context.scaleBy(x: placed.scale, y: placed.scale)
            }
            placed.measured.renderer.render { _, drawInContext in
                drawInContext(context)
            }
        }
        context.restoreGState()
    }

    private static func drawFooter(stamp: Stamp,
                                   pageNumber: Int,
                                   of total: Int,
                                   in context: CGContext,
                                   page: HelpPDFPage) {
        let footer = HelpPDFFooter(stamp: stamp.text,
                                   page: "Page \(pageNumber) of \(total)",
                                   width: page.contentWidth)
        let renderer = ImageRenderer(content: AnyView(
            footer.environment(\.colorScheme, .light)
        ))
        renderer.proposedSize = ProposedViewSize(width: page.contentWidth, height: nil)

        context.saveGState()
        context.translateBy(x: HelpPDFTheme.marginSide, y: HelpPDFTheme.footerInset)
        renderer.render { _, drawInContext in
            drawInContext(context)
        }
        context.restoreGState()
    }
}

// MARK: - Footer

/// The line at the foot of every page: which build wrote this copy, when, and where you are in it.
private struct HelpPDFFooter: View {
    let stamp: String
    let page: String
    let width: CGFloat

    var body: some View {
        VStack(spacing: 5) {
            Rectangle()
                .fill(HelpPDFTheme.rule)
                .frame(width: width, height: 0.5)
            HStack(alignment: .firstTextBaseline) {
                Text(stamp)
                Spacer(minLength: 12)
                Text(page)
            }
            .font(HelpPDFTheme.footer)
            .foregroundStyle(HelpPDFTheme.quietInk)
        }
        .frame(width: width, alignment: .leading)
    }
}

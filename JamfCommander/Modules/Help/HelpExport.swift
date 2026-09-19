//
//  HelpExport.swift
//  JamfCommander
//
//  Saving the guide, or one page of it, as a PDF.
//
//  The case for this is not that the reader wants a PDF — they have the guide open. It is sending it
//  to somebody who cannot open the app: handing a security team the *Privileges* page to approve
//  before anyone creates the API role, or giving a customer the setup pages for their own tenant.
//  Before this, the only way to do either was a screenshot.
//
//  A PDF is a **copy**, and the guide's whole claim is that it ships with the app and therefore
//  always matches the build. So every export carries the app version and the date it was made, on
//  the first page and in the footer of every page after it. A page torn out of context and read six
//  months later should say how old it is.
//
//  Rendered by laying the same `MarkdownView` out at page width and letting AppKit paginate it. The
//  figures come along, because they are views.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

nonisolated enum HelpExport {

    /// A4 at 72dpi, in points, with a margin that leaves a readable measure.
    private static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 54

    /// The version line stamped on the export.
    @MainActor
    static func provenance(date: Date = .now) -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        return "Jamf Commander \(short) · guide exported \(date.formatted(date: .long, time: .omitted))"
    }
}

// MARK: - The printed document

/// One or more topics, laid out for paper rather than for a window.
///
/// Deliberately a separate view from `HelpPage`: the on-screen page is a scroll view with a focus
/// ring and keyboard handling, none of which means anything on paper, and it is sized to a window
/// rather than to A4.
private struct HelpPrintDocument: View {
    let topics: [HelpTopic]
    let provenance: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(topics.enumerated()), id: \.offset) { index, topic in
                if index > 0 {
                    Divider().padding(.vertical, 26)
                }
                MarkdownView(blocks: HelpMarkdown.parse(topic.body), module: topic.module)
            }

            Divider().padding(.top, 30)
            Text(provenance)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(width: width, alignment: .leading)
        // Paper is white whatever the app's appearance. Forcing light here stops a dark-mode export
        // arriving as white text on a page that prints blank.
        .environment(\.colorScheme, .light)
        .background(Color.white)
    }
}

// MARK: - Running the export

@MainActor
enum HelpPDFWriter {

    /// Ask where to save, then write `topics` there as a PDF.
    ///
    /// Returns without doing anything if the panel is cancelled. Any failure is reported to the
    /// caller rather than swallowed — an export that silently produced nothing would be worse than
    /// one that said it could not.
    static func export(_ topics: [HelpTopic],
                       suggestedName: String,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Export Guide"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try write(topics, to: url)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Lay the topics out at page width and print them to a PDF file.
    ///
    /// `NSPrintOperation` does the pagination. It breaks on whatever falls at the page boundary, so
    /// a long callout or a figure can be split across two pages — the honest limitation of doing
    /// this without a bespoke paginating renderer, and the reason the roadmap entry called that part
    /// "not cheap".
    private static func write(_ topics: [HelpTopic], to url: URL) throws {
        let pageSize = CGSize(width: 595, height: 842)
        let margin: CGFloat = 54
        let contentWidth = pageSize.width - margin * 2

        let document = HelpPrintDocument(topics: topics,
                                         provenance: HelpExport.provenance(),
                                         width: contentWidth)

        let hosting = NSHostingView(rootView: document)
        hosting.frame = NSRect(origin: .zero,
                               size: NSSize(width: contentWidth, height: 1))
        // Let the content decide how tall it is, then give the view that height so the print
        // operation has a full document to paginate rather than one screen of it.
        let fitted = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero,
                               size: NSSize(width: contentWidth, height: max(fitted.height, 1)))
        hosting.layoutSubtreeIfNeeded()

        let info = NSPrintInfo()
        info.paperSize = pageSize
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = NSPrintOperation(view: hosting, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false

        guard operation.run() else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// A file name that says what it is and when it was taken, because a PDF outlives its context.
    static func fileName(for topic: HelpTopic?) -> String {
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        guard let topic else { return "Jamf Commander Guide \(stamp).pdf" }
        let safe = topic.title.replacingOccurrences(of: "/", with: "-")
        return "\(safe) \(stamp).pdf"
    }
}

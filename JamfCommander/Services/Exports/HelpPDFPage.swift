//
//  HelpPDFPage.swift
//  JamfCommander
//
//  The sheet an export is laid out on, and the column of content inside it.
//
//  **The size comes from the Mac's own paper setting**, read once per export from `NSPrintInfo`.
//  The alternative was to fix it at A4, which is what this maintainer's own readers expect — but the
//  app is not only used here, and a US reader handed an A4 document gets a page that will not print
//  without scaling. Following the system means the exporter produces whatever the person doing the
//  exporting would have got from Page Setup.
//
//  The cost of that choice, stated plainly because it is real: **the same page exported on two Macs
//  set to different paper is not the same document.** A page count, and where any given paragraph
//  falls, both move. Nothing downstream depends on either, but somebody comparing two copies should
//  know why they differ — which is also why the export popover names the paper it is about to use,
//  and lets the reader override it when they are exporting *for* somebody else.
//
//  Margins are fixed rather than proportional: 64pt of side margin is a comfortable margin on A4 and
//  on Letter alike, and the column it leaves is within a line length that reads well on both.
//

import Foundation
import AppKit

/// One export's page geometry. A value, resolved at the moment of export and then passed around, so
/// no part of the renderer can read a different page size than another part.
nonisolated struct HelpPDFPage: Equatable {
    /// The whole sheet, in points.
    let size: CGSize

    /// The column the content flows in.
    var contentWidth: CGFloat { size.width - HelpPDFTheme.marginSide * 2 }
    /// How much of the sheet's height one page of content may occupy.
    var contentHeight: CGFloat { size.height - HelpPDFTheme.marginTop - HelpPDFTheme.marginBottom }
    /// The whole sheet as a rect, for the media box and the white ground.
    var mediaBox: CGRect { CGRect(origin: .zero, size: size) }

    /// How much a figure is reduced to fit the column. See `HelpPDFTheme.figureDesignWidth`.
    var figureScale: CGFloat { contentWidth / HelpPDFTheme.figureDesignWidth }

    /// The Mac's default paper size, or A4 if the printing system reports nothing usable.
    ///
    /// `NSPrintInfo.shared` is read, not run: this asks the printing system what paper it would
    /// default to and then draws the PDF itself. None of the 19 September failures came from asking
    /// that question — they came from handing `NSPrintOperation` a view and letting it paginate.
    ///
    /// A machine with no printer configured still answers, from the region's default. The guard is
    /// for the pathological case: a zero or absurd size would otherwise produce a document with no
    /// room to put anything on.
    @MainActor
    static func systemDefault() -> HelpPDFPage {
        let paper = NSPrintInfo.shared.paperSize
        let usable = paper.width > 200 && paper.height > 200
            && paper.width < 3000 && paper.height < 3000
        return HelpPDFPage(size: usable ? paper : HelpPDFTheme.a4)
    }

    /// How the paper is described to the reader — "A4", "US Letter", or the size in millimetres when
    /// the printing system has no name for it.
    @MainActor
    static func systemPaperName() -> String {
        let info = NSPrintInfo.shared
        if let name = info.localizedPaperName, !name.isEmpty { return name }
        if let raw = info.paperName?.rawValue, !raw.isEmpty { return raw }
        let size = info.paperSize
        let millimetres = { (points: CGFloat) in Int((points / 72 * 25.4).rounded()) }
        return "\(millimetres(size.width))×\(millimetres(size.height))mm"
    }
}

/// The paper an export is laid out on.
///
/// The system's own setting is the default, because that is what the person exporting would get from
/// Page Setup and what their printer holds. The two named sizes are here because the reader is often
/// not the exporter: a UK administrator sending the *Privileges* page to a security team in the
/// United States wants Letter, whatever their own Mac is set to. Remembered between exports — it is a
/// property of who you send documents to, not of one export.
nonisolated enum HelpPDFPaper: String, CaseIterable, Identifiable, Sendable {
    case system
    case a4
    case letter

    var id: String { rawValue }

    /// US Letter, in points.
    static let usLetter = CGSize(width: 612, height: 792)

    /// What the picker shows. The system option names the paper it resolved to, so the choice can be
    /// made without opening Page Setup to find out what it is.
    @MainActor
    var title: String {
        switch self {
        case .system: return "System default (\(HelpPDFPage.systemPaperName()))"
        case .a4: return "A4"
        case .letter: return "US Letter"
        }
    }

    @MainActor
    var page: HelpPDFPage {
        switch self {
        case .system: return .systemDefault()
        case .a4: return HelpPDFPage(size: HelpPDFTheme.a4)
        case .letter: return HelpPDFPage(size: Self.usLetter)
        }
    }
}

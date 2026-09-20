//
//  HelpPDFTheme.swift
//  JamfCommander
//
//  The guide's print stylesheet: page geometry, ink, and a type scale in fixed points.
//
//  Deliberately not the screen's styling. The guide on screen is set in semantic text styles so it
//  follows the reader's accessibility text size, and in semantic colours so it follows the dark
//  appearance the app is locked to. A PDF has neither: it is a fixed page that will be read by
//  somebody who does not have the app, printed as often as it is scrolled, and it must be black on
//  white whatever the exporting Mac happened to be set to.
//
//  **Every ink here is an explicit value.** `.primary` and `Color(nsColor:)` resolve against the
//  colour scheme, and the 19 September 2026 attempt printed white text on a white page for exactly
//  that reason. `ImageRenderer` does honour `.environment(\.colorScheme, .light)` — that is measured,
//  not assumed — but a document whose body colour cannot be inherited from anywhere cannot fail that
//  way twice.
//
//  Pure arithmetic and constants, so it can be reasoned about without reading a view.
//

import SwiftUI
import AppKit

nonisolated enum HelpPDFTheme {

    // MARK: - The page

    static let marginTop: CGFloat = 64
    static let marginSide: CGFloat = 64
    /// Deeper than the top margin, because the footer stamp lives in it.
    static let marginBottom: CGFloat = 76

    /// How far above the bottom edge the footer stamp sits.
    static let footerInset: CGFloat = 40

    /// A4, the fallback when the printing system reports nothing usable.
    static let a4 = CGSize(width: 595.28, height: 841.89)

    // MARK: - Ink

    /// Body text. Black, and nothing resolves it to anything else.
    static let ink = Color.black
    /// Supporting text — the footer stamp, a code block's language.
    static let quietInk = Color(white: 0.38)
    /// Hairlines: the footer rule, a divider, a code block's border.
    static let rule = Color(white: 0.78)
    /// A code block's ground. Light enough that the text on it is still nearly full contrast.
    static let codeGround = Color(white: 0.955)

    // MARK: - Type

    /// Running text. 11pt is the size a reference document is set in; at 9 or 10 this reads as a
    /// footnote, and the guide is meant to be read rather than referred to.
    static let bodySize: CGFloat = 11
    static let body = Font.system(size: bodySize)
    static let bodyBold = Font.system(size: bodySize, weight: .semibold)
    static let bodyLineSpacing: CGFloat = 3.5

    /// Inline code, and fenced code blocks. A touch smaller than the body, as monospaced faces run
    /// visually larger at the same point size.
    static let codeSize: CGFloat = 9.5
    static let code = Font.system(size: codeSize, design: .monospaced)

    static let footer = Font.system(size: 8)

    /// The heading scale. Level 1 is the page title.
    static func heading(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 23, weight: .bold)
        case 2: return .system(size: 16, weight: .bold)
        case 3: return .system(size: 13, weight: .semibold)
        default: return .system(size: 11.5, weight: .semibold)
        }
    }

    // MARK: - Figures

    /// The width a figure is laid out at before it is scaled onto the page.
    ///
    /// The figures were composed for the guide's 760pt reading column, and several of them — the
    /// sidebar, the four Installomator views — arrange themselves differently when squeezed. Laying
    /// one out at close to its designed width and then scaling the finished drawing down keeps the
    /// arrangement the author intended. Nothing is lost doing it: `ImageRenderer` emits vector text,
    /// so a scaled figure is smaller but not softer.
    static let figureDesignWidth: CGFloat = 700

    // MARK: - Module colour on white

    /// A module's hue, darkened until it is legible on white.
    ///
    /// `ModulePalette` says of itself that its hues are tuned for the dark appearance the app is
    /// locked to, and that several of them fail contrast on white — lime and the Dashboard's neutral
    /// are nearly invisible on paper. Rather than inventing a second palette that would drift from
    /// the first, this keeps the module's hue and takes brightness out of it until the colour clears
    /// the WCAG AA ratio for normal text. Policies stays pink, Scripts stays green; both become
    /// readable.
    ///
    /// Saturation is lifted slightly as brightness falls, because a hue that is only darkened turns
    /// muddy well before it turns legible.
    /// Resolved in the light appearance on purpose. `Color.blue` and its siblings are dynamic, so
    /// `NSColor(_:)` would otherwise hand back whichever variant the *app* is currently showing —
    /// and the app is locked to dark. The result of this function has to depend on its argument
    /// alone, or the same callout would print differently depending on something it cannot see.
    @MainActor
    static func onWhite(_ colour: Color, minimumContrast: Double = 4.5) -> Color {
        var resolved: NSColor?
        let light = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        light.performAsCurrentDrawingAppearance {
            resolved = NSColor(colour).usingColorSpace(.sRGB)
        }
        guard let sRGB = resolved else { return ink }

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        sRGB.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        var candidate = sRGB
        // Walk the brightness down in small steps. Twenty-odd iterations at worst, once per heading.
        while contrastWithWhite(of: candidate) < minimumContrast, brightness > 0.06 {
            brightness = max(brightness - 0.04, 0.06)
            saturation = min(saturation + 0.03, 1)
            candidate = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
                .usingColorSpace(.sRGB) ?? candidate
        }
        return Color(nsColor: candidate)
    }

    // MARK: - Vertical rhythm

    /// How much smaller the page's gaps are than the screen's.
    ///
    /// `HelpRhythm` decides *which* gap each pair of blocks gets — a heading opens a section, a list
    /// belongs to the line that introduces it — and that reasoning is typographic, so it holds on
    /// paper as well. Only the magnitude is tied to the type size, and the page is set at 11pt in a
    /// 467pt column against the screen's 15pt in a 760pt one. Scaling one rule beats maintaining two
    /// that would quietly disagree.
    static let rhythmScale: CGFloat = 0.65

    /// The gap to leave above `block`, on paper.
    static func space(before block: HelpBlock, after previous: HelpBlock?) -> CGFloat {
        (HelpRhythm.space(before: block, after: previous) * rhythmScale).rounded()
    }

    /// `colour` mixed into the white page, as an **opaque** colour.
    ///
    /// The print stylesheet composites its own tints rather than asking the PDF to do it. Alpha is
    /// the one thing a `CGPDFContext` has repeatedly got wrong here — a gradient's stops lose it
    /// outright — so a page that needs none is a page with fewer ways to go wrong.
    @MainActor
    static func onPaper(_ colour: Color, fraction: Double) -> Color {
        var resolved: NSColor?
        let light = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        light.performAsCurrentDrawingAppearance {
            resolved = NSColor(colour).usingColorSpace(.sRGB)
        }
        guard let sRGB = resolved else { return .white }
        let mix = { (component: CGFloat) in 1 - (1 - Double(component)) * fraction }
        return Color(red: mix(sRGB.redComponent),
                     green: mix(sRGB.greenComponent),
                     blue: mix(sRGB.blueComponent))
    }

    /// The WCAG contrast ratio between a colour and white.
    private static func contrastWithWhite(of colour: NSColor) -> Double {
        let luminance = relativeLuminance(of: colour)
        return 1.05 / (luminance + 0.05)
    }

    /// WCAG relative luminance: sRGB components linearised, then weighted.
    private static func relativeLuminance(of colour: NSColor) -> Double {
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(colour.redComponent)
             + 0.7152 * linear(colour.greenComponent)
             + 0.0722 * linear(colour.blueComponent)
    }
}

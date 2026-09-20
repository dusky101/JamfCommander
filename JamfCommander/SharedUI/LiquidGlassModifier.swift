//
//  LiquidGlassModifier.swift
//  JamfCommander
//
//  Liquid Glass helpers — matches the DevDump implementation.
//  Uses glassEffect(in: .rect(cornerRadius:, style: .continuous)) on macOS 26+,
//  falls back to .ultraThinMaterial on older systems.
//
//  One other route exists: `\.isDocumentRendering`, set while a view is being drawn into a PDF
//  rather than onto the screen. See that property for why glass cannot come along.
//

import SwiftUI

extension EnvironmentValues {

    /// Whether this view is being drawn into a document rather than onto the screen.
    ///
    /// Set by the help guide's PDF export (`HelpPDFFigure`), which renders the app's real views so an
    /// illustration cannot go stale. Liquid Glass cannot come with them, for two reasons:
    ///
    /// - **A page has nothing to blur.** Glass samples what is behind it; on paper there is no
    ///   "behind", so the effect has no meaning even where it renders.
    /// - **It does not render reliably off screen.** Rendering the same figure in two processes
    ///   produced the content once and an empty panel the other time, with no change in between.
    ///   An illustration that is sometimes blank is worse than one that is plainly flat.
    ///
    /// So a view drawn into a document gets a flat panel in place of the glass: the same shape, the
    /// same inset, and a ground it can actually be given. Nothing else about the view changes — it is
    /// still the app's own view with the app's own data, which is the whole point of the figures.
    var isDocumentRendering: Bool {
        get { self[DocumentRenderingKey.self] }
        set { self[DocumentRenderingKey.self] = newValue }
    }
}

private struct DocumentRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension View {

    /// Rounded-rect Liquid Glass. Apply AFTER padding so the padding acts as
    /// internal inset: content → .padding(n) → .liquidGlassRect()
    /// Uses the real `glassEffect` on macOS 26+ (the app's deployment target); the
    /// `ultraThinMaterial` branch is a defensive fallback only.
    func liquidGlassRect(cornerRadius: CGFloat = 22) -> some View {
        modifier(LiquidGlassRect(cornerRadius: cornerRadius))
    }

    /// Capsule Liquid Glass — for pill buttons and tags.
    func liquidGlassCapsule() -> some View {
        modifier(LiquidGlassCapsule())
    }

    /// Alias so existing .liquidGlass() call sites still compile.
    func liquidGlass(cornerRadius: CGFloat = 16) -> some View {
        liquidGlassRect(cornerRadius: cornerRadius)
    }

    /// Strips the opaque List background so Liquid Glass shows through beneath.
    @ViewBuilder
    func transparentListBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.clear)
    }
}

/// A flat stand-in for glass: a panel a little lighter than the backdrop, with the hairline glass
/// gets from its own edge. Drawn rather than sampled, because a document has nothing behind the
/// panel to sample. Shared by both shapes so the two cannot drift apart.
private extension View {
    func documentPanel(in shape: some InsettableShape) -> some View {
        background(Color.white.opacity(0.07), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75))
    }
}

private struct LiquidGlassRect: ViewModifier {
    @Environment(\.isDocumentRendering) private var isDocumentRendering
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if isDocumentRendering {
            content.documentPanel(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(.ultraThinMaterial,
                               in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private struct LiquidGlassCapsule: ViewModifier {
    @Environment(\.isDocumentRendering) private var isDocumentRendering

    @ViewBuilder
    func body(content: Content) -> some View {
        if isDocumentRendering {
            content.documentPanel(in: Capsule())
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

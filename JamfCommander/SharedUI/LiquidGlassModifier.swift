//
//  LiquidGlassModifier.swift
//  JamfCommander
//
//  Liquid Glass helpers — matches the DevDump implementation.
//  Uses glassEffect(in: .rect(cornerRadius:, style: .continuous)) on macOS 15+,
//  falls back to .ultraThinMaterial on older systems.

import SwiftUI

extension View {

    /// Rounded-rect Liquid Glass. Apply AFTER padding so the padding acts as
    /// internal inset: content → .padding(n) → .liquidGlassRect()
    @ViewBuilder
    func liquidGlassRect(cornerRadius: CGFloat = 22) -> some View {
        if #available(macOS 15.0, *) {
            self.background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Capsule Liquid Glass — for pill buttons and tags.
    @ViewBuilder
    func liquidGlassCapsule() -> some View {
        if #available(macOS 15.0, *) {
            self.background(.ultraThinMaterial, in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// Alias so existing .liquidGlass() call sites still compile.
    @ViewBuilder
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

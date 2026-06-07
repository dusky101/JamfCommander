//
//  AppBackground.swift
//  JamfCommander
//
//  The app's single signature backdrop — a soft purple→blue wash over an adaptive window
//  base — used on the home detail pane and behind every sheet so the whole app shares one
//  look and nothing ever falls back to a flat black background. Apply with `.appBackground()`.
//

import SwiftUI

struct AppBackground: View {
    /// `elevated` is the surface variant for floating bars/cards: a frosted base (blurs
    /// what's behind) plus a slightly richer gradient, so it sits a touch above the main
    /// backdrop while sharing the same look.
    var elevated: Bool = false

    var body: some View {
        ZStack {
            if elevated {
                // Frosted base — blurs the content/gradient behind the bar (never black).
                Rectangle().fill(.ultraThinMaterial)
            } else {
                // Adaptive base (never pure black; light in Light mode, dark grey in Dark mode).
                Color(nsColor: .windowBackgroundColor)
            }

            // Signature gradient — the same palette as the home screen, a touch richer so
            // it reads clearly without being garish (restrained Apple-26 look).
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var gradientColors: [Color] {
        if elevated {
            return [
                Color(red: 0.35, green: 0.15, blue: 0.65).opacity(0.34),
                Color(red: 0.10, green: 0.25, blue: 0.70).opacity(0.24),
                Color(red: 0.05, green: 0.40, blue: 0.75).opacity(0.20)
            ]
        }
        return [
            Color(red: 0.35, green: 0.15, blue: 0.65).opacity(0.22),
            Color(red: 0.10, green: 0.25, blue: 0.70).opacity(0.15),
            Color(red: 0.05, green: 0.40, blue: 0.75).opacity(0.12)
        ]
    }
}

extension View {
    /// Places the app's signature gradient backdrop behind this view (full-bleed).
    func appBackground() -> some View {
        background(AppBackground().ignoresSafeArea())
    }

    /// Frosted, slightly-richer variant for elevated surfaces such as the action bars —
    /// blurs what's behind instead of sitting on a flat black band.
    func appBarBackground(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(AppBackground(elevated: true))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

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
    var body: some View {
        ZStack {
            // Adaptive base (never pure black; light in Light mode, dark grey in Dark mode).
            Color(nsColor: .windowBackgroundColor)

            // Signature gradient — the same palette as the home screen, a touch richer so
            // it reads clearly on sheets without being garish (restrained Apple-26 look).
            LinearGradient(
                colors: [
                    Color(red: 0.35, green: 0.15, blue: 0.65).opacity(0.22),
                    Color(red: 0.10, green: 0.25, blue: 0.70).opacity(0.15),
                    Color(red: 0.05, green: 0.40, blue: 0.75).opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

extension View {
    /// Places the app's signature gradient backdrop behind this view (full-bleed).
    func appBackground() -> some View {
        background(AppBackground().ignoresSafeArea())
    }
}

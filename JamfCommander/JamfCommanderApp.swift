//
//  JamfCommanderApp.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//

import SwiftUI

@main
struct JamfCommanderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // A floor, not a target. Without any frame here the window had no minimum and,
                // with the default resizability, sized itself to whatever the *content* said it
                // ideally wanted — so switching to a module with a tall filter bar physically grew
                // the window and pushed its own controls off the screen.
                .frame(minWidth: 960, minHeight: 600)
                // The app has one designed appearance. Its neon accents, glass and gradient backdrop
                // were all drawn against dark; the light rendering was those same values inherited
                // onto white, which is why it looked washed out rather than designed.
                //
                // This overrides a system preference, which is not free: some people set light mode
                // for medical reasons (light text on a dark ground haloes badly with astigmatism),
                // and Mac apps are expected to follow the system. The right answer is a *designed*
                // light theme, at which point this line goes and the palette in ModulePalette.swift
                // gains light variants. Until then, one finished appearance beats two, one unfinished.
                .preferredColorScheme(.dark)
        }
        .commands {
            // Replace the default Help item so ⌘? opens the app's own help rather than looking for
            // a help book that doesn't exist.
            CommandGroup(replacing: .help) {
                Button("Jamf Commander Help") {
                    HelpPresenter.shared.isPresented = true
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
        .defaultSize(width: 1360, height: 900)
        // `.contentMinSize` keeps the window under the user's control: it may be any size at or
        // above the content's minimum, and the content's *ideal* size no longer resizes it.
        // (`.automatic` and `.contentSize` both let the content drive the frame — that was the bug.)
        .windowResizability(.contentMinSize)
    }
}

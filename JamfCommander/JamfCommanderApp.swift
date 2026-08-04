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
        }
        .defaultSize(width: 1360, height: 900)
        // `.contentMinSize` keeps the window under the user's control: it may be any size at or
        // above the content's minimum, and the content's *ideal* size no longer resizes it.
        // (`.automatic` and `.contentSize` both let the content drive the frame — that was the bug.)
        .windowResizability(.contentMinSize)
    }
}

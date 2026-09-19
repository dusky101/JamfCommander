//
//  JamfCommanderApp.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//

import SwiftUI

@main
struct JamfCommanderApp: App {
    @Environment(\.openWindow) private var openWindow

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
            // The standard Settings item macOS expects in the application menu, on ⌘, — the sidebar
            // footer opens the same window, not a second way of configuring the app.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsPresenter.shared.request(.general)
                    openWindow(id: SettingsWindowID)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // Replace the default Help item so ⌘? opens the app's own help rather than looking for
            // a help book that doesn't exist.
            CommandGroup(replacing: .help) {
                Button("Jamf Commander Help") {
                    openWindow(id: HelpWindowID)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
        .defaultSize(width: 1360, height: 900)
        // `.contentMinSize` keeps the window under the user's control: it may be any size at or
        // above the content's minimum, and the content's *ideal* size no longer resizes it.
        // (`.automatic` and `.contentSize` both let the content drive the frame — that was the bug.)
        .windowResizability(.contentMinSize)

        // The guide is a **window**, not a sheet.
        //
        // It was a sheet, and a sheet has no title bar: no traffic lights, no title, and no sidebar
        // toggle, so the page began flush against the top edge and read as cramped. More to the
        // point, a sheet cannot be left open beside the thing it describes, which is what reference
        // material is for — you cannot read the *Privileges* page while filling in the API role.
        //
        // `.restorationBehavior(.disabled)` so a guide left open does not reopen on the next launch
        // in front of the app it is meant to sit beside.
        Window("Jamf Commander Guide", id: HelpWindowID) {
            HelpView()
        }
        .defaultSize(width: 1100, height: 900)
        .restorationBehavior(.disabled)

        // Settings is a **window** too, for the same reasons as the guide and one of its own: the
        // credentials it holds are the thing you are most likely to need to *look something up* for.
        // Creating a Jamf Pro API client means reading the Privileges page, or the Jamf console, and
        // a modal sheet is precisely the shape that cannot be put aside while you do.
        //
        // `.restorationBehavior(.disabled)` so Settings left open does not reopen on the next launch
        // in front of the app.
        Window("Settings", id: SettingsWindowID) {
            SettingsWindowContent()
        }
        .defaultSize(width: 860, height: 660)
        .restorationBehavior(.disabled)
    }
}

/// The guide's window identity, shared by every route into it.
let HelpWindowID = "help"

/// Settings' window identity, shared by every route into it.
let SettingsWindowID = "settings"

/// Settings needs the `JamfAPIService` for one button — Platform "Test Connection" — but a `Window`
/// scene cannot reach the service `ContentView` owns.
///
/// It gets its own, which is correct rather than a workaround: that button authenticates against
/// the Platform gateway with the credentials being typed, and it must test *those* rather than
/// whatever session the main window happens to be holding. Nothing else in Settings touches Jamf —
/// every other field is `@AppStorage`.
private struct SettingsWindowContent: View {
    @StateObject private var api = JamfAPIService()

    var body: some View {
        ConfigurationView(api: api)
    }
}

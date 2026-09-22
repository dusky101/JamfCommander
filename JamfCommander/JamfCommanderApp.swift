//
//  JamfCommanderApp.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//

import SwiftUI
import AppKit

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

            // A way back from a window that has been dragged somewhere unhelpful. There are four
            // of them now, each with a different default, and the Installomator header is the
            // reminder that a narrow window is not always a window somebody meant to make narrow.
            CommandGroup(after: .windowSize) {
                Button("Reset Window Size") {
                    guard let window = NSApp.keyWindow else { return }
                    let size = WindowDefaultSize.forWindow(window)
                    var frame = window.frame
                    // Resize from the top-left, the corner that stays put when a Mac window grows,
                    // rather than letting the title bar walk down the screen.
                    frame.origin.y += frame.height - size.height
                    frame.size = size
                    window.setFrame(frame, display: true, animate: true)
                }
                .keyboardShortcut("0", modifiers: [.command, .control])
            }

            // Replace the default Help item so ⌘? opens the app's own help rather than looking for
            // a help book that doesn't exist.
            CommandGroup(replacing: .help) {
                Button("Commander Help") {
                    openWindow(id: HelpWindowID)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
        .defaultSize(WindowDefaultSize.main)
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
        Window("Commander Guide", id: HelpWindowID) {
            HelpView()
        }
        .defaultSize(WindowDefaultSize.help)
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
        .defaultSize(WindowDefaultSize.settings)
        .restorationBehavior(.disabled)

        // Configuring an Installomator deployment is the job that most wants something else open
        // beside it — the Privileges page, the Jamf console, the vendor's download page while
        // pinning a version. It was a sheet, which is the one shape that cannot be put aside.
        //
        // `.restorationBehavior(.disabled)` because a half-configured deployment does not survive
        // being closed, let alone being relaunched into.
        Window("Deploy with Installomator", id: DeploymentWindowID) {
            DeploymentWindowContent()
        }
        .defaultSize(WindowDefaultSize.deployment)
        .restorationBehavior(.disabled)
    }
}

/// Every window's default size, in one place.
///
/// Declared here rather than as literals on each scene because "Reset Window Size" has to know the
/// same numbers. Two copies of a window's default size drift, and the one that drifts is the menu
/// item, because nobody opens it to check.
enum WindowDefaultSize {
    static let main = CGSize(width: 1360, height: 900)
    static let help = CGSize(width: 1100, height: 900)
    static let settings = CGSize(width: 860, height: 660)
    static let deployment = CGSize(width: 1080, height: 820)

    /// The default for whichever window this is.
    ///
    /// SwiftUI names a `Window` scene's `NSWindow` after its scene id, which is what makes this
    /// work without any per-window plumbing. An unrecognised window is the main one.
    static func forWindow(_ window: NSWindow) -> CGSize {
        let id = window.identifier?.rawValue ?? ""
        if id.contains(SettingsWindowID) { return settings }
        if id.contains(DeploymentWindowID) { return deployment }
        if id.contains(HelpWindowID) { return help }
        return main
    }
}

/// The guide's window identity, shared by every route into it.
let HelpWindowID = "help"

/// Settings' window identity, shared by every route into it.
let SettingsWindowID = "settings"

/// The Installomator deployment window's identity.
let DeploymentWindowID = "deployment"

/// Settings needs the `JamfAPIService` for one button — Platform "Test Connection" — but a `Window`
/// scene cannot reach the service `ContentView` owns.
///
/// It gets its own, which is correct rather than a workaround: that button authenticates against
/// the Platform gateway with the credentials being typed, and it must test *those* rather than
/// whatever session the main window happens to be holding. Nothing else in Settings touches Jamf —
/// every other field is `@AppStorage`.
/// Hosts the deployment window, and turns its two outcomes into a closed window.
///
/// The window produces a *plan*; the Installomator module does the deploying. Keeping the writes
/// where they already were is what makes this a layout change rather than a behaviour change.
private struct DeploymentWindowContent: View {
    @ObservedObject private var presenter = DeploymentPresenter.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let api = presenter.api, !presenter.pendingItems.isEmpty {
            DeploymentConfigSheet(
                api: api,
                pendingItems: presenter.pendingItems,
                onConfirm: { plan in
                    presenter.completedPlan = plan
                    dismiss()
                },
                onCancel: { dismiss() }
            )
            // Rebuilt per deployment, so none of the window's `@State` carries over to the next
            // one. See `DeploymentPresenter.sessionID`.
            .id(presenter.sessionID)
        } else {
            // Reachable by reopening the window from the Window menu after a deployment finished.
            ContentUnavailableView(
                "Nothing to deploy",
                systemImage: "arrow.down.app",
                description: Text("Choose one or more labels in Installomator, then Deploy.")
            )
            .appBackground()
        }
    }
}

private struct SettingsWindowContent: View {
    @StateObject private var api = JamfAPIService()

    var body: some View {
        ConfigurationView(api: api)
    }
}

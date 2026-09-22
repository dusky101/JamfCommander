//
//  AppIdentity.swift
//  JamfCommander
//
//  What this app is called, and which build it is, read from the bundle.
//
//  The name is **not** hard-coded here, because the name is not settled: the app is called
//  "Commander" while it is the maintainer's own tool, and a public release would need a name that
//  does not borrow Jamf's. Anything that shows the reader what they are running — the identity figure
//  in the guide, a PDF's stamp, an export's file name — reads it from `CFBundleDisplayName` instead,
//  so it cannot be renamed in one place and left stale in another.
//
//  Jamf's own names are a separate matter and stay as they are. "Jamf Pro", "Jamf Account" and "your
//  Jamf instance" name real things the administrator has to go and find; only the *app's* name is in
//  question here.
//
//  **Renaming the app** means changing `INFOPLIST_KEY_CFBundleDisplayName` in the build settings, and
//  then the places a value cannot reach: the window and menu titles in `JamfCommanderApp`, the help
//  content in `Resources/Help/*.md`, and the topic titles in `HelpLibrary`. The bundle identifier is
//  deliberately not on that list — changing it makes the app a different app to macOS, to the
//  keychain and to anything already deployed.
//
//  Pure bundle reads, so it is safe from any context.
//

import Foundation

nonisolated enum AppIdentity {

    /// The name to show a reader. `CFBundleDisplayName` is what the Finder, the Dock and the
    /// application menu already use, so this cannot disagree with them.
    static var name: String {
        let info = Bundle.main.infoDictionary
        if let display = info?["CFBundleDisplayName"] as? String, !display.isEmpty { return display }
        if let bundleName = info?["CFBundleName"] as? String, !bundleName.isEmpty { return bundleName }
        return "Commander"
    }

    /// The marketing version — `MARKETING_VERSION` in the build settings.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// The build number, when it says something the version does not.
    static var build: String? {
        guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
              build != version else { return nil }
        return build
    }

    /// The name with anything a file name should not carry taken out, for the default name an export
    /// offers in the save panel.
    static var fileNameStem: String {
        let stem = name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
        return stem.isEmpty ? "Commander" : stem
    }
}

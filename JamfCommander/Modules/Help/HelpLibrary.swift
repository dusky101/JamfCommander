//
//  HelpLibrary.swift
//  JamfCommander
//
//  The help guide's table of contents and its bundled-content loader.
//
//  `topics` is the ordered manifest — the index. `loadTopics()` reads each topic's Markdown from the
//  app bundle and returns topics with their `body` filled, so the index, the page and the search
//  index all work from the same loaded set. Content ships in-bundle, so it versions with the app:
//  there is no wiki to drift out of step with what the app actually does.
//
//  Nonisolated and value-only: the manifest is static data and bundle reads are thread-safe.
//

import Foundation

nonisolated enum HelpLibrary {

    /// The complete, ordered set of help topics. Bodies are loaded from the bundle by
    /// `loadTopics()`; only metadata lives here. Keep this in section order — within a section, the
    /// manifest order is the index order.
    static let topics: [HelpTopic] = [

        // MARK: Getting started

        HelpTopic(
            id: "welcome",
            title: "Welcome to Jamf Commander",
            section: .gettingStarted,
            summary: "What this app is, what it changes, and how to find your way around.",
            keywords: ["overview", "introduction", "start", "getting started", "first time",
                       "what is", "about", "help", "guide", "search", "index", "unofficial",
                       "disclaimer", "production", "safety"]),

        HelpTopic(
            id: "getting-connected",
            title: "Getting connected",
            section: .gettingStarted,
            summary: "The three things you need, and where to put them.",
            keywords: ["connect", "connection", "sign in", "login", "instance url", "client id",
                       "client secret", "oauth", "client credentials", "token", "bearer",
                       "initialise", "initialize", "settings", "auto-connect", "reconnect"]),

        HelpTopic(
            id: "api-client",
            title: "Creating the API client in Jamf",
            section: .gettingStarted,
            summary: "Make the API role and client that Jamf Commander signs in with.",
            keywords: ["api client", "api role", "api roles and clients", "new client",
                       "generate client secret", "access token lifetime", "enable", "jamf pro",
                       "setup", "set up", "create"]),

        HelpTopic(
            id: "privileges",
            title: "Privileges",
            section: .gettingStarted,
            summary: "Which Jamf privileges each part of the app needs.",
            keywords: ["privileges", "permissions", "role", "read", "create", "update", "delete",
                       "403", "not permitted", "least privilege", "icon", "update policies"]),

        HelpTopic(
            id: "settings-files",
            title: "Sharing your settings",
            section: .gettingStarted,
            summary: "Move a connection to another Mac with a .jamfconfig file.",
            keywords: ["jamfconfig", "export", "import", "share", "team", "colleague",
                       "settings file", "base64", "obfuscated", "not encrypted", "secret"]),

        // MARK: Using the app

        HelpTopic(
            id: "modules",
            title: "What each section does",
            section: .modules,
            summary: "A tour of the sidebar, module by module.",
            keywords: ["dashboard", "policies", "profiles", "computers", "scripts", "packages",
                       "installomator", "unused", "redundant", "blueprints", "modules", "sidebar",
                       "sections", "navigation"]),

        HelpTopic(
            id: "installomator-setup",
            title: "Before using Installomator",
            section: .modules,
            summary: "Add the Installomator script to Jamf, and label its parameters.",
            keywords: ["installomator", "script", "label", "parameter 4", "parameter4", "debug",
                       "notify", "silent", "github", "raw.githubusercontent.com", "prerequisite",
                       "setup", "overrides", "version pinning"]),

        // MARK: Reference

        HelpTopic(
            id: "troubleshooting",
            title: "If something fails",
            section: .reference,
            summary: "What the common refusals mean, and what to do about them.",
            keywords: ["error", "failed", "failure", "401", "403", "409", "unauthorised",
                       "unauthorized", "forbidden", "duplicate", "expired", "refused",
                       "troubleshooting", "problem", "not working", "no labels"]),
    ]

    /// Load every topic's Markdown body from the bundle, ready for the index, the page and search.
    ///
    /// A missing file yields a clear placeholder rather than a crash, so a content slip degrades to
    /// one obviously-empty page instead of taking the guide down.
    static func loadTopics(bundle: Bundle = .main) -> [HelpTopic] {
        topics.map { topic in
            var loaded = topic
            loaded.body = markdown(forResource: topic.resource, bundle: bundle)
                ?? "# \(topic.title)\n\nThis topic is not yet available."
            return loaded
        }
    }

    /// The raw Markdown for a resource, or `nil` if it is not bundled.
    ///
    /// Tries the `Help` subdirectory first, then the bundle root. This project's target uses
    /// synchronised folders, which **flatten** resources — `Resources/Help/welcome.md` is copied to
    /// `Contents/Resources/welcome.md`, not into a `Help` folder — so the second lookup is the one
    /// that actually succeeds today. The first is kept because it costs nothing and is what works if
    /// the resources are ever bundled as a folder reference instead.
    ///
    /// Because the bundle is flat, a help file's name must be unique across every resource in the
    /// app, not merely within `Resources/Help/`.
    static func markdown(forResource name: String, bundle: Bundle = .main) -> String? {
        let url = bundle.url(forResource: name, withExtension: "md", subdirectory: "Help")
            ?? bundle.url(forResource: name, withExtension: "md")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
    }
}

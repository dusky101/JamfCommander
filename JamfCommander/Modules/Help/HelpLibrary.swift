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
    ///
    /// The "Using the app" section holds **one topic per sidebar module**, in sidebar order, each
    /// carrying its `module` so the guide shows it in the same colour the app does.
    ///
    /// Keywords are the field authored for search: the words an administrator would actually type
    /// that the title does not contain. They are worth more than the body to `HelpSearch`, so a term
    /// belongs here when it is what the page is *about*, not merely something the page mentions.
    static let topics: [HelpTopic] = [

        // MARK: Getting started

        HelpTopic(
            id: "welcome",
            title: "Welcome to Jamf Commander",
            section: .gettingStarted,
            summary: "The app, the version, and how to use this guide.",
            keywords: ["overview", "introduction", "start", "getting started", "first time",
                       "what is", "about", "help", "guide", "search", "index", "unofficial",
                       "disclaimer", "production", "safety"]),

        HelpTopic(
            id: "prerequisites",
            title: "Prerequisites",
            section: .gettingStarted,
            summary: "What Installomator and Blueprints need that this app cannot provide.",
            keywords: ["prerequisite", "prerequisites", "requirement", "requirements", "before you",
                       "need", "needed", "installomator", "installomator.sh", "script", "label",
                       "ddm", "ddm explorer", "declarative", "declaration", "blueprint",
                       "blueprints", "app store", "download", "github", "install", "authoring"]),

        HelpTopic(
            id: "installomator-setup",
            title: "Before using Installomator",
            section: .gettingStarted,
            summary: "Add the Installomator script to Jamf, and label its parameters.",
            keywords: ["installomator", "script", "label", "parameter 4", "parameter4", "debug",
                       "notify", "silent", "github", "raw.githubusercontent.com", "prerequisite",
                       "setup", "overrides", "version pinning", "no labels"]),

        HelpTopic(
            id: "getting-connected",
            title: "Getting connected",
            section: .gettingStarted,
            summary: "The three things you need, and where to put them.",
            keywords: ["connect", "connection", "sign in", "login", "instance url", "client id",
                       "client secret", "oauth", "token", "bearer", "initialise", "initialize",
                       "settings", "auto-connect", "reconnect"]),

        HelpTopic(
            id: "apis",
            title: "Which APIs this app uses",
            section: .gettingStarted,
            summary: "Three Jamf APIs and one public file — what each is for, and what to grant.",
            keywords: ["api", "apis", "classic api", "pro api", "jssresource", "platform api",
                       "api gateway", "xml", "json", "rest", "endpoint", "github", "firewall",
                       "proxy", "allowlist", "outbound", "network", "security review"]),

        HelpTopic(
            id: "api-client",
            title: "Creating the API client in Jamf Pro",
            section: .gettingStarted,
            summary: "Make the API role and client that Jamf Commander signs in with.",
            keywords: ["api client", "api role", "api roles and clients", "new client",
                       "generate client secret", "access token lifetime", "enable", "jamf pro",
                       "setup", "set up", "create"]),

        HelpTopic(
            id: "blueprints-integration",
            title: "Creating the Blueprints integration",
            section: .gettingStarted,
            summary: "The separate credentials Blueprints needs, made in Jamf Account.",
            keywords: ["jamf account", "account.jamf.com", "integration", "integrations",
                       "platform api", "api gateway", "environment id", "scope level",
                       "platform environment", "capabilities", "capability", "region",
                       "region-locked", "us", "eu", "apac", "blueprints", "device-groups",
                       "six months", "expiry", "rotation", "test connection"]),

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

        // MARK: Using the app — one topic per sidebar module, in sidebar order

        HelpTopic(
            id: "dashboard",
            title: "Dashboard",
            section: .modules,
            summary: "Fleet totals, the category manager, and Export All.",
            keywords: ["dashboard", "home", "totals", "counts", "tiles", "overview", "categories",
                       "category manager", "new category", "rename", "export all", "zip",
                       "device status", "check-in", "email domain"],
            resource: "module-dashboard",
            module: .dashboard),

        HelpTopic(
            id: "policies",
            title: "Policies",
            section: .modules,
            summary: "Inspect, move, scope, clone and delete policies in bulk.",
            keywords: ["policy", "policies", "scope", "scoping", "all computers", "unscope",
                       "clone", "copy of", "move category", "self service category", "realign",
                       "disabled", "trigger", "frequency", "bulk", "shift-click"],
            resource: "module-policies",
            module: .policies),

        HelpTopic(
            id: "profiles",
            title: "Profiles",
            section: .modules,
            summary: "macOS configuration profiles — scope, category, clone, delete.",
            keywords: ["profile", "profiles", "configuration profile", "macos configuration",
                       "scoped", "unscoped", "not enabled", "mobileconfig", "payload", "clone",
                       "move category", "bulk"],
            resource: "module-profiles",
            module: .profiles),

        HelpTopic(
            id: "blueprints",
            title: "Blueprints",
            section: .modules,
            summary: "Declarative device management blueprints, from a different API.",
            keywords: ["blueprint", "blueprints", "ddm", "declarative", "declaration",
                       "extensible sso", "deploy", "undeploy", "deployment state", "json",
                       "device groups", "wrap", "component", "platform api", "not configured"],
            resource: "module-blueprints",
            module: .blueprints),

        HelpTopic(
            id: "computers",
            title: "Computers",
            section: .modules,
            summary: "The managed Mac fleet. Read-only.",
            keywords: ["computer", "computers", "mac", "macs", "fleet", "inventory", "serial",
                       "serial number", "filevault", "last contact", "managed", "unmanaged",
                       "user and location", "building", "department", "read-only", "csv"],
            resource: "module-computers",
            module: .computers),

        HelpTopic(
            id: "packages",
            title: "Packages",
            section: .modules,
            summary: "Jamf's package library, and uploading software yourself.",
            keywords: ["package", "packages", "pkg", "mpkg", "dmg", "zip", "upload", "drop",
                       "drag and drop", "package record", "install policy", "uploaded",
                       "deployed", "checking", "disk space", "duplicate name", "409",
                       "distribution point"],
            resource: "module-packages",
            module: .packages),

        HelpTopic(
            id: "scripts",
            title: "Scripts",
            section: .modules,
            summary: "List, inspect, recategorise and delete scripts.",
            keywords: ["script", "scripts", "parameters", "parameter 4", "source", "shell",
                       "uncategorised", "uncategorized", "none", "move category", "delete",
                       "no status", "no scope"],
            resource: "module-scripts",
            module: .scripts),

        HelpTopic(
            id: "installomator",
            title: "Installomator",
            section: .modules,
            summary: "Create and maintain Installomator install policies.",
            keywords: ["installomator", "label", "labels", "deployed", "missing", "withdrawn",
                       "possibly deployed", "explain this label", "self service", "icon",
                       "version pinning", "pin", "github", "labels.txt"],
            resource: "module-installomator",
            module: .installomator),

        HelpTopic(
            id: "unused",
            title: "Unused",
            section: .modules,
            summary: "An audit of policies, profiles and packages that look like they do nothing.",
            keywords: ["unused", "redundant", "audit", "housekeeping", "tidy", "clean up",
                       "cleanup", "disabled", "not enabled", "not scoped", "unscoped",
                       "not attached", "orphan", "orphaned", "unattached", "move to category",
                       "disable", "exclusions", "limitations"],
            resource: "module-unused",
            module: .redundant),

        // MARK: Reference

        HelpTopic(
            id: "troubleshooting",
            title: "If something fails",
            section: .reference,
            summary: "What the common refusals mean, and what to do about them.",
            keywords: ["error", "failed", "failure", "401", "403", "409", "415", "unauthorised",
                       "unauthorized", "forbidden", "duplicate", "expired", "refused",
                       "troubleshooting", "problem", "not working", "no labels", "slow", "hung"]),

        HelpTopic(
            id: "whats-coming",
            title: "What is coming",
            section: .reference,
            summary: "What this app cannot do yet, and what is intended next.",
            keywords: ["roadmap", "future", "planned", "coming", "not supported", "limitation",
                       "limitations", "mobile", "mobile devices", "ipad", "iphone", "ios",
                       "caching", "cache", "slow", "multiple environments", "multiple tenants",
                       "msp", "script usage", "pdf", "print"]),
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
    /// app, not merely within `Resources/Help/`. The per-module pages are named `module-…` for that
    /// reason: `packages.md` or `scripts.md` are exactly the names something else might claim.
    static func markdown(forResource name: String, bundle: Bundle = .main) -> String? {
        let url = bundle.url(forResource: name, withExtension: "md", subdirectory: "Help")
            ?? bundle.url(forResource: name, withExtension: "md")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
    }
}

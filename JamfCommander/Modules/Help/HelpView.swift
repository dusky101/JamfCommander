//
//  HelpView.swift
//  JamfCommander
//
//  In-app help: what the app needs from Jamf, how to set that up, and what each module does.
//
//  Reachable from the sidebar footer and from the standard macOS Help menu (⌘?). Deliberately a
//  single scrolling document rather than a nested help book — an administrator setting this up for
//  the first time wants to read it top to bottom once.
//

import SwiftUI
import Combine

/// Lets the Help menu open the sheet that `ContentView` owns.
final class HelpPresenter: ObservableObject {
    static let shared = HelpPresenter()
    private init() {}

    @Published var isPresented = false
}

struct HelpView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    gettingConnected
                    creatingTheAPIClient
                    privileges
                    installomatorPrerequisite
                    settingsFiles
                    modules
                    troubleshooting
                }
                .padding()
            }
        }
        .frame(minWidth: 640, idealWidth: 760, maxWidth: .infinity,
               minHeight: 560, idealHeight: 720, maxHeight: .infinity)
        .appBackground()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Jamf Commander Help")
                    .font(.headline)
                Text("Setting up Jamf access, and what each section does")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Done", action: onDismiss)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Getting connected

    private var gettingConnected: some View {
        InfoSection(title: "Getting connected", icon: "bolt.horizontal.circle") {
            paragraph("Jamf Commander signs in to your Jamf Pro tenant with OAuth client credentials — an API Client created in Jamf, not your own admin login. You need three things:")
            bullet("The Jamf instance URL, for example https://yourcompany.jamfcloud.com")
            bullet("A Client ID")
            bullet("A Client Secret")
            paragraph("Enter them under **Settings** in the sidebar, then choose **Initialise Connection**. Once saved, the app reconnects automatically each launch.")
            note("The bearer token is held in memory for the session only and is never written to disk.")
        }
    }

    // MARK: - Creating the API client

    private var creatingTheAPIClient: some View {
        InfoSection(title: "Creating the API client in Jamf", icon: "key.horizontal") {
            paragraph("In Jamf Pro, go to **Settings → System → API roles and clients**.")

            step(1, "On the **API Roles** tab, choose **New**. Give the role a name such as \"Jamf Commander\", then add the privileges listed in the next section and save.")
            step(2, "On the **API Clients** tab, choose **New**. Give the client a display name, assign the role you just created, and set an access token lifetime (30 minutes is ample).")
            step(3, "Save, then **Enable** the client.")
            step(4, "Choose **Generate client secret** and copy it immediately.")

            warning("The client secret is shown once. If you lose it you must generate a new one, which invalidates the old secret.")

            paragraph("Copy the Client ID from the same screen, and use your Jamf URL as the instance URL. Grant only the privileges you actually intend to use — the role is what Jamf enforces, so a narrower role is a real safeguard rather than a cosmetic one.")
        }
    }

    // MARK: - Privileges

    private var privileges: some View {
        InfoSection(title: "Privileges for full administrative use", icon: "checklist") {
            paragraph("These cover everything the app currently does. Reduce them to match the work you plan to do.")

            privilegeRow("Computers", "Read — fleet lists, inspectors and CSV export.")
            privilegeRow("Computer Groups", "Read — smart and static groups, used for deployment scope.")
            privilegeRow("Buildings, Departments", "Read — resolves IDs to names in User & Location and exports.")
            privilegeRow("Scripts", "Read — needed to list scripts, and required by the Packages module even if you never open the Scripts section.")
            privilegeRow("Categories", "Read, Create, Update, Delete — category management on the Dashboard, and creating a category from the deployment sheet.")
            privilegeRow("macOS Configuration Profiles", "Read, Update, Create, Delete — profile actions: move category, change scope, clone, delete.")
            privilegeRow("Policies", "Read, Update, Create, Delete — policy actions and Installomator deployment.")

            note("Attaching a Self Service icon to a policy needs **Update Policies**, not just Create Policies. With Create alone, policies are created successfully and every icon attach fails — the results sheet says so per policy.")
        }
    }

    // MARK: - Installomator

    private var installomatorPrerequisite: some View {
        InfoSection(title: "Before using Packages: add the Installomator script", icon: "shippingbox") {
            paragraph("The Packages section does not upload package files. It manages **Installomator install policies** — so your Jamf environment must already contain the Installomator script. Without it, the deployment sheet has nothing to select and no policies can be created.")

            step(1, "Download the current Installomator release from github.com/Installomator/Installomator.")
            step(2, "In Jamf Pro, go to **Settings → Computer management → Scripts** and choose **New**.")
            step(3, "Name it so that the name contains \"Installomator\" — the app pre-selects a script whose name matches, which saves choosing it every time.")
            step(4, "Paste the contents of Installomator.sh into the **Script** tab.")
            step(5, "On the **Options** tab, set the parameter labels so the values are readable later: parameter 4 \"Label\", 5 \"Option\", 6 \"Option\", and 7 to 11 \"Override\".")

            paragraph("When the app creates a policy it passes:")
            InfoRow(label: "Parameter 4", value: "the Installomator label, e.g. googlechrome")
            InfoRow(label: "Parameter 5", value: "DEBUG=0")
            InfoRow(label: "Parameter 6", value: "NOTIFY=silent")
            InfoRow(label: "Parameters 7–11", value: "optional version-pinning overrides")

            note("The script may be named anything you like. If it isn't called \"Installomator\", pick it once in the deployment sheet and the app remembers it — after that, policies using it are recognised as Installomator deployments.")

            paragraph("The Packages section also needs outbound access to **raw.githubusercontent.com**, which is where the upstream label list and the per-label explanations are read from. If GitHub is unreachable the section says so; nothing else in the app is affected.")
        }
    }

    // MARK: - Settings files

    private var settingsFiles: some View {
        InfoSection(title: "Exporting and importing settings", icon: "square.and.arrow.up.on.square") {
            paragraph("**Settings → Export** writes a `.jamfconfig` file so the same connection can be set up on another Mac without retyping it. **Import** reads one back in and fills the fields.")

            paragraph("A `.jamfconfig` file contains:")
            bullet("Jamf instance URL")
            bullet("Client ID")
            bullet("Client Secret")
            bullet("Export date, app version, and a file signature")

            warning("These files are Base64 encoded for light obfuscation — they are **not encrypted**. A `.jamfconfig` file is a secret: treat it exactly as you would the client secret itself, and only move it through channels you would trust with a password. Never email one, and never commit one to source control.")
        }
    }

    // MARK: - Modules

    private var modules: some View {
        InfoSection(title: "What each section does", icon: "square.grid.2x2") {
            moduleRow("Dashboard", "square.grid.2x2.fill",
                      "Fleet totals at a glance, category management (create, rename, delete), device check-ins grouped by email domain, and Export All, which writes every CSV into a single ZIP.")
            moduleRow("Policies", "scroll.fill",
                      "Every policy, grouped by category. Search by name or ID, filter by category, inspect one in detail, and act on a selection: move category, change scope, clone, or delete. Select several for bulk actions.")
            moduleRow("Profiles", "doc.text.fill",
                      "The same pattern for macOS configuration profiles — inspect, move category, change scope, clone, delete, and export.")
            moduleRow("Computers", "desktopcomputer",
                      "The managed Mac fleet. Search by name, serial, assigned user or email; sort any column; filter to managed devices; inspect hardware, OS, profiles and User & Location; export to CSV. Read-only.")
            moduleRow("Packages", "shippingbox.fill",
                      "The Installomator manager. Compares policies already deployed against the upstream label list, then creates Self Service install policies for the labels you select — with a category, script, icon, scope, and optional version pinning. \"Explain This Label\" on any row describes what that label will do on a Mac.")
            moduleRow("Scripts", "applescript.fill",
                      "Browse the scripts in your tenant and read their contents and parameters. Read-only.")
        }
    }

    // MARK: - Troubleshooting

    private var troubleshooting: some View {
        InfoSection(title: "If something fails", icon: "stethoscope") {
            InfoRow(label: "Refused (401)", value: "The session expired — reconnect from Settings.")
            InfoRow(label: "Not permitted (403)", value: "The API role is missing a privilege. Add it in Jamf and reconnect.")
            InfoRow(label: "Name already exists (409)", value: "Jamf requires unique policy names. Change the name template, or deselect that item.")
            InfoRow(label: "No labels in Packages", value: "GitHub could not be reached, or no Installomator script exists in Jamf.")
            note("Actions that change Jamf always ask for confirmation first and then report the real outcome for each item. If something failed, the results sheet says why — nothing is reported as successful unless Jamf confirmed it.")
        }
    }

    // MARK: - Building blocks

    private func paragraph(_ text: String) -> some View {
        Text(.init(text))
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.callout).foregroundColor(.secondary)
            Text(.init(text))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
                .frame(width: 18, alignment: .trailing)
            Text(.init(text))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
    }

    private func note(_ text: String) -> some View {
        Label {
            Text(.init(text))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func warning(_ text: String) -> some View {
        Label {
            Text(.init(text))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundColor(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func privilegeRow(_ object: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(object)
                .font(.callout)
                .fontWeight(.medium)
            Text(.init(detail))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func moduleRow(_ name: String, _ icon: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

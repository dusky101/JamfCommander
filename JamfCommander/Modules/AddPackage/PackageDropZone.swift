//
//  PackageDropZone.swift
//  JamfCommander
//
//  Where a package comes into the app: drop a file from the Finder, or choose one.
//
//  Both routes matter under App Sandbox — a drop and an open panel each grant read access to that one
//  file, which is all the upload needs. Nothing is read here: the zone validates the extension and
//  hands the URL up, so an unusable file is refused before any Jamf request is made.
//

import SwiftUI
import UniformTypeIdentifiers

struct PackageDropZone: View {
    /// What Jamf will accept as a package. Deliberately short: these are the formats a Jamf policy
    /// can install, and anything else would be refused by Jamf after the upload rather than before.
    static let allowedExtensions = ["pkg", "mpkg", "dmg", "zip"]

    var onPick: (URL) -> Void

    @State private var isTargeted = false
    @State private var rejection: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 44))
                .foregroundColor(isTargeted ? .accentColor : .secondary)

            VStack(spacing: 4) {
                Text("Drop a package here")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("PKG, MPKG, DMG or ZIP — the file is uploaded to Jamf as it is.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Choose File…") { chooseFile() }
                .buttonStyle(.borderedProminent)

            if let rejection {
                Label(rejection, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.gray.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
        )
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            accept(urls)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Package drop zone")
        .accessibilityHint("Drop a PKG, MPKG, DMG or ZIP file here, or use Choose File")
    }

    // MARK: - Picking

    /// Takes the first usable file from a drop. A multi-file drop is not an error — a package upload
    /// is one file at a time, so the rest are ignored and the zone says so.
    private func accept(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }

        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            rejection = "That doesn't look like a file on this Mac."
            return false
        }

        guard Self.allowedExtensions.contains(url.pathExtension.lowercased()) else {
            rejection = "'\(url.lastPathComponent)' isn't a package Jamf can install. Drop a PKG, MPKG, DMG or ZIP."
            return false
        }

        rejection = urls.count > 1
            ? "Several files were dropped — using '\(url.lastPathComponent)'. Upload the others one at a time."
            : nil
        onPick(url)
        return true
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose the package to upload to Jamf."
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        rejection = nil
        onPick(url)
    }
}

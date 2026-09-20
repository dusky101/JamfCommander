//
//  HelpExportButton.swift
//  JamfCommander
//
//  The guide's one export affordance: a toolbar button and the popover behind it.
//
//  A popover rather than two menu items, because there is a choice to make as well as an action to
//  take. The paper size decides whether the document prints without scaling at the other end, and the
//  person exporting is frequently not the person reading — a UK administrator sending the *Privileges*
//  page to a security team in the United States wants Letter whatever their own Mac is set to. A menu
//  would hide that behind a submenu nobody opens.
//
//  The choice is remembered, because it is a property of who you send documents to rather than of one
//  export.
//

import SwiftUI

struct HelpExportButton: View {
    /// Every topic, for the whole-guide export.
    let topics: [HelpTopic]
    /// The page currently open, for the single-page export. `nil` disables that button.
    let selectedTopic: HelpTopic?

    @AppStorage("helpPDFPaper") private var storedPaper = HelpPDFPaper.system.rawValue
    @State private var isPresented = false
    @State private var isExporting = false

    private var paper: HelpPDFPaper {
        HelpPDFPaper(rawValue: storedPaper) ?? .system
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Export as PDF", systemImage: "square.and.arrow.up")
        }
        .help("Save this page, or the whole guide, as a PDF")
        .disabled(topics.isEmpty)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popover
        }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export as PDF")
                .font(.headline)

            Picker("Paper", selection: $storedPaper) {
                ForEach(HelpPDFPaper.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("The guide's pages are black on white whatever the app is set to. Figures keep the app's own appearance, so they look like what you see on screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            if isExporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing the document…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    Button("This page") {
                        guard let selectedTopic else { return }
                        export(topics: [selectedTopic], subject: selectedTopic.title)
                    }
                    .disabled(selectedTopic == nil)

                    Button("The whole guide") {
                        export(topics: topics, subject: "Guide")
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    /// Compose, then save.
    ///
    /// `ImageRenderer` is main-actor work and cannot be moved off it, so the whole guide — twenty
    /// topics and fourteen figures — is a second or two during which the window cannot redraw. The
    /// yield is what lets the spinner appear *before* that starts rather than after it finishes.
    private func export(topics: [HelpTopic], subject: String) {
        isExporting = true
        Task {
            await Task.yield()
            let name = HelpPDFExportService.defaultFileName(for: subject)
            _ = HelpPDFExportService.export(topics: topics, defaultName: name, paper: paper)
            isExporting = false
            isPresented = false
        }
    }
}

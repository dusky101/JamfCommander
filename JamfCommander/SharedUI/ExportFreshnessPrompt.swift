//
//  ExportFreshnessPrompt.swift
//  JamfCommander
//
//  Asked before Export All, when the export would be built from data this session already holds.
//
//  Everything else the cache touches is on screen, where a "Read … ago" label sits beside a Refresh
//  button and the reader can judge for themselves. A CSV is not: it leaves the app, gets circulated,
//  and carries no stamp saying when its contents were true. So the one place the app cannot show
//  staleness afterwards is the one place it asks beforehand.
//
//  Two answers, no third. Cancelling the whole export is what the Escape key and the window's own
//  dismissal already do, and a third button would make the common answer harder to find.
//

import SwiftUI

struct ExportFreshnessPrompt: View {
    /// When the oldest of the reads behind this export was taken.
    let readAt: Date

    /// Export now, from what is already held.
    let onUseCurrent: () -> Void

    /// Read everything again first. The closure does the reading; this view shows that it is
    /// happening and calls it before handing back.
    let onRefreshThenExport: () async -> Void

    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: isRefreshing ? "arrow.trianglehead.2.clockwise.rotate.90" : "clock.arrow.circlepath")
                .font(.system(size: 34))
                .foregroundColor(.blue)
                .symbolEffect(.pulse, options: .repeating, isActive: isRefreshing)

            if isRefreshing {
                refreshingState
            } else {
                questionState
            }
        }
        .padding(28)
        .frame(width: 420)
        .animation(.easeInOut(duration: 0.2), value: isRefreshing)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Asking

    private var questionState: some View {
        VStack(spacing: 16) {
            Text("Refresh before exporting?")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(spacing: 6) {
                Text("This export would be built from data read \(readAt, style: .relative) ago.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("A CSV keeps no record of when it was true, so anyone you send it to cannot tell. Refreshing reads the whole instance again and takes a while on a large tenant.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("No, Use Current Data") {
                    onUseCurrent()
                }
                .keyboardShortcut(.cancelAction)

                Button("Yes, Refresh First") {
                    isRefreshing = true
                    Task { await onRefreshThenExport() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Refreshing

    private var refreshingState: some View {
        VStack(spacing: 14) {
            Text("Refreshing data…")
                .font(.title3)
                .fontWeight(.semibold)

            ProgressView()
                .progressViewStyle(.linear)
                .frame(width: 220)

            Text("Reading every policy, profile and package. The export starts on its own when this finishes.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Refreshing data from Jamf. The export will start when it finishes.")
    }
}

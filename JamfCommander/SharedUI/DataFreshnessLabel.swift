//
//  DataFreshnessLabel.swift
//  JamfCommander
//
//  When what is on screen was read from Jamf.
//
//  A cached list is indistinguishable from a freshly read one, and that is exactly how somebody
//  deletes a policy that was already gone, or misses one that was added. This label is the thing
//  that tells the two apart, so it belongs on every screen that can be serving a cached read —
//  beside the Refresh button that replaces it, so the answer to "is this still true?" and the way
//  to find out sit together.
//
//  The time is relative and live: SwiftUI keeps a `.relative` date running, so a window left open
//  over lunch says so without anything having to poll. The absolute time is in the tooltip, for
//  when "2 hrs ago" is not precise enough to act on.
//

import SwiftUI

struct DataFreshnessLabel: View {
    /// When the data this screen is showing was read from Jamf.
    let readAt: Date

    private var absolute: String {
        readAt.formatted(date: .abbreviated, time: .standard)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption2)
            // Deliberately not "Updated": nothing was updated. This says when the app last asked
            // Jamf, which is a different claim and the only one it can honestly make — the tenant
            // may have been changed in the Jamf console since.
            Text("Read \(readAt, style: .relative) ago")
                .font(.caption)
                .monospacedDigit()
        }
        .foregroundColor(.secondary)
        .lineLimit(1)
        .fixedSize()
        .help("Read from Jamf at \(absolute). Refresh to read it again.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Data read from Jamf at \(absolute)")
    }
}

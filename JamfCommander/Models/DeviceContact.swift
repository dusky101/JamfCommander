//
//  DeviceContact.swift
//  JamfCommander
//
//  How recently a Mac last spoke to Jamf, and what that means.
//
//  The Dashboard's Device Status section used to assert that every computer was "Active" — a green
//  badge drawn unconditionally, over a list that was an arbitrary twenty records in whatever order
//  the API returned, under a heading that said "Recent Check-ins". Nothing in it consulted a date.
//  A Mac last seen in June sat at the bottom of the list marked Active.
//
//  This is the arithmetic that replaces it, kept apart from the view for the same reason
//  `HelpRhythm` is: it can be reasoned about, and argued with, without reading any layout.
//
//  Pure and nonisolated.
//

import SwiftUI

/// How long ago a Mac last contacted Jamf, bucketed.
///
/// Three states that tile the whole range, so no machine falls through a gap between them.
nonisolated enum DeviceContactState: String, CaseIterable, Identifiable, Sendable {
    /// Not seen for longer than `staleAfter`, or never seen at all. **The work queue.**
    case notSeen
    /// Seen within `liveWithin` — checking in right now.
    case live
    /// Seen at any point since `staleAfter`. **Includes `live`**, which is the point of it: a
    /// question about what is healthy should not exclude what is healthiest.
    case recent

    var id: String { rawValue }

    // MARK: - The two thresholds

    /// A Mac is "live" if it has been heard from within this. Jamf's default check-in is every 15
    /// minutes, so two hours is several missed check-ins — long enough not to flicker, short enough
    /// to mean "on and talking".
    static let liveWithin: TimeInterval = 2 * 60 * 60

    /// Beyond this, a Mac counts as not seen.
    ///
    /// **Seventeen days, not thirty, and not fourteen.** Two weeks is a normal holiday, and a fleet
    /// list that puts everybody returning from leave at the top of a problem queue trains its reader
    /// to ignore it. Three days of slack past a fortnight covers the leave plus the weekend either
    /// side of it, and anything past that is a machine worth asking about.
    static let staleAfter: TimeInterval = 17 * 24 * 60 * 60

    /// Which state a given age falls into. `nil` — never contacted — is the worst case, not a gap.
    static func state(forAge age: TimeInterval?) -> DeviceContactState {
        guard let age else { return .notSeen }
        if age <= liveWithin { return .live }
        return age <= staleAfter ? .recent : .notSeen
    }

    /// Whether a machine in `state` belongs in this selection. `recent` admits `live` as well.
    func includes(_ state: DeviceContactState) -> Bool {
        switch self {
        case .notSeen: return state == .notSeen
        case .live: return state == .live
        case .recent: return state == .live || state == .recent
        }
    }

    // MARK: - How it presents

    /// The word on the control and on the group header.
    var title: String {
        switch self {
        case .notSeen: return "Not seen"
        case .live: return "Live"
        case .recent: return "Recent"
        }
    }

    /// What the selection means, said once above the list rather than guessed at.
    var explanation: String {
        switch self {
        case .notSeen: return "Not heard from in over 17 days, or never."
        case .live: return "Heard from in the last 2 hours."
        case .recent: return "Heard from at some point in the last 17 days, including right now."
        }
    }

    var symbol: String {
        switch self {
        case .notSeen: return "exclamationmark.triangle.fill"
        case .live: return "dot.radiowaves.left.and.right"
        case .recent: return "clock"
        }
    }

    /// Paired with `symbol` and `title` everywhere it is drawn — never colour alone.
    var colour: Color {
        switch self {
        case .notSeen: return .orange
        case .live: return .green
        case .recent: return .blue
        }
    }

    /// Whether the most stale machine belongs at the top.
    ///
    /// For `notSeen` it does: the list is a queue of things to chase, and the worst one is the one to
    /// start with. For the other two the newest contact is the most interesting.
    var sortsOldestFirst: Bool { self == .notSeen }
}

// MARK: - Reading Jamf's timestamp

nonisolated enum DeviceContactClock {

    /// Parse Jamf's `lastContactTime`. Returns `nil` for a machine that has never checked in, which
    /// Jamf reports as a missing or empty value.
    ///
    /// Two formatters because Jamf is not consistent about fractional seconds between endpoints and
    /// versions, and a timestamp that fails to parse would otherwise promote a healthy Mac into the
    /// problem list.
    static func date(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    /// How long ago that was, or `nil` when it never happened.
    ///
    /// A timestamp in the future — a Mac whose clock is ahead, which does happen — is treated as
    /// zero rather than as a negative age, so it reads as live instead of sorting to the far end.
    static func age(since raw: String?, now: Date = Date()) -> TimeInterval? {
        guard let date = date(from: raw) else { return nil }
        return max(now.timeIntervalSince(date), 0)
    }

    /// The age in words, for the row: "14 minutes ago", "3 days ago", "Never".
    static func relativeDescription(since raw: String?, now: Date = Date()) -> String {
        guard let date = date(from: raw) else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    /// The date itself, for a machine that is not coming back on its own and where the actual day
    /// matters more than how long ago it was.
    static func absoluteDescription(since raw: String?) -> String {
        guard let date = date(from: raw) else { return "Never" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - How many rows to draw

/// The row limit, offered the way Jamf Pro offers it.
///
/// A cap has to exist — the Dashboard draws this inside a `ScrollView`, and an unbounded list on a
/// several-thousand-Mac estate would build every row. Before this it was a hard-coded twenty, taken
/// off an unsorted list, which is the worst of both: a limit nobody chose, hiding records nobody
/// knew were missing.
nonisolated enum DeviceListLimit: Int, CaseIterable, Identifiable, Sendable {
    case ten = 10
    case fifty = 50
    case hundred = 100
    case twoHundred = 200

    var id: Int { rawValue }
    var title: String { "\(rawValue)" }
}

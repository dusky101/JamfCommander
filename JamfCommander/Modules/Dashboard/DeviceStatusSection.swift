//
//  DeviceStatusSection.swift
//  JamfCommander
//
//  The Dashboard's fleet contact section: which Macs Jamf has heard from, and which it has not.
//
//  It replaces a section that claimed more than it knew. That one drew a green "Active" badge on
//  every row unconditionally, over the first twenty records in whatever order the API returned,
//  under a heading reading "Recent Check-ins" — with no date anywhere in the record it was given. A
//  Mac last seen three months earlier appeared in the list marked Active. The rule in `CLAUDE.md`
//  about never reporting a success the API did not confirm applies just as much to a state as to a
//  write.
//
//  Everything here is derived from `lastContactTime`, which Jamf already returns in the section the
//  Dashboard already fetches. See `DeviceContact` for the two thresholds and why they are what they
//  are.
//
//  The four controls are remembered between launches, so the view somebody wants is the view they
//  get. They are the reason this is a file of its own rather than more of `DashboardView`.
//

import SwiftUI

struct DeviceStatusSection: View {
    let computers: [BasicComputerRecord]

    /// Which machines to list. Opens on **Not seen**: a fleet list earns its place by showing what
    /// needs attention, and the healthy majority is one click away.
    @AppStorage("deviceStatusSelection") private var storedSelection = DeviceContactState.notSeen.rawValue
    @AppStorage("deviceStatusGroupByDomain") private var groupByDomain = false
    @AppStorage("deviceStatusLimit") private var storedLimit = DeviceListLimit.fifty.rawValue

    @State private var collapsedDomains: Set<String> = []

    private var selection: DeviceContactState {
        DeviceContactState(rawValue: storedSelection) ?? .notSeen
    }

    private var limit: DeviceListLimit {
        DeviceListLimit(rawValue: storedLimit) ?? .fifty
    }

    // MARK: - What to show

    /// Everything in the chosen state, worst or newest first depending on which state that is.
    ///
    /// Sorted before it is capped, which is the whole difference from what this replaced: a limit
    /// applied to an unordered list hides an arbitrary set of machines, while a limit applied to a
    /// sorted one hides the least interesting.
    private var matching: [BasicComputerRecord] {
        let inState = computers.filter { selection.includes($0.contactState) }
        return inState.sorted { first, second in
            // Never contacted is the most stale thing there is, so it sorts as an infinite age.
            let firstAge = first.contactAge ?? .greatestFiniteMagnitude
            let secondAge = second.contactAge ?? .greatestFiniteMagnitude
            if firstAge == secondAge { return first.name < second.name }
            return selection.sortsOldestFirst ? firstAge > secondAge : firstAge < secondAge
        }
    }

    private var listed: [BasicComputerRecord] { Array(matching.prefix(limit.rawValue)) }

    /// The listed machines grouped by email domain, in a stable, case-insensitive order.
    ///
    /// Case-insensitive because `sorted()` on the raw strings put "No Email Domain" above every real
    /// domain — a capital N sorts before a lowercase m — so the bin of machines with no user at all
    /// led the section. It now sorts as an N, among the names, and the real domains lead.
    private var domainGroups: [(domain: String, computers: [BasicComputerRecord])] {
        Dictionary(grouping: listed, by: \.emailDomain)
            .map { (domain: $0.key, computers: $0.value) }
            .sorted { $0.domain.localizedCaseInsensitiveCompare($1.domain) == .orderedAscending }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            controls
            if computers.isEmpty {
                message("No computers found.")
            } else if listed.isEmpty {
                message("No computers \(selection.title.lowercased()).")
            } else if groupByDomain {
                VStack(spacing: 12) {
                    ForEach(domainGroups, id: \.domain) { group in
                        domainSection(group.domain, group.computers)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(listed) { computer in
                        DeviceContactRow(computer: computer, selection: selection)
                    }
                }
            }
            footnote
        }
    }

    private var header: some View {
        HStack {
            Label("Device Status", systemImage: "antenna.radiowaves.left.and.right")
                .font(.title2).fontWeight(.bold)
            Spacer()
            Text(selection.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The three-way chooser, the domain toggle and the row count.
    ///
    /// A `Picker` rather than a menu for the state, because there are three of them and which one is
    /// selected is the single most important thing about this section — a menu would hide it behind
    /// a click.
    private var controls: some View {
        HStack(spacing: 14) {
            Picker("Show", selection: $storedSelection) {
                ForEach(DeviceContactState.allCases) { state in
                    Label(state.title, systemImage: state.symbol).tag(state.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .accessibilityLabel("Which computers to show")

            Toggle("Group by email domain", isOn: $groupByDomain)
                .toggleStyle(.checkbox)
                .font(.callout)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text("Show")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("Rows", selection: $storedLimit) {
                    ForEach(DeviceListLimit.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
                .accessibilityLabel("How many computers to show")
            }
        }
    }

    /// Says what is on screen against what matched, so a capped list never passes for the whole set.
    @ViewBuilder
    private var footnote: some View {
        if !matching.isEmpty {
            Text(matching.count > listed.count
                 ? "Showing \(listed.count) of \(matching.count) computers \(selection.title.lowercased())."
                 : "\(matching.count) computer\(matching.count == 1 ? "" : "s") \(selection.title.lowercased()).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
    }

    /// One email domain, collapsible. Open by default — the reader asked to group, not to hide.
    private func domainSection(_ domain: String, _ computers: [BasicComputerRecord]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    if collapsedDomains.contains(domain) {
                        collapsedDomains.remove(domain)
                    } else {
                        collapsedDomains.insert(domain)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(.blue)
                    Text(domain)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(computers.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(collapsedDomains.contains(domain) ? 0 : 90))
                }
                .padding(12)
                .background(Color.blue.opacity(0.05), in: .rect(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .accessibilityLabel("\(domain), \(computers.count) computers")

            if !collapsedDomains.contains(domain) {
                VStack(spacing: 8) {
                    ForEach(computers) { computer in
                        DeviceContactRow(computer: computer, selection: selection)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - A row

/// One Mac: what it is called, who has it, and when Jamf last heard from it.
private struct DeviceContactRow: View {
    let computer: BasicComputerRecord
    let selection: DeviceContactState

    private var state: DeviceContactState { computer.contactState }

    /// Relative for a machine that is fine, absolute for one that is not.
    ///
    /// "Three weeks ago" is the right answer to "is this healthy"; once it plainly is not, the
    /// question becomes *when did it stop*, and for that the actual date is what somebody needs to
    /// match against a leaver's date or a hardware refresh.
    private var contactDescription: String {
        state == .notSeen
            ? DeviceContactClock.absoluteDescription(since: computer.lastContactTime)
            : DeviceContactClock.relativeDescription(since: computer.lastContactTime)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(.secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(computer.name)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                if let email = computer.email, !email.isEmpty {
                    Label(email, systemImage: "envelope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let username = computer.username, !username.isEmpty {
                    Label(username, systemImage: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Text(contactDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            badge
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(computer.name), \(state.title), last seen \(contactDescription)")
    }

    /// The state this machine is actually in — which is not always the state that was asked for,
    /// since **Recent** lists live machines too and they should still read as live.
    private var badge: some View {
        HStack(spacing: 4) {
            Image(systemName: state.symbol)
            Text(state.title)
        }
        .font(.caption2)
        .fontWeight(.bold)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(state.colour)
        .background(state.colour.opacity(0.1), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(state.colour.opacity(0.3), lineWidth: 1)
        )
    }
}

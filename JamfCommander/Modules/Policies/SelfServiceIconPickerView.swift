//
//  SelfServiceIconPickerView.swift
//  JamfCommander
//
//  "Reuse an existing icon" picker. Search policies by name or id (the same search the
//  dashboards use), fetch the Self Service icons from the matching policies, de-duplicate
//  them by icon id, and present them in a grid to pick from. Images are cached on disk by
//  icon id (icons are immutable by id, so the cache never goes stale).
//
//  Picking an icon hands a `SelfServiceIcon` back to the editor, which stages it and
//  attaches it to the policy on the confirmed Save.
//

import SwiftUI

/// A distinct icon discovered across one or more policies.
struct DiscoveredIcon: Identifiable, Hashable {
    let iconId: Int
    let icon: SelfServiceIcon
    var policyNames: [String]
    var id: Int { iconId }
}

struct SelfServiceIconPickerView: View {
    @ObservedObject var api: JamfAPIService
    var onPick: (SelfServiceIcon) -> Void
    var onCancel: () -> Void

    @State private var searchText = ""
    @State private var policyList: [PolicyListItem] = []
    @State private var isLoadingList = true
    @State private var listError = false

    @State private var isSearching = false
    @State private var searchedTerm = ""
    @State private var discovered: [DiscoveredIcon] = []
    @State private var truncatedNote: String?

    /// Cap how many matching policies we hydrate, to respect rate limits.
    private let matchCap = 50

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            content
        }
        .frame(width: 660, height: 580)
        .appBackground()
        .task { await loadPolicyList() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose an Icon")
                    .font(.headline)
                Text("Search policies to reuse an icon already in Jamf")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search policies by name or id (e.g. Adobe)", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit { runSearch() }
                .accessibilityLabel("Search policies")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button("Search") { runSearch() }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingList || isSearching || searchText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoadingList {
            stateView(icon: "hourglass", title: "Loading policies…", showsProgress: true)
        } else if listError {
            stateView(icon: "exclamationmark.triangle", title: "Couldn't load the policy list.", subtitle: "Check your connection and try again.")
        } else if isSearching {
            stateView(icon: "hourglass", title: "Searching for icons…", showsProgress: true)
        } else if searchedTerm.isEmpty {
            stateView(icon: "magnifyingglass", title: "Search to find icons", subtitle: "Type a policy name or id (for example “Adobe”) and press Search.")
        } else if discovered.isEmpty {
            stateView(icon: "photo.on.rectangle.angled", title: "No icons found", subtitle: "No policies matching “\(searchedTerm)” have a Self Service icon.")
        } else {
            ScrollView {
                if let truncatedNote {
                    Text(truncatedNote)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .top])
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(discovered) { item in
                        IconPickerCell(item: item, api: api) { onPick(item.icon) }
                    }
                }
                .padding()
            }
        }
    }

    private func stateView(icon: String, title: String, subtitle: String? = nil, showsProgress: Bool = false) -> some View {
        VStack(spacing: 12) {
            if showsProgress {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: icon)
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
            }
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Logic

    private func loadPolicyList() async {
        isLoadingList = true
        listError = false
        do {
            let list = try await api.fetchPolicyList()
            policyList = list
            isLoadingList = false
        } catch {
            listError = true
            isLoadingList = false
        }
    }

    private func runSearch() {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !isLoadingList else { return }

        isSearching = true
        truncatedNote = nil

        Task {
            let matches = policyList.filter {
                $0.name.localizedCaseInsensitiveContains(term) || String($0.id).contains(term)
            }
            let capped = Array(matches.prefix(matchCap))
            let hits = await api.fetchSelfServiceIcons(forPolicyIDs: capped.map(\.id))

            // De-duplicate by icon id, collecting the policy names that use each icon.
            var byIcon: [Int: DiscoveredIcon] = [:]
            for hit in hits {
                guard let iconId = hit.icon.id else { continue }
                if var existing = byIcon[iconId] {
                    existing.policyNames.append(hit.policyName)
                    byIcon[iconId] = existing
                } else {
                    byIcon[iconId] = DiscoveredIcon(iconId: iconId, icon: hit.icon, policyNames: [hit.policyName])
                }
            }
            let result = byIcon.values.sorted {
                ($0.policyNames.first ?? "").localizedCaseInsensitiveCompare($1.policyNames.first ?? "") == .orderedAscending
            }

            await MainActor.run {
                discovered = result
                searchedTerm = term
                if matches.count > matchCap {
                    truncatedNote = "Searched the first \(matchCap) of \(matches.count) matching policies. Refine your search to cover the rest."
                }
                isSearching = false
            }
        }
    }
}

// MARK: - Grid cell

private struct IconPickerCell: View {
    let item: DiscoveredIcon
    @ObservedObject var api: JamfAPIService
    var onPick: () -> Void

    @State private var image: NSImage?

    var body: some View {
        Button(action: onPick) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 72, height: 72)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(item.icon.filename ?? "Icon \(item.iconId)")
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("ID \(item.iconId)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
            }
            .frame(width: 104)
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Used by: \(item.policyNames.joined(separator: ", "))")
        .task(id: item.iconId) {
            image = await IconImageCache.shared.loadImage(id: item.iconId, using: api)
        }
    }
}

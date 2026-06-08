//
//  IconBrowserView.swift
//  JamfCommander
//
//  A paginated, icons-only browser for reusing a Self Service icon — modelled on the Jamf Pro
//  "Choose Image" picker. Icons are laid out in fixed pages; the ‹ / › buttons move between pages
//  with a horizontal slide (the next page slides in from the right while the current slides out to
//  the left, and the reverse on Back). Selection is two-step: tap an icon to highlight it, then
//  "Make Selection" to confirm (a double-click confirms directly). Cells show only the icon — the
//  policies that use it appear in the tooltip, not on the cell.
//
//  The icon set is supplied by the caller (the "Show all" scan in SelfServiceIconPickerView); this
//  view does no fetching of its own beyond lazily loading each icon's image via IconImageCache.
//

import SwiftUI
import AppKit

struct IconBrowserView: View {
    @ObservedObject var api: JamfAPIService
    let icons: [DiscoveredIcon]
    var onPick: (SelfServiceIcon) -> Void
    var onCancel: () -> Void

    @State private var page = 0
    /// The edge the incoming page enters from: trailing for Next, leading for Back.
    @State private var slideFromTrailing = true
    @State private var selected: DiscoveredIcon?

    private let columnCount = 8
    private let rowCount = 5
    private var pageSize: Int { columnCount * rowCount }

    private var pages: [[DiscoveredIcon]] {
        guard !icons.isEmpty else { return [] }
        return stride(from: 0, to: icons.count, by: pageSize).map {
            Array(icons[$0..<min($0 + pageSize, icons.count)])
        }
    }

    private var pageCount: Int { max(pages.count, 1) }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: slideFromTrailing ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: slideFromTrailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pagedGrid
            Divider()
            footer
        }
        .frame(width: 680, height: 600)
        .appBackground()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose an Icon")
                    .font(.headline)
                Text("\(icons.count) icon\(icons.count == 1 ? "" : "s") in use across your policies")
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

    // MARK: - Paged grid

    @ViewBuilder
    private var pagedGrid: some View {
        if pages.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No icons found")
                    .font(.headline)
                Text("None of your policies have a Self Service icon yet.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ZStack {
                gridPage(pages[min(page, pages.count - 1)])
                    .id(page)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding()
        }
    }

    private func gridPage(_ items: [DiscoveredIcon]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 14) {
            ForEach(items) { item in
                BrowserIconCell(
                    item: item,
                    api: api,
                    isSelected: selected?.iconId == item.iconId,
                    onSelect: { selected = item },
                    onConfirm: { onPick(item.icon) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            Button("Cancel", action: onCancel)

            Spacer()

            HStack(spacing: 12) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                }
                .disabled(page == 0)
                .accessibilityLabel("Previous page")
                .help("Previous icons")

                Text("Page \(page + 1) of \(pageCount)")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 120)

                Button(action: next) {
                    Image(systemName: "chevron.right")
                }
                .disabled(page >= pageCount - 1)
                .accessibilityLabel("Next page")
                .help("More icons")
            }

            Spacer()

            Button("Make Selection") {
                if let selected { onPick(selected.icon) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Paging

    private func next() {
        guard page < pageCount - 1 else { return }
        slideFromTrailing = true
        withAnimation(.easeInOut(duration: 0.28)) { page += 1 }
    }

    private func back() {
        guard page > 0 else { return }
        slideFromTrailing = false
        withAnimation(.easeInOut(duration: 0.28)) { page -= 1 }
    }
}

// MARK: - Icon cell (icon only)

private struct BrowserIconCell: View {
    let item: DiscoveredIcon
    @ObservedObject var api: JamfAPIService
    let isSelected: Bool
    var onSelect: () -> Void
    var onConfirm: () -> Void

    @State private var image: NSImage?

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isSelected ? 1 : 0.6))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 64, height: 64)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2),
                            lineWidth: isSelected ? 3 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .help(item.policyNames.isEmpty ? "Icon \(item.iconId)" : "Used by: \(item.policyNames.joined(separator: ", "))")
        .simultaneousGesture(TapGesture(count: 2).onEnded { onConfirm() })
        .task(id: item.iconId) {
            image = await IconImageCache.shared.loadImage(id: item.iconId, using: api)
        }
    }
}

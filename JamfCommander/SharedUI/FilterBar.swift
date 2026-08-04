//
//  FilterBar.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI
import AppKit // Needed for NSEvent (Command-click logic)

struct FilterBar: View {
    @Binding var searchText: String
    var categories: [Category]
    @Binding var selectedCategory: Category?
    
    // Data Sources: Pass one or the other (or both) to populate counts
    var profiles: [ConfigProfile] = []
    var policies: [Policy] = [] // Added for Policy Dashboard support
    
    var onRefresh: (() -> Void)?
    var onExport: (() -> Void)? // Optional export action

    /// Remembered across launches and shared by every dashboard that uses this bar.
    @AppStorage("filterBarCategoriesExpanded") private var isCategoriesExpanded = true

    /// Roughly four rows of chips. Past that the chip area scrolls rather than growing.
    private let maxChipAreaHeight: CGFloat = 132

    /// How many items a category holds, across whichever data source was supplied.
    private func itemCount(for category: Category) -> Int {
        let profileCount = profiles.filter { $0.categoryName == category.name }.count
        let policyCount = policies.filter { ($0.categoryName ?? "No Category") == category.name }.count
        return profileCount + policyCount
    }

    /// Categories that actually have something in them — the number shown next to the disclosure.
    private var visibleCategoryCount: Int {
        categories.filter { itemCount(for: $0) > 0 }.count
    }

    var body: some View {
        VStack(spacing: 12) {
            // --- ROW 1: Search Field ---
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search names, IDs, or scopes...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                
                // Export Button
                if let onExport = onExport {
                    Button(action: onExport) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Export to CSV")
                }
                
                // Refresh Button
                if let onRefresh = onRefresh {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .frame(height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Data")
                }
            }
            
            // --- ROW 2: Filter Chips (collapsible, and height-capped) ---
            //
            // A tenant with thirty categories wants far more rows than the pane can spare. The
            // chips therefore live behind a disclosure and inside a fixed-height scroll area, so
            // this bar's height is bounded no matter how many categories exist — it can never grow
            // the pane (or the window) out from under the controls above it.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { isCategoriesExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .rotationEffect(.degrees(isCategoriesExpanded ? 90 : 0))
                            Text("Categories")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("\(visibleCategoryCount)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCategoriesExpanded ? "Hide category filters" : "Show category filters")

                    // Collapsing must not hide *which* filter is active.
                    if !isCategoriesExpanded {
                        if let selectedCategory {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.fill").font(.caption2)
                                Text(selectedCategory.name).font(.caption)
                                Button {
                                    withAnimation { self.selectedCategory = nil }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear category filter")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(12)
                        } else {
                            Text("All categories")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }

                if isCategoriesExpanded {
                    ScrollView(.vertical) {
                        FlowLayout(spacing: 8) {
                            // "All" Chip
                            FilterChip(
                                title: "All Categories",
                                icon: "square.grid.2x2",
                                color: .blue,
                                isSelected: selectedCategory == nil,
                                count: profiles.count + policies.count // Sum of all items
                            ) {
                                withAnimation { selectedCategory = nil }
                            }

                            // Category Chips
                            ForEach(categories) { category in
                                // Calculate count dynamically based on what data is present
                                let count = itemCount(for: category)

                                // Only show categories that have items (Clean up the view)
                                if count > 0 {
                                    FilterChip(
                                        title: category.name,
                                        icon: "folder",
                                        color: .blue,
                                        isSelected: selectedCategory?.id == category.id,
                                        count: count
                                    ) {
                                        // Command-Click Logic (Select purely this one)
                                        if NSEvent.modifierFlags.contains(.command) {
                                            withAnimation { selectedCategory = category }
                                        } else {
                                            // Toggle Logic
                                            withAnimation {
                                                if selectedCategory?.id == category.id {
                                                    selectedCategory = nil
                                                } else {
                                                    selectedCategory = category
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: maxChipAreaHeight)
                }
            }
        }
        .padding()
        .overlay(
            Divider().opacity(0.5),
            alignment: .bottom
        )
    }
}

// MARK: - Subviews

struct FilterChip: View {
    let title: String
    let icon: String
    
    // Optional override for the selected icon.
    var selectedIcon: String? = nil
    
    let color: Color
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Logic: If selected, use selectedIcon. If that's nil, try icon + ".fill".
                Image(systemName: isSelected ? (selectedIcon ?? icon + ".fill") : icon)
                    .font(.caption)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .lineLimit(1)
                
                // Count Badge
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? color : Color.gray.opacity(0.5))
                    .cornerRadius(8)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? color.opacity(0.15) : Color(nsColor: .controlBackgroundColor).opacity(0.5)
            )
            .foregroundColor(isSelected ? color : .secondary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? color.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout Helper
struct FlowLayout: Layout {
    var spacing: CGFloat
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // An unspecified width must NOT go through `replacingUnspecifiedDimensions()`: its default
        // replacement is 10 × 10, so every chip would be wider than the line and wrap onto a row of
        // its own. With ~30 categories that reports a height of several hundred points, the filter
        // bar claims more room than the window has, and the whole pane is pushed up under the
        // title bar. Measure on a single line instead, which is what "ideal size" should mean here.
        let maxWidth = proposal.width ?? .infinity
        let result = flow(in: maxWidth, subviews: subviews, spacing: spacing)
        return CGSize(width: proposal.width ?? result.contentWidth, height: result.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Lay out against the width we were actually given. Re-flowing against the *proposal* let
        // placement disagree with the measured size, so rows could be positioned outside the bounds.
        let result = flow(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, row) in result.rows.enumerated() {
            let rowWidth = row.map { $0.size.width }.reduce(0, +) + CGFloat(row.count - 1) * spacing
            let xOffset = alignment == .leading ? 0 : (bounds.width - rowWidth) / 2
            var currentX = bounds.minX + xOffset
            let y = bounds.minY + result.rowYs[index]
            for item in row {
                subviews[item.index].place(at: CGPoint(x: currentX, y: y), proposal: ProposedViewSize(item.size))
                currentX += item.size.width + spacing
            }
        }
    }
    
    private struct LayoutResult {
        var rows: [[(index: Int, size: CGSize)]] = []
        var rowYs: [CGFloat] = []
        var size: CGSize = .zero
        /// The width actually used by the widest row — needed when the proposal is unspecified,
        /// where reporting the (infinite) proposed width would be meaningless.
        var contentWidth: CGFloat = 0
    }

    private func flow(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) -> LayoutResult {
        var result = LayoutResult()
        var currentRow: [(index: Int, size: CGSize)] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        func closeRow() {
            guard !currentRow.isEmpty else { return }
            let rowWidth = currentRow.map(\.size.width).reduce(0, +)
                + CGFloat(currentRow.count - 1) * spacing
            widestRow = max(widestRow, rowWidth)
            result.rows.append(currentRow)
            result.rowYs.append(currentY)
        }

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && !currentRow.isEmpty {
                closeRow()
                currentY += currentRowHeight + spacing
                currentRow = []
                currentX = 0
                currentRowHeight = 0
            }
            currentRow.append((index, size))
            currentX += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        if !currentRow.isEmpty {
            closeRow()
            currentY += currentRowHeight
        }

        result.contentWidth = widestRow
        result.size = CGSize(width: maxWidth.isFinite ? maxWidth : widestRow, height: currentY)
        return result
    }
}

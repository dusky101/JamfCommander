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
    
    // We pass profiles so we can show counts on the chips
    var profiles: [ConfigProfile] = []
    
    var onRefresh: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 12) {
            // --- ROW 1: Search Field ---
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search profiles, IDs, or scopes...", text: $searchText)
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
            
            // --- ROW 2: Filter Chips (Flow Layout) ---
            FlowLayout(spacing: 8) {
                // "All" Chip
                FilterChip(
                    title: "All Categories",
                    icon: "square.grid.2x2",
                    color: .blue,
                    isSelected: selectedCategory == nil,
                    count: profiles.count
                ) {
                    withAnimation { selectedCategory = nil }
                }
                
                // Category Chips
                ForEach(categories) { category in
                    let count = profiles.filter { $0.categoryName == category.name }.count
                    
                    // Only show categories that have items (Clean up the view)
                    if count > 0 {
                        FilterChip(
                            title: category.name,
                            icon: "folder",
                            color: .blue,
                            isSelected: selectedCategory?.id == category.id,
                            count: count
                        ) {
                            // Command-Click Logic
                            if NSEvent.modifierFlags.contains(.command) {
                                withAnimation { selectedCategory = category }
                            } else {
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
            .padding(.vertical, 4)
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
    
    // NEW: Optional override for the selected icon.
    // If this is nil, we default to adding ".fill" to the 'icon' string.
    // Use this for symbols like 'desktopcomputer.and.macbook' that don't have a fill variant.
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
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flow(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flow(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        for (index, row) in result.rows.enumerated() {
            let rowWidth = row.map { $0.size.width }.reduce(0, +) + CGFloat(row.count - 1) * spacing
            let xOffset = (bounds.width - rowWidth) / 2
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
    }
    
    private func flow(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) -> LayoutResult {
        var result = LayoutResult()
        var currentRow: [(index: Int, size: CGSize)] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && !currentRow.isEmpty {
                result.rows.append(currentRow)
                result.rowYs.append(currentY)
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
            result.rows.append(currentRow)
            result.rowYs.append(currentY)
            currentY += currentRowHeight
        }
        result.size = CGSize(width: maxWidth, height: currentY)
        return result
    }
}

//
//  ActionBarComponents.swift
//  JamfCommander
//
//  Shared building blocks for the action bars (single + bulk, policies + profiles) so they
//  all share one look: a centred action-name header above a soft, tinted capsule button
//  (matching the category-chip style — a light tinted fill + coloured glyph + outline,
//  rather than a bold solid fill), plus the searchable "Move to Category" picker.
//

import SwiftUI

/// Centred action-name header above its control, equal-width within an action bar.
struct ActionBarColumn<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            content
        }
        .frame(maxWidth: .infinity)
    }
}

/// The soft, tinted capsule used by the action-bar buttons — a light tinted fill, a
/// coloured glyph, and a matching outline. Reused as the label for plain buttons and menus
/// so they look identical and are the same size.
struct SoftIconLabel: View {
    let systemImage: String
    var tint: Color = .blue

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 60, height: 38)
            .background(tint.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// A soft-tinted, icon-only action button with a tooltip.
struct SoftIconButton: View {
    let systemImage: String
    var tint: Color = .blue
    var role: ButtonRole? = nil
    var isDisabled: Bool = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            SoftIconLabel(systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
    }
}

/// The "Move to Category" popover content: a search field plus the categories as blue
/// chips, in a card that auto-sizes to the chips (and scrolls past a cap). Calls `onPick`
/// with the chosen category; the host owns popover presentation/dismissal.
struct CategoryMovePicker: View {
    let categories: [Category]
    var onPick: (Category) -> Void

    @State private var search = ""
    @State private var chipsHeight: CGFloat = 120

    private var filtered: [Category] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let base = query.isEmpty ? categories : categories.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move to Category")
                .font(.headline)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search categories", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            if filtered.isEmpty {
                Text("No categories match “\(search)”.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    FlowLayout(spacing: 8, alignment: .leading) {
                        ForEach(filtered) { category in
                            chip(category)
                        }
                    }
                    .padding(2)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        chipsHeight = newHeight
                    }
                }
                .frame(height: min(chipsHeight + 4, 480))
            }
        }
        .padding(16)
        .frame(width: 600)
    }

    private func chip(_ category: Category) -> some View {
        Button { onPick(category) } label: {
            Text(category.name)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(Color.blue)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.blue.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Move to “\(category.name)”")
    }
}

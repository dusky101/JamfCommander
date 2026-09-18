//
//  RedundantRowView.swift
//  JamfCommander
//
//  One row of the Redundant audit.
//
//  Three kinds of Jamf object share this row, so it leads with what the object *is* and then shows,
//  in badges, every reason it was listed. The reason is never reduced to a single word like "unused":
//  a disabled policy and an unscoped one are different problems with different fixes, and an
//  administrator about to delete something is entitled to see which one they are looking at.
//

import SwiftUI

struct RedundantRowView: View {
    let item: RedundantItem
    var isSelected: Bool = false
    /// Packages are listed for review only, so they carry no selection control at all rather than
    /// one that silently does nothing.
    var isSelectable: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if isSelectable {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .blue : .secondary.opacity(0.4))
            }

            ZStack {
                Circle()
                    .fill(item.kind.colour.opacity(0.1))
                    .frame(width: 42, height: 42)

                Image(systemName: item.kind.icon)
                    .font(.system(size: 20))
                    .foregroundColor(item.kind.colour)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("ID: \(item.jamfID)")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)

                    Text("•")
                        .foregroundColor(.secondary)

                    Label(item.categoryName, systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if item.isInstallomator {
                        Text("Installomator")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                ForEach(item.orderedReasons) { reason in
                    ReasonBadge(reason: reason)
                }
            }
        }
        .padding(12)
        .liquidGlass(cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(isSelected ? 0.7 : 0), lineWidth: 2)
        )
        // The glass effect, unlike a material background, doesn't fill the hit area on its own.
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The row reads as one sentence, because the badges alone are meaningless out of context.
    private var accessibilitySummary: String {
        let reasons = item.orderedReasons.map(\.rawValue).joined(separator: ", ")
        let installomator = item.isInstallomator ? ", installs through Installomator" : ""
        return "\(item.kind.singular) \(item.name), category \(item.categoryName)\(installomator). \(reasons)."
    }
}

/// Why one row is listed. Icon **and** text, never colour alone.
struct ReasonBadge: View {
    let reason: RedundantReason

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: reason.icon)
                .font(.caption2)
                .fontWeight(.bold)

            Text(reason.rawValue)
                .font(.caption2)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundColor(reason.colour)
        .background(reason.colour.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(reason.colour.opacity(0.3), lineWidth: 1)
        )
        .help(reason.explanation)
        .fixedSize()
    }
}

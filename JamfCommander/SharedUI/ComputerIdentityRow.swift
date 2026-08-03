//
//  ComputerIdentityRow.swift
//  JamfCommander
//
//  Shared presentation of "which Mac is this, and whose is it".
//
//  The Computers table and the deployment scope picker need the same identity information in very
//  different containers — a wide `Table` with sortable columns, and a 150 pt tap-to-toggle list.
//  Extracting the Computers `Table` itself was measured and rejected (its column minimums alone
//  exceed the picker's available width, and `Table` selection semantics replace rather than toggle
//  a selection), so what is shared is the *row content*: these three views, plus the derived
//  values on `ComputerInventoryRecord`.
//

import SwiftUI

/// Device icon + computer name. Used for the Computers table's Device cell and as the leading
/// half of `ComputerIdentityRow`. The icon is tinted by management state, and never carries that
/// meaning on its own — the table pairs it with a Managed/Unmanaged badge, the picker with text.
struct ComputerDeviceLabel: View {
    let computer: ComputerInventoryRecord

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: DeviceSymbols.iconName(for: computer.hardware?.model ?? "Mac"))
                .foregroundColor(computer.isManaged ? .blue : .orange)
            Text(computer.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// The assigned user, with their email beneath. Used for the Computers table's User cell.
struct ComputerUserLabel: View {
    let computer: ComputerInventoryRecord
    var showsEmail: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(computer.assignedUserDisplayName ?? "—")
                .lineLimit(1)
                .truncationMode(.tail)
            if showsEmail, let email = computer.assignedUserEmail {
                Text(email)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

/// One dense line identifying a Mac and the person it belongs to, for pickers where a `Table`
/// doesn't fit. Sized for a compact list; there is deliberately no roomier variant until a caller
/// needs one, rather than shipping an unused layout.
struct ComputerIdentityRow: View {
    let computer: ComputerInventoryRecord
    var showsSerial: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            ComputerDeviceLabel(computer: computer)
                .font(.caption)

            Text("·")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(assignedUserText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if showsSerial, let serial = computer.hardware?.serialNumber {
                Text(serial)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(computer.displayName), \(assignedUserText)")
    }

    private var assignedUserText: String {
        computer.assignedUserDisplayName ?? "No assigned user"
    }
}

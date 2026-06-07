//
//  ActionTileButton.swift
//  JamfCommander
//
//  A compact, equal-width action "tile": an SF Symbol above a centred label that wraps to
//  two lines instead of truncating, with the full label as a tooltip. Used by the action
//  bars so long actions (e.g. "Match Self Service Category") stay readable.
//

import SwiftUI

struct ActionTileButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .blue
    var role: ButtonRole? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
        .disabled(isDisabled)
        .help(title)
    }
}

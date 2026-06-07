//
//  CommanderConfirmation.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import SwiftUI

// 1. The State Object
// Controls what the dialog says and does
struct ConfirmationData: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let actionTitle: String
    let role: ButtonRole?
    let action: () -> Void
}

// 2. The View Modifier
// Wraps the native .confirmationDialog to enforce your specific style
struct CommanderConfirmationModifier: ViewModifier {
    @Binding var data: ConfirmationData?
    
    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                data?.title ?? "Confirm Action",
                isPresented: Binding(
                    get: { data != nil },
                    set: { if !$0 { data = nil } }
                ),
                titleVisibility: .visible
            ) {
                // Confirm Button
                Button(data?.actionTitle ?? "Confirm", role: data?.role) {
                    data?.action()
                }
                
                // Cancel Button (Implicit in confirmationDialog, but explicit here for clarity)
                Button("Cancel", role: .cancel) {
                    data = nil
                }
            } message: {
                Text(data?.message ?? "")
            }
    }
}

// 3. Easy Access Extension
extension View {
    func commanderConfirmation(data: Binding<ConfirmationData?>) -> some View {
        self.modifier(CommanderConfirmationModifier(data: data))
    }
}

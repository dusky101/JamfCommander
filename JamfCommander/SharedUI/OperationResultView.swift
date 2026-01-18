//
//  OperationResult.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//


//
//  OperationResultView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import SwiftUI

// 1. The Model for a single operation result
struct OperationResult: Identifiable {
    let id = UUID()
    let itemName: String
    let success: Bool
    let error: String?
}

// 2. The Summary Sheet
struct OperationResultView: View {
    let title: String
    let results: [OperationResult]
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Done") { onDismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // List
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(results) { result in
                        HStack(alignment: .top, spacing: 12) {
                            // Icon
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.success ? .green : .red)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.itemName)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                if let error = result.error {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .fontDesign(.monospaced)
                                } else {
                                    Text("Success")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding()
                        
                        Divider()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
        .liquidGlass(.panel)
    }
}
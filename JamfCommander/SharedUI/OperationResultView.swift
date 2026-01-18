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
    
    // Optional: Only used for Move operations
    var fromCategory: String? = nil
    var toCategory: String? = nil
}

// 2. The Summary Sheet
struct OperationResultView: View {
    let title: String
    let results: [OperationResult]
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER ---
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text("\(results.filter(\.success).count) successful, \(results.filter { !$0.success }.count) failed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Done") { onDismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
            .overlay(Divider(), alignment: .bottom)
            
            // --- LIST ---
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { result in
                        ResultRow(result: result)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(nsColor: .controlBackgroundColor)) // Subtle background difference
        }
        .frame(width: 550, height: 650) // Slightly wider to accommodate the extra info
        .liquidGlass(.panel)
    }
}

// 3. The Row Component (The "Amazing" part)
struct ResultRow: View {
    let result: OperationResult
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Icon Column
            ZStack {
                Circle()
                    .fill(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .frame(width: 32, height: 32)
                
                Image(systemName: result.success ? "checkmark" : "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(result.success ? .green : .red)
            }
            
            // Name & Error Column
            VStack(alignment: .leading, spacing: 4) {
                Text(result.itemName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                if let error = result.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontDesign(.monospaced)
                } else if result.fromCategory == nil {
                    // Only show "Success" text if we AREN'T showing the move UI
                    Text("Operation Successful")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // The "Category Journey" Column (Right Hand Side)
            if let from = result.fromCategory, let to = result.toCategory, result.success {
                VStack(alignment: .trailing, spacing: 2) {
                    // 1. New Category (Top)
                    Text(to)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    
                    // 2. Up Arrow
                    Image(systemName: "arrow.up")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 10) // Center align with text visually
                    
                    // 3. Old Category (Bottom, Opaque)
                    Text(from)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.trailing, 2)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(Divider().padding(.leading, 60), alignment: .bottom)
    }
}

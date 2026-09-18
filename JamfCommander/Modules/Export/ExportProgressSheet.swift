//
//  ExportProgressSheet.swift
//  JamfCommander
//
//  Created by Marc Oliff on 23/02/2026.
//

import SwiftUI
import Combine

struct ExportProgressSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var progress: ExportProgress
    /// Which rows to show. Defaults to everything, which is what Export All produces. A
    /// single-domain export passes just its own, rather than listing rows that will sit at
    /// "pending" for the whole operation and read as though something had stalled.
    var types: [ExportType] = ExportType.allCases
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.green)
                        .rotationEffect(.degrees(progress.isComplete ? 0 : 360))
                        .animation(progress.isComplete ? .none : .linear(duration: 2).repeatForever(autoreverses: false), value: progress.isComplete)
                }
                
                Text(progress.isComplete ? "Export Complete!" : "Exporting Data")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if !progress.isComplete {
                    Text(progress.currentTask)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Progress Items
            VStack(alignment: .leading, spacing: 16) {
                ForEach(types) { type in
                    ExportProgressRow(
                        title: type.title,
                        icon: type.icon,
                        color: type.colour,
                        status: progress.status(for: type),
                        count: progress.count(for: type),
                        total: progress.total(for: type)
                    )
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
            
            // Close button (only shown when complete)
            if progress.isComplete {
                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 450)
        .liquidGlass(cornerRadius: 16)
    }
}

struct ExportProgressRow: View {
    let title: String
    let icon: String
    let color: Color
    let status: ExportStatus
    let count: Int
    let total: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
            }
            
            // Title
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)
            
            Spacer()
            
            // Progress indicator
            HStack(spacing: 8) {
                switch status {
                case .pending:
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Waiting...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                case .fetching:
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                    Text("Fetching...")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                case .processing(let current, let total):
                    ProgressView(value: Double(current), total: Double(total))
                        .frame(width: 60)
                    Text("\(current)/\(total)")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .frame(width: 50, alignment: .trailing)
                    
                case .complete:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("\(count) items")
                        .font(.caption)
                        .foregroundColor(.green)
                        .frame(width: 60, alignment: .trailing)
                    
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text("Failed")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
}

// MARK: - Export Progress Model

enum ExportStatus: Equatable {
    case pending
    case fetching
    case processing(current: Int, total: Int)
    case complete
    case failed
}

class ExportProgress: ObservableObject {
    @Published var currentTask: String = "Preparing..."
    @Published var isComplete: Bool = false

    // Keyed by type rather than a property per domain: adding an export used to mean four new
    // properties, four lines in reset(), a switch case and a hand-written row.
    @Published private(set) var statuses: [ExportType: ExportStatus] = [:]
    @Published private(set) var counts: [ExportType: Int] = [:]
    @Published private(set) var totals: [ExportType: Int] = [:]

    func status(for type: ExportType) -> ExportStatus { statuses[type] ?? .pending }
    func count(for type: ExportType) -> Int { counts[type] ?? 0 }
    func total(for type: ExportType) -> Int { totals[type] ?? 0 }

    func reset() {
        currentTask = "Preparing..."
        isComplete = false
        statuses.removeAll()
        counts.removeAll()
        totals.removeAll()
    }

    func updateProgress(for type: ExportType, status: ExportStatus, count: Int = 0, total: Int = 0) {
        DispatchQueue.main.async {
            self.statuses[type] = status
            self.counts[type] = count
            self.totals[type] = total
        }
    }

    func setCurrentTask(_ task: String) {
        DispatchQueue.main.async {
            self.currentTask = task
        }
    }

    func markComplete() {
        DispatchQueue.main.async {
            self.isComplete = true
            self.currentTask = "Export saved successfully"
        }
    }
}

enum ExportType: String, CaseIterable, Identifiable, Hashable {
    case computers
    case policies
    case profiles
    case scripts
    case packages
    case redundant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .computers: return "Computers"
        case .policies: return "Policies"
        case .profiles: return "Profiles"
        case .scripts: return "Scripts"
        case .packages: return "Packages"
        case .redundant: return "Redundant"
        }
    }

    var icon: String {
        switch self {
        case .computers: return "desktopcomputer"
        case .policies: return "scroll.fill"
        case .profiles: return "doc.text.fill"
        case .scripts: return "applescript.fill"
        case .packages: return "shippingbox.fill"
        case .redundant: return "archivebox.fill"
        }
    }

    /// Matched to the module's colour elsewhere in the app, so a row here is recognisably the same
    /// thing as its sidebar entry and its dashboard tile.
    var colour: Color {
        switch self {
        case .computers: return .moduleAzure
        case .policies: return .moduleMagenta
        case .profiles: return .moduleAmber
        case .scripts: return .moduleLime
        case .packages: return .moduleViolet
        case .redundant: return .moduleRose
        }
    }
}

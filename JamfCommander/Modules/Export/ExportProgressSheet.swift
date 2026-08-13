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
                ExportProgressRow(
                    title: "Computers",
                    icon: "desktopcomputer",
                    color: .blue,
                    status: progress.computersStatus,
                    count: progress.computersCount,
                    total: progress.computersTotal
                )
                
                ExportProgressRow(
                    title: "Policies",
                    icon: "scroll.fill",
                    color: .purple,
                    status: progress.policiesStatus,
                    count: progress.policiesCount,
                    total: progress.policiesTotal
                )
                
                ExportProgressRow(
                    title: "Profiles",
                    icon: "doc.text.fill",
                    color: .orange,
                    status: progress.profilesStatus,
                    count: progress.profilesCount,
                    total: progress.profilesTotal
                )
                
                ExportProgressRow(
                    title: "Scripts",
                    icon: "applescript.fill",
                    color: .gray,
                    status: progress.scriptsStatus,
                    count: progress.scriptsCount,
                    total: progress.scriptsTotal
                )

                ExportProgressRow(
                    title: "Packages",
                    icon: "shippingbox.fill",
                    color: .teal,
                    status: progress.packagesStatus,
                    count: progress.packagesCount,
                    total: progress.packagesTotal
                )
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
    
    @Published var computersStatus: ExportStatus = .pending
    @Published var computersCount: Int = 0
    @Published var computersTotal: Int = 0
    
    @Published var policiesStatus: ExportStatus = .pending
    @Published var policiesCount: Int = 0
    @Published var policiesTotal: Int = 0
    
    @Published var profilesStatus: ExportStatus = .pending
    @Published var profilesCount: Int = 0
    @Published var profilesTotal: Int = 0
    
    @Published var scriptsStatus: ExportStatus = .pending
    @Published var scriptsCount: Int = 0
    @Published var scriptsTotal: Int = 0

    @Published var packagesStatus: ExportStatus = .pending
    @Published var packagesCount: Int = 0
    @Published var packagesTotal: Int = 0

    func reset() {
        currentTask = "Preparing..."
        isComplete = false
        computersStatus = .pending
        policiesStatus = .pending
        profilesStatus = .pending
        scriptsStatus = .pending
        packagesStatus = .pending
        computersCount = 0
        policiesCount = 0
        profilesCount = 0
        scriptsCount = 0
        packagesCount = 0
        computersTotal = 0
        policiesTotal = 0
        profilesTotal = 0
        scriptsTotal = 0
        packagesTotal = 0
    }
    
    func updateProgress(for type: ExportType, status: ExportStatus, count: Int = 0, total: Int = 0) {
        DispatchQueue.main.async {
            switch type {
            case .computers:
                self.computersStatus = status
                self.computersCount = count
                self.computersTotal = total
            case .policies:
                self.policiesStatus = status
                self.policiesCount = count
                self.policiesTotal = total
            case .profiles:
                self.profilesStatus = status
                self.profilesCount = count
                self.profilesTotal = total
            case .scripts:
                self.scriptsStatus = status
                self.scriptsCount = count
                self.scriptsTotal = total
            case .packages:
                self.packagesStatus = status
                self.packagesCount = count
                self.packagesTotal = total
            }
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

enum ExportType {
    case computers
    case policies
    case profiles
    case scripts
    /// Installomator deployments, not Jamf package objects — see `PackageExportService`.
    case packages
}

import SwiftUI
import UIKit

@MainActor
struct DebugInfoView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var pendingTask = "Checking…"
    @State private var copied = false

    var body: some View {
        List {
            Section("Runtime") {
                DebugRow(title: "App version", value: appVersion)
                DebugRow(title: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "Unavailable")
                DebugRow(title: "Platform", value: "iOS \(UIDevice.current.systemVersion)")
            }

            Section("Current state") {
                DebugRow(title: "Reminders", value: viewModel.state.remindersPermission.title)
                DebugRow(title: "Account", value: viewModel.state.authentication.title)
                DebugRow(title: "Selected list", value: viewModel.state.selectedListName ?? "None")
                DebugRow(title: "Active reminders", value: "\(viewModel.state.activeReminderCount)")
                DebugRow(title: "Completed reminders", value: "\(viewModel.state.completedReminderCount)")
                DebugRow(title: "Sync in progress", value: viewModel.isSyncing ? "Yes" : "No")
                DebugRow(title: "Last result", value: syncResultDescription)
            }

            Section("Errors") {
                DebugRow(title: "Reminder error", value: viewModel.reminderError ?? "None")
                DebugRow(title: "Authentication error", value: viewModel.authenticationError ?? "None")
            }

            Section("Background refresh") {
                DebugRow(title: "Task identifier", value: BackgroundSyncScheduler.identifier)
                DebugRow(title: "Pending request", value: pendingTask)
                DebugRow(title: "Last schedule", value: BackgroundSyncScheduler.lastScheduleDescription)
                DebugRow(title: "Last schedule error", value: BackgroundSyncScheduler.lastErrorDescription)
                Button {
                    BackgroundSyncScheduler.schedule(after: Date().addingTimeInterval(5))
                    Task { await refreshPendingTask() }
                } label: {
                    Label("Schedule test refresh", systemImage: "clock.badge.checkmark")
                }
            }

            Section("Deployment") {
                DebugRow(title: "Sync API", value: FloatingBrainEnvironment.syncAPIBaseURL.absoluteString)
                DebugRow(title: "Cognito", value: FloatingBrainEnvironment.cognitoConfiguration == nil ? "Not configured" : "Configured")
                DebugRow(title: "Callback", value: FloatingBrainEnvironment.callbackURL)
            }

            Section {
                Button {
                    UIPasteboard.general.string = diagnosticText
                    copied = true
                } label: {
                    Label(copied ? "Diagnostics copied" : "Copy diagnostics", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } footer: {
                Text("Diagnostics intentionally exclude access tokens and reminder contents.")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshPendingTask() }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private var syncResultDescription: String {
        switch viewModel.state.result {
        case .never: return "Never"
        case let .succeeded(date): return "Succeeded at \(date.formatted(.iso8601))"
        case let .failed(message): return "Failed: \(message)"
        }
    }

    private var diagnosticText: String {
        [
            "App version: \(appVersion)",
            "Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unavailable")",
            "Reminders: \(viewModel.state.remindersPermission.title)",
            "Account: \(viewModel.state.authentication.title)",
            "Selected list: \(viewModel.state.selectedListName ?? "None")",
            "Active reminders: \(viewModel.state.activeReminderCount)",
            "Completed reminders: \(viewModel.state.completedReminderCount)",
            "Last result: \(syncResultDescription)",
            "Reminder error: \(viewModel.reminderError ?? "None")",
            "Authentication error: \(viewModel.authenticationError ?? "None")",
            "Pending request: \(pendingTask)",
            "Last schedule: \(BackgroundSyncScheduler.lastScheduleDescription)",
            "Last schedule error: \(BackgroundSyncScheduler.lastErrorDescription)",
            "Sync API: \(FloatingBrainEnvironment.syncAPIBaseURL.absoluteString)",
            "Cognito: \(FloatingBrainEnvironment.cognitoConfiguration == nil ? "Not configured" : "Configured")"
        ].joined(separator: "\n")
    }

    private func refreshPendingTask() async {
        pendingTask = await BackgroundSyncScheduler.pendingRequestDescription()
    }
}

private struct DebugRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
        }
    }
}

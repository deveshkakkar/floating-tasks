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
                DebugRow(title: "Status", value: viewModel.backendDiagnostics.state.rawValue)
                DebugRow(title: "Message", value: viewModel.backendDiagnostics.message)
                DebugRow(title: "Checked", value: backendCheckedDescription)
                DebugRow(title: "Latency", value: backendLatencyDescription)
                DebugRow(title: "Server selection date", value: viewModel.backendDiagnostics.selectionDate ?? "Unavailable")
                DebugRow(title: "Server selection count", value: viewModel.backendDiagnostics.selectionTaskCount.map(String.init) ?? "Unavailable")
                Button {
                    Task { await viewModel.refreshBackendDiagnostics() }
                } label: {
                    Label(viewModel.isCheckingBackend ? "Checking backend…" : "Check backend now", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(viewModel.isCheckingBackend)
            } header: {
                Text("Backend")
            } footer: {
                Text("Checks the authenticated daily-selection endpoint. Tokens and task text are never shown here.")
            }

            Section {
                PaletteRow(title: "Canvas", color: FloatingBrainPalette.canvas, hex: "#F6F7FB / #101426")
                PaletteRow(title: "Surface", color: FloatingBrainPalette.surface, hex: "#FFFFFF / #1B2238")
                PaletteRow(title: "Brand", color: FloatingBrainPalette.brandPrimary, hex: "#51439B / #A99CF7")
                PaletteRow(title: "Daily task", color: FloatingBrainPalette.taskAccent, hex: "#D94F6D / #FF8EA5")
                PaletteRow(title: "Success", color: FloatingBrainPalette.success, hex: "#147A67 / #67D5BA")
                PaletteRow(title: "Warning", color: FloatingBrainPalette.warning, hex: "#8A5A00 / #F3C56B")
                PaletteRow(title: "Danger", color: FloatingBrainPalette.danger, hex: "#B4232F / #FF8B8B")
            } header: {
                Text("Theme palette")
            } footer: {
                Text("Light / dark values are shown in order. Status is always paired with text or an icon.")
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
        .scrollContentBackground(.hidden)
        .background(FloatingBrainPalette.canvas)
        .tint(FloatingBrainPalette.brandPrimary)
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshPendingTask()
            await viewModel.refreshBackendDiagnostics()
        }
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

    private var backendCheckedDescription: String {
        viewModel.backendDiagnostics.checkedAt?.formatted(.iso8601) ?? "Not checked"
    }

    private var backendLatencyDescription: String {
        guard let latency = viewModel.backendDiagnostics.latencyMilliseconds else { return "Unavailable" }
        return "\(latency) ms"
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
            "Cognito: \(FloatingBrainEnvironment.cognitoConfiguration == nil ? "Not configured" : "Configured")",
            "Backend: \(viewModel.backendDiagnostics.state.rawValue) — \(viewModel.backendDiagnostics.message)",
            "Backend checked: \(backendCheckedDescription)",
            "Backend latency: \(backendLatencyDescription)",
            "Server selection date: \(viewModel.backendDiagnostics.selectionDate ?? "Unavailable")",
            "Server selection count: \(viewModel.backendDiagnostics.selectionTaskCount.map(String.init) ?? "Unavailable")",
            "Theme: Indigo / lavender semantic palette"
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
                .foregroundStyle(FloatingBrainPalette.inkSecondary)
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(FloatingBrainPalette.ink)
                .textSelection(.enabled)
        }
    }
}

private struct PaletteRow: View {
    let title: String
    let color: Color
    let hex: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(FloatingBrainPalette.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(hex)
                    .font(.caption.monospaced())
                    .foregroundStyle(FloatingBrainPalette.inkSecondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(hex)")
    }
}

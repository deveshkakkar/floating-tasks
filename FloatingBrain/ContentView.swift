import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var viewModel: DashboardViewModel

    @MainActor
    init(viewModel: DashboardViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? DashboardViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    statusCard
                    syncCard
                    accountActions
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
            .navigationTitle("Floating Brain")
            .task {
                await viewModel.refreshReminderStatus()
                await SyncIntentHandler.shared.register {
                    await viewModel.syncNow()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A quieter way to remember what matters.")
                .font(.title2.weight(.semibold))
            Text("Your iPhone helper keeps the Floating Brain list ready for the apartment dashboard.")
                .foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            StatusRow(title: "Reminders access", value: viewModel.state.remindersPermission.title, systemImage: "checklist")
            StatusRow(title: "Cloud account", value: viewModel.state.authentication.title, systemImage: "lock.shield")
            StatusRow(title: "Selected list", value: viewModel.state.selectedListName ?? "Not selected", systemImage: "list.bullet")
            StatusRow(title: "Active reminders", value: "\(viewModel.state.activeReminderCount)", systemImage: "circle")
            StatusRow(title: "Completed reminders", value: "\(viewModel.state.completedReminderCount)", systemImage: "checkmark.circle")
            if let reminderError = viewModel.reminderError {
                Text(reminderError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let authenticationError = viewModel.authenticationError {
                Text(authenticationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(viewModel.state.result.title, systemImage: resultIcon)
                .font(.headline)
            if case let .failed(message) = viewModel.state.result {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await viewModel.syncNow() }
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.state.canSync)
            if viewModel.state.remindersPermission != .authorized {
                Button("Allow Reminders Access") {
                    Task { await viewModel.requestReminderAccess() }
                }
                .buttonStyle(.bordered)
            } else if !viewModel.state.canSync {
                Text("Connect your cloud account to sync.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var accountActions: some View {
        Group {
            if viewModel.state.authentication == .signedIn {
                Button("Sign Out", role: .destructive) {
                    viewModel.signOut()
                }
            } else {
                Button("Sign In") {
                    Task { await viewModel.signIn() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
    }

    private var resultIcon: String {
        switch viewModel.state.result {
        case .never: "clock"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

}

private struct StatusRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(.tint)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

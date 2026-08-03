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
                LazyVStack(alignment: .leading, spacing: 16) {
                    hero
                    overviewCard
                    syncCard
                    accountCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .background(Color(red: 0.95, green: 0.95, blue: 0.97).ignoresSafeArea())
            .navigationTitle("Floating Brain")
            .task {
                await viewModel.refreshReminderStatus()
                await SyncIntentHandler.shared.register {
                    await viewModel.syncNow()
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("PRIVATE SYNC", systemImage: "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text("A quieter way to remember what matters.")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text("Keep your Floating Brain list ready for the apartment dashboard.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.20, blue: 0.38), Color(red: 0.30, green: 0.22, blue: 0.46)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Today at a glance")
                    .font(.headline)
                Spacer()
                StatusPill(
                    title: viewModel.state.authentication == .signedIn ? "Connected" : "Offline",
                    color: viewModel.state.authentication == .signedIn ? .green : .orange
                )
            }

            HStack(spacing: 12) {
                MetricTile(value: viewModel.state.activeReminderCount, label: "Active", symbol: "circle.fill", tint: .blue)
                MetricTile(value: viewModel.state.completedReminderCount, label: "Completed", symbol: "checkmark.circle.fill", tint: .green)
            }

            Divider()
            StatusRow(title: "Reminders access", value: viewModel.state.remindersPermission.title, systemImage: "checklist")
            StatusRow(title: "Selected list", value: viewModel.state.selectedListName ?? "Not selected", systemImage: "list.bullet")
            if let reminderError = viewModel.reminderError {
                MessageBanner(text: reminderError, symbol: "exclamationmark.triangle.fill", tint: .red)
            }
            if let authenticationError = viewModel.authenticationError {
                MessageBanner(text: authenticationError, symbol: "lock.trianglebadge.exclamationmark.fill", tint: .red)
            }
        }
        .cardSurface()
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: resultIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(resultTint)
                    .frame(width: 34, height: 34)
                    .background(resultTint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.isSyncing ? "Syncing your reminders" : viewModel.state.result.title)
                        .font(.headline)
                    if case let .failed(message) = viewModel.state.result {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if !viewModel.isSyncing {
                        Text("Your private cloud copy stays up to date.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if viewModel.isSyncing {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await viewModel.syncNow() }
            } label: {
                Label(viewModel.isSyncing ? "Syncing…" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.state.canSync || viewModel.isSyncing)

            if viewModel.state.remindersPermission != .authorized {
                Button("Allow Reminders Access") {
                    Task { await viewModel.requestReminderAccess() }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
            } else if viewModel.state.authentication != .signedIn {
                Text("Connect your cloud account to enable sync.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .cardSurface()
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Account", systemImage: "person.crop.circle")
                .font(.headline)
            Text(viewModel.state.authentication == .signedIn ? "Your account is securely connected." : "Sign in to sync reminders to your private dashboard.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if viewModel.state.authentication == .signedIn {
                Button("Sign Out", role: .destructive) {
                    viewModel.signOut()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await viewModel.signIn() }
                } label: {
                    Label("Sign In", systemImage: "person.badge.key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .cardSurface()
    }

    private var resultIcon: String {
        if viewModel.isSyncing { return "arrow.triangle.2.circlepath" }
        switch viewModel.state.result {
        case .never: return "clock"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var resultTint: Color {
        if viewModel.isSyncing { return .blue }
        switch viewModel.state.result {
        case .never: return .secondary
        case .succeeded: return .green
        case .failed: return .red
        }
    }
}

private struct MetricTile: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.title3.weight(.bold))
                    .contentTransition(.numericText())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Label(title, systemImage: "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct MessageBanner: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
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
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

private extension View {
    func cardSurface() -> some View {
        padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
    }
}

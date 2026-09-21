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
                    dailyTasksCard
                    syncCard
                    accountCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .background(FloatingBrainPalette.canvas.ignoresSafeArea())
            .tint(FloatingBrainPalette.brandPrimary)
            .navigationTitle("Floating Brain")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DebugInfoView(viewModel: viewModel)
                    } label: {
                        Image(systemName: "ladybug.fill")
                    }
                    .accessibilityLabel("Open diagnostics")
                }
            }
            .task {
                await viewModel.refreshReminderStatus()
                await viewModel.processPendingCaptures()
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
                colors: [FloatingBrainPalette.brandDeep, FloatingBrainPalette.brandViolet],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: FloatingBrainPalette.brandDeep.opacity(0.18), radius: 16, y: 8)
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Today at a glance")
                    .font(.headline)
                Spacer()
                StatusPill(
                    title: viewModel.state.authentication == .signedIn ? "Connected" : "Offline",
                    color: viewModel.state.authentication == .signedIn ? FloatingBrainPalette.success : FloatingBrainPalette.warning
                )
            }

            HStack(spacing: 12) {
                MetricTile(value: viewModel.state.activeReminderCount, label: "Active", symbol: "circle.fill", tint: FloatingBrainPalette.info)
                MetricTile(value: viewModel.state.completedReminderCount, label: "Completed", symbol: "checkmark.circle.fill", tint: FloatingBrainPalette.success)
            }

            Divider()
            StatusRow(title: "Reminders access", value: viewModel.state.remindersPermission.title, systemImage: "checklist")
            StatusRow(title: "Selected list", value: viewModel.state.selectedListName ?? "Not selected", systemImage: "list.bullet")
            if let reminderError = viewModel.reminderError {
                MessageBanner(text: reminderError, symbol: "exclamationmark.triangle.fill", tint: FloatingBrainPalette.danger)
            }
            if let authenticationError = viewModel.authenticationError {
                MessageBanner(text: authenticationError, symbol: "lock.trianglebadge.exclamationmark.fill", tint: FloatingBrainPalette.danger)
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
                            .foregroundStyle(FloatingBrainPalette.inkSecondary)
                    } else if !viewModel.isSyncing {
                        Text("Your private cloud copy stays up to date.")
                            .font(.subheadline)
                            .foregroundStyle(FloatingBrainPalette.inkSecondary)
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
                    .foregroundStyle(FloatingBrainPalette.inkSecondary)
            }
        }
        .cardSurface()
    }

    private var dailyTasksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Today's three", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                NavigationLink("See all") {
                    DailyTasksView(viewModel: viewModel)
                }
                .font(.subheadline.weight(.semibold))
            }

            if viewModel.dailyTasks.isEmpty {
                Text("Sync your tasks to choose today's three.")
                    .font(.subheadline)
                    .foregroundStyle(FloatingBrainPalette.inkSecondary)
            } else {
                ForEach(Array(viewModel.dailyTasks.enumerated()), id: \.element.id) { index, task in
                    DailyTaskRow(index: index, task: task) {
                        Task { await viewModel.completeDailyTask(task) }
                    }
                }
            }

            NavigationLink {
                AllTasksView(viewModel: viewModel)
            } label: {
                Label("Browse all tasks", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))
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
                .foregroundStyle(FloatingBrainPalette.inkSecondary)
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
        if viewModel.isSyncing { return FloatingBrainPalette.info }
        switch viewModel.state.result {
        case .never: return FloatingBrainPalette.inkSecondary
        case .succeeded: return FloatingBrainPalette.success
        case .failed: return FloatingBrainPalette.danger
        }
    }
}

@MainActor
private struct DailyTasksView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        List {
            Section {
                if viewModel.dailyTasks.isEmpty {
                    Text("Sync your tasks to choose today's three.")
                        .foregroundStyle(FloatingBrainPalette.inkSecondary)
                } else {
                    ForEach(Array(viewModel.dailyTasks.enumerated()), id: \.element.id) { index, task in
                        DailyTaskRow(index: index, task: task) {
                            Task { await viewModel.completeDailyTask(task) }
                        }
                        .padding(.vertical, 6)
                    }
                }
            } header: {
                Text("These tasks stay the same until tomorrow")
            }
        }
        .navigationTitle("Today's Tasks")
    }
}

private struct DailyTaskRow: View {
    let index: Int
    let task: DailyTask
    var onComplete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onComplete?()
            } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.completed ? FloatingBrainPalette.success : FloatingBrainPalette.taskAccent)
                    .accessibilityLabel(task.completed ? "Completed" : "Finish task")
            }
            .buttonStyle(.plain)
            .disabled(task.completed || onComplete == nil)

            Text("\(index + 1)")
                .font(.headline)
                .foregroundStyle(task.completed ? FloatingBrainPalette.inkSecondary : FloatingBrainPalette.taskAccent)
                .frame(width: 28, height: 28)
                .background((task.completed ? FloatingBrainPalette.inkSecondary : FloatingBrainPalette.taskAccent).opacity(0.12), in: Circle())
            Text(task.text)
                .font(.body)
                .strikethrough(task.completed)
                .foregroundStyle(task.completed ? FloatingBrainPalette.inkSecondary : FloatingBrainPalette.ink)
                .padding(.top, 3)
        }
    }
}

@MainActor
private struct AllTasksView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var isShowingAddReminder = false

    var body: some View {
        List {
            ForEach(viewModel.allTasks) { task in
                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.completeAllTask(task) }
                    } label: {
                        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(task.completed ? FloatingBrainPalette.success : FloatingBrainPalette.taskAccent)
                    }
                    .buttonStyle(.plain)
                    .disabled(task.completed)
                    .accessibilityLabel(task.completed ? "Completed" : "Finish task")

                    Text(task.text)
                        .strikethrough(task.completed)
                        .foregroundStyle(task.completed ? FloatingBrainPalette.inkSecondary : FloatingBrainPalette.ink)
                        .padding(.vertical, 6)
                }
            }

            if let error = viewModel.allTasksError {
                Text(error)
                    .foregroundStyle(FloatingBrainPalette.danger)
            }

            if viewModel.isLoadingAllTasks {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if viewModel.allTasksCursor != nil {
                Button("Load more") {
                    Task { await viewModel.loadAllTasksPage() }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .overlay {
            if viewModel.allTasks.isEmpty && !viewModel.isLoadingAllTasks {
                ContentUnavailableView("No active tasks", systemImage: "checklist")
            }
        }
        .navigationTitle("All Tasks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddReminder = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add reminder")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ArchivedTasksView(viewModel: viewModel)
                } label: {
                    Image(systemName: "archivebox")
                }
                .accessibilityLabel("Archived tasks")
            }
        }
        .sheet(isPresented: $isShowingAddReminder) {
            AddReminderView(viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .task {
            await viewModel.loadAllTasksPage(reset: true)
        }
    }
}

@MainActor
private struct ArchivedTasksView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        List {
            ForEach(viewModel.archivedTasks) { task in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.text)
                        Text(task.source ?? "Unknown source")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if task.source == "APPLE_REMINDERS" {
                        Button("Restore") {
                            Task { await viewModel.restoreArchivedTask(task) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if let error = viewModel.archivedTasksError {
                Text(error).foregroundStyle(FloatingBrainPalette.danger)
            }
        }
        .overlay {
            if viewModel.archivedTasks.isEmpty && !viewModel.isLoadingArchivedTasks {
                ContentUnavailableView("No archived tasks", systemImage: "archivebox")
            }
        }
        .navigationTitle("Archived Tasks")
        .task { await viewModel.loadArchivedTasks() }
    }
}

@MainActor
private struct AddReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: DashboardViewModel
    @State private var text = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("What do you want to remember?", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error = viewModel.allTasksError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(FloatingBrainPalette.danger)
                }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            isSaving = true
                            if await viewModel.addReminder(text: text) {
                                dismiss()
                            }
                            isSaving = false
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
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
                    .foregroundStyle(FloatingBrainPalette.inkSecondary)
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
                .foregroundStyle(FloatingBrainPalette.brandPrimary)
            Text(title)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(FloatingBrainPalette.inkSecondary)
        }
        .font(.subheadline)
    }
}

private extension View {
    func cardSurface() -> some View {
        padding(18)
            .background(FloatingBrainPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(FloatingBrainPalette.border.opacity(0.75), lineWidth: 1)
            }
            .shadow(color: FloatingBrainPalette.brandDeep.opacity(0.10), radius: 8, y: 3)
    }
}

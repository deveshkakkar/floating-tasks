import Combine
import Foundation
import WidgetKit

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var state: SyncState
    @Published private(set) var isLoadingReminders = false
    @Published private(set) var isSyncing = false
    @Published private(set) var reminderError: String?
    @Published private(set) var authenticationError: String?
    @Published private(set) var dailyTasks: [DailyTask] = []
    @Published private(set) var allTasks: [SyncReminder] = []
    @Published private(set) var isLoadingAllTasks = false
    @Published private(set) var allTasksCursor: String?
    @Published private(set) var allTasksError: String?

    private let reminderService: any ReminderAccessService
    private let taskNotificationScheduler: any TaskNotificationScheduling
    private let syncService: any ReminderSyncService
    private let signInService: any SignInService
    private let authenticationSession: (any AuthenticationSession)?

    init(
        state: SyncState = SyncState(),
        reminderService: any ReminderAccessService = EventKitReminderAccessService(),
        taskNotificationScheduler: any TaskNotificationScheduling = LocalTaskNotificationScheduler(),
        syncService: any ReminderSyncService = UnconfiguredReminderSyncService(),
        signInService: any SignInService = UnconfiguredSignInService(),
        authenticationSession: (any AuthenticationSession)? = nil
    ) {
        self.state = state
        self.reminderService = reminderService
        self.taskNotificationScheduler = taskNotificationScheduler
        self.syncService = syncService
        self.signInService = signInService
        self.authenticationSession = authenticationSession
    }

    func refreshReminderStatus() async {
        state.remindersPermission = reminderService.authorizationStatus()
        guard state.remindersPermission == .authorized else { return }
        await loadReminderList()
    }

    func requestReminderAccess() async {
        reminderError = nil
        do {
            let granted = try await reminderService.requestAccess()
            state.remindersPermission = granted ? .authorized : .denied
            if granted {
                await loadReminderList()
            }
        } catch {
            state.remindersPermission = .denied
            reminderError = error.localizedDescription
        }
    }

    func loadReminderList() async {
        guard state.remindersPermission == .authorized else { return }
        guard !isLoadingReminders else { return }
        isLoadingReminders = true
        reminderError = nil
        defer { isLoadingReminders = false }

        do {
            let snapshot = try await reminderService.readFloatingBrainList()
            state.selectedListName = snapshot.listName
            state.activeReminderCount = snapshot.activeCount
            state.completedReminderCount = snapshot.completedCount

            if state.authentication == .signedIn {
                restoreCachedDailyTasks()
                let selectedTasks = try await loadDailyTasksFromServer()
                try? await taskNotificationScheduler.scheduleDailyTaskNotification(for: selectedTasks)
            } else {
                dailyTasks = []
                try? await taskNotificationScheduler.scheduleDailyTaskNotification(for: [])
            }
        } catch {
            if state.authentication == .signedIn {
                restoreCachedDailyTasks()
            }
            reminderError = error.localizedDescription
        }
    }

    func syncNow() async {
        guard !isSyncing else { return }
        guard state.remindersPermission == .authorized else {
            state.result = .failed(message: "Allow Reminders access before syncing.")
            return
        }
        guard state.authentication == .signedIn else {
            state.result = .failed(message: "Sign in before syncing.")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let reminders = try await reminderService.readFloatingBrainReminders()
            let activeReminders = reminders.filter { !$0.completed }
            state.result = await syncService.sync(reminders: activeReminders, listName: "Floating Brain")
            if case .succeeded = state.result {
                do {
                    let selectedTasks = try await loadDailyTasksFromServer()
                    try? await taskNotificationScheduler.scheduleDailyTaskNotification(for: selectedTasks)
                } catch {
                    // The upload succeeded; cloud notification refresh can retry on the next refresh.
                }
            }
        } catch {
            state.result = .failed(message: error.localizedDescription)
        }
    }

    func processPendingCaptures() async {
        guard state.authentication == .signedIn else { return }

        let inbox = CaptureInbox()
        let captures = inbox.pending()
        guard !captures.isEmpty else { return }

        do {
            try await syncService.capture(tasks: captures)
            inbox.remove(ids: Set(captures.map(\.id)))
            let selectedTasks = try await loadDailyTasksFromServer()
            try? await taskNotificationScheduler.scheduleDailyTaskNotification(for: selectedTasks)
        } catch {
            // Keep captures queued for the next refresh when the network is unavailable.
        }
    }

    func loadAllTasksPage(reset: Bool = false) async {
        guard state.authentication == .signedIn, !isLoadingAllTasks else { return }
        if reset {
            allTasks = []
            allTasksCursor = nil
            allTasksError = nil
        }
        if !reset, allTasksCursor == nil, !allTasks.isEmpty { return }

        isLoadingAllTasks = true
        allTasksError = nil
        defer { isLoadingAllTasks = false }
        do {
            let page = try await syncService.fetchActiveRemindersPage(limit: 25, cursor: reset ? nil : allTasksCursor)
            allTasks.append(contentsOf: page.items)
            allTasksCursor = page.nextCursor
        } catch {
            allTasksError = error.localizedDescription
        }
    }

    func addReminder(text: String) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            allTasksError = "Enter a reminder before saving."
            return false
        }

        do {
            try await syncService.capture(tasks: [CapturedTask(text: trimmedText)])
            await loadAllTasksPage(reset: true)
            return allTasksError == nil
        } catch {
            allTasksError = error.localizedDescription
            return false
        }
    }

    func completeDailyTask(_ task: DailyTask) async {
        guard !task.completed else { return }
        do {
            try await reminderService.completeReminder(withID: task.id)
            let updatedTasks = dailyTasks.map { current in
                guard current.id == task.id else { return current }
                var completed = current
                completed.completed = true
                return completed
            }
            saveDailyTasks(updatedTasks)
        } catch {
            reminderError = error.localizedDescription
        }
    }

    func signIn() async {
        authenticationError = nil
        do {
            _ = try await signInService.signIn()
            state.authentication = .signedIn
            if state.remindersPermission == .authorized {
                await loadReminderList()
                await processPendingCaptures()
            }
        } catch {
            authenticationError = error.localizedDescription
        }
    }

    func signOut() {
        try? authenticationSession?.signOut()
        state.authentication = .signedOut
        dailyTasks = []
        allTasks = []
        allTasksCursor = nil
        allTasksError = nil
        DailyTaskStore().clear()
        WidgetTaskStore().save([])
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            try? await taskNotificationScheduler.scheduleDailyTaskNotification(for: [])
        }
    }

    private func loadDailyTasksFromServer() async throws -> [SyncReminder] {
        let reminders = try await syncService.fetchDailyReminders()
        let completedIDs = Set(DailyTaskStore().selection()?.tasks.filter(\.completed).map(\.id) ?? [])
        let tasks = reminders.map {
            DailyTask(id: $0.externalID, text: $0.text, priority: $0.priority, completed: completedIDs.contains($0.externalID))
        }
        saveDailyTasks(tasks)
        return reminders
    }

    private func restoreCachedDailyTasks() {
        guard let selection = DailyTaskStore().selection() else { return }
        dailyTasks = selection.tasks
        WidgetTaskStore().save(selection.tasks.map { WidgetTask(id: $0.id, text: $0.text, priority: $0.priority, completed: $0.completed) })
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func saveDailyTasks(_ tasks: [DailyTask]) {
        DailyTaskStore().save(DailyTaskSelection(dateKey: DailyTaskStore.dateKey(), tasks: tasks))
        dailyTasks = tasks
        WidgetTaskStore().save(tasks.map { WidgetTask(id: $0.id, text: $0.text, priority: $0.priority, completed: $0.completed) })
        WidgetCenter.shared.reloadAllTimelines()
    }
}

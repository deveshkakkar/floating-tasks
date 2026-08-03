import Combine
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var state: SyncState
    @Published private(set) var isLoadingReminders = false
    @Published private(set) var reminderError: String?
    @Published private(set) var authenticationError: String?

    private let reminderService: any ReminderAccessService
    private let syncService: any ReminderSyncService
    private let signInService: any SignInService
    private let authenticationSession: (any AuthenticationSession)?

    init(
        state: SyncState = SyncState(),
        reminderService: any ReminderAccessService = EventKitReminderAccessService(),
        syncService: any ReminderSyncService = UnconfiguredReminderSyncService(),
        signInService: any SignInService = UnconfiguredSignInService(),
        authenticationSession: (any AuthenticationSession)? = nil
    ) {
        self.state = state
        self.reminderService = reminderService
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
        isLoadingReminders = true
        reminderError = nil
        defer { isLoadingReminders = false }

        do {
            let snapshot = try await reminderService.readFloatingBrainList()
            state.selectedListName = snapshot.listName
            state.activeReminderCount = snapshot.activeCount
            state.completedReminderCount = snapshot.completedCount
        } catch {
            reminderError = error.localizedDescription
        }
    }

    func syncNow() async {
        guard state.remindersPermission == .authorized else {
            state.result = .failed(message: "Allow Reminders access before syncing.")
            return
        }
        guard state.authentication == .signedIn else {
            state.result = .failed(message: "Sign in before syncing.")
            return
        }

        do {
            let reminders = try await reminderService.readFloatingBrainReminders()
            state.result = await syncService.sync(reminders: reminders, listName: "Floating Brain")
        } catch {
            state.result = .failed(message: error.localizedDescription)
        }
    }

    func signIn() async {
        authenticationError = nil
        do {
            _ = try await signInService.signIn()
            state.authentication = .signedIn
        } catch {
            authenticationError = error.localizedDescription
        }
    }

    func signOut() {
        try? authenticationSession?.signOut()
        state.authentication = .signedOut
    }
}

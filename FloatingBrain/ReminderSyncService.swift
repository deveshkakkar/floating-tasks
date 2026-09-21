import Foundation

protocol ReminderSyncService {
    func sync(reminders: [SyncReminder], listName: String) async -> SyncResult
    func fetchActiveReminders() async throws -> [SyncReminder]
    func fetchDailyReminders() async throws -> [SyncReminder]
    func checkBackend() async -> BackendDiagnostics
    func fetchActiveRemindersPage(limit: Int, cursor: String?) async throws -> ReminderPage
    func fetchArchivedReminders() async throws -> [ArchivedReminder]
    func restoreReminder(withID externalID: String) async throws
    func completeReminder(withID externalID: String) async throws
    func capture(tasks: [CapturedTask]) async throws
}

struct ReminderPage: Equatable {
    let items: [SyncReminder]
    let nextCursor: String?
}

struct UnconfiguredReminderSyncService: ReminderSyncService {
    func sync(reminders: [SyncReminder], listName: String) async -> SyncResult {
        .failed(message: "Sync is not configured yet.")
    }

    func fetchActiveReminders() async throws -> [SyncReminder] {
        throw ReminderSyncAPIError.missingAccessToken
    }

    func fetchDailyReminders() async throws -> [SyncReminder] {
        throw ReminderSyncAPIError.missingAccessToken
    }

    func checkBackend() async -> BackendDiagnostics {
        BackendDiagnostics(
            state: .unconfigured,
            message: "The sync service is not configured.",
            checkedAt: Date(),
            latencyMilliseconds: nil,
            selectionDate: nil,
            selectionTaskCount: nil
        )
    }

    func fetchActiveRemindersPage(limit: Int, cursor: String?) async throws -> ReminderPage {
        throw ReminderSyncAPIError.missingAccessToken
    }

    func fetchArchivedReminders() async throws -> [ArchivedReminder] {
        throw ReminderSyncAPIError.missingAccessToken
    }

    func restoreReminder(withID externalID: String) async throws {
        throw ReminderSyncAPIError.missingAccessToken
    }

    func completeReminder(withID externalID: String) async throws {
        throw ReminderSyncAPIError.missingAccessToken
    }

    func capture(tasks: [CapturedTask]) async throws {
        throw ReminderSyncAPIError.missingAccessToken
    }
}

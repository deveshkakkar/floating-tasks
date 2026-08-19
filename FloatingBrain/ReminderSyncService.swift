import Foundation

protocol ReminderSyncService {
    func sync(reminders: [SyncReminder], listName: String) async -> SyncResult
    func fetchActiveReminders() async throws -> [SyncReminder]
    func fetchDailyReminders() async throws -> [SyncReminder]
    func fetchActiveRemindersPage(limit: Int, cursor: String?) async throws -> ReminderPage
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

    func fetchActiveRemindersPage(limit: Int, cursor: String?) async throws -> ReminderPage {
        throw ReminderSyncAPIError.missingAccessToken
    }

    func capture(tasks: [CapturedTask]) async throws {
        throw ReminderSyncAPIError.missingAccessToken
    }
}

import Foundation

protocol ReminderSyncService {
    func sync(reminders: [SyncReminder], listName: String) async -> SyncResult
}

struct UnconfiguredReminderSyncService: ReminderSyncService {
    func sync(reminders: [SyncReminder], listName: String) async -> SyncResult {
        .failed(message: "Sync is not configured yet.")
    }
}

import Foundation

protocol ReminderSyncService {
    func sync() async -> SyncResult
}

struct UnconfiguredReminderSyncService: ReminderSyncService {
    func sync() async -> SyncResult {
        .failed(message: "Sync is not configured yet.")
    }
}

import BackgroundTasks
import Foundation
import OSLog
import UserNotifications

enum TaskNotificationSchedulerError: LocalizedError, Equatable {
    case permissionDenied

    var errorDescription: String? {
        "Notifications permission is required for the 8:00 AM task reminder."
    }
}

protocol TaskNotificationScheduling {
    func scheduleDailyTaskNotification(for tasks: [SyncReminder]) async throws
}

struct LocalTaskNotificationScheduler: TaskNotificationScheduling {
    static let identifier = "com.floatingbrain.app.daily-tasks"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func scheduleDailyTaskNotification(for tasks: [SyncReminder]) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard !tasks.isEmpty else { return }

        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw TaskNotificationSchedulerError.permissionDenied
        }

        let selectedTasks = Array(tasks.prefix(3))
        let content = UNMutableNotificationContent()
        content.title = "Three tasks for today"
        content.body = selectedTasks.enumerated().map { index, task in
            "\(index + 1). \(task.text)"
        }.joined(separator: "\n")
        content.sound = .default
        content.userInfo = ["reminderIDs": selectedTasks.map(\.externalID)]

        var date = DateComponents()
        date.hour = 8
        date.minute = 0
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        )
        try await center.add(request)
    }
}

enum BackgroundSyncScheduler {
    static let identifier = "com.floatingbrain.app.refresh"
    private static let interval: TimeInterval = 15 * 60
    private static let logger = Logger(subsystem: "com.floatingbrain.app", category: "BackgroundSync")
    private static let lastScheduleKey = "backgroundSync.lastSchedule"
    private static let lastErrorKey = "backgroundSync.lastError"

    static var lastScheduleDescription: String {
        UserDefaults.standard.string(forKey: lastScheduleKey) ?? "Not scheduled in this process"
    }

    static var lastErrorDescription: String {
        UserDefaults.standard.string(forKey: lastErrorKey) ?? "None recorded"
    }

    static func schedule(after date: Date = Date().addingTimeInterval(interval)) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        do {
            try BGTaskScheduler.shared.submit(request)
            UserDefaults.standard.set(date.formatted(.iso8601), forKey: lastScheduleKey)
            UserDefaults.standard.removeObject(forKey: lastErrorKey)
            logger.info("Scheduled app refresh for after \(date.formatted(.iso8601), privacy: .public).")
        } catch {
            UserDefaults.standard.set(String(describing: error), forKey: lastErrorKey)
            logger.error("Unable to schedule app refresh: \(String(describing: error), privacy: .public)")
        }
    }

    static func pendingRequestDescription() async -> String {
        await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                let matching = requests.filter { $0.identifier == identifier }
                guard let request = matching.first else {
                    continuation.resume(returning: "No pending request")
                    return
                }
                let date = request.earliestBeginDate?.formatted(.iso8601) ?? "unspecified"
                continuation.resume(returning: "Pending; earliest start: \(date)")
            }
        }
    }

    static func logRunStarted() {
        logger.info("Background sync task started.")
    }

    static func logRunFinished() {
        logger.info("Background sync task finished.")
    }
}

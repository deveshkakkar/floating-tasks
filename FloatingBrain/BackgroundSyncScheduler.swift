import BackgroundTasks
import Foundation
import OSLog

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

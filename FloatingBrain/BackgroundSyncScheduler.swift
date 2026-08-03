import BackgroundTasks
import Foundation
import OSLog

enum BackgroundSyncScheduler {
    static let identifier = "com.floatingbrain.app.refresh"
    private static let interval: TimeInterval = 15 * 60
    private static let logger = Logger(subsystem: "com.floatingbrain.app", category: "BackgroundSync")

    static func schedule(after date: Date = Date().addingTimeInterval(interval)) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled app refresh for after \(date.formatted(.iso8601), privacy: .public).")
        } catch {
            logger.error("Unable to schedule app refresh: \(String(describing: error), privacy: .public)")
        }
    }

    static func logRunStarted() {
        logger.info("Background sync task started.")
    }

    static func logRunFinished() {
        logger.info("Background sync task finished.")
    }
}

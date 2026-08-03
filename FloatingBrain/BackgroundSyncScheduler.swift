import BackgroundTasks
import Foundation

enum BackgroundSyncScheduler {
    static let identifier = "com.floatingbrain.app.refresh"
    private static let interval: TimeInterval = 15 * 60

    static func schedule(after date: Date = Date().addingTimeInterval(interval)) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        try? BGTaskScheduler.shared.submit(request)
    }
}

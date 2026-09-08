import XCTest
@testable import FloatingBrain

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testAuthorizedReminderListUpdatesDashboardCounts() async {
        let service = MockReminderAccessService(
            status: .authorized,
            snapshot: ReminderListSnapshot(listName: "Floating Brain", activeCount: 3, completedCount: 2)
        )
        let notificationScheduler = MockTaskNotificationScheduler()
        let viewModel = DashboardViewModel(
            reminderService: service,
            taskNotificationScheduler: notificationScheduler
        )

        await viewModel.refreshReminderStatus()

        XCTAssertEqual(viewModel.state.selectedListName, "Floating Brain")
        XCTAssertEqual(viewModel.state.activeReminderCount, 3)
        XCTAssertEqual(viewModel.state.completedReminderCount, 2)
        XCTAssertNil(viewModel.reminderError)
        XCTAssertEqual(notificationScheduler.scheduledTaskCount, 0)
    }

    func testDeniedAccessDoesNotAttemptToReadList() async {
        let service = MockReminderAccessService(status: .denied, snapshot: nil)
        let viewModel = DashboardViewModel(reminderService: service)

        await viewModel.refreshReminderStatus()

        XCTAssertEqual(viewModel.state.remindersPermission, .denied)
        XCTAssertFalse(service.didReadList)
    }
}

private final class MockTaskNotificationScheduler: TaskNotificationScheduling {
    private(set) var scheduledTaskCount: Int?

    func scheduleDailyTaskNotification(for tasks: [SyncReminder]) async throws {
        scheduledTaskCount = tasks.count
    }
}

private final class MockReminderAccessService: ReminderAccessService {
    let status: PermissionStatus
    let snapshot: ReminderListSnapshot?
    private(set) var didReadList = false

    init(status: PermissionStatus, snapshot: ReminderListSnapshot?) {
        self.status = status
        self.snapshot = snapshot
    }

    func authorizationStatus() -> PermissionStatus { status }

    func requestAccess() async throws -> Bool { status == .authorized }

    func readFloatingBrainList() async throws -> ReminderListSnapshot {
        didReadList = true
        guard let snapshot else { throw ReminderAccessError.listNotFound }
        return snapshot
    }

    func readFloatingBrainReminders() async throws -> [SyncReminder] { [] }

    func completeReminder(withID externalID: String) async throws {}
}

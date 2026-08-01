import XCTest
@testable import FloatingBrain

final class SyncStateTests: XCTestCase {
    func testSyncRequiresBothRemindersPermissionAndAuthentication() {
        var state = SyncState()
        XCTAssertFalse(state.canSync)

        state.remindersPermission = .authorized
        XCTAssertFalse(state.canSync)

        state.authentication = .signedIn
        XCTAssertTrue(state.canSync)
    }

    func testDefaultStateIsSafeAndUnconfigured() {
        let state = SyncState()

        XCTAssertEqual(state.remindersPermission, .notDetermined)
        XCTAssertEqual(state.authentication, .signedOut)
        XCTAssertNil(state.selectedListName)
        XCTAssertEqual(state.activeReminderCount, 0)
        XCTAssertEqual(state.completedReminderCount, 0)
        XCTAssertEqual(state.result, .never)
    }

    func testUnconfiguredServiceReturnsActionableFailure() async {
        let result = await UnconfiguredReminderSyncService().sync()

        XCTAssertEqual(result, .failed(message: "Sync is not configured yet."))
    }
}

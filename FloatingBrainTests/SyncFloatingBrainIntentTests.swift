import XCTest
@testable import FloatingBrain

final class SyncFloatingBrainIntentTests: XCTestCase {
    func testIntentFailsClearlyUntilSyncHandlerIsConfigured() async {
        await SyncIntentHandler.shared.clear()

        do {
            try await SyncIntentHandler.shared.run()
            XCTFail("Expected the unconfigured intent to fail")
        } catch {
            XCTAssertEqual(error as? SyncIntentError, .notConfigured)
        }
    }

    func testIntentHandlerRunsRegisteredOperation() async throws {
        actor CallCounter {
            var count = 0
            func increment() { count += 1 }
            func value() -> Int { count }
        }
        let counter = CallCounter()
        await SyncIntentHandler.shared.register {
            await counter.increment()
        }

        try await SyncIntentHandler.shared.run()

        let callCount = await counter.value()
        XCTAssertEqual(callCount, 1)
        await SyncIntentHandler.shared.clear()
    }
}

import XCTest
@testable import FloatingBrain

final class ReminderSyncAPIClientTests: XCTestCase {
    func testRequestUsesAuthenticatedSyncEndpointAndPayload() throws {
        let reminder = SyncReminder(externalID: "id", text: "Think", completed: false, createdAt: nil, modifiedAt: nil, dueAt: nil, priority: 0)
        let request = try ReminderSyncAPIRequestBuilder(baseURL: URL(string: "https://api.example.com")!).build(
            reminders: [reminder],
            listName: "Floating Brain",
            accessToken: "access-token"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/reminders/sync")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertTrue(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("Think"))
    }

    func testRequestOmitsCompletedReminders() throws {
        let active = SyncReminder(externalID: "active", text: "Keep", completed: false, createdAt: nil, modifiedAt: nil, dueAt: nil, priority: 0)
        let completed = SyncReminder(externalID: "completed", text: "Done", completed: true, createdAt: nil, modifiedAt: nil, dueAt: nil, priority: 0)
        let request = try ReminderSyncAPIRequestBuilder(baseURL: URL(string: "https://api.example.com")!).build(
            reminders: [active, completed], listName: "Floating Brain", accessToken: "access-token"
        )

        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("active"))
        XCTAssertFalse(body.contains("completed"))
        XCTAssertFalse(body.contains("Done"))
    }

    func testEmptyAccessTokenIsRejectedBeforeCreatingRequest() {
        XCTAssertThrowsError(
            try ReminderSyncAPIRequestBuilder(baseURL: URL(string: "https://api.example.com")!).build(
                reminders: [], listName: "Floating Brain", accessToken: ""
            )
        ) { error in
            XCTAssertEqual(error as? ReminderSyncAPIError, .missingAccessToken)
        }
    }

    func testRetryPolicyRetriesTransientFailuresOnly() {
        let policy = SyncRetryPolicy(maxAttempts: 3, baseDelayNanoseconds: 10)

        XCTAssertTrue(ReminderSyncAPIError.serverError(statusCode: 503).isRetryable)
        XCTAssertTrue(ReminderSyncAPIError.serverError(statusCode: 429).isRetryable)
        XCTAssertTrue(ReminderSyncAPIError.transport("offline").isRetryable)
        XCTAssertFalse(ReminderSyncAPIError.serverError(statusCode: 400).isRetryable)
        XCTAssertFalse(ReminderSyncAPIError.missingAccessToken.isRetryable)
        XCTAssertEqual(policy.delay(forRetryNumber: 1), 0)
        XCTAssertEqual(policy.delay(forRetryNumber: 2), 10)
    }
}

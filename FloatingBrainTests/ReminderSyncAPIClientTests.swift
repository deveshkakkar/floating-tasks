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

    func testRequestSeparatesActiveRemindersFromCompletionHistory() throws {
        let active = SyncReminder(externalID: "active", text: "Keep", completed: false, createdAt: nil, modifiedAt: nil, dueAt: nil, priority: 0)
        let completed = SyncReminder(externalID: "completed", text: "Done", completed: true, createdAt: nil, modifiedAt: nil, dueAt: nil, priority: 0)
        let request = try ReminderSyncAPIRequestBuilder(baseURL: URL(string: "https://api.example.com")!).build(
            reminders: [active, completed], listName: "Floating Brain", accessToken: "access-token"
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let body = try decoder.decode(ReminderSyncRequest.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.items, [active])
        XCTAssertEqual(body.completedItems, [completed])
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

    func testActiveRequestUsesAuthenticatedReadEndpoint() throws {
        let request = try ReminderSyncAPIRequestBuilder(baseURL: URL(string: "https://api.example.com")!).buildActiveRequest(
            accessToken: "access-token"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/reminders/active?limit=25")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
    }

    func testDailyRequestUsesAuthenticatedReadEndpoint() throws {
        let request = try ReminderSyncAPIRequestBuilder(baseURL: URL(string: "https://api.example.com")!).buildDailyRequest(
            accessToken: "access-token"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/reminders/daily")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
    }

    func testActiveRequestSupportsPaginationParameters() throws {
        let cursor = "cursor/value?part=1&next=%23#section with space"
        let request = try ReminderSyncAPIRequestBuilder(baseURL: URL(string: "https://api.example.com")!).buildActiveRequest(
            accessToken: "access-token",
            limit: 25,
            cursor: cursor
        )

        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/v1/reminders/active")
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "cursor", value: cursor)
        ])
        XCTAssertNil(components.fragment)
    }

    func testArchivedRequestUsesAuthenticatedReadEndpoint() throws {
        let request = try ReminderSyncAPIRequestBuilder(baseURL: URL(string: "https://api.example.com")!).buildArchivedRequest(
            accessToken: "access-token"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/reminders/archived")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
    }

    func testRestoreRequestCarriesExternalIDAndAuthentication() throws {
        let request = try ReminderSyncAPIRequestBuilder(baseURL: URL(string: "https://api.example.com")!).buildRestoreRequest(
            externalID: "old-task", accessToken: "access-token"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/reminders/restore")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertTrue(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("old-task"))
    }

    func testCaptureRequestUsesAuthenticatedEndpointAndISO8601Date() throws {
        let capture = CapturedTask(text: "Capture this")
        let request = try ReminderSyncAPIRequestBuilder(baseURL: URL(string: "https://api.example.com")!).buildCaptureRequest(
            tasks: [capture],
            accessToken: "access-token"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/items/capture")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertTrue(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("capturedAt"))
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

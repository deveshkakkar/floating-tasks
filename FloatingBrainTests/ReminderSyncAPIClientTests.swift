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

    func testEmptyAccessTokenIsRejectedBeforeCreatingRequest() {
        XCTAssertThrowsError(
            try ReminderSyncAPIRequestBuilder(baseURL: URL(string: "https://api.example.com")!).build(
                reminders: [], listName: "Floating Brain", accessToken: ""
            )
        ) { error in
            XCTAssertEqual(error as? ReminderSyncAPIError, .missingAccessToken)
        }
    }
}

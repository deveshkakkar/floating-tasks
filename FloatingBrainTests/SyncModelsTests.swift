import XCTest
@testable import FloatingBrain

final class SyncModelsTests: XCTestCase {
    func testPayloadUsesBackendFieldNamesAndISO8601Dates() throws {
        let request = ReminderSyncRequest(
            syncID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            generatedAt: Date(timeIntervalSince1970: 0),
            listName: "Floating Brain",
            items: [
                SyncReminder(
                    externalID: "apple-1",
                    text: "Replace the bedroom air filter",
                    completed: false,
                    createdAt: Date(timeIntervalSince1970: 0),
                    modifiedAt: nil,
                    dueAt: nil,
                    priority: 1
                )
            ]
        )

        let data = try SyncPayloadEncoder().encode(request)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(
            json,
            "{\"generatedAt\":\"1970-01-01T00:00:00Z\",\"items\":[{\"completed\":false,\"createdAt\":\"1970-01-01T00:00:00Z\",\"dueAt\":null,\"externalId\":\"apple-1\",\"modifiedAt\":null,\"priority\":1,\"text\":\"Replace the bedroom air filter\"}],\"listName\":\"Floating Brain\",\"syncId\":\"00000000-0000-0000-0000-000000000001\"}"
        )
    }

    func testPayloadRoundTripsWithoutChangingReminderData() throws {
        let reminder = SyncReminder(
            externalID: "apple-2",
            text: "Read the whole note",
            completed: true,
            createdAt: nil,
            modifiedAt: Date(timeIntervalSince1970: 42),
            dueAt: Date(timeIntervalSince1970: 84),
            priority: 0
        )
        let request = ReminderSyncRequest(syncID: UUID(), generatedAt: Date(timeIntervalSince1970: 10), listName: "Floating Brain", items: [reminder])

        let data = try SyncPayloadEncoder().encode(request)
        let decoded = try JSONDecoder.iso8601.decode(ReminderSyncRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

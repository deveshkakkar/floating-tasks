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

    func testDailySelectionResponsePreservesServerOrdering() throws {
        let data = Data("""
        {
          "date": "2026-08-18",
          "generatedAt": "2026-08-18T06:00:00Z",
          "items": [
            {"slot": 2, "externalId": "two", "text": "Two", "priority": 1},
            {"slot": 1, "externalId": "one", "text": "One", "priority": 0}
          ]
        }
        """.utf8)

        let response = try JSONDecoder.iso8601.decode(DailySelectionResponse.self, from: data)

        XCTAssertEqual(response.items.map(\.slot), [2, 1])
        XCTAssertEqual(response.items[0].reminder.externalID, "two")
        XCTAssertEqual(response.items[0].reminder.priority, 1)
    }

    func testWidgetTaskStoreRoundTripsTasks() {
        let suiteName = "FloatingBrainWidgetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tasks = [WidgetTask(id: "task-1", text: "Walk the dog", priority: 1)]
        WidgetTaskStore(defaults: defaults).save(tasks)

        XCTAssertEqual(WidgetTaskStore(defaults: defaults).load(), tasks)
    }

    func testExistingTaskDataDefaultsToNotCompleted() throws {
        let data = Data("{\"id\":\"task-1\",\"text\":\"Keep going\",\"priority\":0}".utf8)

        XCTAssertEqual(
            try JSONDecoder().decode(DailyTask.self, from: data),
            DailyTask(id: "task-1", text: "Keep going", priority: 0)
        )
    }

}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

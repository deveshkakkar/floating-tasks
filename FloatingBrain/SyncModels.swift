import Foundation

struct SyncReminder: Codable, Equatable, Identifiable {
    let externalID: String
    let text: String
    let completed: Bool
    let createdAt: Date?
    let modifiedAt: Date?
    let dueAt: Date?
    let priority: Int

    var id: String { externalID }

    enum CodingKeys: String, CodingKey {
        case externalID = "externalId"
        case text
        case completed
        case createdAt
        case modifiedAt
        case dueAt
        case priority
    }
}

struct ReminderSyncRequest: Codable, Equatable {
    let syncID: UUID
    let generatedAt: Date
    let listName: String
    let items: [SyncReminder]

    enum CodingKeys: String, CodingKey {
        case syncID = "syncId"
        case generatedAt
        case listName
        case items
    }
}

struct SyncPayloadEncoder {
    private let encoder: JSONEncoder

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    func encode(_ request: ReminderSyncRequest) throws -> Data {
        try encoder.encode(request)
    }
}

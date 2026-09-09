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

struct ArchivedReminder: Decodable, Equatable, Identifiable {
    let externalID: String
    let text: String
    let source: String?
    let createdAt: Date?
    let modifiedAt: Date?
    let dueAt: Date?
    let priority: Int

    var id: String { externalID }

    enum CodingKeys: String, CodingKey {
        case externalID = "externalId"
        case text, source, createdAt, modifiedAt, dueAt, priority
    }
}

struct DailySelectionResponse: Decodable, Equatable {
    let date: String
    let generatedAt: Date
    let items: [DailySelectionItem]
}

struct DailySelectionItem: Decodable, Equatable {
    let slot: Int
    let externalID: String
    let text: String
    let priority: Int

    enum CodingKeys: String, CodingKey {
        case slot
        case externalID = "externalId"
        case text
        case priority
    }

    var reminder: SyncReminder {
        SyncReminder(
            externalID: externalID,
            text: text,
            completed: false,
            createdAt: nil,
            modifiedAt: nil,
            dueAt: nil,
            priority: priority
        )
    }
}

struct BackendDiagnostics: Equatable {
    enum State: String {
        case notChecked = "Not checked"
        case configured = "Healthy"
        case unauthenticated = "Authentication required"
        case unavailable = "Unavailable"
        case invalidResponse = "Invalid response"
        case unconfigured = "Not configured"
    }

    let state: State
    let message: String
    let checkedAt: Date?
    let latencyMilliseconds: Int?
    let selectionDate: String?
    let selectionTaskCount: Int?

    static let notChecked = BackendDiagnostics(
        state: .notChecked,
        message: "Run a backend check to verify the authenticated API and daily selection.",
        checkedAt: nil,
        latencyMilliseconds: nil,
        selectionDate: nil,
        selectionTaskCount: nil
    )
}

struct ReminderSyncRequest: Codable, Equatable {
    let syncID: UUID
    let generatedAt: Date
    let listName: String
    let items: [SyncReminder]
    let completedItems: [SyncReminder]

    init(syncID: UUID, generatedAt: Date, listName: String, items: [SyncReminder], completedItems: [SyncReminder] = []) {
        self.syncID = syncID
        self.generatedAt = generatedAt
        self.listName = listName
        self.items = items
        self.completedItems = completedItems
    }

    enum CodingKeys: String, CodingKey {
        case syncID = "syncId"
        case generatedAt
        case listName
        case items
        case completedItems
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

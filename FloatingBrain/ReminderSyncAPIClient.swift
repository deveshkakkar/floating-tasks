import Foundation

struct ReminderSyncAPIRequestBuilder {
    let baseURL: URL

    func build(reminders: [SyncReminder], listName: String, accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw ReminderSyncAPIError.missingAccessToken }
        let endpoint = baseURL.appendingPathComponent("v1/reminders/sync")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try SyncPayloadEncoder().encode(
            ReminderSyncRequest(syncID: UUID(), generatedAt: Date(), listName: listName, items: reminders)
        )
        return request
    }
}

enum ReminderSyncAPIError: LocalizedError, Equatable {
    case missingAccessToken
    case invalidResponse
    case serverError(statusCode: Int)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            "Sign in before syncing."
        case .invalidResponse:
            "The sync service returned an invalid response."
        case let .serverError(statusCode):
            "Sync failed with status \(statusCode)."
        case let .transport(message):
            message
        }
    }
}

struct ReminderSyncAPIClient: ReminderSyncService {
    let baseURL: URL
    let tokenStore: any TokenStore
    let session: URLSession

    init(baseURL: URL, tokenStore: any TokenStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session
    }

    func sync(reminders: [SyncReminder], listName: String) async -> SyncResult {
        do {
            guard let tokens = try tokenStore.load() else {
                throw ReminderSyncAPIError.missingAccessToken
            }
            let request = try ReminderSyncAPIRequestBuilder(baseURL: baseURL).build(
                reminders: reminders,
                listName: listName,
                accessToken: tokens.accessToken
            )
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReminderSyncAPIError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ReminderSyncAPIError.serverError(statusCode: httpResponse.statusCode)
            }
            return .succeeded(date: Date())
        } catch let error as ReminderSyncAPIError {
            return .failed(message: error.localizedDescription)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}

import Foundation

struct ReminderSyncAPIRequestBuilder {
    let baseURL: URL

    func build(reminders: [SyncReminder], listName: String, accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw ReminderSyncAPIError.missingAccessToken }
        let endpoint = baseURL.appendingPathComponent("v1/reminders/sync")
        let activeReminders = reminders.filter { !$0.completed }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try SyncPayloadEncoder().encode(
            ReminderSyncRequest(syncID: UUID(), generatedAt: Date(), listName: listName, items: activeReminders)
        )
        return request
    }
}

enum ReminderSyncAPIError: LocalizedError, Equatable {
    case missingAccessToken
    case invalidResponse
    case serverError(statusCode: Int)
    case transport(String)

    var isRetryable: Bool {
        switch self {
        case .invalidResponse, .transport:
            true
        case let .serverError(statusCode):
            statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        case .missingAccessToken:
            false
        }
    }

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

struct SyncRetryPolicy: Equatable {
    let maxAttempts: Int
    let baseDelayNanoseconds: UInt64

    init(maxAttempts: Int = 3, baseDelayNanoseconds: UInt64 = 500_000_000) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelayNanoseconds = baseDelayNanoseconds
    }

    func delay(forRetryNumber retryNumber: Int) -> UInt64 {
        baseDelayNanoseconds * UInt64(max(0, retryNumber - 1))
    }
}

struct ReminderSyncAPIClient: ReminderSyncService {
    let baseURL: URL
    let tokenStore: any TokenStore
    let tokenRefresher: (any CognitoTokenRefreshing)?
    let session: URLSession
    let retryPolicy: SyncRetryPolicy

    init(baseURL: URL, tokenStore: any TokenStore, tokenRefresher: (any CognitoTokenRefreshing)? = nil, session: URLSession = .shared, retryPolicy: SyncRetryPolicy = SyncRetryPolicy()) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.tokenRefresher = tokenRefresher
        self.session = session
        self.retryPolicy = retryPolicy
    }

    func sync(reminders: [SyncReminder], listName: String) async -> SyncResult {
        do {
            guard let tokens = try tokenStore.load() else {
                throw ReminderSyncAPIError.missingAccessToken
            }
            var accessToken = tokens.accessToken
            var didRefreshToken = false
            for attempt in 1...retryPolicy.maxAttempts {
                do {
                    let request = try ReminderSyncAPIRequestBuilder(baseURL: baseURL).build(
                        reminders: reminders,
                        listName: listName,
                        accessToken: accessToken
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
                    if case .serverError(401) = error,
                       !didRefreshToken,
                       let refreshToken = tokens.refreshToken,
                       let tokenRefresher {
                        let refreshedTokens = try await tokenRefresher.refreshAccessToken(using: refreshToken)
                        accessToken = refreshedTokens.accessToken
                        didRefreshToken = true
                        continue
                    }
                    guard error.isRetryable, attempt < retryPolicy.maxAttempts else { throw error }
                    try? await Task.sleep(nanoseconds: retryPolicy.delay(forRetryNumber: attempt))
                } catch {
                    guard attempt < retryPolicy.maxAttempts else {
                        throw ReminderSyncAPIError.transport(error.localizedDescription)
                    }
                    try? await Task.sleep(nanoseconds: retryPolicy.delay(forRetryNumber: attempt))
                }
            }
            throw ReminderSyncAPIError.invalidResponse
        } catch let error as ReminderSyncAPIError {
            return .failed(message: error.localizedDescription)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}

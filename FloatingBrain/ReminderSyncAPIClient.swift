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

    func buildActiveRequest(accessToken: String, limit: Int = 25, cursor: String? = nil) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw ReminderSyncAPIError.missingAccessToken }
        let endpoint = baseURL.appendingPathComponent("v1/reminders/active")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw ReminderSyncAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    func buildArchivedRequest(accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw ReminderSyncAPIError.missingAccessToken }
        let endpoint = baseURL.appendingPathComponent("v1/reminders/archived")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    func buildRestoreRequest(externalID: String, accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw ReminderSyncAPIError.missingAccessToken }
        let endpoint = baseURL.appendingPathComponent("v1/reminders/restore")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["externalId": externalID])
        return request
    }

    func buildDailyRequest(accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw ReminderSyncAPIError.missingAccessToken }
        let endpoint = baseURL.appendingPathComponent("v1/reminders/daily")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    func buildCaptureRequest(tasks: [CapturedTask], accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else { throw ReminderSyncAPIError.missingAccessToken }
        let endpoint = baseURL.appendingPathComponent("v1/items/capture")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(CaptureRequest(items: tasks))
        return request
    }
}

private struct CaptureRequest: Encodable {
    let items: [CapturedTask]
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

    func fetchActiveReminders() async throws -> [SyncReminder] {
        guard let tokens = try tokenStore.load() else {
            throw ReminderSyncAPIError.missingAccessToken
        }

        var accessToken = tokens.accessToken
        var didRefreshToken = false
        var cursor: String?
        var reminders: [SyncReminder] = []
        while true {
            let request = try ReminderSyncAPIRequestBuilder(baseURL: baseURL).buildActiveRequest(accessToken: accessToken, cursor: cursor)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReminderSyncAPIError.invalidResponse
            }

            if httpResponse.statusCode == 401,
               !didRefreshToken,
               let refreshToken = tokens.refreshToken,
               let tokenRefresher {
                let refreshedTokens = try await tokenRefresher.refreshAccessToken(using: refreshToken)
                accessToken = refreshedTokens.accessToken
                didRefreshToken = true
                continue
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw ReminderSyncAPIError.serverError(statusCode: httpResponse.statusCode)
            }

            let page = try decodeReminderPage(data)
            reminders.append(contentsOf: page.items)
            guard let nextCursor = page.nextCursor else { return reminders }
            cursor = nextCursor
        }
    }

    func fetchDailyReminders() async throws -> [SyncReminder] {
        try await fetchDailySelection().items.sorted { $0.slot < $1.slot }.map { $0.reminder }
    }

    func checkBackend() async -> BackendDiagnostics {
        let startedAt = Date()
        do {
            let selection = try await fetchDailySelection()
            return BackendDiagnostics(
                state: .configured,
                message: "Authenticated API responded successfully.",
                checkedAt: Date(),
                latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
                selectionDate: selection.date,
                selectionTaskCount: selection.items.count
            )
        } catch let error as ReminderSyncAPIError {
            let state: BackendDiagnostics.State
            switch error {
            case .missingAccessToken:
                state = .unauthenticated
            case .serverError(401):
                state = .unauthenticated
            case .invalidResponse:
                state = .invalidResponse
            default:
                state = .unavailable
            }
            return BackendDiagnostics(
                state: state,
                message: error.localizedDescription,
                checkedAt: Date(),
                latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
                selectionDate: nil,
                selectionTaskCount: nil
            )
        } catch {
            return BackendDiagnostics(
                state: .unavailable,
                message: error.localizedDescription,
                checkedAt: Date(),
                latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
                selectionDate: nil,
                selectionTaskCount: nil
            )
        }
    }

    private func fetchDailySelection() async throws -> DailySelectionResponse {
        guard let tokens = try tokenStore.load() else {
            throw ReminderSyncAPIError.missingAccessToken
        }

        var accessToken = tokens.accessToken
        var didRefreshToken = false
        while true {
            let request = try ReminderSyncAPIRequestBuilder(baseURL: baseURL).buildDailyRequest(accessToken: accessToken)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReminderSyncAPIError.invalidResponse
            }
            if httpResponse.statusCode == 401,
               !didRefreshToken,
               let refreshToken = tokens.refreshToken,
               let tokenRefresher {
                let refreshedTokens = try await tokenRefresher.refreshAccessToken(using: refreshToken)
                accessToken = refreshedTokens.accessToken
                didRefreshToken = true
                continue
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ReminderSyncAPIError.serverError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(DailySelectionResponse.self, from: data)
        }
    }

    func fetchActiveRemindersPage(limit: Int, cursor: String?) async throws -> ReminderPage {
        guard let tokens = try tokenStore.load() else {
            throw ReminderSyncAPIError.missingAccessToken
        }

        var accessToken = tokens.accessToken
        var didRefreshToken = false
        while true {
            let request = try ReminderSyncAPIRequestBuilder(baseURL: baseURL).buildActiveRequest(
                accessToken: accessToken,
                limit: limit,
                cursor: cursor
            )
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReminderSyncAPIError.invalidResponse
            }
            if httpResponse.statusCode == 401,
               !didRefreshToken,
               let refreshToken = tokens.refreshToken,
               let tokenRefresher {
                let refreshedTokens = try await tokenRefresher.refreshAccessToken(using: refreshToken)
                accessToken = refreshedTokens.accessToken
                didRefreshToken = true
                continue
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ReminderSyncAPIError.serverError(statusCode: httpResponse.statusCode)
            }
            return try decodeReminderPage(data)
        }
    }

    func fetchArchivedReminders() async throws -> [ArchivedReminder] {
        guard let tokens = try tokenStore.load() else { throw ReminderSyncAPIError.missingAccessToken }
        var accessToken = tokens.accessToken
        var didRefreshToken = false
        while true {
            let request = try ReminderSyncAPIRequestBuilder(baseURL: baseURL).buildArchivedRequest(accessToken: accessToken)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw ReminderSyncAPIError.invalidResponse }
            if httpResponse.statusCode == 401, !didRefreshToken, let refreshToken = tokens.refreshToken, let tokenRefresher {
                let refreshedTokens = try await tokenRefresher.refreshAccessToken(using: refreshToken)
                accessToken = refreshedTokens.accessToken
                didRefreshToken = true
                continue
            }
            guard (200...299).contains(httpResponse.statusCode) else { throw ReminderSyncAPIError.serverError(statusCode: httpResponse.statusCode) }
            struct Response: Decodable { let items: [ArchivedReminder] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Response.self, from: data).items
        }
    }

    func restoreReminder(withID externalID: String) async throws {
        guard let tokens = try tokenStore.load() else { throw ReminderSyncAPIError.missingAccessToken }
        var accessToken = tokens.accessToken
        var didRefreshToken = false
        while true {
            let request = try ReminderSyncAPIRequestBuilder(baseURL: baseURL).buildRestoreRequest(externalID: externalID, accessToken: accessToken)
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw ReminderSyncAPIError.invalidResponse }
            if httpResponse.statusCode == 401, !didRefreshToken, let refreshToken = tokens.refreshToken, let tokenRefresher {
                let refreshedTokens = try await tokenRefresher.refreshAccessToken(using: refreshToken)
                accessToken = refreshedTokens.accessToken
                didRefreshToken = true
                continue
            }
            guard (200...299).contains(httpResponse.statusCode) else { throw ReminderSyncAPIError.serverError(statusCode: httpResponse.statusCode) }
            return
        }
    }

    private func decodeReminderPage(_ data: Data) throws -> ReminderPage {
        struct ActiveReminderResponse: Decodable {
            let items: [SyncReminder]
            let nextCursor: String?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(ActiveReminderResponse.self, from: data)
        return ReminderPage(items: response.items, nextCursor: response.nextCursor)
    }

    func capture(tasks: [CapturedTask]) async throws {
        guard !tasks.isEmpty else { return }
        guard let tokens = try tokenStore.load() else {
            throw ReminderSyncAPIError.missingAccessToken
        }

        var accessToken = tokens.accessToken
        var didRefreshToken = false
        while true {
            let request = try ReminderSyncAPIRequestBuilder(baseURL: baseURL).buildCaptureRequest(
                tasks: tasks,
                accessToken: accessToken
            )
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReminderSyncAPIError.invalidResponse
            }

            if httpResponse.statusCode == 401,
               !didRefreshToken,
               let refreshToken = tokens.refreshToken,
               let tokenRefresher {
                let refreshedTokens = try await tokenRefresher.refreshAccessToken(using: refreshToken)
                accessToken = refreshedTokens.accessToken
                didRefreshToken = true
                continue
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw ReminderSyncAPIError.serverError(statusCode: httpResponse.statusCode)
            }
            return
        }
    }
}

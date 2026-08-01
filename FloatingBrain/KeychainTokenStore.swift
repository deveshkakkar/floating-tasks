import Foundation
import Security

enum KeychainTokenStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidToken
}

struct AuthTokens: Equatable {
    let accessToken: String
    let refreshToken: String?

    init(accessToken: String, refreshToken: String? = nil) throws {
        guard !accessToken.isEmpty else { throw KeychainTokenStoreError.invalidToken }
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

protocol TokenStore {
    func save(_ tokens: AuthTokens) throws
    func load() throws -> AuthTokens?
    func clear() throws
}

final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    init(service: String = "com.floatingbrain.app", account: String = "cognito.tokens") {
        self.service = service
        self.account = account
    }

    func save(_ tokens: AuthTokens) throws {
        let payload = try JSONEncoder().encode(TokenPayload(tokens: tokens))
        let query = baseQuery()
        let attributes: [CFString: Any] = [kSecValueData: payload]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertQuery = query
            insertQuery[kSecValueData as String] = payload
            let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw KeychainTokenStoreError.unexpectedStatus(insertStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainTokenStoreError.unexpectedStatus(updateStatus)
        }
    }

    func load() throws -> AuthTokens? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainTokenStoreError.unexpectedStatus(errSecDecode)
        }

        let payload = try JSONDecoder().decode(TokenPayload.self, from: data)
        return try AuthTokens(accessToken: payload.accessToken, refreshToken: payload.refreshToken)
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}

private struct TokenPayload: Codable {
    let accessToken: String
    let refreshToken: String?

    init(tokens: AuthTokens) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
    }
}

import Foundation

struct CognitoTokenRequestBuilder {
    let configuration: CognitoConfiguration

    func buildAuthorizationCodeRequest(code: String, verifier: String) throws -> URLRequest {
        guard !code.isEmpty, !verifier.isEmpty else {
            throw CognitoTokenClientError.invalidResponse
        }

        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            ("grant_type", "authorization_code"),
            ("client_id", configuration.clientID),
            ("code", code),
            ("redirect_uri", configuration.redirectURI),
            ("code_verifier", verifier)
        ]).data(using: .utf8)
        return request
    }

    private func formEncoded(_ values: [(String, String)]) -> String {
        values.map { "\($0.0.urlFormEncoded)=\($0.1.urlFormEncoded)" }.joined(separator: "&")
    }
}

enum CognitoTokenClientError: LocalizedError, Equatable {
    case invalidResponse
    case serverError(statusCode: Int)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Cognito returned an invalid token response."
        case let .serverError(statusCode):
            "Cognito sign-in failed with status \(statusCode)."
        case let .transport(message):
            message
        }
    }
}

struct CognitoTokenClient {
    let configuration: CognitoConfiguration
    let tokenStore: any TokenStore
    let session: URLSession

    init(configuration: CognitoConfiguration, tokenStore: any TokenStore, session: URLSession = .shared) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.session = session
    }

    func exchangeAuthorizationCode(code: String, verifier: String) async throws -> AuthTokens {
        let request = try CognitoTokenRequestBuilder(configuration: configuration).buildAuthorizationCodeRequest(code: code, verifier: verifier)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CognitoTokenClientError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw CognitoTokenClientError.serverError(statusCode: httpResponse.statusCode)
            }

            let tokenResponse = try JSONDecoder().decode(CognitoTokenResponse.self, from: data)
            let tokens = try AuthTokens(accessToken: tokenResponse.accessToken, refreshToken: tokenResponse.refreshToken)
            try tokenStore.save(tokens)
            return tokens
        } catch let error as CognitoTokenClientError {
            throw error
        } catch let error as KeychainTokenStoreError {
            throw error
        } catch {
            throw CognitoTokenClientError.transport(error.localizedDescription)
        }
    }
}

private struct CognitoTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))) ?? self
    }
}

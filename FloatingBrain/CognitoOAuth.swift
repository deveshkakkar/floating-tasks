import CryptoKit
import Foundation
import Security

struct CognitoConfiguration: Equatable {
    let authorizationEndpoint: URL
    let clientID: String
    let redirectURI: String
    let scopes: [String]

    init(authorizationEndpoint: URL, clientID: String, redirectURI: String, scopes: [String] = ["openid", "email"]) throws {
        guard !clientID.isEmpty, !redirectURI.isEmpty else {
            throw CognitoOAuthError.invalidConfiguration
        }
        self.authorizationEndpoint = authorizationEndpoint
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
    }
}

struct PKCEChallenge: Equatable {
    let verifier: String
    let challenge: String

    static func generate() throws -> PKCEChallenge {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CognitoOAuthError.randomGenerationFailed
        }

        let verifier = Data(bytes).base64URLEncodedString
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return PKCEChallenge(verifier: verifier, challenge: Data(digest).base64URLEncodedString)
    }
}

struct CognitoAuthorizationRequest: Equatable {
    let url: URL
    let state: String
    let verifier: String
}

enum CognitoOAuthError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidAuthorizationURL
    case randomGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Cognito authentication is not configured yet."
        case .invalidAuthorizationURL:
            "The Cognito authorization URL could not be created."
        case .randomGenerationFailed:
            "Unable to create a secure sign-in challenge."
        }
    }
}

struct CognitoAuthorizationRequestBuilder {
    let configuration: CognitoConfiguration

    func build(state: String, challenge: PKCEChallenge) throws -> CognitoAuthorizationRequest {
        guard var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw CognitoOAuthError.invalidAuthorizationURL
        }

        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge.challenge)
        ]

        guard let url = components.url else {
            throw CognitoOAuthError.invalidAuthorizationURL
        }
        return CognitoAuthorizationRequest(url: url, state: state, verifier: challenge.verifier)
    }
}

private extension Data {
    var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

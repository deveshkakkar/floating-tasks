import AuthenticationServices
import Foundation

struct CognitoAuthorizationResult: Equatable {
    let authorizationCode: String
    let state: String
    let verifier: String
}

enum CognitoWebAuthenticationError: LocalizedError, Equatable {
    case cancelled
    case invalidCallback
    case stateMismatch
    case unableToStart

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Sign-in was cancelled."
        case .invalidCallback:
            "Cognito returned an invalid sign-in response."
        case .stateMismatch:
            "The sign-in response could not be verified."
        case .unableToStart:
            "Unable to start secure sign-in."
        }
    }
}

struct CognitoCallbackValidator {
    static func validate(url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw CognitoWebAuthenticationError.invalidCallback
        }

        if queryItems.first(where: { $0.name == "error" }) != nil {
            throw CognitoWebAuthenticationError.cancelled
        }

        guard queryItems.first(where: { $0.name == "state" })?.value == expectedState else {
            throw CognitoWebAuthenticationError.stateMismatch
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw CognitoWebAuthenticationError.invalidCallback
        }
        return code
    }
}

final class CognitoWebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let requestBuilder: CognitoAuthorizationRequestBuilder
    private let callbackURLScheme: String
    private let presentationAnchorProvider: () -> ASPresentationAnchor
    private var session: ASWebAuthenticationSession?

    init(
        requestBuilder: CognitoAuthorizationRequestBuilder,
        callbackURLScheme: String,
        presentationAnchorProvider: @escaping () -> ASPresentationAnchor
    ) {
        self.requestBuilder = requestBuilder
        self.callbackURLScheme = callbackURLScheme
        self.presentationAnchorProvider = presentationAnchorProvider
    }

    func authenticate() async throws -> CognitoAuthorizationResult {
        let challenge = try PKCEChallenge.generate()
        let state = UUID().uuidString
        let request = try requestBuilder.build(state: state, challenge: challenge)

        return try await withCheckedThrowingContinuation { continuation in
            let authenticationSession = ASWebAuthenticationSession(
                url: request.url,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                self?.session = nil
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: CognitoWebAuthenticationError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: CognitoWebAuthenticationError.invalidCallback)
                    return
                }

                do {
                    let code = try CognitoCallbackValidator.validate(url: callbackURL, expectedState: state)
                    continuation.resume(returning: CognitoAuthorizationResult(authorizationCode: code, state: state, verifier: challenge.verifier))
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            authenticationSession.presentationContextProvider = self
            authenticationSession.prefersEphemeralWebBrowserSession = false
            guard authenticationSession.start() else {
                continuation.resume(throwing: CognitoWebAuthenticationError.unableToStart)
                return
            }
            session = authenticationSession
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationAnchorProvider()
    }
}

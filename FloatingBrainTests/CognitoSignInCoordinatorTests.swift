import XCTest
@testable import FloatingBrain

final class CognitoSignInCoordinatorTests: XCTestCase {
    func testCoordinatorPassesCodeAndVerifierToTokenExchange() async throws {
        let authorization = CognitoAuthorizationResult(authorizationCode: "code", state: "state", verifier: "verifier")
        let provider = MockAuthorizationProvider(result: authorization)
        let exchanger = MockTokenExchanger(tokens: try AuthTokens(accessToken: "access", refreshToken: "refresh"))
        let coordinator = CognitoSignInCoordinator(authorizationProvider: provider, tokenExchanger: exchanger)

        let tokens = try await coordinator.signIn()

        XCTAssertEqual(tokens.accessToken, "access")
        XCTAssertEqual(exchanger.receivedCode, "code")
        XCTAssertEqual(exchanger.receivedVerifier, "verifier")
    }

    func testCoordinatorDoesNotExchangeWhenAuthorizationFails() async {
        let provider = MockAuthorizationProvider(error: CognitoWebAuthenticationError.cancelled)
        let exchanger = MockTokenExchanger(tokens: try! AuthTokens(accessToken: "access"))
        let coordinator = CognitoSignInCoordinator(authorizationProvider: provider, tokenExchanger: exchanger)

        do {
            _ = try await coordinator.signIn()
            XCTFail("Expected sign-in to fail")
        } catch {
            XCTAssertEqual(error as? CognitoWebAuthenticationError, .cancelled)
            XCTAssertNil(exchanger.receivedCode)
        }
    }
}

private struct MockAuthorizationProvider: CognitoAuthorizationCodeProvider {
    let result: CognitoAuthorizationResult?
    let error: Error?

    init(result: CognitoAuthorizationResult) {
        self.result = result
        error = nil
    }

    init(error: Error) {
        result = nil
        self.error = error
    }

    func authorize() async throws -> CognitoAuthorizationResult {
        if let error { throw error }
        return result!
    }
}

private final class MockTokenExchanger: CognitoTokenExchanging {
    let tokens: AuthTokens
    private(set) var receivedCode: String?
    private(set) var receivedVerifier: String?

    init(tokens: AuthTokens) { self.tokens = tokens }

    func exchangeAuthorizationCode(code: String, verifier: String) async throws -> AuthTokens {
        receivedCode = code
        receivedVerifier = verifier
        return tokens
    }
}

import XCTest
@testable import FloatingBrain

final class KeychainTokenStoreTests: XCTestCase {
    func testEmptyAccessTokensAreRejected() {
        XCTAssertThrowsError(try AuthTokens(accessToken: "")) { error in
            XCTAssertEqual(error as? KeychainTokenStoreError, .invalidToken)
        }
    }

    func testAuthenticationRestoresSignedOutWhenStoreIsEmpty() throws {
        let store = InMemoryTokenStore()
        let session = KeychainAuthenticationSession(tokenStore: store)

        XCTAssertEqual(try session.restore(), .signedOut)
        XCTAssertEqual(session.state, .signedOut)
    }

    func testAuthenticationSignsOutAndClearsStoredTokens() throws {
        let store = InMemoryTokenStore()
        try store.save(AuthTokens(accessToken: "access", refreshToken: "refresh"))
        let session = KeychainAuthenticationSession(tokenStore: store)

        XCTAssertEqual(try session.restore(), .signedIn)
        try session.signOut()

        XCTAssertEqual(session.state, .signedOut)
        XCTAssertNil(try store.load())
    }
}

private final class InMemoryTokenStore: TokenStore {
    private var tokens: AuthTokens?

    func save(_ tokens: AuthTokens) { self.tokens = tokens }
    func load() -> AuthTokens? { tokens }
    func clear() { tokens = nil }
}

import XCTest
@testable import FloatingBrain

final class CognitoOAuthTests: XCTestCase {
    func testAuthorizationRequestContainsPKCEAndNoClientSecret() throws {
        let configuration = try CognitoConfiguration(
            authorizationEndpoint: URL(string: "https://floating-brain.auth.us-west-2.amazoncognito.com/oauth2/authorize")!,
            tokenEndpoint: URL(string: "https://floating-brain.auth.us-west-2.amazoncognito.com/oauth2/token")!,
            clientID: "public-client",
            redirectURI: "floatingbrain://oauth/callback",
            scopes: ["openid", "email"]
        )
        let challenge = PKCEChallenge(verifier: "verifier", challenge: "challenge")
        let request = try CognitoAuthorizationRequestBuilder(configuration: configuration).build(state: "state-123", challenge: challenge)
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        XCTAssertEqual(request.verifier, "verifier")
        XCTAssertEqual(query.first(where: { $0.name == "response_type" })?.value, "code")
        XCTAssertEqual(query.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
        XCTAssertEqual(query.first(where: { $0.name == "code_challenge" })?.value, "challenge")
        XCTAssertFalse(request.url.absoluteString.contains("client_secret"))
    }

    func testGeneratedPKCEChallengeUsesURLSafeValues() throws {
        let challenge = try PKCEChallenge.generate()

        XCTAssertFalse(challenge.verifier.contains("+"))
        XCTAssertFalse(challenge.verifier.contains("/"))
        XCTAssertFalse(challenge.verifier.contains("="))
        XCTAssertFalse(challenge.challenge.contains("+"))
        XCTAssertFalse(challenge.challenge.contains("/"))
        XCTAssertFalse(challenge.challenge.contains("="))
    }

    func testMissingClientIDIsRejected() {
        XCTAssertThrowsError(
            try CognitoConfiguration(
                authorizationEndpoint: URL(string: "https://example.com/authorize")!,
                tokenEndpoint: URL(string: "https://example.com/token")!,
                clientID: "",
                redirectURI: "floatingbrain://oauth/callback"
            )
        ) { error in
            XCTAssertEqual(error as? CognitoOAuthError, .invalidConfiguration)
        }
    }
}

import XCTest
@testable import FloatingBrain

final class CognitoTokenClientTests: XCTestCase {
    func testAuthorizationCodeRequestUsesPKCEAndNoClientSecret() throws {
        let configuration = try CognitoConfiguration(
            authorizationEndpoint: URL(string: "https://example.com/authorize")!,
            tokenEndpoint: URL(string: "https://example.com/token")!,
            clientID: "public-client",
            redirectURI: "floatingbrain://oauth/callback"
        )

        let request = try CognitoTokenRequestBuilder(configuration: configuration).buildAuthorizationCodeRequest(code: "code value", verifier: "verifier")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("client_id=public-client"))
        XCTAssertTrue(body.contains("code=code%20value"))
        XCTAssertTrue(body.contains("code_verifier=verifier"))
        XCTAssertFalse(body.contains("client_secret"))
    }

    func testEmptyAuthorizationCodeIsRejected() throws {
        let configuration = try CognitoConfiguration(
            authorizationEndpoint: URL(string: "https://example.com/authorize")!,
            tokenEndpoint: URL(string: "https://example.com/token")!,
            clientID: "public-client",
            redirectURI: "floatingbrain://oauth/callback"
        )

        XCTAssertThrowsError(try CognitoTokenRequestBuilder(configuration: configuration).buildAuthorizationCodeRequest(code: "", verifier: "verifier")) { error in
            XCTAssertEqual(error as? CognitoTokenClientError, .invalidResponse)
        }
    }
}

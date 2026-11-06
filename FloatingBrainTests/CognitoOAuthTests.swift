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

final class FloatingBrainDeploymentConfigurationTests: XCTestCase {
    private var configuredValues: [String: Any] {
        [
            "FLOATING_BRAIN_API_URL": "https://api.example.com",
            "COGNITO_AUTHORIZATION_ENDPOINT": "https://auth.example.com/oauth2/authorize",
            "COGNITO_TOKEN_ENDPOINT": "https://auth.example.com/oauth2/token",
            "COGNITO_CLIENT_ID": "public-client"
        ]
    }

    func testCleanCheckoutAndPartialSettingsDoNotConfigureCloudServices() {
        XCTAssertNil(FloatingBrainDeploymentConfiguration(values: [:]))
        for key in configuredValues.keys {
            var values = configuredValues
            values[key] = "  "
            XCTAssertNil(FloatingBrainDeploymentConfiguration(values: values), key)
            values[key] = "$(\(key))"
            XCTAssertNil(FloatingBrainDeploymentConfiguration(values: values), key)
        }
    }

    func testCompletePublicClientConfigurationIsLoaded() throws {
        let deployment = try XCTUnwrap(FloatingBrainDeploymentConfiguration(values: configuredValues))
        XCTAssertEqual(deployment.syncAPIBaseURL.absoluteString, "https://api.example.com")
        XCTAssertEqual(deployment.cognitoConfiguration.clientID, "public-client")
        XCTAssertEqual(deployment.cognitoConfiguration.redirectURI, "floatingbrain://oauth/callback")
    }

    func testUnsafeAndPlaceholderEndpointsAreRejected() {
        for key in ["FLOATING_BRAIN_API_URL", "COGNITO_AUTHORIZATION_ENDPOINT", "COGNITO_TOKEN_ENDPOINT"] {
            for endpoint in ["http://api.example.com", "https://user:password@api.example.com", "https://api.example.com?token=value", "https://api.example.com#fragment", "https://api.example.invalid", "not-a-url"] {
                var values = configuredValues
                values[key] = endpoint
                XCTAssertNil(FloatingBrainDeploymentConfiguration(values: values), "\(key): \(endpoint)")
            }
        }
    }

    func testStageInAPIOriginAndMismatchedOAuthOriginsAreRejected() {
        var values = configuredValues
        values["FLOATING_BRAIN_API_URL"] = "https://api.example.com/v1"
        XCTAssertNil(FloatingBrainDeploymentConfiguration(values: values))
        values = configuredValues
        values["COGNITO_TOKEN_ENDPOINT"] = "https://other.example.com/oauth2/token"
        XCTAssertNil(FloatingBrainDeploymentConfiguration(values: values))
    }
}

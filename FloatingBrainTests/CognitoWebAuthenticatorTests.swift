import XCTest
@testable import FloatingBrain

final class CognitoWebAuthenticatorTests: XCTestCase {
    func testCallbackValidatorReturnsCodeForMatchingState() throws {
        let url = URL(string: "floatingbrain://oauth/callback?code=abc123&state=expected")!

        XCTAssertEqual(try CognitoCallbackValidator.validate(url: url, expectedState: "expected"), "abc123")
    }

    func testCallbackValidatorRejectsMismatchedState() {
        let url = URL(string: "floatingbrain://oauth/callback?code=abc123&state=wrong")!

        XCTAssertThrowsError(try CognitoCallbackValidator.validate(url: url, expectedState: "expected")) { error in
            XCTAssertEqual(error as? CognitoWebAuthenticationError, .stateMismatch)
        }
    }

    func testCallbackValidatorRejectsOAuthError() {
        let url = URL(string: "floatingbrain://oauth/callback?error=access_denied&state=expected")!

        XCTAssertThrowsError(try CognitoCallbackValidator.validate(url: url, expectedState: "expected")) { error in
            XCTAssertEqual(error as? CognitoWebAuthenticationError, .cancelled)
        }
    }
}

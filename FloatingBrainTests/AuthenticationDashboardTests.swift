import XCTest
@testable import FloatingBrain

@MainActor
final class AuthenticationDashboardTests: XCTestCase {
    func testUnconfiguredSignInLeavesAccountDisconnectedAndShowsError() async {
        let viewModel = DashboardViewModel()

        await viewModel.signIn()

        XCTAssertEqual(viewModel.state.authentication, .signedOut)
        XCTAssertEqual(viewModel.authenticationError, "Cognito authentication is not configured yet.")
    }
}

import AuthenticationServices
import SwiftUI
import UIKit

@main
struct FloatingBrainApp: App {
    @StateObject private var viewModel: DashboardViewModel

    init() {
        let tokenStore = KeychainTokenStore()

        if let configuration = FloatingBrainEnvironment.cognitoConfiguration {
            let authenticator = CognitoWebAuthenticator(
                requestBuilder: CognitoAuthorizationRequestBuilder(configuration: configuration),
                callbackURLScheme: FloatingBrainEnvironment.callbackURLScheme,
                presentationAnchorProvider: Self.presentationAnchor
            )
            let tokenClient = CognitoTokenClient(configuration: configuration, tokenStore: tokenStore)
            let signInService: any SignInService = CognitoSignInCoordinator(
                authorizationProvider: authenticator,
                tokenExchanger: tokenClient
            )
            let syncService: any ReminderSyncService = ReminderSyncAPIClient(
                baseURL: FloatingBrainEnvironment.syncAPIBaseURL,
                tokenStore: tokenStore
            )
            _viewModel = StateObject(wrappedValue: DashboardViewModel(
                syncService: syncService,
                signInService: signInService
            ))
        } else {
            _viewModel = StateObject(wrappedValue: DashboardViewModel())
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }

    private static func presentationAnchor() -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow()
    }
}

import BackgroundTasks
import AuthenticationServices
import SwiftUI
import UIKit

@main
struct FloatingBrainApp: App {
    @StateObject private var viewModel: DashboardViewModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let tokenStore = KeychainTokenStore()
        let authenticationSession = KeychainAuthenticationSession(tokenStore: tokenStore)
        var initialState = SyncState()
        if (try? authenticationSession.restore()) == .signedIn {
            initialState.authentication = .signedIn
        }

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
                state: initialState,
                syncService: syncService,
                signInService: signInService,
                authenticationSession: authenticationSession
            ))
        } else {
            _viewModel = StateObject(wrappedValue: DashboardViewModel(state: initialState, authenticationSession: authenticationSession))
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .backgroundTask(.appRefresh(BackgroundSyncScheduler.identifier)) {
            await viewModel.refreshReminderStatus()
            await viewModel.syncNow()
            BackgroundSyncScheduler.schedule()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background {
                BackgroundSyncScheduler.schedule()
            }
        }
    }

    private static func presentationAnchor() -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow()
    }
}

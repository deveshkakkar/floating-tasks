import Foundation

enum AuthenticationState: Equatable {
    case signedOut
    case signedIn
}

protocol AuthenticationSession {
    var state: AuthenticationState { get }
    func restore() throws -> AuthenticationState
    func signOut() throws
}

final class KeychainAuthenticationSession: AuthenticationSession {
    private let tokenStore: any TokenStore
    private(set) var state: AuthenticationState = .signedOut

    init(tokenStore: any TokenStore = KeychainTokenStore()) {
        self.tokenStore = tokenStore
    }

    @discardableResult
    func restore() throws -> AuthenticationState {
        state = try tokenStore.load() == nil ? .signedOut : .signedIn
        return state
    }

    func signOut() throws {
        try tokenStore.clear()
        state = .signedOut
    }
}

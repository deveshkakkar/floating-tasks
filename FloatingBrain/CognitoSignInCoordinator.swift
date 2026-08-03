import Foundation

protocol CognitoAuthorizationCodeProvider {
    func authorize() async throws -> CognitoAuthorizationResult
}

protocol CognitoTokenExchanging {
    func exchangeAuthorizationCode(code: String, verifier: String) async throws -> AuthTokens
}

extension CognitoWebAuthenticator: CognitoAuthorizationCodeProvider {
    func authorize() async throws -> CognitoAuthorizationResult {
        try await authenticate()
    }
}
extension CognitoTokenClient: CognitoTokenExchanging {}

struct CognitoSignInCoordinator {
    let authorizationProvider: any CognitoAuthorizationCodeProvider
    let tokenExchanger: any CognitoTokenExchanging

    func signIn() async throws -> AuthTokens {
        let authorization = try await authorizationProvider.authorize()
        return try await tokenExchanger.exchangeAuthorizationCode(
            code: authorization.authorizationCode,
            verifier: authorization.verifier
        )
    }
}

extension CognitoSignInCoordinator: SignInService {}

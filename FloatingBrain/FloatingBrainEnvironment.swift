import Foundation

enum FloatingBrainEnvironment {
    static let callbackURL = "floatingbrain://oauth/callback"
    static let callbackURLScheme = "floatingbrain"
    static let deployment = FloatingBrainDeploymentConfiguration(values: Bundle.main.infoDictionary ?? [:])
    static var syncAPIBaseURL: URL? { deployment?.syncAPIBaseURL }
    static var cognitoConfiguration: CognitoConfiguration? { deployment?.cognitoConfiguration }
}

/// Public client configuration injected through Xcode build settings.
/// Incomplete or unsafe configuration leaves all cloud services unconfigured.
struct FloatingBrainDeploymentConfiguration {
    let syncAPIBaseURL: URL
    let cognitoConfiguration: CognitoConfiguration

    init?(values: [String: Any]) {
        guard let apiURL = Self.httpsURL(values["FLOATING_BRAIN_API_URL"]),
              apiURL.path.isEmpty || apiURL.path == "/",
              let authorizationURL = Self.httpsURL(values["COGNITO_AUTHORIZATION_ENDPOINT"]),
              let tokenURL = Self.httpsURL(values["COGNITO_TOKEN_ENDPOINT"]),
              authorizationURL.host == tokenURL.host,
              authorizationURL.port == tokenURL.port,
              let clientID = Self.setting(values["COGNITO_CLIENT_ID"]),
              let cognito = try? CognitoConfiguration(
                authorizationEndpoint: authorizationURL,
                tokenEndpoint: tokenURL,
                clientID: clientID,
                redirectURI: FloatingBrainEnvironment.callbackURL
              ) else { return nil }

        syncAPIBaseURL = apiURL
        cognitoConfiguration = cognito
    }

    private static func setting(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func httpsURL(_ value: Any?) -> URL? {
        guard let value = setting(value),
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              host.lowercased() != "invalid", !host.lowercased().hasSuffix(".invalid"),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        return components.url
    }
}

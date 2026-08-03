import Foundation

enum FloatingBrainEnvironment {
    static let callbackURL = "floatingbrain://oauth/callback"
    static let callbackURLScheme = "floatingbrain"
    static let syncAPIBaseURL = URL(string: "https://xv5xsshic3.execute-api.us-east-1.amazonaws.com")!

    static let cognitoConfiguration: CognitoConfiguration? = {
        try? CognitoConfiguration(
            authorizationEndpoint: URL(string: "https://floating-brain-dev.auth.us-east-1.amazoncognito.com/oauth2/authorize")!,
            tokenEndpoint: URL(string: "https://floating-brain-dev.auth.us-east-1.amazoncognito.com/oauth2/token")!,
            clientID: "5kb00q1qsduj6pvelg48cn6rn2",
            redirectURI: callbackURL
        )
    }()
}

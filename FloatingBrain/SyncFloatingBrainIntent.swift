import AppIntents
import Foundation

enum SyncIntentError: LocalizedError, Equatable {
    case notConfigured

    var errorDescription: String? {
        "Floating Brain sync is not configured yet."
    }
}

actor SyncIntentHandler {
    static let shared = SyncIntentHandler()
    private var operation: (@Sendable () async throws -> Void)?

    func register(operation: @escaping @Sendable () async throws -> Void) {
        self.operation = operation
    }

    func clear() {
        operation = nil
    }

    func run() async throws {
        guard let operation else { throw SyncIntentError.notConfigured }
        try await operation()
    }
}

struct SyncFloatingBrainIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync Floating Brain"
    static let description = IntentDescription("Synchronize reminders from the Floating Brain list.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        try await SyncIntentHandler.shared.run()
        return .result()
    }
}

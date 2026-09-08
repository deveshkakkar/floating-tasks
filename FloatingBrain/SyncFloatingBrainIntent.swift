import AppIntents
import Foundation

enum SyncIntentError: LocalizedError, Equatable {
    case notConfigured
    case emptyTask

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Floating Brain sync is not configured yet."
        case .emptyTask:
            "Tell me what task to add."
        }
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

struct AddFloatingBrainTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Floating Brain Task"
    static let description = IntentDescription("Save a task to Floating Brain for the next sync.")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Task",
        requestValueDialog: "What task should I add?"
    )
    var task: String

    func perform() async throws -> some IntentResult {
        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTask.isEmpty else {
            throw SyncIntentError.emptyTask
        }

        CaptureInbox().append(CapturedTask(text: trimmedTask))
        return .result(dialog: "Added \(trimmedTask) to Floating Brain.")
    }
}

struct FloatingBrainShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddFloatingBrainTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "Remember this with \(.applicationName)"
            ],
            shortTitle: "Add Task",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: SyncFloatingBrainIntent(),
            phrases: ["Sync \(.applicationName)"],
            shortTitle: "Sync",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}

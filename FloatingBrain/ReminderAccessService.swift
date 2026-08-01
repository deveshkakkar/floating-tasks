import EventKit
import Foundation

struct ReminderListSnapshot: Equatable {
    let listName: String
    let activeCount: Int
    let completedCount: Int
}

enum ReminderAccessError: LocalizedError, Equatable {
    case permissionDenied
    case listNotFound
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Reminders access is required to read the Floating Brain list."
        case .listNotFound:
            "Create a Reminders list named Floating Brain to continue."
        case .unavailable:
            "Reminders are unavailable on this device."
        }
    }
}

protocol ReminderAccessService {
    func authorizationStatus() -> PermissionStatus
    func requestAccess() async throws -> Bool
    func readFloatingBrainList() async throws -> ReminderListSnapshot
}

final class EventKitReminderAccessService: ReminderAccessService {
    private let eventStore: EKEventStore
    private let listName = "Floating Brain"

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func authorizationStatus() -> PermissionStatus {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            .notDetermined
        case .fullAccess:
            .authorized
        case .writeOnly, .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToReminders()
    }

    func readFloatingBrainList() async throws -> ReminderListSnapshot {
        guard authorizationStatus() == .authorized else {
            throw ReminderAccessError.permissionDenied
        }

        guard let list = eventStore.calendars(for: .reminder).first(where: { $0.title == listName }) else {
            throw ReminderAccessError.listNotFound
        }

        let reminders = try await fetchReminders(matching: eventStore.predicateForReminders(in: [list]))
        let activeCount = reminders.filter { !$0.isCompleted }.count
        let completedCount = reminders.filter(\.isCompleted).count
        return ReminderListSnapshot(listName: list.title, activeCount: activeCount, completedCount: completedCount)
    }

    private func fetchReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }
}

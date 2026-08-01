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
    func readFloatingBrainReminders() async throws -> [SyncReminder]
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
        let reminders = try await readFloatingBrainReminders()
        let activeCount = reminders.filter { !$0.completed }.count
        let completedCount = reminders.filter(\.completed).count
        return ReminderListSnapshot(listName: listName, activeCount: activeCount, completedCount: completedCount)
    }

    func readFloatingBrainReminders() async throws -> [SyncReminder] {
        guard authorizationStatus() == .authorized else {
            throw ReminderAccessError.permissionDenied
        }

        guard let list = eventStore.calendars(for: .reminder).first(where: { $0.title == listName }) else {
            throw ReminderAccessError.listNotFound
        }

        let reminders = try await fetchReminders(matching: eventStore.predicateForReminders(in: [list]))
        return reminders.compactMap(SyncReminder.init)
    }

    private func fetchReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }
}

private extension SyncReminder {
    init?(eventKitReminder: EKReminder) {
        guard let externalID = eventKitReminder.calendarItemIdentifier.nilIfEmpty,
              let text = eventKitReminder.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        self.init(
            externalID: externalID,
            text: text,
            completed: eventKitReminder.isCompleted,
            createdAt: eventKitReminder.creationDate,
            modifiedAt: eventKitReminder.lastModifiedDate,
            dueAt: eventKitReminder.dueDateComponents?.date,
            priority: eventKitReminder.priority
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

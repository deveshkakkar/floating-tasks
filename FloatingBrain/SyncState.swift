import Foundation

enum PermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied

    var title: String {
        switch self {
        case .notDetermined: "Not requested"
        case .authorized: "Allowed"
        case .denied: "Needs attention"
        }
    }
}

enum AuthenticationStatus: Equatable {
    case signedOut
    case signedIn

    var title: String {
        switch self {
        case .signedOut: "Not connected"
        case .signedIn: "Connected"
        }
    }
}

enum SyncResult: Equatable {
    case never
    case succeeded(date: Date)
    case failed(message: String)

    var title: String {
        switch self {
        case .never: "Not synced yet"
        case .succeeded: "Last sync succeeded"
        case .failed: "Last sync failed"
        }
    }
}

struct SyncState: Equatable {
    var remindersPermission: PermissionStatus = .notDetermined
    var authentication: AuthenticationStatus = .signedOut
    var selectedListName: String?
    var activeReminderCount = 0
    var completedReminderCount = 0
    var result: SyncResult = .never

    var canSync: Bool {
        remindersPermission == .authorized && authentication == .signedIn
    }
}

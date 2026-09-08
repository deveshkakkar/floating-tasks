import Foundation

struct CapturedTask: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let capturedAt: Date

    init(id: UUID = UUID(), text: String, capturedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.capturedAt = capturedAt
    }
}

final class CaptureInbox {
    static let appGroup = "group.com.floatingbrain.app"
    private static let key = "pending-captures"

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) {
        self.defaults = defaults ?? .standard
    }

    func append(_ capture: CapturedTask) {
        var captures = pending()
        captures.append(capture)
        save(captures)
    }

    func pending() -> [CapturedTask] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([CapturedTask].self, from: data)) ?? []
    }

    func remove(ids: Set<UUID>) {
        save(pending().filter { !ids.contains($0.id) })
    }

    private func save(_ captures: [CapturedTask]) {
        guard let data = try? JSONEncoder().encode(captures) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

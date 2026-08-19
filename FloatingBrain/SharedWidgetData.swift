import Foundation

struct DailyTask: Codable, Equatable, Identifiable {
    let id: String
    let text: String
    let priority: Int
    var completed: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, text, priority, completed
    }

    init(id: String, text: String, priority: Int, completed: Bool = false) {
        self.id = id
        self.text = text
        self.priority = priority
        self.completed = completed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        priority = try container.decode(Int.self, forKey: .priority)
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
    }
}

struct WidgetTask: Codable, Equatable, Identifiable {
    let id: String
    let text: String
    let priority: Int
    var completed: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, text, priority, completed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        priority = try container.decode(Int.self, forKey: .priority)
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
    }

    init(id: String, text: String, priority: Int = 0, completed: Bool = false) {
        self.id = id
        self.text = text
        self.priority = priority
        self.completed = completed
    }
}

final class WidgetTaskStore {
    static let appGroup = "group.com.floatingbrain.app"
    private static let key = "widget-tasks"

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) {
        self.defaults = defaults ?? .standard
    }

    func save(_ tasks: [WidgetTask]) {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func load() -> [WidgetTask] {
        guard let data = defaults.data(forKey: Self.key),
              let tasks = try? JSONDecoder().decode([WidgetTask].self, from: data) else {
            return []
        }
        return tasks
    }
}

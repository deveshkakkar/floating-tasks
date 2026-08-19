import Foundation
import SwiftUI
import UIKit

enum FloatingBrainPalette {
    static let canvas = adaptive(light: "F6F7FB", dark: "101426")
    static let surface = adaptive(light: "FFFFFF", dark: "1B2238")
    static let surfaceElevated = adaptive(light: "FFFFFF", dark: "252E49")
    static let ink = adaptive(light: "18223F", dark: "F7F8FC")
    static let inkSecondary = adaptive(light: "59627A", dark: "B7BED3")
    static let border = adaptive(light: "DDE2EE", dark: "39435F")
    static let brandPrimary = adaptive(light: "51439B", dark: "A99CF7")
    static let brandDeep = adaptive(light: "263361", dark: "171E38")
    static let brandViolet = adaptive(light: "4D3875", dark: "302653")
    static let taskAccent = adaptive(light: "D94F6D", dark: "FF8EA5")
    static let success = adaptive(light: "147A67", dark: "67D5BA")
    static let warning = adaptive(light: "8A5A00", dark: "F3C56B")
    static let danger = adaptive(light: "B4232F", dark: "FF8B8B")
    static let info = adaptive(light: "1769A6", dark: "82C7FF")

    static var heroGradient: LinearGradient {
        LinearGradient(colors: [brandDeep, brandViolet], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let value = Int(hex, radix: 16) ?? 0
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

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

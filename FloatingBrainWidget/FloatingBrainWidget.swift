import SwiftUI
import WidgetKit

struct FloatingBrainWidgetEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
}

struct FloatingBrainWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FloatingBrainWidgetEntry {
        FloatingBrainWidgetEntry(
            date: Date(),
            tasks: [
                WidgetTask(id: "one", text: "Your next task"),
                WidgetTask(id: "two", text: "Another small step"),
                WidgetTask(id: "three", text: "Make progress")
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FloatingBrainWidgetEntry) -> Void) {
        completion(FloatingBrainWidgetEntry(date: Date(), tasks: WidgetTaskStore().load().prefix(3).map { $0 }))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FloatingBrainWidgetEntry>) -> Void) {
        let entry = FloatingBrainWidgetEntry(date: Date(), tasks: WidgetTaskStore().load().prefix(3).map { $0 })
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct FloatingBrainWidgetView: View {
    let entry: FloatingBrainWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(FloatingBrainPalette.brandPrimary)
                Text("Floating Brain")
                    .font(.headline)
                    .lineLimit(1)
            }

            if entry.tasks.isEmpty {
                Text("Open the app to sync your tasks.")
                    .font(.caption)
                    .foregroundStyle(FloatingBrainPalette.inkSecondary)
            } else {
                ForEach(entry.tasks) { task in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.completed ? FloatingBrainPalette.success : FloatingBrainPalette.taskAccent)
                        Text(task.text)
                            .font(.caption)
                            .lineLimit(2)
                            .strikethrough(task.completed)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .widgetURL(URL(string: "floatingbrain://"))
        .containerBackground(FloatingBrainPalette.surface, for: .widget)
    }
}

struct FloatingBrainWidget: Widget {
    let kind = "FloatingBrainWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FloatingBrainWidgetProvider()) { entry in
            FloatingBrainWidgetView(entry: entry)
        }
        .configurationDisplayName("Floating Brain")
        .description("Keep your next three tasks visible.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct FloatingBrainWidgetBundle: WidgetBundle {
    var body: some Widget {
        FloatingBrainWidget()
    }
}

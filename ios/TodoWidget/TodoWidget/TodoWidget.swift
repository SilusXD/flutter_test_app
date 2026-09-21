import WidgetKit
import SwiftUI

// MARK: - Модель данных

/// Одна задача, пришедшая из Flutter-приложения.
struct TodoItem: Identifiable {
    let id: String
    let title: String
    let done: Bool
}

/// Данные, которые виджет показывает в конкретный момент времени.
struct TodoEntry: TimelineEntry {
    let date: Date
    let items: [TodoItem]

    /// Сколько задач ещё не выполнено.
    let pending: Int

    /// Доступен ли общий контейнер App Group. Нужно, чтобы отличать «задач нет»
    /// от «приложение не может делиться данными» — это разные диагнозы.
    let sharedStorageAvailable: Bool

    var total: Int { items.count }

    static let placeholder = TodoEntry(
        date: Date(),
        items: [
            TodoItem(id: "1", title: "Купить молоко", done: false),
            TodoItem(id: "2", title: "Позвонить маме", done: true),
            TodoItem(id: "3", title: "Сдать отчёт", done: false),
        ],
        pending: 2,
        sharedStorageAvailable: true
    )

    /// Контейнер доступен, но задач нет.
    static let empty = TodoEntry(
        date: Date(),
        items: [],
        pending: 0,
        sharedStorageAvailable: true
    )

    /// Общий контейнер недоступен: App Group не активирована.
    static let unavailable = TodoEntry(
        date: Date(),
        items: [],
        pending: 0,
        sharedStorageAvailable: false
    )
}

/// Структура JSON, которую пишет Flutter (ключ `todos_json`).
private struct TodoPayload: Decodable {
    let id: String
    let title: String
    let done: Bool
}

// MARK: - Чтение общего хранилища (App Group)

/// Читает задачи из общего контейнера App Group.
///
/// Тот же идентификатор группы должен быть указан в entitlements приложения
/// (`ios/Runner/Runner.entitlements`) и расширения
/// (`ios/TodoWidget/TodoWidget/TodoWidget.entitlements`), а также в Dart-коде
/// (`TodoStore.defaultAppGroupId`).
enum TodoSharedStorage {
    static let appGroupId = "group.com.example.flutterTestApp"
    static let jsonKey = "todos_json"
    static let pendingKey = "todos_pending"

    /// Выдала ли система URL общего контейнера.
    ///
    /// Если entitlement `com.apple.security.application-groups` не применён при
    /// подписи, контейнера нет — и это надёжный признак, что приложение и виджет
    /// физически не могут обмениваться данными.
    static var isContainerAvailable: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) != nil
    }

    static func load() -> TodoEntry {
        guard isContainerAvailable else {
            return .unavailable
        }

        guard
            let defaults = UserDefaults(suiteName: appGroupId),
            let raw = defaults.string(forKey: jsonKey),
            let data = raw.data(using: .utf8)
        else {
            // Контейнер есть, но приложение ещё ничего не записало.
            return .empty
        }

        do {
            let payload = try JSONDecoder().decode([TodoPayload].self, from: data)
            let items = payload.map {
                TodoItem(id: $0.id, title: $0.title, done: $0.done)
            }
            let storedPending = defaults.object(forKey: pendingKey) as? Int
            let pending = storedPending ?? items.filter { !$0.done }.count
            return TodoEntry(
                date: Date(),
                items: items,
                pending: pending,
                sharedStorageAvailable: true
            )
        } catch {
            return .empty
        }
    }
}

// MARK: - Провайдер таймлайна

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        completion(context.isPreview ? .placeholder : TodoSharedStorage.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        let entry = TodoSharedStorage.load()

        // Основной сценарий: приложение само просит перерисовать виджет через
        // WidgetCenter.reloadTimelines(ofKind:). Резервное обновление — раз в 15 минут.
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - UI виджета

struct TodoWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var entry: TodoEntry

    /// Сколько задач показываем в зависимости от размера виджета.
    private var visibleItems: [TodoItem] {
        let limit: Int
        switch family {
        case .systemSmall: limit = 3
        case .systemMedium: limit = 4
        default: limit = 8
        }
        return Array(entry.items.prefix(limit))
    }

    private var hiddenCount: Int {
        max(0, entry.items.count - visibleItems.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if entry.items.isEmpty {
                Spacer(minLength: 0)
                if entry.sharedStorageAvailable {
                    Text("Задач пока нет")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Добавьте их в приложении")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Нет доступа к общему хранилищу")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("App Group не активирована")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleItems) { item in
                        row(for: item)
                    }
                }
                Spacer(minLength: 0)
                if hiddenCount > 0 {
                    Text("и ещё \(hiddenCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetContainerBackground()
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.caption)
            Text("Осталось: \(entry.pending)")
                .font(.caption)
                .fontWeight(.semibold)
            Spacer(minLength: 0)
            if entry.total > 0 {
                Text("из \(entry.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(for item: TodoItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(item.done ? Color.accentColor : Color.secondary)

            Text(item.title)
                .font(.caption)
                .strikethrough(item.done, color: .secondary)
                .foregroundStyle(item.done ? Color.secondary : Color.primary)
                .lineLimit(1)
        }
    }
}

// MARK: - Конфигурация виджета

/// Фон виджета: на iOS 17+ его обязан задавать сам виджет (containerBackground),
/// а на iOS 16 и ниже фон рисует система и такого API там просто нет.
private extension View {
    @ViewBuilder
    func widgetContainerBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(.fill.tertiary, for: .widget)
        } else {
            self
        }
    }
}

struct TodoWidget: Widget {
    /// Значение `kind` обязано совпадать с `iOSWidgetName` в Dart-коде
    /// (`TodoStore.iOSWidgetName`), иначе обновление виджета не сработает.
    let kind = "TodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TodoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Список дел")
        .description("Краткий список задач из приложения «Список дел».")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

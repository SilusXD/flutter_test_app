import WidgetKit
import SwiftUI

// MARK: - Модель данных

/// Одна задача, пришедшая из Flutter-приложения.
struct TodoItem: Identifiable {
    let id: String
    let title: String
    let done: Bool
}

/// Что удалось получить на этом обновлении.
enum TodoEntryState {
    /// Данные загружены, задачи есть.
    case ok
    /// Данные загружены, список пуст.
    case empty
    /// Адрес данных не задан при сборке.
    case notConfigured
    /// Сеть или разбор не удались, кеша тоже нет.
    case failed
}

/// Данные, которые виджет показывает в конкретный момент времени.
struct TodoEntry: TimelineEntry {
    let date: Date
    let items: [TodoItem]

    /// Сколько задач ещё не выполнено.
    let pending: Int

    let state: TodoEntryState

    /// Данные взяты из кеша, потому что сеть не ответила. Показывается
    /// пользователю: иначе виджет выглядит «замороженным» без объяснения.
    let isFromCache: Bool

    var total: Int { items.count }

    static let placeholder = TodoEntry(
        date: Date(),
        items: [
            TodoItem(id: "1", title: "Купить молоко", done: false),
            TodoItem(id: "2", title: "Позвонить маме", done: true),
            TodoItem(id: "3", title: "Сдать отчёт", done: false),
        ],
        pending: 2,
        state: .ok,
        isFromCache: false
    )

    static func message(_ state: TodoEntryState) -> TodoEntry {
        TodoEntry(
            date: Date(),
            items: [],
            pending: 0,
            state: state,
            isFromCache: false
        )
    }
}

/// Структура JSON, которую пишет Flutter.
private struct TodoPayload: Decodable {
    let id: String
    let title: String
    let done: Bool
}

// MARK: - Источник данных

/// Читает задачи по HTTPS из приватного Gist.
///
/// Обмен через App Group на бесплатном Apple ID невозможен (iOS не создаёт общий
/// контейнер без платного профиля), поэтому единственный общий канал —
/// сеть: приложение пишет JSON в Gist, виджет его скачивает. Адрес подставляется
/// на этапе сборки из GitHub Secret `TODO_GIST_URL`.
enum TodoRemoteSource {
    /// Значение по умолчанию заменяется в workflow перед сборкой виджета.
    static let gistRawURL = "__TODO_GIST_URL__"

    private static let cacheKey = "cached_todos_json"
    private static let cacheDateKey = "cached_todos_date"

    /// Задан ли реальный адрес (а не placeholder из шаблона).
    static var isConfigured: Bool {
        !gistRawURL.isEmpty
            && !gistRawURL.hasPrefix("__")
            && URL(string: gistRawURL) != nil
    }

    /// Загружает задачи; при неудаче отдаёт последние удачные из кеша.
    static func load(completion: @escaping (TodoEntry) -> Void) {
        guard isConfigured, let baseURL = URL(string: gistRawURL) else {
            completion(.message(.notConfigured))
            return
        }

        var request = URLRequest(url: bustCache(baseURL))
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data, let entry = decode(data) {
                UserDefaults.standard.set(data, forKey: cacheKey)
                UserDefaults.standard.set(Date(), forKey: cacheDateKey)
                completion(entry)
                return
            }

            // Сети нет — показываем последнее, что удалось загрузить,
            // и помечаем данные как кеш.
            if let cached = UserDefaults.standard.data(forKey: cacheKey),
               let entry = decode(cached) {
                let cachedAt = UserDefaults.standard.object(forKey: cacheDateKey) as? Date
                completion(entry.asCached(at: cachedAt))
                return
            }

            completion(.message(.failed))
        }.resume()
    }

    /// Добавляет к адресу метку времени.
    ///
    /// raw-ссылка gist отдаётся через CDN, и без параметра он может вернуть
    /// закешированную ревизию файла — тогда виджет «не обновляется» даже после
    /// пересоздания. Уникальный query заставляет запросить свежую версию.
    private static func bustCache(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = [
            URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970)))
        ]
        return components.url ?? url
    }

    private static func decode(_ data: Data) -> TodoEntry? {
        guard let payload = try? JSONDecoder().decode([TodoPayload].self, from: data) else {
            return nil
        }
        let items = payload.map {
            TodoItem(id: $0.id, title: $0.title, done: $0.done)
        }
        return TodoEntry(
            date: Date(),
            items: items,
            pending: items.filter { !$0.done }.count,
            state: items.isEmpty ? .empty : .ok,
            isFromCache: false
        )
    }
}

private extension TodoEntry {
    /// Помечает запись как полученную из кеша и переносит время кеширования.
    func asCached(at cachedAt: Date?) -> TodoEntry {
        TodoEntry(
            date: cachedAt ?? date,
            items: items,
            pending: pending,
            state: state,
            isFromCache: true
        )
    }
}

// MARK: - Провайдер таймлайна

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        TodoRemoteSource.load(completion: completion)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        TodoRemoteSource.load { entry in
            // Основное обновление инициирует приложение вызовом
            // WidgetCenter.reloadTimelines; резервное — раз в 30 минут.
            let next = Date().addingTimeInterval(30 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
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

    /// Показывает, когда данные были получены: сразу видно, обновился виджет
    /// или показывает кеш.
    private var freshnessLabel: String? {
        guard entry.state == .ok else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: entry.date)
        return entry.isFromCache ? "кеш от \(time)" : "обновлено \(time)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if entry.state == .ok {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleItems) { item in
                        row(for: item)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    if hiddenCount > 0 {
                        Text("и ещё \(hiddenCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let freshnessLabel {
                        Text(freshnessLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Spacer(minLength: 0)
                messageView
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetContainerBackground()
    }

    @ViewBuilder
    private var messageView: some View {
        switch entry.state {
        case .empty:
            Text("Задач пока нет")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Добавьте их в приложении")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .notConfigured:
            Text("Виджет не настроен")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Задайте TODO_GIST_URL при сборке")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .failed:
            Text("Нет данных")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Проверьте интернет и настройки")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .ok:
            EmptyView()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.caption)
            Text(entry.state == .ok ? "Осталось: \(entry.pending)" : "Список дел")
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

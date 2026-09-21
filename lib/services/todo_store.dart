import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/todo.dart';

/// Результат публикации задач в виджет.
///
/// Показывается прямо в приложении: без Mac логи посмотреть негде, а по одному
/// лишь пустому виджету невозможно понять, в чём причина — нет данных или
/// недоступен общий контейнер.
enum WidgetSyncStatus {
  /// Платформа не iOS — виджета на главном экране нет.
  notApplicable,

  /// Данные легли в общий контейнер и успешно прочитаны обратно.
  synced,

  /// Запись выполнена, но прочитать её обратно не удалось: почти наверняка
  /// App Group не активирована (например, при бесплатном Apple ID).
  notShared,

  /// Плагин вернул ошибку при записи.
  failed;

  String get shortMessage {
    switch (this) {
      case WidgetSyncStatus.notApplicable:
        return 'Виджет доступен только на iOS';
      case WidgetSyncStatus.synced:
        return 'Виджет обновлён';
      case WidgetSyncStatus.notShared:
        return 'Виджет не получает данные: App Group не активирована';
      case WidgetSyncStatus.failed:
        return 'Виджет: ошибка синхронизации';
    }
  }

  /// Требует ли статус внимания пользователя.
  bool get isProblem {
    return this == WidgetSyncStatus.notShared || this == WidgetSyncStatus.failed;
  }
}

/// Хранилище задач: персистентность в приложении + публикация в iOS-виджет.
///
/// Данные живут в двух местах:
///  * `SharedPreferences` — обычное хранилище приложения (работает всегда);
///  * App Group-контейнер — общий контейнер с расширением виджета, откуда
///    Swift-код виджета читает `todos_json`.
///
/// App Group требует entitlement у обоих таргетов. Если группа недоступна,
/// публикация не удаётся: приложение продолжает работать, а виджет показывает
/// заглушку. Отличить эти случаи помогает [WidgetSyncStatus].
class TodoStore {
  TodoStore({this.appGroupId = defaultAppGroupId});

  /// Идентификатор App Group. Должен буквально совпадать с тем, что указан в
  /// `ios/Runner/Runner.entitlements` и `ios/TodoWidget/TodoWidget/TodoWidget.entitlements`.
  static const String defaultAppGroupId = 'group.com.example.flutterTestApp';

  /// Имя виджета для iOS — параметр `kind` в Swift-конфигурации виджета.
  static const String iOSWidgetName = 'TodoWidget';

  static const String _prefsKey = 'todos_v1';
  static const String _widgetJsonKey = 'todos_json';
  static const String _widgetPendingKey = 'todos_pending';
  static const String _widgetUpdatedAtKey = 'todos_updated_at';

  final String appGroupId;

  /// Читает задачи из локального хранилища.
  Future<List<Todo>> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) {
        return <Todo>[];
      }
      return Todo.listFromJson(raw);
    } catch (error) {
      debugPrint('TodoStore.load: $error');
      return <Todo>[];
    }
  }

  /// Сохраняет задачи локально и публикует их в виджет.
  ///
  /// Возвращает статус публикации, чтобы экран мог показать его пользователю.
  Future<WidgetSyncStatus> save(List<Todo> todos) async {
    final String raw = Todo.listToJson(todos);

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, raw);
    } catch (error) {
      debugPrint('TodoStore.save (локально): $error');
    }

    return publishToWidget(todos, raw);
  }

  /// Публикует задачи в App Group и просит iOS перерисовать виджет.
  Future<WidgetSyncStatus> publishToWidget(
    List<Todo> todos, [
    String? encoded,
  ]) async {
    if (!_widgetSupported) {
      return WidgetSyncStatus.notApplicable;
    }

    final String raw = encoded ?? Todo.listToJson(todos);
    final int pending = todos.where((Todo todo) => !todo.isDone).length;

    try {
      await HomeWidget.setAppGroupId(appGroupId);
      await HomeWidget.saveWidgetData<String>(_widgetJsonKey, raw);
      await HomeWidget.saveWidgetData<int>(_widgetPendingKey, pending);
      await HomeWidget.saveWidgetData<int>(
        _widgetUpdatedAtKey,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      await HomeWidget.updateWidget(iOSName: iOSWidgetName);

      // Обратное чтение — единственный способ отличить «данные записаны в общий
      // контейнер» от «запись ушла в никуда из-за отсутствия App Group».
      final String? readBack = await HomeWidget.getWidgetData<String>(
        _widgetJsonKey,
      );
      return readBack == raw
          ? WidgetSyncStatus.synced
          : WidgetSyncStatus.notShared;
    } catch (error) {
      // Ожидаемая ситуация, если App Group недоступна или плагин не загружен
      // (например, в widget-тестах).
      debugPrint('TodoStore: публикация в виджет не удалась: $error');
      return WidgetSyncStatus.failed;
    }
  }

  /// Виджет существует только на iOS и только вне тестов/web.
  bool get _widgetSupported {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS;
  }
}

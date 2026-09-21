import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/todo.dart';

/// Хранилище задач: персистентность в приложении + публикация в iOS-виджет.
///
/// Данные живут в двух местах:
///  * `SharedPreferences` — обычное хранилище приложения (работает всегда);
///  * App Group-контейнер — общий контейнер с расширением виджета, откуда
///    Swift-код виджета читает `todos_json`.
///
/// App Group требует entitlement у обоих таргетов. Если группа недоступна
/// (например, при подписи бесплатным Apple ID), публикация просто не удаётся:
/// приложение продолжает работать, а виджет показывает заглушку.
class TodoStore {
  TodoStore({this.appGroupId = defaultAppGroupId});

  /// Идентификатор App Group. Должен буквально совпадать с тем, что указан в
  /// `ios/Runner/Runner.entitlements` и `ios/TodoWidget/TodoWidget.entitlements`.
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
  Future<void> save(List<Todo> todos) async {
    final String raw = Todo.listToJson(todos);

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, raw);
    } catch (error) {
      debugPrint('TodoStore.save (локально): $error');
    }

    await publishToWidget(todos, raw);
  }

  /// Публикует задачи в App Group и просит iOS перерисовать виджет.
  Future<void> publishToWidget(List<Todo> todos, [String? encoded]) async {
    if (!_widgetSupported) {
      return;
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
    } catch (error) {
      // Ожидаемая ситуация, если App Group недоступна или плагин не загружен
      // (например, в widget-тестах). Виджет покажет заглушку.
      debugPrint('TodoStore: публикация в виджет не удалась: $error');
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

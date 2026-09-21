import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/todo.dart';
import 'gist_client.dart';
import 'sync_settings.dart';

/// Результат синхронизации задач с виджетом.
///
/// Показывается прямо в приложении: без Mac логи посмотреть негде, а по одному
/// лишь пустому виджету невозможно понять причину.
enum WidgetSyncStatus {
  /// Платформа не iOS — виджета на главном экране нет.
  notApplicable,

  /// Задачи отправлены в Gist, виджет попросили перерисоваться.
  synced,

  /// Не заданы raw-URL гиста и токен.
  notConfigured,

  /// Отправка не удалась (нет сети, истёк токен, неверный URL).
  failed;

  String get shortMessage {
    switch (this) {
      case WidgetSyncStatus.notApplicable:
        return 'Виджет доступен только на iOS';
      case WidgetSyncStatus.synced:
        return 'Виджет обновлён';
      case WidgetSyncStatus.notConfigured:
        return 'Виджет не настроен: укажите Gist URL и токен';
      case WidgetSyncStatus.failed:
        return 'Виджет: не удалось отправить данные';
    }
  }

  bool get isProblem {
    return this == WidgetSyncStatus.notConfigured ||
        this == WidgetSyncStatus.failed;
  }
}

/// Хранилище задач: персистентность в приложении + передача данных в виджет.
///
/// App Group на бесплатном Apple ID недоступна (проверено на двух установщиках),
/// поэтому канал обмена — сеть: приложение пишет JSON в приватный GitHub Gist,
/// виджет читает его по raw-URL. Адрес виджету задаётся при сборке
/// (GitHub Secret `TODO_GIST_URL`).
class TodoStore {
  TodoStore({GistClient? gistClient}) : _gist = gistClient ?? GistClient();

  /// Имя виджета для iOS — параметр `kind` в Swift-конфигурации виджета.
  static const String iOSWidgetName = 'TodoWidget';

  static const String _prefsKey = 'todos_v1';

  final GistClient _gist;

  /// Текст последней ошибки — показывается рядом со статусом, чтобы причину
  /// можно было понять без логов.
  String? lastError;

  /// Снимок, ожидающий отправки, и текущая отправка.
  ///
  /// Отправки идут строго по одной, а промежуточные снимки пропускаются. Без
  /// этого при быстром добавлении задач несколько PATCH-запросов уходили
  /// параллельно, и в Gist мог остаться снимок с одной задачей — тот, чей ответ
  /// пришёл последним.
  String? _pendingRaw;
  Future<WidgetSyncStatus>? _inFlight;

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

  /// Сохраняет задачи локально и ставит их в очередь на отправку в виджет.
  Future<WidgetSyncStatus> save(List<Todo> todos) async {
    final String raw = Todo.listToJson(todos);

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, raw);
    } catch (error) {
      debugPrint('TodoStore.save (локально): $error');
    }

    return sync(raw);
  }

  /// Ставит снимок в очередь на отправку.
  ///
  /// Возвращает результат последней отправки в очереди. Если отправка уже идёт,
  /// новый снимок заменит ожидающий — в Gist уйдёт самое свежее состояние.
  Future<WidgetSyncStatus> sync(String raw) {
    _pendingRaw = raw;
    return _inFlight ??= _drainQueue();
  }

  Future<WidgetSyncStatus> _drainQueue() async {
    WidgetSyncStatus status = WidgetSyncStatus.notApplicable;
    try {
      while (_pendingRaw != null) {
        final String raw = _pendingRaw!;
        _pendingRaw = null;
        status = await _upload(raw);
      }
      return status;
    } finally {
      _inFlight = null;
    }
  }

  Future<WidgetSyncStatus> _upload(String raw) async {
    if (!_widgetSupported) {
      return WidgetSyncStatus.notApplicable;
    }

    final SyncSettings settings = await SyncSettings.load();
    final String? gistId = settings.gistId;
    if (!settings.isConfigured || gistId == null) {
      lastError = null;
      return WidgetSyncStatus.notConfigured;
    }

    try {
      await _gist.upload(
        gistId: gistId,
        token: settings.token,
        content: raw,
        fileName: settings.fileName,
      );
      // reloadTimelines не требует App Group — виджет сам сходит в сеть.
      await HomeWidget.updateWidget(iOSName: iOSWidgetName);
      lastError = null;
      return WidgetSyncStatus.synced;
    } on GistSyncException catch (error) {
      debugPrint('TodoStore: отправка в Gist не удалась: ${error.message}');
      lastError = error.message;
      return WidgetSyncStatus.failed;
    } catch (error) {
      debugPrint('TodoStore: отправка в Gist не удалась: $error');
      lastError = '$error';
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

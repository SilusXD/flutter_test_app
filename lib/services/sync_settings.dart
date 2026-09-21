import 'package:shared_preferences/shared_preferences.dart';

/// Настройки синхронизации с виджетом через GitHub Gist.
///
/// App Group на бесплатном Apple ID недоступна, поэтому единственный общий
/// «канал» между приложением и расширением виджета — сеть: приложение пишет
/// JSON в Gist по токену, виджет читает его по raw-URL.
///
/// Токен хранится локально в SharedPreferences в открытом виде — это осознанный
/// компромисс бесплатного варианта. Используйте отдельный токен только со
/// scope `gist`.
class SyncSettings {
  const SyncSettings({this.gistUrl = '', this.token = ''});

  /// Raw-URL файла в гисте. Хранится уже нормализованным: см. [normalizedGistUrl].
  final String gistUrl;

  /// GitHub-токен со scope `gist`.
  final String token;

  static const String _urlKey = 'sync_gist_url';
  static const String _tokenKey = 'sync_gist_token';

  /// Имя файла по умолчанию — должно совпадать с тем, что читает виджет.
  static const String defaultFileName = 'todos.json';

  /// Имя файла, в который пишет приложение и из которого читает виджет.
  ///
  /// Берётся из URL, чтобы данные попадали ровно в тот файл, на который смотрит
  /// виджет: если в гисте файл назван иначе, жёсткое `todos.json` создало бы
  /// второй файл, а виджет продолжал бы читать пустой первый.
  String get fileName {
    final Uri? uri = Uri.tryParse(normalizedGistUrl);
    if (uri == null || uri.pathSegments.isEmpty) {
      return defaultFileName;
    }
    final String last = uri.pathSegments.last.trim();
    return last.isEmpty ? defaultFileName : last;
  }

  bool get isConfigured => gistUrl.isNotEmpty && token.isNotEmpty;

  /// URL без привязки к ревизии.
  ///
  /// Ссылка «Raw» на github.com содержит хеш коммита:
  /// `.../raw/8f3c1a…/todos.json`. Такой адрес всегда отдаёт ту версию файла,
  /// которая была на момент копирования, поэтому виджет показывал бы устаревшие
  /// данные. Хеш из пути убираем, имя файла сохраняем.
  String get normalizedGistUrl {
    final String trimmed = gistUrl.trim();
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || uri.pathSegments.length < 3) {
      return trimmed;
    }

    final List<String> segments = uri.pathSegments;
    final int rawIndex = segments.indexOf('raw');
    if (rawIndex == -1 || rawIndex + 1 >= segments.length) {
      return trimmed;
    }

    final List<String> pathSegments = <String>[
      ...segments.sublist(0, rawIndex + 1),
      segments.last,
    ];

    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      pathSegments: pathSegments,
    ).toString();
  }

  /// Идентификатор гиста, извлечённый из raw-URL.
  ///
  /// Нужен для записи через API: `PATCH /gists/{id}`.
  String? get gistId {
    final Uri? uri = Uri.tryParse(normalizedGistUrl);
    if (uri == null || !uri.hasScheme) {
      return null;
    }
    // Путь: /<user>/<gistId>/raw/<file> — идентификатор идёт вторым сегментом.
    final List<String> segments = uri.pathSegments;
    if (segments.length < 2) {
      return null;
    }
    final String candidate = segments[1].trim();
    return candidate.isEmpty ? null : candidate;
  }

  SyncSettings copyWith({String? gistUrl, String? token}) {
    return SyncSettings(
      gistUrl: gistUrl ?? this.gistUrl,
      token: token ?? this.token,
    );
  }

  static Future<SyncSettings> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return SyncSettings(
        gistUrl: prefs.getString(_urlKey) ?? '',
        token: prefs.getString(_tokenKey) ?? '',
      );
    } catch (_) {
      return const SyncSettings();
    }
  }

  /// Сохраняет настройки, нормализуя URL (убирая хеш ревизии).
  Future<void> save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, normalizedGistUrl);
    await prefs.setString(_tokenKey, token.trim());
  }
}

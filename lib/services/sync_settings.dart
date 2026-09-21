import 'package:shared_preferences/shared_preferences.dart';

/// Настройки синхронизации с виджетом через GitHub Gist.
///
/// App Group на бесплатном Apple ID недоступна, поэтому единственный общий
/// «канал» между приложением и расширением виджета — сеть: приложение пишет
/// JSON в Gist по токену, виджет читает его по публичному raw-URL.
///
/// Токен хранится локально в SharedPreferences в открытом виде — это осознанный
/// компромисс бесплатного варианта. Используйте отдельный токен только со
/// scope `gist`.
class SyncSettings {
  const SyncSettings({this.gistUrl = '', this.token = ''});

  /// Raw-URL файла в гисте:
  /// `https://gist.githubusercontent.com/<user>/<gistId>/raw/todos.json`
  final String gistUrl;

  /// GitHub-токен со scope `gist`.
  final String token;

  static const String _urlKey = 'sync_gist_url';
  static const String _tokenKey = 'sync_gist_token';

  bool get isConfigured => gistUrl.isNotEmpty && token.isNotEmpty;

  /// Идентификатор гиста, извлечённый из raw-URL.
  ///
  /// Нужен для записи через API: `PATCH /gists/{id}`.
  String? get gistId {
    final Uri? uri = Uri.tryParse(gistUrl.trim());
    if (uri == null || !uri.hasScheme) {
      return null;
    }
    // Путь: /<user>/<gistId>/raw/... — идентификатор идёт вторым сегментом.
    final List<String> segments = uri.pathSegments;
    if (segments.length < 2) {
      return null;
    }
    final String candidate = segments[1].trim();
    return candidate.isEmpty ? null : candidate;
  }

  /// Имя файла внутри гиста (используется при записи). Должно совпадать
  /// с тем, что читает виджет.
  static const String gistFileName = 'todos.json';

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

  Future<void> save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, gistUrl.trim());
    await prefs.setString(_tokenKey, token.trim());
  }
}

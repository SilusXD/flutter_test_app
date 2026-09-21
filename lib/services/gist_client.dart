import 'dart:convert';
import 'dart:io';

import 'sync_settings.dart';

/// Запись задач в GitHub Gist.
///
/// Используется HttpClient из `dart:io`, чтобы не добавлять в проект ещё одну
/// зависимость: сеть нужна ровно для одного PATCH-запроса.
class GistClient {
  GistClient({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  /// Отправляет содержимое в файл [fileName] гиста.
  ///
  /// Имя файла берётся из URL настроек, чтобы запись шла ровно в тот файл,
  /// который читает виджет.
  ///
  /// Бросает [GistSyncException] при любой неудаче, чтобы вызывающий код мог
  /// показать пользователю внятную причину.
  Future<void> upload({
    required String gistId,
    required String token,
    required String content,
    String fileName = SyncSettings.defaultFileName,
  }) async {
    final Uri uri = Uri.https('api.github.com', '/gists/$gistId');

    try {
      final HttpClientRequest request = await _client.patchUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'flutter_test_app');
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, dynamic>{
          'files': <String, dynamic>{
            fileName: <String, String>{'content': content},
          },
        }),
      );

      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();

      if (response.statusCode != HttpStatus.ok) {
        throw GistSyncException(_describe(response.statusCode, body));
      }
    } on GistSyncException {
      rethrow;
    } on SocketException catch (error) {
      throw GistSyncException('Нет связи с github.com: ${error.message}');
    } catch (error) {
      throw GistSyncException('Не удалось отправить данные: $error');
    }
  }

  /// Читает файл из гиста — используется кнопкой «Проверить связь».
  Future<String?> download({required String gistUrl}) async {
    final Uri? uri = Uri.tryParse(gistUrl.trim());
    if (uri == null || !uri.hasScheme) {
      throw const GistSyncException('Некорректный raw-URL гиста');
    }

    try {
      final HttpClientRequest request = await _client.getUrl(uri);
      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw GistSyncException(
          'Чтение вернуло HTTP ${response.statusCode}. Проверьте, что URL указывает '
          'на файл в гисте и что файл существует',
        );
      }
      return body;
    } on GistSyncException {
      rethrow;
    } on SocketException catch (error) {
      throw GistSyncException('Нет связи с github.com: ${error.message}');
    }
  }

  void close() => _client.close(force: true);

  String _describe(int statusCode, String body) {
    switch (statusCode) {
      case HttpStatus.unauthorized:
        return 'Токен отклонён (401): проверьте, что он действующий и со scope «gist»';
      case HttpStatus.notFound:
        return 'Гист не найден (404): проверьте raw-URL и что он принадлежит этому токену';
      case HttpStatus.forbidden:
        return 'Доступ запрещён (403): у токена нет права на запись в гисты';
      default:
        return 'GitHub вернул HTTP $statusCode: ${body.trim()}';
    }
  }
}

/// Ошибка синхронизации с понятным пользователю текстом.
class GistSyncException implements Exception {
  const GistSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

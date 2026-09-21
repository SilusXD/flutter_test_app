import 'dart:async';

import 'package:flutter/material.dart';

import '../services/gist_client.dart';
import '../services/sync_settings.dart';

/// Настройки обмена данными с виджетом через GitHub Gist.
///
/// Возвращает `true` через Navigator.pop, если настройки сохранены: экран списка
/// по этому сигналу сразу отправляет задачи в гист.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final GistClient _gist = GistClient();

  String? _message;
  bool _isMessageError = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _gist.close();
    super.dispose();
  }

  Future<void> _load() async {
    final SyncSettings settings = await SyncSettings.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _urlController.text = settings.gistUrl;
      _tokenController.text = settings.token;
    });
  }

  SyncSettings get _currentSettings {
    return SyncSettings(
      gistUrl: _urlController.text,
      token: _tokenController.text,
    );
  }

  void _showMessage(String message, {required bool isError}) {
    setState(() {
      _message = message;
      _isMessageError = isError;
    });
  }

  Future<void> _save() async {
    final SyncSettings settings = _currentSettings;
    if (settings.gistId == null) {
      _showMessage(
        'Не удалось разобрать идентификатор гиста. Нужен raw-URL вида '
        'https://gist.githubusercontent.com/<user>/<id>/raw/todos.json',
        isError: true,
      );
      return;
    }

    setState(() => _busy = true);
    await settings.save();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    Navigator.of(context).pop(true);
  }

  /// Проверяет связь: сначала чтение по raw-URL, затем пробная запись.
  Future<void> _check() async {
    final SyncSettings settings = _currentSettings;
    final String? gistId = settings.gistId;
    if (!settings.isConfigured || gistId == null) {
      _showMessage('Заполните оба поля', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final String? body = await _gist.download(gistUrl: settings.gistUrl);
      final String preview = (body ?? '').trim();
      _showMessage(
        preview.isEmpty
            ? 'Файл прочитан, но он пуст — задачи ещё не отправлялись'
            : 'Файл прочитан: ${preview.length} символов',
        isError: false,
      );
    } on GistSyncException catch (error) {
      _showMessage('Чтение: ${error.message}', isError: true);
      if (mounted) {
        setState(() => _busy = false);
      }
      return;
    }

    try {
      await _gist.upload(
        gistId: gistId,
        token: settings.token,
        content: '[]',
      );
      _showMessage('Проверка успешна: запись в гист работает', isError: false);
    } on GistSyncException catch (error) {
      _showMessage('Запись: ${error.message}', isError: true);
    }

    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки виджета')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Как это работает',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'App Group на бесплатном Apple ID недоступна, поэтому приложение '
            'отправляет задачи в приватный GitHub Gist, а виджет читает их '
            'по HTTPS. Данные уходят на сервер GitHub — учитывайте это.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Raw-URL файла в гисте',
              hintText:
                  'https://gist.githubusercontent.com/user/id/raw/todos.json',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tokenController,
            decoration: const InputDecoration(
              labelText: 'GitHub-токен (scope «gist»)',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            autocorrect: false,
          ),
          const SizedBox(height: 8),
          Text(
            'Токен хранится на устройстве в открытом виде. Создайте отдельный '
            'токен только с правом «gist» и не используйте основной.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 20),
          if (_message != null) ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isMessageError
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _isMessageError
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Сохранить'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _check,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('Проверить связь'),
          ),
          const SizedBox(height: 24),
          Text(
            'Порядок настройки',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '1. Создайте на github.com секретный gist с файлом '
            '«${SyncSettings.gistFileName}» и содержимым «[]».\n'
            '2. Скопируйте ссылку Raw для этого файла и вставьте её выше.\n'
            '3. Создайте токен: Settings → Developer settings → '
            'Personal access tokens (classic) → scope «gist».\n'
            '4. Добавьте тот же raw-URL в GitHub Secrets репозитория как '
            'TODO_GIST_URL и пересоберите приложение — виджет получает адрес '
            'на этапе сборки.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

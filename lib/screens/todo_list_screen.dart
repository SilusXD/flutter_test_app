import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/todo.dart';
import '../services/todo_store.dart';
import '../widgets/todo_tile.dart';

/// Экран списка дел: добавление, отметка выполнения и удаление задач.
///
/// Задачи сохраняются между запусками приложения и публикуются в общий
/// контейнер, откуда их читает виджет на главном экране iOS.
class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key, this.store});

  /// Хранилище вынесено в параметр, чтобы подменять его в тестах.
  final TodoStore? store;

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  late final TodoStore _store = widget.store ?? TodoStore();
  final List<Todo> _todos = <Todo>[];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// Защита от перезаписи сохранённых задач пустым списком до окончания загрузки.
  bool _restored = false;

  /// Статус синхронизации с виджетом. Показывается пользователю, потому что
  /// иначе причину пустого виджета на устройстве не увидеть.
  WidgetSyncStatus? _widgetStatus;

  int get _completedCount => _todos.where((Todo todo) => todo.isDone).length;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final List<Todo> saved = await _store.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _todos
        ..clear()
        ..addAll(saved);
      _restored = true;
    });
    // Обновляем виджет сразу после запуска: например, если приложение
    // переустановили, но общий контейнер сохранился.
    final WidgetSyncStatus status = await _store.publishToWidget(_todos);
    if (!mounted) {
      return;
    }
    setState(() => _widgetStatus = status);
  }

  void _persist() {
    if (!_restored) {
      return;
    }
    unawaited(_saveAndSync());
  }

  Future<void> _saveAndSync() async {
    final WidgetSyncStatus status = await _store.save(_todos);
    if (!mounted) {
      return;
    }
    setState(() => _widgetStatus = status);
  }

  /// Идентификатор задачи: время + случайный хвост, чтобы ключи не повторялись
  /// после перезапуска приложения.
  String _newId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(10000)}';
  }

  void _addTodo() {
    final String title = _controller.text.trim();
    if (title.isEmpty) {
      return;
    }

    setState(() {
      _todos.insert(0, Todo(id: _newId(), title: title));
    });
    _controller.clear();
    // Фокус остаётся в поле, чтобы удобно вводить задачи одну за другой.
    _focusNode.requestFocus();
    _persist();
  }

  void _toggleTodo(Todo todo) {
    setState(() {
      final int index = _todos.indexWhere((Todo item) => item.id == todo.id);
      if (index == -1) {
        return;
      }
      _todos[index] = _todos[index].copyWith(isDone: !_todos[index].isDone);
    });
    _persist();
  }

  void _removeTodo(Todo todo) {
    setState(() {
      _todos.removeWhere((Todo item) => item.id == todo.id);
    });
    _persist();
  }

  void _clearCompleted() {
    setState(() {
      _todos.removeWhere((Todo todo) => todo.isDone);
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final int remaining = _todos.length - _completedCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Список дел'),
        actions: <Widget>[
          if (_completedCount > 0)
            IconButton(
              onPressed: _clearCompleted,
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Удалить выполненные',
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_todos.isNotEmpty)
            _SummaryBar(remaining: remaining, total: _todos.length),
          if (_widgetStatus != null &&
              _widgetStatus != WidgetSyncStatus.notApplicable)
            _WidgetStatusBar(status: _widgetStatus!),
          Expanded(
            child: _todos.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    itemCount: _todos.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Todo todo = _todos[index];
                      return TodoTile(
                        todo: todo,
                        onToggle: () => _toggleTodo(todo),
                        onDismissed: () => _removeTodo(todo),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: _Composer(
              controller: _controller,
              focusNode: _focusNode,
              onSubmit: _addTodo,
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка статуса синхронизации с iOS-виджетом.
///
/// Нужна для диагностики на самом устройстве: если виджет пуст, здесь видно,
/// дошли ли данные до общего контейнера.
class _WidgetStatusBar extends StatelessWidget {
  const _WidgetStatusBar({required this.status});

  final WidgetSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool problem = status.isProblem;
    final Color background = problem
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.secondaryContainer;
    final Color foreground = problem
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSecondaryContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: background,
      child: Row(
        children: <Widget>[
          Icon(
            problem ? Icons.sync_problem : Icons.widgets_outlined,
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status.shortMessage,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка со счётчиком задач.
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.remaining, required this.total});

  final int remaining;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        'Осталось: $remaining из $total',
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Заглушка для пустого списка.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.checklist_rounded,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text('Пока пусто', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Добавьте первую задачу ниже',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// Поле ввода новой задачи с кнопкой добавления.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (String _) => onSubmit(),
              decoration: const InputDecoration(
                hintText: 'Новая задача',
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton.filled(
            onPressed: onSubmit,
            icon: const Icon(Icons.add),
            tooltip: 'Добавить',
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Одна задача списка дел.
@immutable
class Todo {
  const Todo({
    required this.id,
    required this.title,
    this.isDone = false,
  });

  /// Идентификатор задачи — используется как ключ в списке.
  final String id;

  /// Текст задачи.
  final String title;

  /// Выполнена ли задача.
  final bool isDone;

  /// Возвращает копию задачи с изменёнными полями.
  Todo copyWith({String? title, bool? isDone}) {
    return Todo(
      id: id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
    );
  }

  /// Представление задачи для хранения и для передачи в iOS-виджет.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'done': isDone,
    };
  }

  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      isDone: json['done'] as bool? ?? false,
    );
  }

  /// Сериализует список задач в JSON-строку.
  ///
  /// Именно эта строка попадает в App Group-контейнер по ключу `todos_json`,
  /// откуда её читает Swift-код виджета.
  static String listToJson(List<Todo> todos) {
    return jsonEncode(todos.map((Todo todo) => todo.toJson()).toList());
  }

  /// Разбирает JSON-строку обратно в список задач.
  ///
  /// Устойчив к повреждённым данным: вместо исключения возвращает то, что
  /// удалось разобрать.
  static List<Todo> listFromJson(String raw) {
    if (raw.trim().isEmpty) {
      return <Todo>[];
    }

    final dynamic decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <Todo>[];
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Todo.fromJson)
        .where((Todo todo) => todo.title.isNotEmpty)
        .toList();
  }
}

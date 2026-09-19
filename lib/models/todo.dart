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
}

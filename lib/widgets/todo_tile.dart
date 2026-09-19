import 'package:flutter/material.dart';

import '../models/todo.dart';

/// Строка списка: отметка выполнения и удаление свайпом влево.
class TodoTile extends StatelessWidget {
  const TodoTile({
    super.key,
    required this.todo,
    required this.onToggle,
    required this.onDismissed,
  });

  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Dismissible(
      key: ValueKey<String>('todo-${todo.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (DismissDirection _) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      child: CheckboxListTile(
        value: todo.isDone,
        onChanged: (bool? _) => onToggle(),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          todo.title,
          style: todo.isDone
              ? theme.textTheme.bodyLarge?.copyWith(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : theme.textTheme.bodyLarge,
        ),
      ),
    );
  }
}

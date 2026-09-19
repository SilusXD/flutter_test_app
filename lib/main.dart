import 'package:flutter/material.dart';

import 'screens/todo_list_screen.dart';

void main() {
  runApp(const TodoApp());
}

/// Корневое приложение — простой список дел.
class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Список дел',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const TodoListScreen(),
    );
  }
}

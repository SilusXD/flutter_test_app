import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_test_app/main.dart';

void main() {
  setUp(() {
    // Хранилище подменяется in-memory реализацией: плагина в тестах нет.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('показывает пустой список и добавляет задачу', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TodoApp());
    await tester.pumpAndSettle();

    expect(find.text('Пока пусто'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Купить молоко');
    await tester.tap(find.byTooltip('Добавить'));
    await tester.pumpAndSettle();

    expect(find.text('Купить молоко'), findsOneWidget);
    expect(find.text('Осталось: 1 из 1'), findsOneWidget);
    expect(find.text('Пока пусто'), findsNothing);
  });

  testWidgets('отмечает задачу выполненной', (WidgetTester tester) async {
    await tester.pumpWidget(const TodoApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Позвонить маме');
    await tester.tap(find.byTooltip('Добавить'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    expect(find.text('Осталось: 0 из 1'), findsOneWidget);
  });

  testWidgets('восстанавливает задачи из хранилища', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'todos_v1':
          '[{"id":"1","title":"Задача из хранилища","done":false},'
              '{"id":"2","title":"Уже сделано","done":true}]',
    });

    await tester.pumpWidget(const TodoApp());
    await tester.pumpAndSettle();

    expect(find.text('Задача из хранилища'), findsOneWidget);
    expect(find.text('Уже сделано'), findsOneWidget);
    expect(find.text('Осталось: 1 из 2'), findsOneWidget);
  });
}

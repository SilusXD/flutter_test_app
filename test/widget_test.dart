import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_test_app/main.dart';

void main() {
  testWidgets('показывает пустой список и добавляет задачу', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TodoApp());

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

    await tester.enterText(find.byType(TextField), 'Позвонить маме');
    await tester.tap(find.byTooltip('Добавить'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    expect(find.text('Осталось: 0 из 1'), findsOneWidget);
  });
}

# flutter_test_app

Простой список дел (to-do list) на Flutter.

## Возможности

- добавление задачи через поле внизу экрана (или клавишей Enter / «Готово»);
- отметка задачи выполненной чекбоксом — текст зачёркивается;
- удаление задачи свайпом влево;
- счётчик «Осталось: N из M»;
- кнопка в AppBar для удаления всех выполненных задач;
- заглушка «Пока пусто», когда список пуст.

## Структура

```
lib/
├── main.dart                     # точка входа и тема приложения
├── models/todo.dart              # модель задачи
├── screens/todo_list_screen.dart # экран списка, счётчик, поле ввода
└── widgets/todo_tile.dart        # строка списка (чекбокс + свайп-удаление)
test/widget_test.dart             # widget-тесты основных сценариев
```

Данные хранятся в памяти виджета (`setState`) — после перезапуска приложения
список пуст. Внешних пакетов нет: только Flutter SDK, поэтому сборка под iOS не
требует дополнительных CocoaPods-зависимостей.

## Запуск

```bash
flutter pub get
flutter run          # на подключённом устройстве или эмуляторе
flutter analyze      # статический анализ
flutter test         # widget-тесты
```

## Сборка под iOS

Собрать iOS-приложение можно **только на macOS**: нужны Xcode и CocoaPods,
которых на Windows/Linux нет. Папка `ios/` в проекте уже сгенерирована, так что
на Mac достаточно скопировать проект и выполнить:

```bash
# на macOS
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
flutter doctor                 # проверьте, что Xcode и CocoaPods без ошибок
flutter pub get
cd ios && pod install && cd .. # приложение пока без плагинов, но шаг безопасен
flutter build ios --release    # сборка без подписи
flutter build ipa              # архив .ipa для App Store / TestFlight
open ios/Runner.xcworkspace    # либо сборка и запуск прямо из Xcode
```

Полезно знать:

- **Bundle Identifier** сейчас `com.example.flutterTestApp`
  (`ios/Runner.xcodeproj/project.pbxproj`). Перед публикацией замените
  `com.example` на свой домен и заведите App ID в Apple Developer.
- **Минимальная версия iOS** — 13.0 (`IPHONEOS_DEPLOYMENT_TARGET`).
- Для запуска на реальном устройстве нужна команда разработчика Apple:
  в Xcode откройте `ios/Runner.xcworkspace` → таргет `Runner` → вкладка
  *Signing & Capabilities* → выберите свою Team и включите
  *Automatically manage signing*.
- Сборка без подписи для проверки компиляции: `flutter build ios --no-codesign`.
- Для распространения: `flutter build ipa`, затем `open build/ios/archive/`
  и загрузка через Xcode Organizer или `xcrun altool` / Transporter.

## Что можно добавить дальше

- сохранение задач между запусками (например, `shared_preferences`);
- фильтры «Все / Активные / Выполненные»;
- редактирование текста задачи и дедлайны.

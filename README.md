# flutter_test_app

Простой список дел (to-do list) на Flutter + настроенный CI, который собирает
**неподписанный `.ipa`** под iOS и публикует его в GitHub Releases.

Личный Mac не нужен: сборка идёт на macOS-раннере GitHub Actions, а подпись выполняет
SideStore прямо на iPhone.

## Возможности

- добавление задачи через поле внизу экрана (или клавишей Enter / «Готово»);
- отметка задачи выполненной чекбоксом — текст зачёркивается;
- удаление задачи свайпом влево;
- счётчик «Осталось: N из M»;
- кнопка в AppBar для удаления всех выполненных задач;
- заглушка «Пока пусто», когда список пуст.

## Структура

```
.github/workflows/build-ios.yml   # CI: сборка unsigned .ipa + публикация в Releases
docs/IOS_SIDESTORE_GUIDE.md       # пошаговая установка .ipa на iPhone через SideStore
lib/
├── main.dart                     # точка входа и тема приложения
├── models/todo.dart              # модель задачи
├── screens/todo_list_screen.dart # экран списка, счётчик, поле ввода
└── widgets/todo_tile.dart        # строка списка (чекбокс + свайп-удаление)
test/widget_test.dart             # widget-тесты основных сценариев
ios/                              # iOS-проект Xcode (используется в CI)
```

Данные хранятся в памяти виджета (`setState`) — после перезапуска приложения
список пуст. Внешних пакетов нет: только Flutter SDK.

## Запуск

```bash
flutter pub get
flutter run          # на подключённом устройстве или эмуляторе
flutter analyze      # статический анализ
flutter test         # widget-тесты
```

## CI: как получить `.ipa`

1. Запушьте изменения в `master` (или `main`), **либо** запустите вручную:
   GitHub → вкладка **Actions** → **Build unsigned iOS IPA** → **Run workflow**.
2. Дождитесь завершения сборки (~5–10 минут в первый раз, дальше быстрее за счёт кэша).
3. Забирайте результат:
   - **Releases** — файл `flutter_test_app-<версия>-unsigned.ipa`; эту ссылку удобно
     открыть прямо в Safari на iPhone и скачать `.ipa` в приложение «Файлы»;
   - **Artifacts** — `flutter-test-app-unsigned-ipa` (скачивание требует входа в GitHub).

Что делает workflow: checkout → установка Flutter (версия зафиксирована, кэш SDK и pub) →
`flutter pub get` → кэш CocoaPods → `pod install` (только если есть `Podfile`) →
`flutter build ios --release --no-codesign` → упаковка `Runner.app` в `Payload/*.ipa` →
проверка структуры архива → upload artifact → создание GitHub Release.

Секреты для этого проекта **не нужны**: все зависимости публичные, подпись не выполняется.
`GITHUB_TOKEN` используется автоматически для создания Release (`permissions: contents: write`).
Если появятся приватные зависимости, понадобятся `PRIVATE_REPO_TOKEN` (HTTPS) или
`PRIVATE_REPO_SSH_KEY` (SSH) — добавляются в Settings → Secrets and variables → Actions.

## Сборка под iOS локально (альтернатива CI)

Возможна **только на macOS** — нужны Xcode и CocoaPods, которых на Windows/Linux нет:

```bash
# на macOS
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
flutter doctor
flutter pub get
flutter build ios --release --no-codesign   # сборка без подписи
open ios/Runner.xcworkspace                 # либо сборка и запуск из Xcode
```

Полезно знать:

- **Bundle Identifier** — `com.example.flutterTestApp`
  (`ios/Runner.xcodeproj/project.pbxproj`). Менять не обязательно, если приложение
  ставится через SideStore; для App Store понадобится свой App ID.
- **Минимальная версия iOS** — 13.0 (`IPHONEOS_DEPLOYMENT_TARGET`).
- **CocoaPods сейчас не используется**: в проекте нет плагинов с нативным кодом, поэтому
  `ios/Podfile` не создаётся и `pod install` запускать не нужно. Как только появится первый
  плагин (например, `shared_preferences`), Flutter создаст `Podfile` сам, и шаг в CI
  начнёт работать автоматически.
- Подпись для установки на устройство в этой схеме не нужна: её делает SideStore.

## Установка на iPhone через SideStore

Полная инструкция — [`docs/IOS_SIDESTORE_GUIDE.md`](docs/IOS_SIDESTORE_GUIDE.md).

Кратко: iTunes (драйверы) → [iloader](https://iloader.app) → установка SideStore по кабелю →
[LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044) из App Store → режим
разработчика и доверие сертификату → скачать `.ipa` из Releases в Safari →
SideStore → My Apps → «+».

Лимиты бесплатного Apple ID: **3 приложения** (включая сам SideStore), **7 дней** до
переподписи, 10 App ID в неделю.

## Что можно добавить дальше

- сохранение задач между запусками (например, `shared_preferences`);
- фильтры «Все / Активные / Выполненные»;
- редактирование текста задачи и дедлайны.

# flutter_test_app

Простой список дел (to-do list) на Flutter: приложение + **виджет на главный экран iOS**
+ CI, который собирает **неподписанный `.ipa`** и публикует его в GitHub Releases.

Личный Mac не нужен: сборка идёт на macOS-раннере GitHub Actions, а подпись выполняет
установщик (iloader / SideStore) прямо на iPhone.

## Возможности

- добавление задачи через поле внизу экрана (или клавишей Enter / «Готово»);
- отметка задачи выполненной чекбоксом — текст зачёркивается;
- удаление задачи свайпом влево;
- счётчик «Осталось: N из M»;
- кнопка в AppBar для удаления всех выполненных задач;
- задачи сохраняются между запусками приложения;
- **виджет iOS** с кратким списком задач (маленький, средний и большой размеры).

## Структура

```
.github/workflows/build-ios.yml      # CI: сборка .ipa (приложение + виджет) и Release
docs/IOS_SIDESTORE_GUIDE.md          # установка на iPhone, виджет, ограничения App Groups
lib/
├── main.dart                        # точка входа и тема приложения
├── models/todo.dart                 # модель задачи + JSON для виджета
├── services/todo_store.dart         # хранилище: SharedPreferences + App Group
├── screens/todo_list_screen.dart    # экран списка, счётчик, поле ввода
└── widgets/todo_tile.dart           # строка списка (чекбокс + свайп-удаление)
test/widget_test.dart                # widget-тесты основных сценариев
tools/validate_pbxproj.py            # проверка Xcode-проектов без macOS
ios/
├── Runner/                          # приложение (Flutter)
│   └── Runner.entitlements          # App Group для приложения
└── TodoWidget/                      # виджет: отдельный Xcode-проект
    ├── TodoWidget.xcodeproj
    └── TodoWidget/                  # Swift-код виджета, Info.plist, entitlements
```

Задачи хранятся локально (`shared_preferences`), а для виджета дублируются в общий
App Group-контейнер (`home_widget`) — оттуда их читает Swift-код виджета.

## Виджет iOS

Виджет — это расширение `TodoWidget` (SwiftUI + WidgetKit). Dart-код в нём не
исполняется: приложение только пишет задачи в общий контейнер и просит систему
перерисовать виджет (`WidgetCenter.reloadTimelines`). Идентификатор App Group
`group.com.example.flutterTestApp` должен совпадать в трёх местах:
`lib/services/todo_store.dart`, `ios/Runner/Runner.entitlements`,
`ios/TodoWidget/TodoWidget/TodoWidget.entitlements`.

Важное ограничение: **App Groups Apple выдаёт только платным аккаунтам Apple
Developer**. С бесплатным Apple ID общий контейнер, скорее всего, не появится, и виджет
покажет заглушку «Задач пока нет» (приложение при этом работает нормально). Подпись
бандла с entitlements делается в CI именно для того, чтобы установщик мог перенести
группу при sideloading. Подробности — в
[`docs/IOS_SIDESTORE_GUIDE.md`](docs/IOS_SIDESTORE_GUIDE.md).

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

Секреты для этого проекта **не нужны**: все зависимости публичные, Apple-аккаунт для
сборки не требуется. `GITHUB_TOKEN` используется автоматически для создания Release
(`permissions: contents: write`).
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
- **CocoaPods используется**: в проекте есть плагины (`shared_preferences`, `home_widget`),
  поэтому Flutter генерирует `Podfile` (`flutter build ios --config-only`), после чего
  выполняется `pod install`. В git `Podfile` не хранится.
- **Виджет** собирается отдельным проектом `ios/TodoWidget/TodoWidget.xcodeproj` и
  встраивается в `Runner.app/PlugIns/` на этапе CI — Flutter-проект при этом не
  модифицируется вообще.
- **Минимальная версия iOS для виджета** — 17.0 (WidgetKit и используемые API);
  само приложение по-прежнему собирается с `IPHONEOS_DEPLOYMENT_TARGET = 13.0`.
- Подпись для установки делает ваш установщик (iloader / SideStore). CI подписывает
  бандл ad-hoc только для того, чтобы в подписи сохранились entitlements (App Group).

## Установка на iPhone через SideStore

Полная инструкция — [`docs/IOS_SIDESTORE_GUIDE.md`](docs/IOS_SIDESTORE_GUIDE.md).

Кратко: iTunes (драйверы) → [iloader](https://iloader.app) → установка SideStore по кабелю →
[LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044) из App Store → режим
разработчика и доверие сертификату → скачать `.ipa` из Releases в Safari →
SideStore → My Apps → «+».

Лимиты бесплатного Apple ID: **3 приложения** (включая сам SideStore), **7 дней** до
переподписи, 10 App ID в неделю.

## Что можно добавить дальше

- фильтры «Все / Активные / Выполненные»;
- редактирование текста задачи и дедлайны;
- интерактивный виджет: отмечать задачи прямо с главного экрана (iOS 17+).

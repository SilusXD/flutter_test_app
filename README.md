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
├── services/
│   ├── todo_store.dart              # хранилище + отправка данных в виджет
│   ├── gist_client.dart             # запись и чтение GitHub Gist
│   └── sync_settings.dart           # raw-URL и токен (локально)
├── screens/
│   ├── todo_list_screen.dart        # экран списка, счётчик, поле ввода
│   └── settings_screen.dart         # настройки обмена с виджетом
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

Виджет — расширение `TodoWidget` (SwiftUI + WidgetKit). Dart-код в нём не исполняется:
виджеты iOS пишутся только на Swift, Flutter-часть отвечает за данные.

**Канал обмена — сеть.** App Group, через которую виджет обычно читает данные
приложения, на бесплатном Apple ID недоступна: iOS создаёт общий контейнер только если
этот entitlement есть в provisioning profile, а Apple добавляет App Groups лишь в платную
программу Apple Developer. Это проверено на двух установщиках (SideStore и iloader) —
оба дали «App Group не активирована».

Поэтому схема такая:

```
Flutter → PATCH https://api.github.com/gists/<id>  →  приватный Gist  →  URLSession в виджете
                (токен со scope «gist»)                  (raw-URL)         + кеш в контейнере расширения
```

Настройка (один раз):

1. Создайте на github.com **секретный** gist с файлом `todos.json` и содержимым `[]`.
2. Скопируйте ссылку **Raw** на этот файл. Из неё автоматически убирается хеш ревизии
   (`.../raw/8f3c1a…/todos.json` → `.../raw/todos.json`): адрес с хешем всегда отдаёт
   старую версию файла, и виджет показывал бы устаревшие данные. Имя файла берётся из
   URL — приложение пишет ровно в тот файл, который читает виджет.
3. Создайте GitHub-токен (Personal access tokens **classic**) со scope `gist`.
4. В приложении: иконка шестерёнки → вставьте raw-URL и токен → «Проверить связь» → «Сохранить».
5. В репозитории: Settings → Secrets and variables → Actions → новый секрет
   **`TODO_GIST_URL`** с тем же raw-URL. Адрес виджету задаётся при сборке, потому что
   прочитать настройки приложения он не может.
6. Пересоберите приложение — виджет покажет задачи.

Ограничения, о которых стоит помнить: список задач хранится на сервере GitHub, токен
лежит на устройстве в открытом виде (создавайте отдельный токен только с правом `gist`),
а без интернета виджет покажет последние закешированные данные.

Диагностика встроена: под счётчиком задач видно статус — «Виджет обновлён»,
«Виджет не настроен: укажите Gist URL и токен» или текст ошибки (например,
«Токен отклонён (401)»). Подробности — в
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
- **Минимальная версия iOS** — 16.0 (`IPHONEOS_DEPLOYMENT_TARGET`). Ниже нельзя:
  плагин `home_widget` требует минимум 14.0, а сборка идёт современным Xcode.
- **CocoaPods используется**: в проекте есть плагины (`shared_preferences`, `home_widget`),
  поэтому Flutter генерирует `Podfile` (`flutter build ios --config-only`), после чего
  выполняется `pod install`. В git `Podfile` не хранится.
- **Виджет** собирается отдельным проектом `ios/TodoWidget/TodoWidget.xcodeproj` и
  встраивается в `Runner.app/PlugIns/` на этапе CI — Flutter-проект при этом не
  модифицируется вообще.
- **Минимальная версия iOS для виджета** — 16.0, как и у приложения (фон виджета
  задаётся через `containerBackground` только на iOS 17+, на 16 и ниже его рисует система).
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

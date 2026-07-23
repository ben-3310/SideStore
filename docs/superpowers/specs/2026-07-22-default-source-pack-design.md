# Default Source Pack Design

## Цель

Перед сборкой IPA встроить в приложение snapshot пользовательского списка
репозиториев из:

`/Users/ben/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/RepoInstaller/Settings/pack.json`

Файл `pack.json` сейчас указывает на `default.json`; реальный pack лежит в
`RepoInstaller/Packs/default.json` и содержит объект с ключом `repos` на 81 URL.
После установки/первого запуска собранного приложения эти источники должны быть
добавлены в локальную Core Data базу SideStore без ручного ввода пользователем.

## Выбранный подход

В репозиторий добавляется собственный JSON-ресурс приложения, например
`AltStore/Resources/DefaultSources.json`. Он является committed snapshot
текущего pack, а не ссылкой на iCloud-файл и не сетевой загрузкой во время
archive. Это делает IPA воспроизводимым: Task 4 archive/export будет собирать
уже зафиксированный список sources.

В app target добавляется отдельный importer, например
`AltStore/Managing Apps/DefaultSourcePackImporter.swift`. Importer запускается
из `AppDelegate` только после успешного `DatabaseManager.shared.start`, потому
что к этому моменту Core Data уже загружена и `DatabaseManager.prepareDatabase`
создал официальный SideStore source. Importer остаётся в app layer, а не в
`AltStoreCore`, потому что готовая логика `AppManager.shared.fetchSource` и
`FetchSourceOperation` находится в app target.

`AppManager.add(_:presentingViewController:)` не используется: он требует UI
confirmation. Для этого build пользователь явно запросил предзагрузку списка,
поэтому importer выполняет trust bypass осознанно, только для bundled pack.

## Данные и идемпотентность

Bundled resource должен содержать:

- `version`: целое число pack-version, начальное значение `1`;
- `name`: имя pack, например `Default`;
- `repos`: массив URL из `RepoInstaller/Packs/default.json`.

Importer хранит в `UserDefaults.shared` приватный marker последней полностью
обработанной версии pack. Если marker больше или равен `version`, importer
ничего не делает.

Перед сетевым fetch для каждого URL importer вычисляет `Source.sourceID(from:)`
и пропускает source, если source с таким identifier уже существует в Core Data.
Это сохраняет пользовательские изменения и не создаёт дубликаты при повторном
запуске или обновлении pack.

Bundled snapshot сохраняет все 81 URL исходного pack в исходном порядке. Пара
`https://pokemmo.com/altstore/` и `https://pokemmo.com/altstore` является
ожидаемым нормализованным дубликатом: importer добавляет первый источник и
пропускает второй, поэтому snapshot содержит 80 уникальных source identifiers.

Marker обновляется после завершения всего прохода по pack, даже если отдельные
репозитории недоступны, заблокированы или имеют невалидный JSON. Это важно,
чтобы приложение не создавало 81 сетевой запрос на каждом старте. Новый проход
запускается только при повышении bundled `version`.

## Выполнение и ошибки

Importer не блокирует запуск UI. После старта базы `AppDelegate` запускает
асинхронную задачу импорта и пишет ход в `debugLog`.

Сетевые fetch выполняются с ограниченной конкуренцией, максимум 4 URL
одновременно. Для каждого успешно fetched source importer сохраняет его
background context в persistent store и публикует
`AppManager.didAddSourceNotification` с сохранённым `Source`, чтобы существующие
экраны sources могли обновиться.

Ошибки отдельных URL логируются с URL и sanitized error description, но не
прерывают весь import и не приводят к crash. Ошибка загрузки самого bundled
resource является programming error: importer логирует её и не обновляет marker,
потому что без resource он не может доказать, какую версию pack обработал.

## Тестирование

План реализации должен идти через TDD.

Минимальные проверки:

- contract test для `AltStore/Resources/DefaultSources.json`: resource существует,
  имеет `version == 1`, содержит ровно 81 URL, все URL имеют схему `http` или
  `https`, после нормализации получаются ровно 80 уникальных identifiers, а
  единственный дубликат — ожидаемая пара `pokemmo.com/altstore`;
- contract/static test для importer: он загружает именно bundled resource,
  имеет marker-key/idempotency guard, вызывает `Source.sourceID(from:)` перед
  fetch, использует `AppManager.shared.fetchSource`, сохраняет context и не
  вызывает UI-only `AppManager.add`;
- build-level validation перед IPA archive: существующие targeted Python tests
  для source pack проходят вместе с Task 1/2 tests; Xcode archive из Task 4
  проверяет, что ресурс попадает в app bundle.

Тесты не должны ходить в сеть и не должны читать iCloud pack напрямую после
того, как snapshot попал в репозиторий. iCloud-файл является входом для
создания snapshot, а committed resource является source of truth для сборки IPA.

## Границы

Эта функция не меняет remote trusted-sources endpoint
`https://sidestore.io/trusted-sources`, не добавляет UI для выбора pack и не
создаёт внешнюю TestFlight/App Store submission. Она только предзагружает
committed source pack в локальную базу приложения до сборки IPA по текущему
плану.

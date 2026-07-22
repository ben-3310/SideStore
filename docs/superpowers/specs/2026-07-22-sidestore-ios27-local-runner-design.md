# Дизайн локального SideStore runner для Xcode и iOS 27

## Цель

Подготовить текущий Mac `Denyss-MacBook-Pro.local` как второй изолированный
repository-level GitHub Actions runner для `ben-3310/SideStore`. Новый runner
проверяет совместимость SideStore с уже установленными Xcode 27.0 и iOS 27.0,
не заменяет release runner `air-sidestore` с Xcode 26.6 и не получает
production/deploy secrets.

## Подтверждённое окружение

- macOS 27.0, Apple Silicon `arm64`;
- выбранный developer directory:
  `/Applications/Xcode-beta.app/Contents/Developer`;
- Xcode 27.0, build `27A5194q`;
- iOS 27.0 SDK и Simulator runtime `24A5355p`;
- device type Simulator `iPhone 13` поддерживается Xcode 27 и создаётся для
  runtime iOS 27.0, потому что Xcode не создаёт его автоматически;
- Homebrew build tools `ldid`, `xcbeautify` и `wget` уже установлены;
- официальный GitHub Actions runner 2.336.0 для macOS ARM64, SHA-256
  `8e8839c49b7060b6b2154f4931f815df330c27f167d53ef2239ee3dfce28b079`.

Xcode не устанавливается, не переименовывается и не переключается глобально.
Runner использует существующий `Xcode-beta.app` через собственный
`DEVELOPER_DIR`.

## Изоляция пользователя

Локальная учётная запись `github-runner-sidestore` имеет:

- UID 502 и основную группу `staff`;
- отсутствие членства в `admin` и отсутствие `sudo`;
- password attribute `*`, поэтому интерактивный парольный вход невозможен;
- отсутствие членства в `com.apple.access_ssh`;
- только необходимое членство в `_developer` для Xcode/Simulator;
- HOME `/Users/github-runner-sidestore` с режимом `0700`;
- отдельные `_work`, DerivedData, SwiftPM/Homebrew caches, logs и smoke-каталог;
- точечный deny ACL на `/Users/ben`.

Профиль runner задаёт:

```text
PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
SIMULATOR_DEVICE=iPhone 13
SIMULATOR_OS=27.0
```

LaunchDaemon дополнительно задаёт umask `0077`.

## Регистрация GitHub runner

Runner регистрируется только в `ben-3310/SideStore`:

- name: `denys-mbp-sidestore`;
- standard labels: `self-hosted`, `macOS`, `ARM64`;
- custom labels: `sidestore`, `xcode-27-0`, `ios-27`;
- work directory: `_work` внутри HOME runner;
- runner auto-update остаётся включён.

Одноразовый registration token передаётся непосредственно в `config.sh` и не
сохраняется в shell history, файлы проекта или service plist. Созданные
`.credentials` и `.credentials_rsaparams` закрываются режимом `0600`.

## Headless service

Официальный пользовательский LaunchAgent не используется, потому что runner
должен работать без GUI login session. Root-owned LaunchDaemon
`/Library/LaunchDaemons/actions.runner.ben-3310-SideStore.denys-mbp-sidestore.plist`
запускает официальный `runsvc.sh` от имени `github-runner-sidestore`.

Service использует `RunAtLoad`, `KeepAlive`, `ProcessType=Interactive`,
`SessionCreate=true`, `Umask=0077` и закрытые stdout/stderr logs в HOME runner.
При питании от адаптера системный sleep отключается; display sleep и батарейный
режим не изменяются.

## CI-маршрутизация

`nightly.yml` и `stable.yml` остаются на `air-sidestore` с label
`xcode-26-6`. Новый beta runner не участвует в release-сборках.

Отдельный candidate workflow `.github/workflows/ios27-compatibility.yml`:

- запускается только на доверенном `push` в `develop` и вручную через
  `workflow_dispatch`;
- использует точные labels
  `[self-hosted, macOS, ARM64, sidestore, xcode-27-0, ios-27]`;
- не запускается на `pull_request`;
- не получает deploy/signing secrets и не публикует release;
- проверяет Xcode 27.0, `SIMULATOR_DEVICE=iPhone 13`, `SIMULATOR_OS=27.0`,
  iOS 27.0 runtime и build tools;
- выполняет repository regression checks, archive без signing, simulator
  build-for-testing и headless boot `iPhone 13` на iOS 27.0;
- загружает только диагностические build logs, если workflow будет опубликован.

Изменения workflow остаются локальным candidate до отдельного разрешения на
push.

## Состояние Xcode tests

Текущие `SideStore.xcscheme` и `SideStoreTests.xctestplan` ссылаются на
`UITests` target `A8E2DB202D684CBD009E5D31`, но этот target был намеренно удалён
из `AltStore.xcodeproj/project.pbxproj` коммитом `3927cbd4`. Поэтому
`build-for-testing` компилирует приложение, а `test-without-building` сообщает
`There are no test bundles available to test`.

Настройка runner не восстанавливает удалённый test target и не объявляет UI
tests зелёными. Для текущей задачи iOS 27 acceptance включает compile/archive,
build-for-testing и реальный boot Simulator. Восстановление test target и
стабилизация UI tests требуют отдельного review-gated изменения проекта.

## Проверка готовности

Готовность подтверждается следующим evidence:

1. Пользователь существует, не входит в `admin`/SSH и не может читать
   `/Users/ben`.
2. HOME, `_work`, caches и credentials закрыты; процесс runner работает с UID
   502 и umask `0077`.
3. Xcode 27.0, iOS 27.0 runtime, `ldid`, `xcbeautify` и `wget` доступны от имени
   runner.
4. GitHub показывает `denys-mbp-sidestore` как `online`/`idle` с точными labels.
5. LaunchDaemon восстанавливает listener после адресной остановки процесса.
6. Чистый checkout с submodules проходит archive, IPA/dSYM packaging,
   build-for-testing и boot iOS 27.0 Simulator.
7. В plist, `.env`, `.path` и logs нет registration token, пароля или private
   key.
8. `air-sidestore` остаётся `online`, release workflows не изменены.
9. Пользовательские `.build`, IPA и dSYM в основном checkout сохранены.
10. Push не выполняется без отдельного разрешения.

## Откат

1. Остановить и удалить только LaunchDaemon
   `actions.runner.ben-3310-SideStore.denys-mbp-sidestore`.
2. Удалить GitHub registration через официальный `config.sh remove` с
   одноразовым remove token.
3. Удалить локальный compatibility workflow candidate или вернуть его commit.
4. Удалить `github-runner-sidestore` и его HOME только после проверки
   отсутствия уникальных logs/artifacts.
5. Вернуть AC sleep к исходному значению `1`, если пользователь хочет полный
   системный откат.

Откат не изменяет Xcode-beta, Homebrew, основной checkout и удалённый runner
`air-sidestore`.

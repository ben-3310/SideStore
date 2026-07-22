# Дизайн self-hosted runner для SideStore

## Цель

Подготовить Mac `air` (`192.168.88.222`, Apple Silicon, macOS 26) как
репозиторный GitHub Actions runner для `ben-3310/SideStore`. Runner должен
выполнять только доверенные сборки SideStore и не затрагивать существующий
runner `china_link`, работающий под пользователем `ben`.

Репозиторий публичный. Workflow `pull_request` остаётся на GitHub-hosted
`macos-26`: код из внешнего fork нельзя запускать на постоянном runner в
домашней сети.

## Выбранный вариант

Используется постоянный repository-level runner для доверенных событий:

- `nightly.yml`: `push` в `develop`, `schedule`, `workflow_dispatch`;
- `stable.yml`: доверенные теги и `workflow_dispatch`.

Следующие workflow не переводятся на новый runner:

- `pr.yml` — публичные pull request;
- `alpha.yml` — пока требует Xcode 26.2, тогда как целевой toolchain runner —
  Xcode 26.6;
- Linux-задачи `attach_build_products.yml` и `triage.yml`.

Публикация изменений workflow в GitHub выполняется только после отдельного
разрешения пользователя. До публикации runner может быть зарегистрирован и
проверен ручным безопасным заданием или локальным smoke-test.

Фактический preflight 2026-07-22 подтвердил установленный Xcode 26.6. Поэтому
целевой toolchain и label изменены с первоначально запланированного Xcode 26.4
на Xcode 26.6; установка второго Xcode не требуется.

## Изоляция учётной записи

На `air` создаётся стандартный локальный пользователь
`github-runner-sidestore` со следующими свойствами:

- без членства в `admin` и без `sudo`;
- домашний каталог `/Users/github-runner-sidestore` с режимом `0700`;
- отключённая парольная аутентификация локальной учётной записи;
- доступ по SSH через отдельный ключ в `~/.ssh/authorized_keys`;
- членство только в группах, необходимых для SSH и developer tools;
- отдельные каталоги runner, `_work`, Xcode/SwiftPM и инструментальных кэшей;
- отсутствие доступа на запись к профилю, runner и кэшам пользователя `ben`.
- точечный deny ACL на `/Users/ben` для `github-runner-sidestore`, поскольку
  стандартная macOS-группа `staff` иначе позволяет читать group-readable файлы.

Локально создаётся отдельный ключ
`/Users/ben/.ssh/air_github_runner_sidestore_ed25519`. Закрытый ключ имеет режим
`0600`, публичный ключ устанавливается удалённому пользователю. Пароли,
регистрационные токены и содержимое закрытого ключа не выводятся в журналы.

## Toolchain SideStore

Перед регистрацией runner проверяются:

- Xcode 26.6 в `/Applications` и выбранный `DEVELOPER_DIR`;
- принятая лицензия и выполненный `xcodebuild -runFirstLaunch`;
- iOS 26 runtime и доступность требуемого SDK;
- `xcodebuild`, `xcrun`, `simctl`, `git`, `python3`, `make`, `bash`, `zip`,
  `unzip`, `curl`;
- рекурсивное извлечение Git submodules;
- `ldid`, `xcbeautify` и `wget` в `/opt/homebrew/bin` (`wget` нужен
  `Dependencies/em_proxy/fetch-prebuilt.sh`);
- не менее 100 GiB свободного места после установки Xcode и runtime;
- исходящее HTTPS-соединение с GitHub.

Общий Homebrew остаётся под управлением `ben`/администратора. Runner получает
доступ на выполнение уже установленных бинарников, но не право изменять
`/opt/homebrew`. В доверенных self-hosted workflow шаг `brew install` заменяется
проверкой наличия `ldid`, `xcbeautify` и `wget`; для GitHub-hosted workflow
эти зависимости устанавливаются явным шагом.

Чтобы сервис не становился `offline` во время простоя, на питании от адаптера
системный sleep отключён (`pmset -c sleep 0`). Настройки экрана и батарейного
режима не изменяются.

## GitHub Actions runner

Устанавливается актуальный официальный пакет `actions/runner` для macOS ARM64.
Перед распаковкой проверяется SHA-256 из официального release. Параметры
регистрации:

- repository: `https://github.com/ben-3310/SideStore`;
- имя: `air-sidestore`;
- стандартные labels: `self-hosted`, `macOS`, `ARM64`;
- пользовательские labels: `sidestore`, `xcode-26-6`;
- рабочий каталог: `_work` внутри каталога runner;
- автоматическое обновление runner включено.

Регистрационный token получается через аутентифицированный GitHub CLI и
передаётся непосредственно `config.sh`; token не сохраняется в файлы и не
печатается.

Runner запускается root-owned LaunchDaemon
`/Library/LaunchDaemons/actions.runner.ben-3310-SideStore.air-sidestore.plist`
от имени `github-runner-sidestore` и автоматически стартует после перезагрузки.
LaunchDaemon используется потому, что официальный пользовательский LaunchAgent
не загружается из headless SSH-сессии без GUI bootstrap domain. Сервис вызывает
официальный `runsvc.sh`, использует `RunAtLoad` и `KeepAlive`, имеет отдельные
stdout/stderr журналы в HOME runner и не получает права администратора.

## Профиль и окружение

Профиль пользователя и окружение сервиса задают минимальный детерминированный
`PATH`:

`/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin`

Создаются закрытые каталоги для:

- `~/actions-runner` и `~/actions-runner/_work`;
- `~/Library/Developer/Xcode/DerivedData`;
- `~/Library/Caches/org.swift.swiftpm`;
- `~/Library/Caches/Homebrew`;
- временных файлов runner.

В профиле не размещаются GitHub token, Apple Account, signing certificates или
другие секреты. Сборка проекта использует существующий режим без обязательного
code signing.

## Изменения workflow

После готовности и smoke-test в `nightly.yml` и `stable.yml` значение
`runs-on` меняется на:

```yaml
runs-on: [self-hosted, macOS, ARM64, sidestore, xcode-26-6]
```

Шаг подготовки зависимостей становится условно идемпотентным: на self-hosted
runner он проверяет `ldid`, `xcbeautify` и `wget`, а не изменяет Homebrew. Setup Xcode
должен выбрать уже установленный Xcode 26.6 либо workflow задаёт
`DEVELOPER_DIR` напрямую после проверки версии.

Simulator destinations в `Makefile` используют `OS=latest`, чтобы Xcode выбрал
установленный iOS 26.5 runtime вместо отсутствующего жёстко заданного 26.0.

`pr.yml` сохраняет `runs-on: macos-26`. Это обязательный security boundary.

## Проверка готовности

Готовность подтверждается следующими evidence:

1. SSH-вход по выделенному ключу без пароля и отказ парольного входа.
2. `id` подтверждает отсутствие `admin` и выполнение от
   `github-runner-sidestore`.
3. Каталоги пользователя, runner, `_work`, SSH и кэшей принадлежат новому
   пользователю и закрыты от других локальных пользователей; runner не может
   читать `/Users/ben`.
4. Xcode 26.6, SDK и требуемые CLI-инструменты видны из окружения runner.
5. Runner отображается в `ben-3310/SideStore` как `online` и `idle` с точными
   labels.
6. `launchd` запускает процесс под правильным UID и восстанавливает его после
   остановки процесса или перезагрузки сервиса.
7. Локальный checkout с рекурсивными submodules проходит preflight, archive,
   fake signing, упаковку IPA/dSYM и build-for-testing без signing secrets;
   iOS Simulator успешно загружается в headless-сессии.
8. В service plist, process environment и журналах нет registration token,
   SSH-пароля или закрытого ключа.
9. Существующий runner `china_link` остаётся `online` и работает под `ben`.
10. До публикации workflow не выполняется реальная маршрутизация production
    nightly/stable jobs на новый runner.

## Ошибки и остановка

- Если Xcode 26.6 или iOS 26 runtime отсутствуют, регистрация может быть
  завершена, но workflow не маршрутизируются и runner не объявляется готовым.
- Если стандартный пользователь не может использовать toolchain без `admin`,
  выдача `admin` запрещена; устраняется только конкретное системное разрешение.
- Если smoke-test требует секреты или signing identities, проверка останавливается
  до отдельного разрешения пользователя.
- Если GitHub runner не получает job из-за labels, исправляются регистрация или
  labels; workflow не расширяется до общих `self-hosted` labels.
- Если обнаружено влияние на `china_link`, SideStore service останавливается и
  изменения изоляции пересматриваются.

## Откат

Откат выполняется в обратном порядке:

1. вернуть `nightly.yml` и `stable.yml` на `macos-26`, если они были изменены;
2. остановить и удалить SideStore `launchd` service;
3. удалить регистрацию `air-sidestore` из `ben-3310/SideStore`;
4. сохранить диагностические журналы без секретов;
5. удалить отдельного пользователя и его home только после проверки, что там
   нет нужных артефактов;
6. удалить локальный выделенный SSH-ключ только по отдельному подтверждению.

Откат не изменяет Xcode, Homebrew и существующий `china_link` runner.

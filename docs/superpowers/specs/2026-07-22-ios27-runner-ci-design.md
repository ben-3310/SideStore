# Уточнённое задание: SideStore runner и UI smoke на iOS 27

Дата: 2026-07-22

## Результат аудита

Первоначальный план был шире реальной задачи. Проверка репозитория, истории и
живой сборки Xcode 27 показала:

- `UITests` удалён коммитом `b407bb72`, но его исходники, shared scheme и test
  plan остались. Это незавершённое удаление, поэтому target нужно восстановить.
- `DataStructureTests` удалён тем же коммитом, но не входит в test plan схемы
  `SideStore` и не нужен iOS 27 runner. Его восстановление — отдельная задача.
- Восстановленный `UITests` успешно компилируется на `iPhone 13`, iOS 27.
- Слепо восстановленный старый xcconfig теперь создаёт bundle ID `.UITests`:
  после рефакторинга `Build.xcconfig` нужно наследовать
  `MAIN_BUNDLE_IDENTIFIER`, а не ссылаться на `PRODUCT_BUNDLE_IDENTIFIER`
  рекурсивно.
- Текущий `SideStoreTests.xctestplan` запускает все сетевые UI-тесты. Они
  удаляют приложение, зависят от локализованных системных alert и внешних URL.
  Такой набор нельзя делать обязательным CI gate.
- `workflow.py` запускает `tests-build` и `tests-run` через shell pipelines без
  `pipefail`. Ошибка `xcodebuild` может быть скрыта успешным `xcbeautify` или
  `tee`.
- iOS 27 workflow создаёт или переиспользует симулятор по имени, но не передаёт
  его UDID в `xcodebuild` и вообще не запускает XCTest.
- Локальная ветка содержит более двух тысяч строк процессной документации.
  Публиковать её вместе с небольшим CI-изменением не нужно.

## Скорректированная цель

Подготовить два уже зарегистрированных runner к их фактическим ролям:

- `air-sidestore`, Xcode 26.6 — доверенные nightly/stable сборки;
- `denys-mbp-sidestore`, Xcode 27 — проверка `iPhone 13`, iOS 27.

Для Xcode 27 нужен честный минимальный gate:

1. архив SideStore собирается;
2. `UITests` target существует и компилируется;
3. на отдельном `iPhone 13`, iOS 27 выполняется один детерминированный launch
   smoke;
4. ненулевой exit code `xcodebuild` всегда делает job красным;
5. `.xcresult` сохраняется для диагностики.

## Изменения в проекте

### UITests target

Восстанавливается только `UITests` с прежним target ID
`A8E2DB202D684CBD009E5D31`, чтобы существующая схема продолжила работать.
Возвращаются его product reference, build phases, target dependency,
configuration list и membership исходников.

`xcconfigs/UITests.xcconfig` должен использовать текущий контракт:

```xcconfig
#include "../Build.xcconfig"

PRODUCT_BUNDLE_IDENTIFIER = $(MAIN_BUNDLE_IDENTIFIER).UITests
```

Regression-тест проверяет target graph, разрешение scheme/test plan и итоговый
bundle ID. `DataStructureTests` в этот diff не входит.

### Детерминированный UI smoke

В `UITestsLaunchTests` включается один тест, который запускает приложение и
проверяет переход в foreground. Обязательная CI-конфигурация test plan исключает
четыре сетевых bulk-source сценария.

Исходники сетевых тестов не удаляются: они остаются для ручного запуска и
отдельной стабилизации. CI не должен обращаться к внешним каталогам приложений.

### Честное выполнение команд

В `workflow.py` test pipelines получают `set -o pipefail`. Проверка считается
успешной только по реальному exit code `make`/`xcodebuild`, а не последней
команды pipeline.

Makefile принимает полный `SIMULATOR_DESTINATION`. Workflow создаёт уникальный
симулятор, записывает destination с его UDID и удаляет только этот симулятор в
`always()` cleanup.

После `build-for-testing` workflow загружает симулятор, выполняет
`test-without-building` и всегда публикует `.xcresult`.

## GitHub Actions и безопасность

- Self-hosted iOS 27 workflow запускается только из доверенного контекста:
  `push` в `develop` и `workflow_dispatch`.
- `pull_request` и `pull_request_target` для self-hosted job не добавляются.
- Workflow получает только `contents: read`.
- Actions, используемые этим новым включаемым workflow, закрепляются за commit
  SHA. Массовое переписывание всех старых workflow не входит в задачу.
- Nightly/stable routing к `air-sidestore` сохраняется, но эти workflow в форке
  не включаются автоматически.
- `CROSS_REPO_PUSH_KEY` не создаётся. Любой cross-repository deploy остаётся
  недоступным.

## Публикация

Процессные спецификации и планы остаются локальными. Для GitHub создаётся
чистая публикационная ветка от `origin/develop`, содержащая только необходимый
product/CI diff и его regression-тесты.

Push, PR и merge допустимы только в `ben-3310/SideStore`. Перед каждой записью
проверяется owner. `SideStore/SideStore` используется только для чтения.

## Не входит в задачу

- восстановление `DataStructureTests`;
- стабилизация всех сетевых UI-тестов;
- изменение `pr.yml`, alpha, release metadata или внешнего apps repository;
- массовое обновление/pinning всех старых actions;
- branch protection и rulesets до появления стабильного CI check;
- публикация AI-планов и внутренних runbook в продуктовый PR;
- удаление пользовательских `.ipa`, `.zip`, `.build` и других артефактов;
- изменение runner другого проекта на удалённом Mac.

## Критерии завершения

- Xcode 27 показывает `UITests` target и корректный bundle ID.
- `build-for-testing` и один launch smoke проходят на отдельном `iPhone 13`,
  iOS 27.
- Искусственно сломанный test command подтверждает, что pipeline возвращает
  ошибку, а не ложный success.
- Симулятор адресуется точным UDID и удаляется после job.
- На GitHub опубликован только компактный функциональный diff в
  `ben-3310/SideStore`; upstream не изменён.

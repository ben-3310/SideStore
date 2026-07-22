# Скорректированный план SideStore UI smoke на iOS 27

## 1. Сузить восстановление до UITests

Файлы:

- `AltStore.xcodeproj/project.pbxproj`;
- `xcconfigs/UITests.xcconfig`;
- `scripts/ci/test_xcode_test_targets.py`.

Действия:

1. Из regression-теста убрать требования к `DataStructureTests`.
2. Из уже подготовленного project diff удалить все объекты
   `DataStructureTests` и его xcconfig.
3. Исправить `UITests.xcconfig` на
   `$(MAIN_BUNDLE_IDENTIFIER).UITests`.
4. Проверить `xcodebuild -list` и `-showBuildSettings -target UITests`.
5. Ожидать bundle ID вида `com.SideStore.SideStore.UITests`, не `.UITests`.

Коммит: `fix: restore SideStore UITests target`.

## 2. Сделать один устойчивый UI launch smoke

Файлы:

- `SideStore/Tests/UITests/UITestsLaunchTests.swift`;
- `SideStore/Tests/SideStoreTests.xctestplan`;
- `AltStore.xcodeproj/xcshareddata/xcschemes/SideStore.xcscheme`;
- `scripts/ci/test_xcode_test_targets.py`.

Действия:

1. Сначала тестом потребовать активный `testLaunch()` и отсутствие ссылки на
   несуществующий `UITests/testExample()`.
2. Включить launch smoke, который проверяет foreground state приложения.
3. В обязательной конфигурации test plan пропустить четыре сетевых теста и
   выполнять launch smoke.
4. Сетевые тестовые исходники не удалять.

Коммит: `test: add deterministic SideStore launch smoke`.

## 3. Исправить ложнозелёные test pipelines

Файлы:

- `scripts/ci/workflow.py`;
- новый или существующий тест в `scripts/ci/`.

Действия:

1. Regression-тестом подтвердить, что pipeline с падающей первой командой не
   возвращает ноль.
2. Добавить `set -o pipefail &&` в `tests_build()` и `tests_run()`.
3. Не менять release/deploy функции.

Коммит: `fix: propagate SideStore test failures`.

## 4. Использовать точный simulator destination

Файлы:

- `Makefile`;
- `scripts/ci/test_runner_workflows.py`.

Действия:

1. Добавить
   `SIMULATOR_DESTINATION ?= platform=iOS Simulator,name=$(SIMULATOR_DEVICE),OS=$(SIMULATOR_OS)`.
2. Все test-команды направить в `$(SIMULATOR_DESTINATION)`.
3. Сохранить совместимость ручного запуска по имени/OS.

Коммит: `ci: support exact simulator destination`.

## 5. Завершить минимальный iOS 27 workflow

Файлы:

- `.github/workflows/ios27-compatibility.yml`;
- `scripts/ci/test_runner_workflows.py`.

Действия:

1. Оставить только `push: develop` и `workflow_dispatch`.
2. Добавить `permissions: contents: read`.
3. Создавать уникальный `iPhone 13` на runtime iOS 27 и передавать его UDID в
   `SIMULATOR_DESTINATION`.
4. Выполнить archive build, `tests-build`, boot и `tests-run`.
5. Загружать `.xcresult` с `if: always()`.
6. В cleanup выключать и удалять только созданный workflow симулятор.
7. Закрепить используемые checkout/upload actions за commit SHA.

Коммит: `ci: run SideStore launch smoke on iOS 27`.

## 6. Проверить exact candidate

Обязательные проверки:

```bash
rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s scripts/ci -p 'test_*.py' -v
rtk actionlint
rtk xcodebuild -project AltStore.xcodeproj -list
```

На отдельном временном симуляторе:

- `iPhone 13`, runtime iOS 27;
- `build-for-testing`;
- `test-without-building`;
- `.xcresult` содержит ровно обязательный launch smoke и ненулевой test count;
- временный симулятор удалён.

Затем зафиксировать candidate SHA и провести полный review диапазона
`origin/develop..candidate`. Допускается не более двух узких fixes-циклов.

## 7. Подготовить компактную публикацию

1. Создать чистую ветку от `origin/develop`.
2. Перенести только функциональные изменения runner/CI, UITests и regression
   tests. Не включать `docs/superpowers/**`.
3. Повторить обязательные проверки на точном publication SHA.
4. Проверить `origin == ben-3310/SideStore`.
5. Push и PR делать только в `ben-3310/SideStore:develop`.
6. Не включать nightly/stable/release workflow автоматически.
7. После merge проверить push-run iOS 27 на `denys-mbp-sidestore`.
8. При post-merge ошибке исправлять отдельной веткой/PR только в форке.

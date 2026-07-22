# План реализации XCTest CI SideStore для iOS 27

> План выполняется последовательно в отдельном Git worktree. После каждого
> смыслового этапа создаётся локальный коммит. Публикация разрешена только в
> `ben-3310/SideStore`.

**Цель:** восстановить удалённые XCTest targets, запустить детерминированные
unit- и UI-smoke-тесты на `iPhone 13` с iOS 27 и сделать безопасный CI в форке.

**Архитектура:** существующие shared schemes и test plans снова связываются с
историческими target ID. Один CI test plan объединяет unit-тесты структур данных
и один устойчивый UI launch smoke. Workflow создаёт отдельный симулятор,
передаёт его UDID в Makefile, выполняет `build-for-testing` и
`test-without-building`, затем публикует `.xcresult`. Self-hosted workflow
исполняется для push в `develop`, ручного запуска и только для внутренних PR из
того же форка.

**Стек:** Xcode 27, `xcodebuild`, XCTest/Swift Testing, CoreSimulator `simctl`,
Python `unittest`, GitHub Actions YAML, `actionlint`, Git/GitHub CLI.

---

## Задача 1. Создать изолированное рабочее дерево

**Файлы:** без изменений.

1. Проверить, что основной checkout содержит только известные пользовательские
   untracked-артефакты.

   ```bash
   rtk git status --short --branch
   rtk git worktree list
   ```

   Ожидание: `develop` опережает `origin/develop`; `.build` и архивы остаются
   нетронутыми.

2. Убедиться, что `.worktrees` игнорируется.

   ```bash
   rtk git check-ignore -q .worktrees
   ```

3. Создать ветку и worktree от текущего `develop`.

   ```bash
   rtk git worktree add .worktrees/ios27-xctest-ci -b agent/ios27-xctest-ci develop
   ```

4. Инициализировать закреплённые submodules без `--remote`.

   ```bash
   rtk git submodule update --init --recursive
   ```

5. Зафиксировать два base SHA:

   ```bash
   rtk git rev-parse HEAD                # task base
   rtk git rev-parse origin/develop      # publication/review base
   ```

   Task base содержит утверждённую спецификацию и этот план. Полный frozen
   review перед PR обязан использовать `origin/develop..candidate`, потому что
   локальный `develop` уже содержит ранее подготовленные runner/CI-коммиты,
   которых ещё нет в форке.

## Задача 2. Зафиксировать отсутствие XCTest targets падающим тестом

**Файлы:**

- создать `scripts/ci/test_xcode_test_targets.py`;
- тестировать `AltStore.xcodeproj/project.pbxproj`;
- тестировать `SideStore/Tests/*.xctestplan` и shared schemes.

1. Добавить `unittest`, который читает проект как текст и JSON test plans.
   Проверить:

   - native target ID `A8E2DB202D684CBD009E5D31` с именем `UITests`;
   - native target ID `A81A8CC42D68BA610086C96F` с именем
     `DataStructureTests`;
   - продукты `UITests.xctest` и `DataStructureTests.xctest`;
   - build phases, configuration lists и зависимость UI target от SideStore;
   - оба target входят в `PBXProject.targets`;
   - test plans и schemes ссылаются только на существующие target ID;
   - оба test-target xcconfig существуют и задают отдельные bundle ID.

2. Запустить только новый тест.

   ```bash
   rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
     scripts.ci.test_xcode_test_targets -v
   ```

   Ожидание: FAIL на отсутствующем `UITests` или `DataStructureTests` target.

3. Закоммитить красный regression-тест.

   ```bash
   rtk git add scripts/ci/test_xcode_test_targets.py
   rtk git commit -m "test: require SideStore XCTest targets"
   ```

## Задача 3. Восстановить XCTest targets и xcconfig

**Файлы:**

- изменить `AltStore.xcodeproj/project.pbxproj`;
- создать `xcconfigs/UITests.xcconfig`;
- создать `xcconfigs/DataStructureTests.xcconfig`.

1. Используя состояние непосредственно перед
   `b407bb72490fcb780f722307daf8ecb4df966710` как источник, восстановить через
   точечные patch-блоки:

   - `PBXContainerItemProxy` и `PBXTargetDependency` для SideStore → UITests;
   - два test product reference;
   - synchronized group exception sets для исходников тестов и тестируемых
     data-structure source files;
   - Sources/Frameworks/Resources phases;
   - оба `PBXNativeTarget`;
   - TargetAttributes и элементы `PBXProject.targets`;
   - Debug/Release `XCBuildConfiguration`;
   - обе `XCConfigurationList`.

2. Восстановить минимальные xcconfig:

   ```text
   #include "../Build.xcconfig"

   PRODUCT_BUNDLE_IDENTIFIER = $(PRODUCT_BUNDLE_IDENTIFIER).UITests
   ```

   и аналогичный suffix `.DataStructureTests`.

3. Не копировать слепо устаревшие signing credentials. Deployment target
   согласовать с текущим проектом, сохранив возможность запуска на iOS 27.

4. Запустить новый тест и список Xcode targets.

   ```bash
   rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
     scripts.ci.test_xcode_test_targets -v
   rtk xcodebuild -project AltStore.xcodeproj -list
   ```

   Ожидание: PASS; в `Targets` присутствуют `UITests` и
   `DataStructureTests`.

5. Закоммитить восстановление.

   ```bash
   rtk git add AltStore.xcodeproj/project.pbxproj xcconfigs \
     scripts/ci/test_xcode_test_targets.py
   rtk git commit -m "fix: restore SideStore XCTest targets"
   ```

## Задача 4. Сделать тестовый набор детерминированным

**Файлы:**

- изменить `SideStore/Tests/UITests/UITestsLaunchTests.swift`;
- изменить `SideStore/Tests/SideStoreTests.xctestplan`;
- при необходимости изменить
  `AltStore.xcodeproj/xcshareddata/xcschemes/SideStore.xcscheme`;
- изменить `scripts/ci/test_xcode_test_targets.py`.

1. Сначала расширить Python-тест требованиями:

   - CI test plan включает `UITests` и `DataStructureTests`;
   - UI test plan запускает ровно устойчивый launch smoke, а сетевые bulk-source
     сценарии исключены из обязательного gate;
   - схема не содержит устаревшего selected test `UITests/testExample()`;
   - `UITestsLaunchTests/testLaunch()` не закомментирован.

2. Запустить тест и получить FAIL.

   ```bash
   rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
     scripts.ci.test_xcode_test_targets -v
   ```

3. Реализовать `testLaunch()`:

   ```swift
   func testLaunch() throws {
       let app = XCUIApplication()
       app.launch()
       XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
   }
   ```

4. Включить в `SideStoreTests.xctestplan` unit target и launch smoke. Сетевые
   UI-тесты оставить доступными для ручного запуска, но исключить из
   обязательной CI-конфигурации.

5. Удалить из scheme ссылку на несуществующий `UITests/testExample()`.

6. Повторно запустить структурный тест и проверить test plans через Xcode.

   ```bash
   rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
     scripts.ci.test_xcode_test_targets -v
   rtk xcodebuild -project AltStore.xcodeproj -scheme SideStore -showTestPlans
   ```

7. Закоммитить детерминированный test plan.

   ```bash
   rtk git add SideStore/Tests AltStore.xcodeproj/xcshareddata/xcschemes \
     scripts/ci/test_xcode_test_targets.py
   rtk git commit -m "test: add deterministic SideStore CI test plan"
   ```

## Задача 5. Передавать точный simulator UDID в Makefile

**Файлы:**

- изменить `Makefile`;
- изменить `scripts/ci/test_runner_workflows.py`.

1. Изменить regression-тест: вместо подсчёта жёстко собранных
   `name=...,OS=...` потребовать переменную:

   ```make
   SIMULATOR_DESTINATION ?= platform=iOS Simulator,name=$(SIMULATOR_DEVICE),OS=$(SIMULATOR_OS)
   ```

   Все три test-команды должны использовать
   `-destination '$(SIMULATOR_DESTINATION)'`.

2. Запустить тест и получить FAIL.

   ```bash
   rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
     scripts.ci.test_runner_workflows.RunnerWorkflowTests.test_simulator_destination_can_be_pinned_by_runner -v
   ```

3. Внести минимальное изменение Makefile и повторить тест.

4. Закоммитить.

   ```bash
   rtk git add Makefile scripts/ci/test_runner_workflows.py
   rtk git commit -m "ci: support exact simulator destination"
   ```

## Задача 6. Превратить iOS 27 workflow в реальный XCTest gate

**Файлы:**

- изменить `.github/workflows/ios27-compatibility.yml`;
- изменить `scripts/ci/test_runner_workflows.py`.

1. Сначала потребовать тестом:

   - верхнеуровневое `permissions: contents: read`;
   - `pull_request_target` допускает job только когда
     `github.event.pull_request.head.repo.full_name == github.repository`;
   - обычный `pull_request` отсутствует;
   - симулятор создаётся с уникальным CI-именем и его UDID записывается в
     `GITHUB_ENV` как `SIMULATOR_DESTINATION=platform=iOS Simulator,id=...`;
   - workflow вызывает `tests-build` и `tests-run`;
   - `.xcresult` загружается с `if: always()`;
   - cleanup удаляет только симулятор, созданный текущим job;
   - release/upload-release и `CROSS_REPO_PUSH_KEY` отсутствуют.

2. Запустить тест и получить FAIL на отсутствии `tests-run`.

   ```bash
   rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
     scripts.ci.test_runner_workflows -v
   ```

3. Реализовать workflow:

   - проверить Xcode 27 и runtime iOS 27;
   - создать отдельный `SideStore-CI-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}`;
   - сохранить UDID и признак владения симулятором через `GITHUB_ENV`;
   - выполнить repository regression checks, archive smoke,
     `tests-build`, загрузку симулятора и `tests-run`;
   - всегда загрузить `build/tests/test-results.xcresult` и логи;
   - в `always()` shutdown/delete только сохранённый CI UDID.

4. Добавить проверку результата после `tests-run` через
   `xcrun xcresulttool`: тестовый run обязан содержать выполненные тесты; нулевой
   test count является ошибкой.

5. Запустить Python-тесты и синтаксическую проверку YAML.

   ```bash
   rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
     -s scripts/ci -p 'test_*.py' -v
   rtk actionlint .github/workflows/ios27-compatibility.yml
   ```

6. Закоммитить.

   ```bash
   rtk git add .github/workflows/ios27-compatibility.yml \
     scripts/ci/test_runner_workflows.py
   rtk git commit -m "ci: run XCTest on iPhone 13 with iOS 27"
   ```

## Задача 7. Усилить включаемые GitHub Actions workflow

**Файлы:**

- изменить `.github/workflows/pr.yml`;
- изменить `.github/workflows/ios27-compatibility.yml`;
- изменить `scripts/ci/test_runner_workflows.py`.

1. Добавить тест, который для двух включаемых workflow запрещает mutable
   action refs и требует полный 40-символьный commit SHA. Отдельно проверить
   отсутствие `actions/cache/*@v3`.

2. Получить FAIL на текущих `@v4`, `@v3` и `@v1.6.0`.

3. Через `git ls-remote` получить текущие commit SHA официальных тегов:

   - `actions/checkout@v4`;
   - `actions/cache/restore@v4` и `actions/cache/save@v4`;
   - `actions/upload-artifact@v4`;
   - `maxim-lobanov/setup-xcode@v1.6.0`.

   Для annotated tags использовать dereferenced `^{}` SHA. Рядом оставить
   комментарий с исходным тегом для обновляемости.

4. В `pr.yml` добавить `permissions: contents: read`, обновить cache action до
   v4 SHA и закрепить остальные actions. Не переводить untrusted PR на
   self-hosted runner.

5. Закрепить actions в iOS 27 workflow.

6. Запустить тесты и `actionlint` для всех workflow.

   ```bash
   rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
     -s scripts/ci -p 'test_*.py' -v
   rtk actionlint
   ```

7. Закоммитить hardening.

   ```bash
   rtk git add .github/workflows/pr.yml \
     .github/workflows/ios27-compatibility.yml \
     scripts/ci/test_runner_workflows.py
   rtk git commit -m "ci: harden fork verification workflows"
   ```

## Задача 8. Выполнить локальные Xcode 27 проверки

**Файлы:** менять только при подтверждённой ошибке теста или совместимости.

1. Проверить toolchain и destination.

   ```bash
   rtk xcodebuild -version
   rtk xcrun simctl list runtimes
   rtk xcrun simctl list devicetypes
   ```

2. Создать отдельный временный `iPhone 13` на runtime iOS 27 и записать его
   UDID. Не использовать и не удалять пользовательские симуляторы.

3. Выполнить полный regression suite.

   ```bash
   rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
     -s scripts/ci -p 'test_*.py' -v
   rtk actionlint
   rtk git diff --check
   ```

4. Выполнить exact-destination Xcode проверки с отключённым signing:

   ```bash
   rtk env SIMULATOR_DESTINATION="platform=iOS Simulator,id=<UDID>" \
     python3 scripts/ci/workflow.py tests-build
   rtk xcrun simctl boot <UDID>
   rtk xcrun simctl bootstatus <UDID> -b
   rtk env SIMULATOR_DESTINATION="platform=iOS Simulator,id=<UDID>" \
     python3 scripts/ci/workflow.py tests-run
   ```

5. Проверить `.xcresult` через `xcresulttool`: должны присутствовать успешный
   UI launch smoke и unit-тесты `LinkedHashMapTests`/`TreeMapTests`, test count
   больше нуля.

6. Всегда выключить и удалить только временный CI simulator.

7. При падении исправлять минимальную причину по TDD, затем повторять весь
   обязательный набор. Создать отдельный fix-коммит.

## Задача 9. Заморозить кандидата и провести самостоятельный review

**Файлы:** только review/fix изменения при наличии блокеров.

1. Зафиксировать все изменения и убедиться, что worktree чистый.

   ```bash
   rtk git status --short
   rtk git rev-parse HEAD
   ```

2. Сформировать handoff:

   - scope: XCTest targets + iOS 27 fork CI;
   - task base SHA из задачи 1;
   - publication base SHA `origin/develop` из задачи 1;
   - candidate SHA;
   - полный `publication base..candidate` diff;
   - точные локальные проверки и test count.

3. Выполнить один полный read-only review frozen diff. Каждому замечанию дать
   стабильный ID, приоритет, `file:line`/сценарий и условие закрытия.

4. Блокирующими считать только корректность, безопасность, потерю данных,
   нарушение спецификации или красную обязательную проверку.

5. Если есть блокеры, выполнить не более двух узких fixes-циклов с новым
   candidate SHA и адресной повторной проверкой известных ID.

6. Проверить, что diff не содержит secrets, push в upstream, release/deploy
   включения или удаления пользовательских артефактов.

## Задача 10. Опубликовать и проверить только пользовательский форк

**GitHub scope:** только `ben-3310/SideStore`.

1. Перед записью проверить remote и authenticated repository:

   ```bash
   rtk git remote -v
   rtk gh repo view ben-3310/SideStore --json nameWithOwner,isFork,parent
   ```

   Ожидание: `origin` указывает на `ben-3310/SideStore`; `upstream` используется
   только для чтения.

2. До создания PR включить только безопасный PR workflow в
   `ben-3310/SideStore` и прочитать его state обратно. Остальные workflow
   оставить выключенными.

3. Push только candidate branch:

   ```bash
   rtk git push --set-upstream origin agent/ios27-xctest-ci
   ```

4. Создать PR только внутри форка:

   ```bash
   rtk gh pr create --repo ben-3310/SideStore --base develop \
     --head agent/ios27-xctest-ci --title "Restore XCTest CI for iOS 27" \
     --body-file <подготовленный-файл>
   ```

5. Прочитать PR обратно и проверить `baseRepository.nameWithOwner`,
   `headRepository.nameWithOwner`, base/head refs и candidate SHA. Если любой
   owner не `ben-3310`, остановиться без дальнейшей записи.

6. Проверить, что PR workflow был запущен событием создания PR, затем проверить
   его checks и логи. Release/nightly/alpha/stable/attach-build-products должны
   оставаться disabled.

7. Bootstrap-особенность: новый iOS 27 workflow ещё отсутствует в default
   branch, поэтому его pre-merge доказательством служит локальный exact-SHA run
   из задачи 8. После зелёного PR build и review слить PR только в
   `ben-3310/SideStore:develop`.

8. После merge проверить автоматический push-run iOS 27 workflow на
   `denys-mbp-sidestore`, его candidate/merge SHA, test count и артефакт
   `.xcresult`. При ошибке создать fixes-ветку и новый PR в том же форке.

9. Убедиться, что iOS 27 и PR verification workflow включены; остальные
   оставить disabled.

10. После появления стабильных check names настроить protection для
   `ben-3310/SideStore:develop`: запрет force-push/delete и обязательные
   безопасные checks для будущих внутренних PR. Прочитать настройки обратно.

11. Финально подтвердить через GitHub API:

    - нет PR/веток/релизов, созданных в `SideStore/SideStore`;
    - PR и merge находятся только в `ben-3310/SideStore`;
    - оба runners online, нужный job выполнился на iOS 27 runner;
    - release/deploy workflow не включены;
    - локальные пользовательские артефакты сохранены.

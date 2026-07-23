# Локальный запуск SideStore на физическом iPhone — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use inline execution in the current session; execute each task with a test checkpoint before moving to the next task.

**Цель:** добавить локальный инструмент, который подписывает Debug SideStore, запускает launch-тест на физическом iPhone 13 / iOS 27, устанавливает Debug app и запускает его в foreground.

**Архитектура:** чистые функции выбора устройства, построения команд и проверки XCTest будут отделены от orchestration-кода. `devicectl` и `xcodebuild` запускаются списками аргументов, а их вывод проходит через redactor; simulator CI остаётся без изменений.

**Стек:** Python 3 `unittest`, Xcode 27.0, `xcodebuild`, `xcresulttool`, `codesign`, `xcrun devicectl`, USB-connected iPhone 13 on iOS 27.0.

## Глобальные ограничения

- Не изменять `.github/workflows/**`, GitHub Runner, runner labels или GitHub Actions.
- Не менять `Build.xcconfig`, bundle identifiers и entitlements: Debug suffix уже обеспечивает отдельное приложение.
- Не удалять приложения, контейнеры, pairing-файлы или provisioning profiles с телефона.
- Не использовать `-allowProvisioningDeviceRegistration`; `-allowProvisioningUpdates` разрешён только как явный fallback после локальной попытки.
- Не печатать и не сохранять UDID, CoreDevice identifier, provisioning UUID, сертификаты или Apple Account data.
- Сохранять результат в `build/device/`, который не коммитится.
- Все shell-команды в документации и проверках запускаются через `rtk`; точный необрезанный вывод — через `rtk proxy`.

---

### Задача 1: зафиксировать failing unit-тесты для выбора устройства и команд

**Файлы:**
- Создать: `scripts/device/test_run_on_iphone.py`
- Создать: `scripts/device/__init__.py`

**Интерфейсы:**
- Тесты импортируют `Device`, `DeviceSelectionError`, `select_device`, `redact_output`, `build_build_for_testing_command`, `build_test_without_building_command`, `build_install_command`, `build_launch_command` и `parse_test_summary` из `scripts.device.run_on_iphone`.

- [ ] **Шаг 1: написать тесты до реализации**

```python
from pathlib import Path
import unittest

from scripts.device.run_on_iphone import (
    DeviceSelectionError,
    build_build_for_testing_command,
    build_install_command,
    build_launch_command,
    build_test_without_building_command,
    parse_test_summary,
    redact_output,
    select_device,
)


def valid_device(identifier):
    return {
        "identifier": identifier,
        "deviceProperties": {
            "name": "13",
            "osVersionNumber": "27.0",
            "developerModeStatus": "enabled",
        },
        "hardwareProperties": {
            "marketingName": "iPhone 13",
            "productType": "iPhone14,5",
            "platform": "iOS",
        },
        "connectionProperties": {
            "pairingState": "paired",
            "transportType": "wired",
        },
    }


def simulator_device():
    record = valid_device("simulator")
    record["hardwareProperties"]["platform"] = "iOS Simulator"
    return record


def wrong_os_device():
    record = valid_device("wrong-os")
    record["deviceProperties"]["osVersionNumber"] = "26.5"
    return record


def unpaired_device():
    record = valid_device("unpaired")
    record["connectionProperties"]["pairingState"] = "unpaired"
    return record


def no_developer_mode_device():
    record = valid_device("developer-mode-off")
    record["deviceProperties"]["developerModeStatus"] = "disabled"
    return record


class DeviceSelectionTests(unittest.TestCase):
    def test_selects_one_paired_developer_mode_iphone_13_on_ios_27(self):
        device = select_device({"result": {"devices": [valid_device("device-1")]}})
        self.assertEqual(device.identifier, "device-1")

    def test_rejects_zero_or_multiple_matching_devices(self):
        with self.assertRaises(DeviceSelectionError):
            select_device({"result": {"devices": []}})
        with self.assertRaises(DeviceSelectionError):
            select_device({"result": {"devices": [valid_device("a"), valid_device("b")]}})

    def test_rejects_simulator_wrong_os_unpaired_or_disabled_developer_mode(self):
        for record in (simulator_device(), wrong_os_device(), unpaired_device(), no_developer_mode_device()):
            with self.subTest(record=record):
                with self.assertRaises(DeviceSelectionError):
                    select_device({"result": {"devices": [record]}})

class CommandTests(unittest.TestCase):
    def test_device_build_and_test_commands_use_exact_destination_and_signing(self):
        build = build_build_for_testing_command("device-1", Path("build/device/DerivedData"))
        test = build_test_without_building_command("device-1", Path("build/device/SideStore-Device.xcresult"))
        self.assertNotIn("platform=iOS Simulator", build)
        self.assertIn("platform=iOS,id=device-1", build)
        self.assertNotIn("CODE_SIGNING_ALLOWED=NO", build)
        self.assertIn("-only-testing:UITests/UITestsLaunchTests/testLaunch", test)

    def test_install_and_launch_commands_are_argument_lists(self):
        install = build_install_command("device-1", Path("build/device/DerivedData/Build/Products/Debug-iphoneos/SideStore.app"))
        launch = build_launch_command("device-1", "com.SideStore.SideStore.S32Z3HMYVQ")
        self.assertEqual(install[:5], ["xcrun", "devicectl", "device", "install", "app"])
        self.assertEqual(launch[:5], ["xcrun", "devicectl", "device", "process", "launch"])
        self.assertNotIsInstance(install, str)
        self.assertNotIsInstance(launch, str)

class ReportingTests(unittest.TestCase):
    def test_redacts_device_identifier_and_uuid_like_values(self):
        output = redact_output("device-1 01234567-89ab-cdef-0123-456789abcdef", "device-1")
        self.assertNotIn("device-1", output)
        self.assertNotIn("01234567-89ab-cdef-0123-456789abcdef", output)

    def test_accepts_exactly_one_passed_test(self):
        parse_test_summary({"totalTestCount": 1, "failedTests": 0, "skippedTests": 0})

    def test_rejects_failed_skipped_or_wrong_count(self):
        for summary in (
            {"totalTestCount": 0, "failedTests": 0, "skippedTests": 0},
            {"totalTestCount": 1, "failedTests": 1, "skippedTests": 0},
            {"totalTestCount": 1, "failedTests": 0, "skippedTests": 1},
        ):
            with self.subTest(summary=summary):
                with self.assertRaises(RuntimeError):
                    parse_test_summary(summary)
```

Тестовые fixture-функции возвращают только синтетические записи; реальные
идентификаторы телефона в тестах не используются.

- [ ] **Шаг 2: проверить RED**

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.device.test_run_on_iphone -v`

Expected: FAIL с `ModuleNotFoundError` или отсутствующими интерфейсами из
`scripts.device.run_on_iphone`; production-файл ещё не создан.

- [ ] **Шаг 3: commit**

```bash
git add scripts/device/__init__.py scripts/device/test_run_on_iphone.py
git commit -m "test: specify physical iPhone device workflow"
```

---

### Задача 2: реализовать чистые функции и безопасный redactor

**Файлы:**
- Создать: `scripts/device/run_on_iphone.py`

**Интерфейсы:**
- `Device` хранит `identifier`, `name`, `model`, `os_version`, `developer_mode`, `pairing_state`, `transport`.
- `select_device(payload: dict) -> Device` выбирает ровно один wired, paired, Developer Mode enabled, physical iPhone 13 с `os_version == "27.0"`; иначе выбрасывает `DeviceSelectionError` без идентификаторов в тексте ошибки.
- `redact_output(text: str, device_identifier: str) -> str` заменяет переданный ID и UUID-подобные токены на `<redacted-device>`.
- Командные builders возвращают `list[str]`, принимают `allow_provisioning_updates: bool = False` для Xcode-команд и используют `platform=iOS,id=<id>`.
- `parse_test_summary(summary: dict) -> None` принимает только `totalTestCount == 1`, `failedTests == 0`, `skippedTests == 0`.

- [ ] **Шаг 1: написать минимальную реализацию**

Использовать `dataclasses.dataclass(frozen=True)`, `pathlib.Path`, `subprocess` и
`re`. Ни одна функция не должна использовать `shell=True` или печатать полный
список аргументов с device identifier.

Команды должны содержать:

```text
xcodebuild build-for-testing -project AltStore.xcodeproj -scheme SideStore
-configuration Debug -sdk iphoneos -destination platform=iOS,id=<id>
-derivedDataPath build/device/DerivedData

xcodebuild test-without-building -project AltStore.xcodeproj -scheme SideStore
-configuration Debug -sdk iphoneos -destination platform=iOS,id=<id>
-resultBundlePath build/device/SideStore-Device.xcresult
-only-testing:UITests/UITestsLaunchTests/testLaunch

xcrun devicectl device install app --device <id> <SideStore.app>
xcrun devicectl device process launch --device <id> --terminate-existing
com.SideStore.SideStore.<development-team>
```

- [ ] **Шаг 2: проверить GREEN**

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.device.test_run_on_iphone -v`

Expected: all new unit tests PASS.

- [ ] **Шаг 3: commit**

```bash
git add scripts/device/run_on_iphone.py
git commit -m "feat: add safe physical iPhone command orchestration"
```

---

### Задача 3: добавить orchestration preflight/build/test/install/launch

**Файлы:**
- Modify: `scripts/device/run_on_iphone.py`
- Modify: `scripts/device/test_run_on_iphone.py`

**Интерфейсы:**
- `main(argv: Sequence[str]) -> int` выполняет весь локальный сценарий.
- `list_devices_json() -> dict` создаёт `TemporaryDirectory`, вызывает
  `devicectl list devices --json-output`, читает JSON и гарантированно удаляет
  временный файл.
- `run_checked(args: Sequence[str], *, redact_id: str | None = None) -> str`
  запускает дочерний процесс без shell и потоково редактирует stdout/stderr.
- `run_device_flow(repo_root: Path, allow_provisioning_updates: bool) -> None`
  создаёт `build/device`, выполняет preflight, build-for-testing, codesign
  verification, xcresult test, summary validation, install и launch.

- [ ] **Шаг 1: добавить failing tests orchestration boundaries**

Добавить тесты, которые передают синтетический JSON в `select_device`, проверяют
что `run_checked` получает list аргументов, и что provisioning fallback не
добавляет `-allowProvisioningDeviceRegistration`.

- [ ] **Шаг 2: проверить RED**

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.device.test_run_on_iphone -v`

Expected: новые тесты FAIL на отсутствующей orchestration-логике.

- [ ] **Шаг 3: реализовать CLI**

CLI по умолчанию запускает весь flow. `--allow-provisioning-updates` разрешает
только повтор build/test с `-allowProvisioningUpdates`; без флага первая попытка
не изменяет Apple Developer state. Ошибки печатаются после redaction и сохраняют
`build/device` для диагностики; приложение автоматически не удаляется.

- [ ] **Шаг 4: проверить GREEN и рефакторинг**

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.device.test_run_on_iphone -v`

Expected: все новые тесты PASS без warnings; после этого вынести повторяющийся
код команд и redaction в маленькие функции, не меняя поведение.

- [ ] **Шаг 5: commit**

```bash
git add scripts/device/run_on_iphone.py scripts/device/test_run_on_iphone.py
git commit -m "feat: run signed SideStore smoke on physical iPhone"
```

---

### Задача 4: локальная device-валидация

**Файлы:**
- Runtime output only: `build/device/**` (ignored; не добавлять в Git)

**Интерфейсы:**
- CLI использует подключённый iPhone 13 / iOS 27 и Debug bundle ID с командным
  суффиксом из `Build.xcconfig`.

- [ ] **Шаг 1: выполнить все регрессионные проверки**

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v`

Expected: 17 существующих тестов PASS.

Run: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.device.test_run_on_iphone -v`

Expected: все новые device-тесты PASS.

- [ ] **Шаг 2: проверить diff и отсутствие workflow-изменений**

Run: `git diff --check`

Expected: no output; workflow-файлы не изменены.

- [ ] **Шаг 3: выполнить подписанный device flow**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/device/run_on_iphone.py`

Expected:

- preflight находит ровно один подходящий physical iPhone;
- build-for-testing завершается успешно и `codesign --verify --deep --strict`
  принимает `SideStore.app`;
- `xcresult` summary показывает 1 тест, 0 failures, 0 skipped;
- Debug app устанавливается и запускается foreground;
- временные идентификаторы отсутствуют в терминальном отчёте.

- [ ] **Шаг 4: при конкретной provisioning-ошибке повторить один раз**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 scripts/device/run_on_iphone.py --allow-provisioning-updates`

Ожидание: разрешается только обновление существующих profiles; при требовании
регистрации устройства остановиться и вернуть точную очищенную ошибку.

- [ ] **Шаг 5: commit validation metadata only if needed**

Не коммитить `build/device`, JSON, `.xcresult`, IPA, сертификаты или профили.

---

### Задача 5: self-review и handoff

**Файлы:**
- Проверить: `scripts/device/run_on_iphone.py`
- Проверить: `scripts/device/test_run_on_iphone.py`
- Проверить: `.github/workflows/**` (ожидается отсутствие diff)

- [ ] **Шаг 1: выполнить targeted review**

Проверить отсутствие `shell=True`, необредактированных ID в сообщениях,
`allowProvisioningDeviceRegistration`, удаления приложений и изменений Runner.

- [ ] **Шаг 2: проверить чистоту worktree и артефакты**

Run: `git status --short --branch`

Expected: только намеренные исходные файлы; runtime artifacts остаются ignored.

- [ ] **Шаг 3: подготовить результат**

Отчёт содержит только модель/OS, факт build/test/install/launch и ссылки на
локальные исходные файлы; UDID, CoreDevice identifiers, Apple Account и profile
UUID не публикуются.

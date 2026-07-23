# Xcode 27 Listed Warnings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Устранить все перечисленные пользователем предупреждения Xcode 27 точечными изменениями корневого проекта и storyboard-файлов.

**Architecture:** Regression-тесты структурно проверяют конкретные PBX-объекты и XML-элементы по стабильным ID. Настройки исправляются только в таргетах SideStore и `em_proxy-swift`; защищённые локальные зависимости остаются неизменными.

**Tech Stack:** Xcode 27, PBX project format, Interface Builder storyboard XML, Python `unittest`, Apple `libtool`.

## Global Constraints

- Не изменять символьную ссылку `Dependencies` или `/Users/ben/Repo/SideStore_Dependencies`.
- Не менять deployment target, code signing, entitlements и bundle identifiers.
- Сохранить несвязанные staged, unstaged и untracked изменения пользователя.
- Из-за уже изменённых пользователем общих файлов не создавать code-коммиты и не менять их staging state.
- Проверять Debug и Release там, где предупреждение относится к build settings.

---

### Task 1: Структурные regression-тесты

**Files:**
- Modify: `scripts/ci/test_xcode27_source_cleanup.py`
- Test: `scripts/ci/test_xcode27_source_cleanup.py`

**Interfaces:**
- Consumes: `source_text(relative_path)` и `pbx_object(project, object_id)`.
- Produces: класс `Xcode27ListedWarningsTests`, фиксирующий одобренный контракт.

- [ ] **Step 1: Добавить XML helper и failing tests**

```python
import xml.etree.ElementTree as ET


def storyboard_element(relative_path: str, object_id: str) -> ET.Element | None:
    root = ET.parse(ROOT / relative_path).getroot()
    return next((element for element in root.iter() if element.get("id") == object_id), None)


class Xcode27ListedWarningsTests(unittest.TestCase):
    def test_project_records_xcode_27_upgrade(self) -> None:
        project = source_text("AltStore.xcodeproj/project.pbxproj")
        self.assertIn("LastUpgradeCheck = 2700;", project)

    def test_sidestore_has_no_obsolete_minimuxer_library_search_path(self) -> None:
        project = source_text("AltStore.xcodeproj/project.pbxproj")
        obsolete_path = '"$(PROJECT_DIR)/Dependencies/minimuxer/Sources/RustBridge/lib"'
        for configuration_id in ("BFD2477F2284B9A700981D42", "BFD247802284B9A700981D42"):
            self.assertNotIn(obsolete_path, pbx_object(project, configuration_id))

    def test_sidestore_marks_embedded_openssl_as_runtime_needed(self) -> None:
        project = source_text("AltStore.xcodeproj/project.pbxproj")
        side_store_target = pbx_object(project, "BFD247692284B9A500981D42")
        frameworks_phase = pbx_object(project, "BFD247672284B9A500981D42")
        embed_frameworks_phase = pbx_object(project, "BF088D2B2501A087008082D9")
        self.assertIn("A823DC542FF0D82100AD4DAF", frameworks_phase)
        self.assertNotIn("A823DC542FF0D82100AD4DAF", embed_frameworks_phase)
        self.assertIn("A823DC532FF0D82100AD4DAF", side_store_target)
        self.assertIn("A82526E72FF0E1C000FB2EDD", project)
        for configuration_id in ("BFD2477F2284B9A700981D42", "BFD247802284B9A700981D42"):
            configuration = pbx_object(project, configuration_id)
            self.assertIn('"-needed_framework",', configuration)
            self.assertIn("OpenSSL,", configuration)

    def test_em_proxy_swift_only_suppresses_empty_object_warnings(self) -> None:
        project = source_text("AltStore.xcodeproj/project.pbxproj")
        for configuration_id in ("A85A51462F4B4532002E2E11", "A85A51472F4B4532002E2E11"):
            configuration = pbx_object(project, configuration_id)
            self.assertIn('OTHER_LIBTOOLFLAGS = "-no_warning_for_no_symbols";', configuration)

    def test_storyboards_use_supported_xcode_27_values(self) -> None:
        settings = source_text("AltStore/Settings/Settings.storyboard")
        self.assertIn('image="apple.terminal"', settings)
        self.assertNotIn('image="terminal"', settings)
        self.assertIsNone(storyboard_element("AltStore/Sources/Sources.storyboard", "W0l-zW-MjJ"))
        navigation_item = storyboard_element("AltStore/Base.lproj/Main.storyboard", "FLf-DS-F77")
        self.assertIsNotNone(navigation_item)
        self.assertNotIn("style", navigation_item.attrib)
```

- [ ] **Step 2: Запустить выбранный класс и подтвердить RED**

Run:

```bash
python3 -m unittest scripts.ci.test_xcode27_source_cleanup.Xcode27ListedWarningsTests -v
```

Expected: пять тестов FAIL по текущим `LastUpgradeCheck`, Rust search path,
OpenSSL PBX IDs, отсутствующему `OTHER_LIBTOOLFLAGS` и storyboard XML.

### Task 2: Точечные PBX-исправления

**Files:**
- Modify: `AltStore.xcodeproj/project.pbxproj`
- Test: `scripts/ci/test_xcode27_source_cleanup.py`

**Interfaces:**
- Consumes: PBX IDs, зафиксированные в Task 1.
- Produces: проект без устаревшего search path, с явно необходимым runtime-link OpenSSL и без шумных empty-object warnings.

- [ ] **Step 1: Обновить marker и пометить OpenSSL как runtime-needed**

```text
LastUpgradeCheck = 2700;

Сохранить A823DC532FF0D82100AD4DAF в packageProductDependencies.
Сохранить A823DC542FF0D82100AD4DAF в BFD247672284B9A500981D42.
В обе SideStore-конфигурации добавить к OTHER_LDFLAGS:
"-Xlinker", "-needed_framework", "-Xlinker", OpenSSL.
Сохранить A82526E72FF0E1C000FB2EDD и A82526E62FF0E1C000FB2EDD для SideBackup.
```

- [ ] **Step 2: Удалить Rust search path в обеих SideStore-конфигурациях**

```text
В BFD2477F2284B9A700981D42 и BFD247802284B9A700981D42 удалить весь локальный
LIBRARY_SEARCH_PATHS block, состоящий из $(inherited) и отсутствующего RustBridge/lib.
```

- [ ] **Step 3: Добавить узкий Apple libtool flag**

```text
В A85A51462F4B4532002E2E11 и A85A51472F4B4532002E2E11 добавить:
OTHER_LIBTOOLFLAGS = "-no_warning_for_no_symbols";
```

- [ ] **Step 4: Запустить PBX-подмножество тестов**

Run:

```bash
python3 -m unittest \
  scripts.ci.test_xcode27_source_cleanup.Xcode27ListedWarningsTests.test_project_records_xcode_27_upgrade \
  scripts.ci.test_xcode27_source_cleanup.Xcode27ListedWarningsTests.test_sidestore_has_no_obsolete_minimuxer_library_search_path \
  scripts.ci.test_xcode27_source_cleanup.Xcode27ListedWarningsTests.test_sidestore_marks_embedded_openssl_as_runtime_needed \
  scripts.ci.test_xcode27_source_cleanup.Xcode27ListedWarningsTests.test_em_proxy_swift_only_suppresses_empty_object_warnings -v
```

Expected: четыре теста PASS.

### Task 3: Storyboard-исправления

**Files:**
- Modify: `AltStore/Settings/Settings.storyboard`
- Modify: `AltStore/Sources/Sources.storyboard`
- Modify: `AltStore/Base.lproj/Main.storyboard`
- Test: `scripts/ci/test_xcode27_source_cleanup.py`

**Interfaces:**
- Consumes: storyboard IDs `1cD-4y-vTJ`, `W0l-zW-MjJ`, `FLf-DS-F77`.
- Produces: XML, который компилируется `ibtool` без трёх исходных warnings.

- [ ] **Step 1: Обновить SF Symbol**

```xml
<imageReference key="image" image="apple.terminal" catalog="system" symbolScale="large"/>
<image name="apple.terminal" catalog="system" width="128" height="97"/>
```

- [ ] **Step 2: Удалить пустую prototype-cell**

Удалить из Add Source scene весь блок:

```xml
<cells>
    <collectionViewCell ... id="W0l-zW-MjJ">...</collectionViewCell>
</cells>
```

- [ ] **Step 3: Удалить неподдерживаемый style, сохранив custom view**

```xml
<barButtonItem key="rightBarButtonItem" id="FLf-DS-F77">
```

- [ ] **Step 4: Запустить storyboard regression-тест**

Run:

```bash
python3 -m unittest scripts.ci.test_xcode27_source_cleanup.Xcode27ListedWarningsTests.test_storyboards_use_supported_xcode_27_values -v
```

Expected: PASS.

### Task 4: Полная проверка

**Files:**
- Verify: `AltStore.xcodeproj/project.pbxproj`
- Verify: `AltStore/Settings/Settings.storyboard`
- Verify: `AltStore/Sources/Sources.storyboard`
- Verify: `AltStore/Base.lproj/Main.storyboard`
- Verify: `scripts/ci/test_xcode27_source_cleanup.py`

**Interfaces:**
- Consumes: результаты Tasks 1-3.
- Produces: воспроизводимое доказательство успешной сборки без исходных warnings.

- [ ] **Step 1: Запустить обязательные scoped regression-тесты**

Run:

```bash
python3 -m unittest scripts.ci.test_xcode27_source_cleanup.Xcode27ListedWarningsTests -v
```

Expected: пять тестов PASS.

- [ ] **Step 2: Сверить полный regression-файл с известным baseline**

Run:

```bash
python3 scripts/ci/test_xcode27_source_cleanup.py -v
```

Expected в текущем сохранённом пользовательском состоянии: 25 тестов,
12 известных failures — 10 только в `AltSignCleanupTests` и
`OpenSSLModernizationTests`, ожидающих невнесённых изменений защищённого
`Dependencies`, и 2 subtest failures `test_deployment_target_remains_ios_15`,
тогда как существующий пользовательский diff задаёт 17.6. Новых failures нет,
все пять `Xcode27ListedWarningsTests` проходят. Эти 12 failures не исправлять в
рамках данного плана.

- [ ] **Step 3: Создать новый DerivedData и выполнить clean unsigned build**

Run:

```bash
SIDESTORE_DERIVED_DATA=$(mktemp -d /tmp/codex-sidestore-warnings.XXXXXX)
xcodebuild -project AltStore.xcodeproj -scheme SideStore -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath "$SIDESTORE_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO clean build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Проверить activity log по точным сообщениям**

Проверить отсутствие строк:

```text
Search path '.../Dependencies/minimuxer/Sources/RustBridge/lib' not found
linking with (@rpath/OpenSSL.framework/OpenSSL) but not using any symbols from it
SF Symbol 'terminal' is deprecated
Prototype collection view cells must have reuse identifiers
Plain Style unsupported in a Navigation Item
libem_proxy_static.a(...) has no symbols
No valid content was found in this file
```

Expected: ни одного совпадения.

- [ ] **Step 5: Проверить runtime-размещение OpenSSL**

Run:

```bash
ls "$SIDESTORE_DERIVED_DATA/Build/Products/Debug-iphoneos/SideStore.app/Frameworks/OpenSSL.framework/OpenSSL"
otool -L "$SIDESTORE_DERIVED_DATA/Build/Products/Debug-iphoneos/SideStore.app/SideStore"
otool -L "$SIDESTORE_DERIVED_DATA/Build/Products/Debug-iphoneos/SideStore.app/Frameworks/AltStoreCore.framework/AltStoreCore"
```

Expected: OpenSSL binary существует; SideStore и AltStoreCore содержат
`@rpath/OpenSSL.framework/OpenSSL`.

- [ ] **Step 6: Проверить границы diff и статус Dependencies**

Run:

```bash
git diff -- AltStore.xcodeproj/project.pbxproj \
  AltStore/Settings/Settings.storyboard \
  AltStore/Sources/Sources.storyboard \
  AltStore/Base.lproj/Main.storyboard \
  scripts/ci/test_xcode27_source_cleanup.py
ls -ld Dependencies
readlink Dependencies
```

Expected: согласованные сигнатуры присутствуют в соответствующих hunks;
предсуществующие сторонние изменения в общих файлах сохранены, не переписаны и не
включены в scope этого плана. Ссылка указывает на `../SideStore_Dependencies`.

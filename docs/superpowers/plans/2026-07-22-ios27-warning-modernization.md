# Полировка SideStore для Xcode 27 и физического iPhone — план реализации

> **Для agentic workers:** ОБЯЗАТЕЛЬНЫЙ SUB-SKILL: использовать `subagent-driven-development` (рекомендуется) либо inline-выполнение плана по задачам. Все шаги отслеживаются checkbox-ами.

**Цель:** устранить compile error и first-party/local-AltSign warnings Xcode 27, сохранить signing-функциональность и повторно подтвердить проект на физическом iPhone 13 с iOS 27.0.

**Архитектура:** исправления разделены на source modernization, EVP migration, Swift 6/Roxas cleanup и build-graph cleanup. Новый warning gate разбирает clean build log и допускает только одно точное внешнее предупреждение последнего официального `ZIPFoundation 0.9.20`; физический device-flow остаётся финальным end-to-end gate.

**Стек:** Swift, Swift Package Manager, OpenSSL 3 EVP, UIKit, Core Data, Xcode 27, Python `unittest`, `xcodebuild`, `xcresulttool`, `devicectl`.

## Глобальные ограничения

- Целевое устройство: ровно один wired/paired iPhone 13 с iOS 27.0 и включённым Developer Mode.
- Не хранить Apple account, Team ID, certificate IDs, provisioning profile names или device identifiers в Git и логах.
- Не использовать глобальное подавление warnings.
- Не редактировать SwiftPM checkout или DerivedData вручную.
- Не менять Runner/workflows.
- Не включать `Dependencies/em_proxy/em_proxy.xcodeproj/xcuserdata/` в commits.
- Сохранить локальные Xcode signing overrides в `AltStore.xcodeproj/project.pbxproj` незакоммиченными; stage'ить из этого файла только отдельные build-graph hunks без локального Team ID.
- Публиковать только в `ben-3310/SideStore`; upstream не изменять.

---

### Задача 1: Warning gate и source regression harness

**Файлы:**
- Создать: `scripts/ci/xcode_warning_gate.py`
- Создать: `scripts/ci/test_xcode_warning_gate.py`
- Создать: `scripts/ci/test_xcode27_source_cleanup.py`

**Интерфейсы:**
- `unexpected_warnings(log: str) -> list[str]` возвращает warning-строки, не входящие в точный внешний allowlist.
- CLI `python3 scripts/ci/xcode_warning_gate.py <build.log>` возвращает `0` только при отсутствии неожиданных warnings.

- [ ] **Шаг 1: написать failing tests warning parser**

```python
class WarningGateTests(unittest.TestCase):
    def test_allows_only_zipfoundation_manifest_warning(self):
        allowed = (
            "/tmp/DerivedData/SourcePackages/checkouts/ZIPFoundation/"
            "Package@swift-5.9.swift:23:61: warning: 'v4' is deprecated: "
            "watchOS 9.0 is the oldest supported version"
        )
        self.assertEqual(unexpected_warnings(allowed), [])

    def test_rejects_first_party_and_other_dependency_warnings(self):
        log = "\n".join([
            "/repo/AltStoreCore/Foo.swift:1:1: warning: broken",
            "/tmp/ZIPFoundation/Foo.swift:1:1: warning: new warning",
        ])
        self.assertEqual(len(unexpected_warnings(log)), 2)
```

- [ ] **Шаг 2: подтвердить RED**

Выполнить: `rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.ci.test_xcode_warning_gate -v`

Ожидание: `ImportError` для отсутствующего `xcode_warning_gate`.

- [ ] **Шаг 3: реализовать точный parser и CLI**

```python
ZIPFOUNDATION_MANIFEST_WARNING = re.compile(
    r"SourcePackages/checkouts/ZIPFoundation/Package@swift-5\.9\.swift:"
    r"\d+:\d+: warning: 'v4' is deprecated: watchOS 9\.0 is the oldest supported version$"
)

def unexpected_warnings(log: str) -> list[str]:
    warnings = [line.strip() for line in log.splitlines() if "warning:" in line]
    return [line for line in warnings if not ZIPFOUNDATION_MANIFEST_WARNING.search(line)]
```

CLI читает UTF-8 log, печатает только unexpected warnings и завершает работу с кодом `1`, если список непустой.

- [ ] **Шаг 4: добавить source cleanup baseline tests**

`test_xcode27_source_cleanup.py` сначала утверждает наличие текущих нежелательных patterns (`RSA_new`, `as? UICollectionView`, `.isNetworkActivityIndicatorVisible`, String associated keys и прочих), чтобы последующие задачи переводили каждый набор RED → GREEN. Тесты должны читать только tracked source и не сканировать `build/` или `Dependencies/em_proxy`.

- [ ] **Шаг 5: проверить GREEN warning parser и зафиксировать harness**

Выполнить:

```bash
rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.ci.test_xcode_warning_gate -v
rtk git add scripts/ci/xcode_warning_gate.py scripts/ci/test_xcode_warning_gate.py scripts/ci/test_xcode27_source_cleanup.py
rtk git commit -m "test: add Xcode 27 warning gates"
```

---

### Задача 2: Безопасная чистка локального AltSign

**Файлы:**
- Изменить: `Dependencies/AltSign/Sources/Model/ALTApplication.swift:173-263`
- Изменить: `Dependencies/AltSign/Sources/ALTAppleAPI+Operations.swift:168,223`
- Изменить: `Dependencies/AltSign/SwiftBridge/CoreCryptoBridge.swift:263`
- Изменить: `scripts/ci/test_xcode27_source_cleanup.py`

**Интерфейсы:** публичная сигнатура `@objc public func dumpMachOInfo() -> String` сохраняется.

- [ ] **Шаг 1: заменить baseline assertions на desired-state assertions**

Проверить, что `dumpMachOInfo` расположен не внутри `private extension`, что `certificate.name` не использует `??`, и что строка `let combined = ciphertext + tag` отсутствует.

- [ ] **Шаг 2: подтвердить RED**

Выполнить: `rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.ci.test_xcode27_source_cleanup.AltSignCleanupTests -v`

Ожидание: failures по всем трём текущим patterns.

- [ ] **Шаг 3: исправить access boundary и non-optional logging**

Закрыть private extension перед методом и открыть обычный extension:

```swift
}

extension ALTApplication {
    @objc
    public func dumpMachOInfo() -> String {
        // существующая реализация без изменения
    }
}
```

Логирование заменить на:

```swift
verboseLog("[AltSign] fetchCertificates completed: \(certificates?.map { "\($0.name) (\($0.identifier ?? "nil"))" } ?? [])")
verboseLog("[AltSign] revoke certificate starting for: \(certificate.name) (ID: \(certificate.identifier ?? "nil"))")
```

В AES-GCM decrypt удалить только неиспользуемую строку `let combined = ciphertext + tag`.

- [ ] **Шаг 4: проверить GREEN и AltSign compile**

Выполнить:

```bash
rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.ci.test_xcode27_source_cleanup.AltSignCleanupTests -v
rtk env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --package-path Dependencies/AltSign
```

- [ ] **Шаг 5: commit**

```bash
rtk git add Dependencies/AltSign/Sources/Model/ALTApplication.swift Dependencies/AltSign/Sources/ALTAppleAPI+Operations.swift Dependencies/AltSign/SwiftBridge/CoreCryptoBridge.swift scripts/ci/test_xcode27_source_cleanup.py
rtk git commit -m "fix: clean up AltSign Xcode 27 diagnostics"
```

---

### Задача 3: Перевести CSR key generation на OpenSSL EVP

**Файлы:**
- Изменить: `Dependencies/AltSign/Package.swift`
- Изменить: `Dependencies/AltSign/SwiftBridge/CertificatesManager.swift:135-223`
- Создать: `Dependencies/AltSign/Tests/SwiftBridgeTests/CertificatesManagerTests.swift`
- Изменить: `scripts/ci/test_xcode27_source_cleanup.py`

**Интерфейсы:** `CertificatesManager.generateCSR(subject:) throws -> (csr: Data, privateKey: Data)` сохраняется.

- [ ] **Шаг 1: добавить behavioral test CSR/key round trip**

Добавить в `Package.swift`:

```swift
.testTarget(
    name: "SwiftBridgeTests",
    dependencies: ["SwiftBridge", "OpenSSL"],
    path: "Tests/SwiftBridgeTests"
)
```

Тест:

```swift
import XCTest
import OpenSSL
@testable import SwiftBridge

final class CertificatesManagerTests: XCTestCase {
    func testGenerateCSRReturnsParseablePEMPrivateKey() throws {
        let output = try CertificatesManager.generateCSR(subject: .init(
            country: "US", state: "CA", locality: "Cupertino",
            organization: "SideStore Tests", commonName: "Device Test"
        ))
        XCTAssertTrue(String(decoding: output.csr, as: UTF8.self).contains("BEGIN CERTIFICATE REQUEST"))
        XCTAssertTrue(String(decoding: output.privateKey, as: UTF8.self).contains("BEGIN PRIVATE KEY"))
        let key = CertificatesManager.readPrivateKey(output.privateKey)
        XCTAssertNotNil(key)
        if let key { EVP_PKEY_free(key) }
    }
}
```

- [ ] **Шаг 2: подтвердить behavioral baseline и source RED**

Сначала behavioral test должен пройти на старой реализации, а source test должен падать из-за `RSA_new`, `RSA_free`, `RSA_generate_key_ex`, `EVP_PKEY_set1_RSA`.

Выполнить:

```bash
rtk env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Dependencies/AltSign --filter CertificatesManagerTests
rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.ci.test_xcode27_source_cleanup.OpenSSLModernizationTests -v
```

- [ ] **Шаг 3: реализовать EVP ownership**

Заменить legacy allocation/generation на:

```swift
guard let keyContext = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, nil),
      let req = X509_REQ_new() else {
    throw Error.operationFailed("Allocation failed")
}
defer {
    EVP_PKEY_CTX_free(keyContext)
    X509_REQ_free(req)
}

guard EVP_PKEY_keygen_init(keyContext) == 1,
      EVP_PKEY_CTX_set_rsa_keygen_bits(keyContext, 2048) == 1 else {
    throw Error.operationFailed("RSA key configuration failed")
}

var generatedKey: OpaquePointer?
guard EVP_PKEY_keygen(keyContext, &generatedKey) == 1,
      let pkey = generatedKey else {
    throw Error.operationFailed("RSA key generation failed")
}
defer { EVP_PKEY_free(pkey) }
```

Оставить существующие `X509_REQ_set_pubkey`, `X509_REQ_sign`, PEM serialization и returned tuple. Если Swift importer не экспортирует setter macro, добавить узкую C-функцию `alt_evp_generate_rsa_key(Int32) -> OpaquePointer?` в существующий NativeBridge и покрыть тем же behavioral test.

- [ ] **Шаг 4: проверить GREEN и отсутствие deprecated RSA symbols**

```bash
rtk env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Dependencies/AltSign --filter CertificatesManagerTests
rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.ci.test_xcode27_source_cleanup.OpenSSLModernizationTests -v
```

- [ ] **Шаг 5: commit**

```bash
rtk git add Dependencies/AltSign/Package.swift Dependencies/AltSign/SwiftBridge/CertificatesManager.swift Dependencies/AltSign/Tests/SwiftBridgeTests/CertificatesManagerTests.swift scripts/ci/test_xcode27_source_cleanup.py
rtk git commit -m "fix: generate certificate keys with OpenSSL EVP"
```

---

### Задача 4: Swift 6 conformance и Roxas/UIKit cleanup

**Файлы:**
- Изменить: `AltStoreCore/Extensions/JSONDecoder+Properties.swift`
- Изменить: `AltStoreCore/Model/DatabaseManager/DatabaseManager.swift`
- Изменить: `AltStoreCore/Roxas/RSTArrayDataSource.swift`
- Изменить: `AltStoreCore/Roxas/RSTBlockOperation.swift`
- Изменить: `AltStoreCore/Roxas/RSTCompositeDataSource.swift`
- Изменить: `AltStoreCore/Roxas/RSTFetchedResultsDataSource.swift`
- Изменить: `AltStoreCore/Roxas/RSTLoadOperation.swift`
- Изменить: `AltStoreCore/Roxas/RSTOperation.swift`
- Изменить: `AltStoreCore/Roxas/RSTOperationQueue.swift`
- Изменить: `AltStoreCore/Roxas/RSTPersistentContainer.swift`
- Изменить: `AltStoreCore/Roxas/RSTRelationshipPreservingMergePolicy.swift`
- Изменить: `AltStoreCore/Roxas/RSTToastView.swift`
- Изменить: `AltStoreCore/Roxas/UICollectionView+CellContent.swift`
- Изменить: `AltStoreCore/Roxas/UIKit+ActivityIndicating.swift`
- Изменить: `Shared/Errors/ALTWrappedError.swift`
- Изменить: `Shared/Extensions/NSError+AltStore.swift`
- Изменить: `Shared/Extensions/OperatingSystemVersion+Comparable.swift`
- Изменить: `scripts/ci/test_xcode27_source_cleanup.py`

**Интерфейсы:** публичные Objective-C/Swift names и behavior data sources сохраняются.

- [ ] **Шаг 1: добавить desired-state source tests и подтвердить RED**

Проверить точные declarations с `@unchecked Sendable`, отсутствие redundant casts/nil checks/deprecated UIKit calls, `@retroactive Comparable`, `UInt8` associated keys и `_ = NSConstraintConflict.cacheSnapshots`.

Выполнить: `rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.ci.test_xcode27_source_cleanup.RoxasModernizationTests -v`

- [ ] **Шаг 2: restate унаследованный Sendable contract**

Использовать следующие declarations:

```swift
public final class JSONDecoder: Foundation.JSONDecoder, @unchecked Sendable
fileprivate class PersistentContainer: RSTPersistentContainer, @unchecked Sendable
open class RSTOperation: Operation, @unchecked Sendable
open class RSTBlockOperation: RSTOperation, @unchecked Sendable
open class RSTAsyncBlockOperation: RSTBlockOperation, @unchecked Sendable
open class RSTLoadOperation: RSTOperation, @unchecked Sendable
open class RSTOperationQueue: OperationQueue, @unchecked Sendable
public class RSTPersistentContainer: NSPersistentContainer, @unchecked Sendable
public class ALTWrappedError: NSError, @unchecked Sendable
```

- [ ] **Шаг 3: убрать redundant type/window checks**

Во всех специализированных collection/table data sources заменить:

```swift
if let collectionView = self.contentView,
   let cellIndexPath = collectionView.indexPath(for: cell) { ... }
```

и эквивалент для `tableView`. В fetched-results callbacks использовать:

```swift
if contentView?.window != nil { ... }
```

- [ ] **Шаг 4: исправить UIKit/Foundation warnings без визуальной регрессии**

```swift
_ = NSConstraintConflict.cacheSnapshots(for: conflicts)

@objc public let activityIndicatorView = UIActivityIndicatorView(style: .medium)
// initialize():
activityIndicatorView.color = .white

func startIndicatingActivity() {}
func stopIndicatingActivity() {}

private struct AssociatedKeys {
    nonisolated(unsafe) static var nestedUpdatesCounter: UInt8 = 0
    nonisolated(unsafe) static var operations: UInt8 = 0
}

let indexA = preferredKeyOrder.firstIndex(of: a.key)
let indexB = preferredKeyOrder.firstIndex(of: b.key)

extension OperatingSystemVersion: @retroactive Comparable
```

- [ ] **Шаг 5: проверить GREEN и все Python gates**

```bash
rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.ci.test_xcode27_source_cleanup -v
rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v
```

- [ ] **Шаг 6: commit**

Явно добавить только перечисленные source/test files и выполнить:

```bash
rtk git commit -m "fix: modernize AltStoreCore for Xcode 27"
```

---

### Задача 5: Availability и Xcode build graph

**Файлы:**
- Изменить: `AltWidget/Intents/ViewAppIntent.swift:75-85`
- Изменить: `AltStore.xcodeproj/project.pbxproj:149-276,564-575,718-755`
- Изменить: `scripts/ci/test_xcode27_source_cleanup.py`

**Интерфейсы:** SideStore scheme сохраняет targets `SideStore`, `AltWidgetExtension`, `SideBackup`, `UITests`; `SideBackup.ipa` остаётся ресурсом signed app.

- [ ] **Шаг 1: написать project-structure expectations и подтвердить RED**

Тесты должны требовать обе availability domains для `SelectAppIntent`, исключение `AltStoreFree.entitlements` из synchronized target membership, отсутствие no-op phase `Build Minimuxer Rust Bridge`, а для `Build SideBackup.ipa` — declared output и intentional `alwaysOutOfDate = 1`.

- [ ] **Шаг 2: исправить availability**

```swift
@available(iOS 17, *)
@available(iOSApplicationExtension 17, *)
struct SelectAppIntent: WidgetConfigurationIntent
```

- [ ] **Шаг 3: исправить synchronized resources и shell phases**

- Добавить `AltStoreFree.entitlements` в `membershipExceptions` SideStore target exception set `A8EEC8CB...`, сохранив существующее build-phase exception.
- Удалить `A8D768...` из `SideStore.buildPhases` и сам no-op `PBXShellScriptBuildPhase`, поскольку он не выполняет build (`make build` закомментирован).
- Для `Build SideBackup.ipa` добавить:

```text
alwaysOutOfDate = 1;
outputPaths = (
    "$(PROJECT_DIR)/AltStore/Resources/SideBackup.ipa",
);
```

Declared output создаёт корректную dependency edge до Resources/CodeSign, а `alwaysOutOfDate` сохраняет текущее намерение обновлять вложенный IPA при каждой сборке.

- [ ] **Шаг 4: проверить project tests и build settings**

```bash
rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.ci.test_xcode27_source_cleanup.ProjectWarningCleanupTests -v
rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v
rtk env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project AltStore.xcodeproj -scheme SideStore -showBuildSettings >/dev/null
```

- [ ] **Шаг 5: commit**

```bash
rtk git add AltWidget/Intents/ViewAppIntent.swift scripts/ci/test_xcode27_source_cleanup.py
rtk git add -p AltStore.xcodeproj/project.pbxproj
rtk git commit -m "fix: clean Xcode 27 project diagnostics"
```

При `git add -p` принять только hunks exception sets/build phases и отклонить все hunks `DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY`, `CODE_SIGN_STYLE` и `PROVISIONING_PROFILE_SPECIFIER`. После commit локальные signing overrides должны остаться в working tree.

---

### Задача 6: Clean build, warning proof и физический iPhone

**Файлы:**
- При необходимости изменить только regression tests или уже затронутые source files, если clean build обнаружит связанный warning.
- Создать локально, не коммитить: `build/device/xcode27-clean.log`, DerivedData, xcresult.

**Интерфейсы:** существующий `scripts/device/run_on_iphone.py` остаётся единственной командой physical-device orchestration.

- [ ] **Шаг 1: прогнать полный статический gate**

```bash
rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.device.test_run_on_iphone -v
rtk env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v
rtk env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Dependencies/AltSign
rtk git diff --check
```

- [ ] **Шаг 2: выполнить чистый подписанный physical-device flow с redacted log**

В локальной shell-сессии установить `SIDE_STORE_DEVELOPMENT_TEAM` из выбранной Xcode signing team, не записывая значение в файл или history. Затем:

```bash
rtk proxy zsh -lc 'set -o pipefail; DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer PYTHONDONTWRITEBYTECODE=1 python3 scripts/device/run_on_iphone.py --development-team "$SIDE_STORE_DEVELOPMENT_TEAM" --allow-provisioning-updates 2>&1 | tee build/device/xcode27-clean.log'
```

Ожидание: build-for-testing success; 1 passed/0 failed/0 skipped; codesign success; install, foreground launch и running-process proof success.

- [ ] **Шаг 3: доказать warning baseline**

```bash
rtk env PYTHONDONTWRITEBYTECODE=1 python3 scripts/ci/xcode_warning_gate.py build/device/xcode27-clean.log
```

Ожидание: exit `0`; допустима только точная строка external `ZIPFoundation` manifest warning.

- [ ] **Шаг 4: проверить privacy и scope**

```bash
rtk git grep -n -E 'i@ben3310\.com|[0-9A-F]{8}-[0-9A-F]{16}' -- .
rtk git diff --name-only origin/develop...HEAD | rtk rg '^\.github/workflows/'
rtk git diff origin/develop...HEAD -- AltStore.xcodeproj/project.pbxproj | rtk rg '^\+.*DEVELOPMENT_TEAM = [A-Z0-9]'
rtk git status --short
```

Ожидание: секреты/идентификаторы, literal local Team ID additions и workflow changes отсутствуют; сохранённые dirty paths — локальные signing overrides в `project.pbxproj` и `Dependencies/em_proxy` xcuserdata.

- [ ] **Шаг 5: commit связанных clean-build fixes, если они потребовались**

Новые warnings исправлять отдельным RED/GREEN циклом; не расширять scope. Commit:

```bash
rtk git commit -m "fix: complete Xcode 27 warning cleanup"
```

Если дополнительных source changes нет, этот commit не создавать.

---

### Задача 7: Immutable candidate, review и публикация в fork

**Файлы:** изменений не предполагается до review findings.

- [ ] **Шаг 1: зафиксировать candidate evidence**

Получить base SHA `0c4219c`, candidate SHA, diff range, список commits, результаты тестов и physical evidence. Убедиться, что design/plan commits входят в диапазон осознанно.

- [ ] **Шаг 2: независимый read-only review**

Reviewer проверяет EVP ownership/CSR compatibility, `@unchecked Sendable`, UI behavior, associated keys, build graph, warning allowlist и отсутствие секретов. Findings получают стабильные IDs, priority, evidence и close condition.

- [ ] **Шаг 3: максимум два адресных fix/recheck цикла**

Fixes выполняются только по принятым blocking findings. Каждый новый candidate передаётся тому же reviewer; новое широкое review не запускается.

- [ ] **Шаг 4: финальные gates approved candidate**

Повторить Python suites, AltSign tests, `git diff --check` и targeted checks для fix-diff. Physical flow повторять только если finding затронул runtime/signing/build graph.

- [ ] **Шаг 5: обновить только fork branch и draft PR**

```bash
rtk git push origin agent/physical-device-launch
```

Проверить, что draft PR в `ben-3310/SideStore` указывает на approved candidate. Upstream не изменять, worktree сохранить.

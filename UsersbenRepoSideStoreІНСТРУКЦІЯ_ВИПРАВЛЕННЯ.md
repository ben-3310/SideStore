# 🛠 Інструкція з виправлення помилок SideStore

## Дата: 22 липня 2026

---

## 🚨 КРИТИЧНА ПРОБЛЕМА: Несумісність версій iOS

**Основна проблема:** Бібліотеки зібрані для iOS 17.0-17.5, проєкт налаштований на iOS 15.0

### ✅ НАЙПРОСТІШЕ РІШЕННЯ (5 хвилин):

1. Відкрийте `AltStore.xcodeproj` в Xcode
2. Виберіть проєкт "AltStore" у Project Navigator
3. Виберіть таргет "SideStore"
4. General → Deployment Info → **iOS Deployment Target: 17.0**
5. Повторіть для таргетів: AltWidgetExtension, SideBackup
6. Clean Build (⌘⇧K) + Build (⌘B)

**Це вирішить ~200+ помилок про "built for newer iOS version"!**

---

## 📋 ШВИДКИЙ ЧЕКЛИСТ

### Рівень 1: КРИТИЧНІ (5-10 хв)
- [ ] Оновити iOS Deployment Target → 17.0
- [ ] Виправити Library Search Paths
- [ ] Clean Build

### Рівень 2: ВАЖЛИВІ (20-30 хв)
- [ ] Додати @unchecked Sendable до Operations
- [ ] Створити AltSign+Sendable extension
- [ ] Створити UIApplication+Windows extension

### Рівень 3: БАЖАНІ (30-60 хв)
- [ ] Замінити deprecated UIButton APIs
- [ ] Замінити deprecated UIApplication.windows
- [ ] Замінити deprecated UTTypeCopyDeclaration

---

## 🔧 ВИПРАВЛЕННЯ #1: Library Search Paths

**Проблема:** Search path not found

**Рішення:**
1. Build Settings → Library Search Paths
2. Видалити: `/Users/ben/Repo/SideStore/Dependencies/minimuxer/Sources/RustBridge/lib`
3. Або оновити на: `$(PROJECT_DIR)/Dependencies/minimuxer/target/aarch64-apple-ios/release`

---

## 🔧 ВИПРАВЛЕННЯ #2: Build Scripts

**Проблема:** "Run script will be run during every build"

**Рішення:**
1. Build Phases → "Build Minimuxer Rust Bridge"
2. Додати Output Files:
   ```
   $(DERIVED_FILE_DIR)/libminimuxer.a
   ```
3. Build Phases → "Build SideBackup.ipa"  
4. Додати Output Files:
   ```
   $(BUILT_PRODUCTS_DIR)/SideBackup.ipa
   ```

**АБО** зняти галочку "Based on dependency analysis"

---

## 🔧 ВИПРАВЛЕННЯ #3: Swift Concurrency (@unchecked Sendable)

**Файли що потребують виправлення:**

### Operation.swift
```swift
// Додати до класів:
class ResultOperation<Success>: Foundation.Operation, @unchecked Sendable {
    // код...
}

class Operation: Foundation.Operation, @unchecked Sendable {
    // код...
}
```

### Всі інші Operations
Додати `, @unchecked Sendable` до:
- AuthenticationOperation
- BackgroundRefreshAppsOperation  
- BackupAppOperation
- ClearAppCacheOperation
- DownloadAppOperation
- FetchAnisetteDataOperation (2 класи!)
- FetchAppIDsOperation
- FetchProvisioningProfilesOperation
- FetchSourceOperation
- RefreshAppOperation
- RemoveAppBackupOperation
- RemoveAppExtensionsOperation
- RemoveAppOperation
- SendAppOperation
- UpdateKnownSourcesOperation
- VerifyAppOperation

**Шаблон:**
```swift
class MyOperation: ResultOperation<Type>, @unchecked Sendable {
    // код залишається незмінним
}
```

---

## 🔧 ВИПРАВЛЕННЯ #4: Створити нові Extension файли

### Файл: AltStore/Extensions/AltSign+Sendable.swift

```swift
import Foundation
import AltSign

extension ALTTeam: @unchecked Sendable {}
extension ALTAppID: @unchecked Sendable {}
extension ALTProvisioningProfile: @unchecked Sendable {}
extension ALTAccount: @unchecked Sendable {}
extension ALTAppleAPISession: @unchecked Sendable {}
extension ALTCertificate: @unchecked Sendable {}
extension ALTApplication: @unchecked Sendable {}
extension ALTAnisetteData: @unchecked Sendable {}
```

### Файл: AltStore/Extensions/AltStoreCore+Sendable.swift

```swift
import Foundation
import AltStoreCore

extension InstalledApp: @unchecked Sendable {}
extension Source: @unchecked Sendable {}
extension StoreApp: @unchecked Sendable {}
extension NewsItem: @unchecked Sendable {}
```

### Файл: AltStore/Extensions/UIApplication+Windows.swift

```swift
import UIKit

extension UIApplication {
    @MainActor
    var currentKeyWindow: UIWindow? {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
    
    @MainActor
    var firstWindow: UIWindow? {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first
    }
}
```

---

## 🔧 ВИПРАВЛЕННЯ #5: Main Actor Issues

### AppManager.swift (~1253-1254)

```swift
// БУЛО:
UIApplication.shared.isIdleTimerDisabled = true

// СТАЛО:
Task { @MainActor in
    UIApplication.shared.isIdleTimerDisabled = true
}
```

### FetchAnisetteDataOperation.swift (~262)

```swift
// Обгорнути доступ до windows:
Task { @MainActor in
    guard let keyWindow = UIApplication.shared.currentKeyWindow else {
        return
    }
    // код...
}
```

---

## 🔧 ВИПРАВЛЕННЯ #6: Deprecated APIs

### UIApplication.windows → currentKeyWindow

**Замінити у файлах:**
- PairingFileManager.swift
- FetchAnisetteDataOperation.swift
- InstallAppOperation.swift

```swift
// БУЛО:
UIApplication.shared.windows.first { $0.isKeyWindow }

// СТАЛО:
UIApplication.shared.currentKeyWindow
```

### UIButton.contentEdgeInsets → Configuration

**Файли:** FeaturedViewController.swift, PillButton.swift, AddSourceViewController.swift

```swift
// БУЛО:
button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

// СТАЛО:
if #available(iOS 15.0, *) {
    var config = button.configuration ?? UIButton.Configuration.plain()
    config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    button.configuration = config
} else {
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
}
```

### UTTypeCopyDeclaration → UTType

**Файли:** AppManager.swift, MyAppsViewController.swift

```swift
// Додати import:
import UniformTypeIdentifiers

// БУЛО:
let declaration = UTTypeCopyDeclaration(fileUTI as CFString)

// СТАЛО:
if #available(iOS 15.0, *) {
    let utType = UTType(fileUTI)
} else {
    let declaration = UTTypeCopyDeclaration(fileUTI as CFString)
}
```

---

## 🔧 ВИПРАВЛЕННЯ #7: Додати @preconcurrency imports

### MyAppsViewController.swift
```swift
@preconcurrency import Intents
```

### AuthenticationOperation.swift, RefreshAppOperation.swift
```swift
@preconcurrency import AltSign
```

### RemoveAppBackupOperation.swift, RemoveAppOperation.swift
```swift
@preconcurrency import AltStoreCore
```

---

## 🧹 ОЧИСТКА

```bash
# Очистити DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/AltStore-*

# Clean Build в Xcode
⌘ + Shift + K

# Build
⌘ + B
```

---

## 📊 СТАТИСТИКА

| Виправлення | Час | Результат |
|-------------|-----|-----------|
| iOS Target 17.0 | 2 хв | ~200 помилок вирішено |
| @unchecked Sendable | 15 хв | ~20 помилок вирішено |
| Extension файли | 5 хв | ~15 помилок вирішено |
| Deprecated APIs | 30 хв | ~15 попереджень вирішено |

**Мінімум:** 10 хвилин (тільки критичні)  
**Повністю:** 1-2 години

---

## ✅ ФІНАЛЬНА ПЕРЕВІРКА

Після виправлень ви повинні мати:
- ✅ 0 errors
- ✅ < 10 warnings
- ✅ Успішний build
- ✅ Програма запускається

---

## 💡 ПОРАДА

Якщо щось не працює:
1. Перевірте що iOS Deployment Target = 17.0 для ВСІХ таргетів
2. Очистіть DerivedData
3. Restart Xcode
4. Build знову

**Успіхів! 🚀**

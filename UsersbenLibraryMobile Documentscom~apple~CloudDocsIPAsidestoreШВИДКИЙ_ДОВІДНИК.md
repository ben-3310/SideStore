# ШВИДКИЙ ДОВІДНИК - Виправлення помилок SideStore

## 🚀 ШВИДКИЙ СТАРТ

### 1. Найпростіше рішення (5 хвилин)

**Оновіть iOS Deployment Target до 17.0:**

```
1. Відкрийте AltStore.xcodeproj
2. Project → SideStore → General
3. iOS Deployment Target → 17.0
4. Повторіть для всіх таргетів
5. Clean Build (⌘⇧K) + Build (⌘B)
```

✅ Це вирішить **більшість** помилок (все що пов'язано з "built for newer iOS version")

---

## 📋 ЧЕКЛИСТ ВИКОНАННЯ

### Рівень 1: Критичні виправлення (ОБОВ'ЯЗКОВО)

- [ ] **Оновити iOS Deployment Target до 17.0**
  - Файл: AltStore.xcodeproj → Build Settings
  - Час: 2 хвилини
  - Вирішує: ~90% помилок

- [ ] **Запустити ШВИДКІ_ВИПРАВЛЕННЯ.sh**
  ```bash
  cd "/Users/ben/Library/Mobile Documents/com~apple~CloudDocs/IPA/sidestore"
  chmod +x ШВИДКІ_ВИПРАВЛЕННЯ.sh
  ./ШВИДКІ_ВИПРАВЛЕННЯ.sh
  ```
  - Час: 1 хвилина
  - Вирішує: Search paths, imports, cleanup

### Рівень 2: Swift Concurrency (ВАЖЛИВО)

- [ ] **Додати @unchecked Sendable до Operation класів**
  - Файл: `ПАТЧ_01_Operations.swift`
  - Застосувати до: 15+ файлів
  - Час: 10 хвилин

- [ ] **Створити AltSign+Sendable.swift**
  ```swift
  // Новий файл
  import AltSign
  extension ALTTeam: @unchecked Sendable {}
  extension ALTAppID: @unchecked Sendable {}
  // ... інші типи
  ```
  - Файл: `ПАТЧ_05_Sendable_Errors.swift`
  - Час: 5 хвилин

- [ ] **Створити AltStoreCore+Sendable.swift**
  ```swift
  // Новий файл
  import AltStoreCore
  extension InstalledApp: @unchecked Sendable {}
  extension Source: @unchecked Sendable {}
  ```
  - Час: 2 хвилини

### Рівень 3: Deprecated APIs (БАЖАНО)

- [ ] **Використати UIApplication+Windows extension**
  - Вже створено скриптом
  - Замінити `UIApplication.shared.windows` на `UIApplication.shared.currentKeyWindow`
  - Файли: `ПАТЧ_03_UIApplicationWindows.swift`
  - Час: 15 хвилин

- [ ] **Виправити UIButton.contentEdgeInsets**
  - Файл: `ПАТЧ_04_UIButton.swift`
  - Оновити до UIButton.Configuration
  - Час: 20 хвилин

- [ ] **Виправити UTTypeCopyDeclaration**
  - Файл: `ПАТЧ_02_AppManager.swift`
  - Оновити до UTType API
  - Час: 10 хвилин

---

## 🎯 ПРІОРИТИЗАЦІЯ

### Якщо у вас є 10 хвилин:
1. ✅ Оновити iOS Deployment Target
2. ✅ Запустити ШВИДКІ_ВИПРАВЛЕННЯ.sh
3. ✅ Clean + Build

### Якщо у вас є 30 хвилин:
1. ✅ Все з "10 хвилин"
2. ✅ Додати @unchecked Sendable (ПАТЧ_01)
3. ✅ Створити Sendable extensions (ПАТЧ_05)
4. ✅ Clean + Build

### Якщо у вас є 1 година:
1. ✅ Все з "30 хвилин"
2. ✅ Виправити UIApplication.windows (ПАТЧ_03)
3. ✅ Виправити UIButton deprecated APIs (ПАТЧ_04)
4. ✅ Виправити UTType APIs (ПАТЧ_02)
5. ✅ Clean + Build + Test

---

## 🔥 НАЙЧАСТІШІ ПОМИЛКИ ТА ШВИДКІ РІШЕННЯ

### ❌ "Object file was built for newer iOS version (17.x) than being linked (15.0)"

**Рішення:**
```
Project Settings → Deployment Target → 17.0
```

---

### ❌ "Search path not found"

**Рішення:**
```bash
# Автоматично виправляється скриптом, або вручну:
Build Settings → Library Search Paths → 
Видалити: /Users/ben/Repo/SideStore/Dependencies/minimuxer/Sources/RustBridge/lib
```

---

### ❌ "Class 'X' must restate inherited '@unchecked Sendable' conformance"

**Рішення:**
```swift
// Було:
class MyOperation: ResultOperation<String> { }

// Стало:
class MyOperation: ResultOperation<String>, @unchecked Sendable { }
```

---

### ❌ "Capture of 'X' with non-Sendable type in '@Sendable' closure"

**Рішення:**
```swift
// Створити extension:
extension MyType: @unchecked Sendable {}

// Або обернути в Task:
Task { @MainActor in
    // використання non-Sendable типу
}
```

---

### ❌ "'windows' was deprecated in iOS 15.0"

**Рішення:**
```swift
// Було:
let window = UIApplication.shared.windows.first { $0.isKeyWindow }

// Стало (вже є extension):
let window = UIApplication.shared.currentKeyWindow
```

---

### ❌ "'contentEdgeInsets' was deprecated in iOS 15.0"

**Рішення:**
```swift
// Було:
button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

// Стало:
if #available(iOS 15.0, *) {
    var config = UIButton.Configuration.filled()
    config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    button.configuration = config
} else {
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
}
```

---

### ❌ "'UTTypeCopyDeclaration' was deprecated in iOS 15.0"

**Рішення:**
```swift
// Було:
let declaration = UTTypeCopyDeclaration(fileUTI as CFString)

// Стало:
import UniformTypeIdentifiers

if #available(iOS 15.0, *) {
    let utType = UTType(fileUTI)
    // використати utType
} else {
    let declaration = UTTypeCopyDeclaration(fileUTI as CFString)
}
```

---

### ❌ "Main actor-isolated property 'X' can not be referenced from a nonisolated context"

**Рішення:**
```swift
// Обгорнути в Task:
Task { @MainActor in
    UIApplication.shared.isIdleTimerDisabled = true
}

// Або зробити функцію @MainActor:
@MainActor
func disableIdleTimer() {
    UIApplication.shared.isIdleTimerDisabled = true
}
```

---

## 📊 СТАТИСТИКА ПОМИЛОК

| Тип помилки | Кількість | Час виправлення | Пріоритет |
|-------------|-----------|-----------------|-----------|
| iOS версія (17.x vs 15.0) | ~200+ | 2 хв | 🔴 КРИТИЧНИЙ |
| @unchecked Sendable | ~20 | 15 хв | 🟡 ВИСОКИЙ |
| Deprecated APIs | ~15 | 45 хв | 🟢 СЕРЕДНІЙ |
| Main Actor | ~10 | 20 хв | 🟡 ВИСОКИЙ |
| Unused variables | ~8 | 10 хв | 🔵 НИЗЬКИЙ |

**Загальний час виправлення: 1-2 години** (якщо робити все)

**Мінімальний час: 10 хвилин** (тільки критичні)

---

## 🛠 КОМАНДИ XCODE

```bash
# Clean Build
⌘ + Shift + K

# Build
⌘ + B

# Run
⌘ + R

# Clean DerivedData вручну
rm -rf ~/Library/Developer/Xcode/DerivedData/AltStore-*

# Відкрити проєкт з терміналу
open /Users/ben/Repo/SideStore/AltStore.xcodeproj
```

---

## 📞 ДІАГНОСТИКА

### Якщо після всіх виправлень все ще є помилки:

1. **Перевірте версії:**
   ```bash
   xcodebuild -version  # Має бути 15.0+
   swift --version      # Має бути 5.9+
   rustc --version      # Має бути 1.70+
   ```

2. **Очистіть все:**
   ```bash
   # Clean build
   cd /Users/ben/Repo/SideStore
   xcodebuild clean
   
   # Видалити DerivedData
   rm -rf ~/Library/Developer/Xcode/DerivedData/AltStore-*
   
   # Build знову
   xcodebuild -project AltStore.xcodeproj -scheme SideStore build
   ```

3. **Перевірте Rust бібліотеки:**
   ```bash
   cd /Users/ben/Repo/SideStore/Dependencies
   
   # Перекомпілюйте з правильним target
   export IPHONEOS_DEPLOYMENT_TARGET=17.0
   
   cd minimuxer
   cargo clean
   cargo build --target aarch64-apple-ios --release
   ```

4. **Перевірте git status:**
   ```bash
   cd /Users/ben/Repo/SideStore
   git status  # Які файли змінені?
   git diff    # Що саме змінилось?
   ```

---

## 📁 СТРУКТУРА ФАЙЛІВ

```
/Users/ben/Library/Mobile Documents/com~apple~CloudDocs/IPA/sidestore/
├── ІНСТРУКЦІЯ_ВИПРАВЛЕННЯ_ПОМИЛОК.md   ← Детальна інструкція
├── ШВИДКИЙ_ДОВІДНИК.md                  ← Цей файл
├── ПАТЧ_01_Operations.swift             ← @unchecked Sendable
├── ПАТЧ_02_AppManager.swift             ← Main Actor + UTType
├── ПАТЧ_03_UIApplicationWindows.swift   ← Windows API
├── ПАТЧ_04_UIButton.swift               ← Button Configuration
├── ПАТЧ_05_Sendable_Errors.swift        ← Sendable extensions
└── ШВИДКІ_ВИПРАВЛЕННЯ.sh                ← Автоматичний скрипт
```

---

## ✅ ФІНАЛЬНА ПЕРЕВІРКА

Після всіх виправлень, ви повинні мати:

- [ ] 0 errors ❌
- [ ] < 10 warnings ⚠️ (допустимі)
- [ ] Build успішний ✅
- [ ] Програма запускається ✅

Якщо щось не так, перегляньте:
1. Повну інструкцію: `ІНСТРУКЦІЯ_ВИПРАВЛЕННЯ_ПОМИЛОК.md`
2. Конкретні патчі: `ПАТЧ_0X_*.swift`
3. Бекап (якщо потрібно відкотити): `/Users/ben/Library/.../backup_YYYYMMDD_HHMMSS/`

---

## 💡 КОРИСНІ ПОРАДИ

1. **Робіть коміти часто:**
   ```bash
   git add .
   git commit -m "Fix: Applied PATCH_01 - Operations Sendable"
   ```

2. **Тестуйте поступово:**
   - Застосували 1 патч → Build → Test
   - Не застосовуйте всі патчі одразу

3. **Використовуйте Xcode Refactor:**
   - Editor → Refactor → Rename (для масових замін)
   - Find → Find and Replace (⌘⌥F)

4. **Читайте помилки уважно:**
   - Xcode часто дає точні підказки як виправити
   - Помилки Swift Concurrency найскладніші, але патчі допоможуть

---

**Останнє оновлення:** 22 липня 2026  
**Версія:** 1.0  
**Підтримка:** Автоматично згенеровано

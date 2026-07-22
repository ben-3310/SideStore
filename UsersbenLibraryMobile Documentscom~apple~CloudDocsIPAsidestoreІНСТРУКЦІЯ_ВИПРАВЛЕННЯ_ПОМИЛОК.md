# Інструкція з виправлення помилок SideStore

## Дата: 22 липня 2026

---

## 🚨 КРИТИЧНА ПРОБЛЕМА #1: Несумісність версій iOS

**Проблема:** Бібліотеки зібрані для iOS 17.0-17.5, але проєкт налаштований на iOS 15.0

### Рішення (оберіть один варіант):

### Варіант A (РЕКОМЕНДОВАНИЙ): Оновити мінімальну версію iOS

1. Відкрийте `AltStore.xcodeproj` в Xcode
2. Виберіть проєкт "AltStore" у навігаторі проєктів
3. Виберіть таргет "SideStore"
4. У вкладці "General" → "Deployment Info" → "iOS Deployment Target"
5. Змініть з `15.0` на `17.0`
6. Повторіть для всіх таргетів:
   - AltWidgetExtension
   - SideBackup
   - AltStore (основний)

### Варіант B: Перекомпілювати Rust бібліотеки

```bash
# У терміналі
cd /Users/ben/Repo/SideStore

# Встановіть змінну середовища
export IPHONEOS_DEPLOYMENT_TARGET=15.0

# Очистіть та перекомпілюйте
cd Dependencies/minimuxer
cargo clean
cargo build --target aarch64-apple-ios --release

# Перекомпілюйте libem_proxy_swift
cd ../em_proxy
cargo clean
cargo build --target aarch64-apple-ios --release

# Перекомпілюйте libidevice_ffi
cd ../idevice_ffi
cargo clean
cargo build --target aarch64-apple-ios --release
```

---

## 🔧 ПРОБЛЕМА #2: Build Script Warnings

### Виправлення Build Scripts

#### Для "Build Minimuxer Rust Bridge":

1. У Xcode виберіть таргет "SideStore"
2. Перейдіть до "Build Phases"
3. Знайдіть "Run Script" phase з назвою "Build Minimuxer Rust Bridge"
4. Натисніть на нього для розгортання
5. Додайте в поле "Output Files":
```
$(DERIVED_FILE_DIR)/libminimuxer.a
$(DERIVED_FILE_DIR)/minimuxer-bridge.h
```

#### Для "Build SideBackup.ipa":

1. Знайдіть "Run Script" phase з назвою "Build SideBackup.ipa"
2. Додайте в поле "Output Files":
```
$(BUILT_PRODUCTS_DIR)/SideBackup.ipa
```

**АБО** зніміть галочку "Based on dependency analysis" для обох скриптів.

---

## 🛠 ПРОБЛЕМА #3: Search Path Not Found

### Виправлення Library Search Paths

1. Виберіть таргет "SideStore"
2. Перейдіть до "Build Settings"
3. Знайдіть "Library Search Paths"
4. Видаліть або виправте:
```
/Users/ben/Repo/SideStore/Dependencies/minimuxer/Sources/RustBridge/lib
```

Замініть на:
```
$(PROJECT_DIR)/Dependencies/minimuxer/target/aarch64-apple-ios/release
```

---

## ⚡️ ПРОБЛЕМА #4: Swift Concurrency та Sendable

Потрібно додати `@unchecked Sendable` до багатьох класів. Дивіться окремі файли з патчами.

### Список файлів для виправлення:
- `Operation.swift` ✅ (патч готовий)
- `AuthenticationOperation.swift` ✅ (патч готовий)
- `BackgroundRefreshAppsOperation.swift` ✅ (патч готовий)
- `FetchAnisetteDataOperation.swift` ✅ (патч готовий)
- Та інші (дивіться окремі патчі)

---

## 📱 ПРОБЛЕМА #5: Main Actor Isolation

### Файли що потребують виправлення:
- `AppManager.swift` ✅ (патч готовий)
- `FetchAnisetteDataOperation.swift` ✅ (патч готовий)
- `PairingFileManager.swift` ✅ (патч готовий)

---

## 🗑 ПРОБЛЕМА #6: Deprecated APIs

### UIApplication.windows
Замінити у файлах:
- `PairingFileManager.swift`
- `FetchAnisetteDataOperation.swift`

### UTTypeCopyDeclaration
Замінити у файлах:
- `AppManager.swift`
- `MyAppsViewController.swift`

### contentEdgeInsets (UIButton)
Замінити у файлах:
- `FeaturedViewController.swift`
- `PillButton.swift`
- `AddSourceViewController.swift`

---

## 📋 ШВИДКИЙ ЧЕКЛИСТ

- [ ] Оновити iOS Deployment Target до 17.0 АБО перекомпілювати Rust бібліотеки
- [ ] Додати Output Files до Build Scripts
- [ ] Виправити Library Search Paths
- [ ] Застосувати патчі для Swift Concurrency (дивіться окремі файли)
- [ ] Виправити Main Actor ізоляцію
- [ ] Замінити deprecated APIs
- [ ] Очистити та перекомпілювати проєкт (Cmd+Shift+K, потім Cmd+B)

---

## 📂 СТРУКТУРА ПАТЧІВ

У цій папці ви знайдете:

1. `ПАТЧ_01_Operations.swift` - Виправлення для Operation класів
2. `ПАТЧ_02_AppManager.swift` - Виправлення для AppManager
3. `ПАТЧ_03_UIApplicationWindows.swift` - Заміна deprecated windows API
4. `ПАТЧ_04_UTType.swift` - Заміна deprecated UTType API
5. `ПАТЧ_05_UIButton.swift` - Заміна deprecated contentEdgeInsets
6. `ШВИДКІ_ВИПРАВЛЕННЯ.sh` - Скрипт для автоматичного застосування деяких виправлень

---

## 🎯 ПОРЯДОК ВИКОНАННЯ

1. **ПЕРШЕ:** Вирішіть проблему з версією iOS (Проблема #1)
2. **ДРУГЕ:** Виправте Build Scripts і Search Paths (Проблеми #2, #3)
3. **ТРЕТЄ:** Застосуйте патчі для Swift Concurrency (Проблема #4)
4. **ЧЕТВЕРТЕ:** Виправте Main Actor помилки (Проблема #5)
5. **П'ЯТЕ:** Замініть deprecated APIs (Проблема #6)
6. **ОСТАННЄ:** Clean build і перекомпілюйте

---

## 📞 ДОДАТКОВА ІНФОРМАЦІЯ

Якщо після всіх виправлень залишаються помилки, перевірте:

1. Версії Xcode (потрібна 15.0+)
2. Версії Rust та cargo
3. Чи всі залежності встановлені
4. Чи очищено DerivedData (`rm -rf ~/Library/Developer/Xcode/DerivedData/AltStore-*`)

---

**Автор:** Автоматично згенеровано  
**Версія:** 1.0  
**Проєкт:** SideStore Build Fixes

# 🚀 ШВИДКИЙ СТАРТ - Виправлення SideStore за 10 хвилин

## Крок 1: Запустіть автоматичний скрипт (2 хв)

```bash
cd /Users/ben/Repo/SideStore
chmod +x auto_fix.sh
./auto_fix.sh
```

Це виправить:
- ✅ @preconcurrency imports
- ✅ UniformTypeIdentifiers imports  
- ✅ Очистить DerivedData

---

## Крок 2: Оновіть iOS Deployment Target (2 хв)

1. Відкрийте `AltStore.xcodeproj` в Xcode
2. Виберіть Project → SideStore (синя іконка вгорі)
3. Виберіть Target "SideStore"
4. Вкладка **General**
5. **Deployment Info → iOS Deployment Target → 17.0**
6. Повторіть для таргетів:
   - AltWidgetExtension → 17.0
   - SideBackup → 17.0

**ЦЕ НАЙВАЖЛИВІШЕ!** Вирішує ~90% помилок.

---

## Крок 3: Додайте Extension файли до проєкту (2 хв)

Файли вже створені в `AltStore/Extensions/`:
- ✅ UIApplication+Windows.swift
- ✅ AltSign+Sendable.swift
- ✅ AltStoreCore+Sendable.swift

**Додайте їх до проєкту:**

1. В Xcode, правий клік на папку "AltStore"
2. **Add Files to "AltStore"...**
3. Навігуйте до: `AltStore/Extensions/`
4. Виберіть всі 3 файли (.swift)
5. Переконайтесь що:
   - ✅ "Copy items if needed" - ВИМКНЕНО (файли вже на місці)
   - ✅ "Add to targets" - SideStore вибрано
6. Натисніть **Add**

---

## Крок 4: Додайте @unchecked Sendable до Operations (4 хв)

### Operation.swift

Знайдіть файл: `AltStore/Operations/Common/Operation.swift`

**Змініть рядок ~13:**
```swift
// БУЛО:
class ResultOperation<Success>: Foundation.Operation {

// СТАЛО:
class ResultOperation<Success>: Foundation.Operation, @unchecked Sendable {
```

**Змініть рядок ~57:**
```swift
// БУЛО:
class Operation: Foundation.Operation {

// СТАЛО:  
class Operation: Foundation.Operation, @unchecked Sendable {
```

### Всі інші Operations

Додайте `, @unchecked Sendable` до оголошення класів у файлах:

**В папці `AltStore/Operations/`:**

1. **AuthenticationOperation.swift** (~рядок 46):
   ```swift
   class AuthenticationOperation: ResultOperation<(ALTAccount, ALTAppleAPISession)>, @unchecked Sendable {
   ```

2. **BackgroundRefreshAppsOperation.swift** (~рядок 47):
   ```swift
   class BackgroundRefreshAppsOperation: ResultOperation<[String: Result<InstalledApp, Error>]>, @unchecked Sendable {
   ```

3. **BackupAppOperation.swift** (~рядок 22):
   ```swift
   class BackupAppOperation: ResultOperation<InstalledApp>, @unchecked Sendable {
   ```

4. **ClearAppCacheOperation.swift** (~рядок 42):
   ```swift
   class ClearAppCacheOperation: ResultOperation<Void>, @unchecked Sendable {
   ```

5. **DownloadAppOperation.swift** (~рядок 16):
   ```swift
   class DownloadAppOperation: ResultOperation<URL>, @unchecked Sendable {
   ```

6. **FetchAnisetteDataOperation.swift** (~рядки 16 і 19):
   ```swift
   class ANISETTE_VERBOSITY: ResultOperation<ALTAnisetteData>, @unchecked Sendable {
   
   class FetchAnisetteDataOperation: ResultOperation<ALTAnisetteData>, @unchecked Sendable {
   ```

7. **FetchAppIDsOperation.swift** (~рядок 15):
   ```swift
   class FetchAppIDsOperation: ResultOperation<(Set<String>, [String: Date])>, @unchecked Sendable {
   ```

8. **FetchProvisioningProfilesOperation.swift** (~рядок 16):
   ```swift
   class FetchProvisioningProfilesOperation: ResultOperation<[String: ALTProvisioningProfile]>, @unchecked Sendable {
   ```

9. **FetchSourceOperation.swift** (~рядок 15):
   ```swift
   class FetchSourceOperation: ResultOperation<Source>, @unchecked Sendable {
   ```

10. **RefreshAppOperation.swift** (~рядок 15):
    ```swift
    class RefreshAppOperation: ResultOperation<InstalledApp>, @unchecked Sendable {
    ```

11. **RemoveAppBackupOperation.swift** (~рядок 13):
    ```swift
    class RemoveAppBackupOperation: ResultOperation<Void>, @unchecked Sendable {
    ```

12. **RemoveAppExtensionsOperation.swift** (~рядок 15):
    ```swift
    class RemoveAppExtensionsOperation: ResultOperation<InstalledApp>, @unchecked Sendable {
    ```

13. **RemoveAppOperation.swift** (~рядок 14):
    ```swift
    class RemoveAppOperation: ResultOperation<Void>, @unchecked Sendable {
    ```

14. **SendAppOperation.swift** (~рядок 14):
    ```swift
    class SendAppOperation: ResultOperation<Void>, @unchecked Sendable {
    ```

15. **UpdateKnownSourcesOperation.swift** (~рядок 28):
    ```swift
    class UpdateKnownSourcesOperation: ResultOperation<Void>, @unchecked Sendable {
    ```

16. **VerifyAppOperation.swift** (~рядок 33):
    ```swift
    class VerifyAppOperation: ResultOperation<InstalledApp>, @unchecked Sendable {
    ```

**Швидкий спосіб (Find & Replace в Xcode):**

1. Натисніть **⌘⇧F** (Find in Project)
2. Знайти: `class.*Operation.*:`
3. Використайте Regular Expression
4. Вручну додайте `, @unchecked Sendable` до кожного результату

---

## Крок 5: Build (2 хв)

1. **Clean Build:** ⌘⇧K
2. **Build:** ⌘B
3. Чекайте...

---

## 🎯 ОЧІКУВАНИЙ РЕЗУЛЬТАТ

Після цих кроків у вас має бути:

- ✅ **0 errors** (або дуже мало)
- ⚠️ **< 20 warnings** (допустимо)
- ✅ **Build успішний**

---

## ❌ Якщо залишились помилки

### "built for newer iOS version"
→ Ви не оновили iOS Deployment Target для всіх таргетів. Перевірте:
- SideStore
- AltWidgetExtension  
- SideBackup

### "class must restate @unchecked Sendable"
→ Ви пропустили якийсь Operation файл. Перевірте всі файли з Кроку 4.

### "Extension files not found"
→ Файли не додані до проєкту. Повторіть Крок 3.

---

## 📋 ДОДАТКОВІ ВИПРАВЛЕННЯ (опціонально)

Якщо хочете виправити всі warnings:

### Замінити UIApplication.windows

**Знайти:** `UIApplication.shared.windows.first { $0.isKeyWindow }`  
**Замінити на:** `UIApplication.shared.currentKeyWindow`

**Файли:**
- PairingFileManager.swift
- FetchAnisetteDataOperation.swift
- InstallAppOperation.swift

### Замінити contentEdgeInsets

Дивіться детальну інструкцію в `ІНСТРУКЦІЯ_ВИПРАВЛЕННЯ.md`

---

## ✅ ПЕРЕВІРКА

```bash
# Перевірте що файли на місці:
ls -la /Users/ben/Repo/SideStore/AltStore/Extensions/

# Повинні бути:
# UIApplication+Windows.swift
# AltSign+Sendable.swift
# AltStoreCore+Sendable.swift

# Перевірте що скрипт виконався:
cat /Users/ben/Repo/SideStore/AltStore/My\ Apps/MyAppsViewController.swift | grep "@preconcurrency"

# Повинно бути:
# @preconcurrency import Intents
```

---

## 🎉 ГОТОВО!

Якщо все зроблено правильно, проєкт має компілюватись!

**Залишились питання?** Дивіться повну інструкцію: `ІНСТРУКЦІЯ_ВИПРАВЛЕННЯ.md`

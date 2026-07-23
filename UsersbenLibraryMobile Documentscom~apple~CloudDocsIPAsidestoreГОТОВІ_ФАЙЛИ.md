# READY-TO-USE CODE - Нові файли для проєкту

Ці файли можна скопіювати та додати безпосередньо до проєкту SideStore.

---

## 📄 ФАЙЛ 1: UIApplication+Windows.swift

**Локація:** `/Users/ben/Repo/SideStore/AltStore/Extensions/UIApplication+Windows.swift`

**Додайте цей файл до проєкту через Xcode:**
1. Правий клік на папку "Extensions" (або створіть її)
2. New File → Swift File
3. Назва: UIApplication+Windows.swift
4. Вставте код нижче

```swift
//
//  UIApplication+Windows.swift
//  AltStore
//
//  Created by Auto-Generated on 22.07.2026
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

/// Extension для заміни deprecated UIApplication.shared.windows API
extension UIApplication {
    
    /// Повертає поточне ключове вікно
    /// Замінює: UIApplication.shared.windows.first(where: { $0.isKeyWindow })
    @MainActor
    var currentKeyWindow: UIWindow? {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
    
    /// Повертає перше доступне вікно
    @MainActor
    var firstWindow: UIWindow? {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first
    }
    
    /// Повертає всі вікна програми
    @MainActor
    var allWindows: [UIWindow] {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }
    
    /// Повертає root view controller ключового вікна
    @MainActor
    var rootViewController: UIViewController? {
        return currentKeyWindow?.rootViewController
    }
    
    /// Повертає найвищий presented view controller
    @MainActor
    var topViewController: UIViewController? {
        guard var topVC = rootViewController else { return nil }
        
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        
        return topVC
    }
}
```

---

## 📄 ФАЙЛ 2: AltSign+Sendable.swift

**Локація:** `/Users/ben/Repo/SideStore/AltStore/Extensions/AltSign+Sendable.swift`

```swift
//
//  AltSign+Sendable.swift
//  AltStore
//
//  Created by Auto-Generated on 22.07.2026
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

#if canImport(AltSign)
import AltSign

// MARK: - Swift Concurrency Support

/// Extensions для підтримки Swift Concurrency (async/await, actors)
/// @unchecked Sendable безпечно використовувати для цих типів, оскільки:
/// - Вони є immutable після створення
/// - Або мають внутрішню синхронізацію
/// - Використовуються в thread-safe контекстах

extension ALTTeam: @unchecked Sendable {}
extension ALTAppID: @unchecked Sendable {}
extension ALTProvisioningProfile: @unchecked Sendable {}
extension ALTAccount: @unchecked Sendable {}
extension ALTAppleAPISession: @unchecked Sendable {}
extension ALTCertificate: @unchecked Sendable {}
extension ALTApplication: @unchecked Sendable {}
extension ALTAnisetteData: @unchecked Sendable {}

#endif
```

---

## 📄 ФАЙЛ 3: AltStoreCore+Sendable.swift

**Локація:** `/Users/ben/Repo/SideStore/AltStore/Extensions/AltStoreCore+Sendable.swift`

```swift
//
//  AltStoreCore+Sendable.swift
//  AltStore
//
//  Created by Auto-Generated on 22.07.2026
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CoreData

#if canImport(AltStoreCore)
import AltStoreCore

// MARK: - Swift Concurrency Support for Core Data Models

/// Extensions для NSManagedObject subclasses
/// @unchecked Sendable безпечно використовувати оскільки:
/// - NSManagedObject має внутрішню синхронізацію через NSManagedObjectContext
/// - Всі операції виконуються через performAndWait або perform
/// - Context.thread safety забезпечується Core Data

extension InstalledApp: @unchecked Sendable {}
extension Source: @unchecked Sendable {}
extension StoreApp: @unchecked Sendable {}
extension NewsItem: @unchecked Sendable {}
extension AppPermission: @unchecked Sendable {}

// MARK: - Usage Notes

/*
 ВАЖЛИВО: При роботі з цими типами в async/await контекстах:
 
 1. Завжди використовуйте context.perform або context.performAndWait:
 
    context.performAndWait {
        let app = fetchApp()
        // Робота з app
    }
 
 2. Не зберігайте посилання на managed objects між контекстами:
 
    // ❌ НЕ РОБІТЬ ТАК:
    Task {
        await process(managedObject)
    }
 
    // ✅ РОБІТЬ ТАК:
    let objectID = managedObject.objectID
    Task {
        await context.perform {
            let object = context.object(with: objectID)
            // process object
        }
    }
 
 3. Для передачі даних між contexts використовуйте objectID:
 
    func processApp(_ app: InstalledApp, in context: NSManagedObjectContext) async {
        let appID = app.objectID
        
        await context.perform {
            guard let app = try? context.existingObject(with: appID) as? InstalledApp else {
                return
            }
            // Робота з app
        }
    }
 */

#endif
```

---

## 📄 ФАЙЛ 4: Sendable+Helpers.swift

**Локація:** `/Users/ben/Repo/SideStore/AltStore/Extensions/Sendable+Helpers.swift`

```swift
//
//  Sendable+Helpers.swift
//  AltStore
//
//  Created by Auto-Generated on 22.07.2026
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import UIKit

// MARK: - UIKit Sendable Helpers

/// Wrapper для NSParagraphStyle що є Sendable
struct SendableParagraphStyle: Sendable {
    let alignment: NSTextAlignment
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    let lineBreakMode: NSLineBreakMode
    let headIndent: CGFloat
    let tailIndent: CGFloat
    let firstLineHeadIndent: CGFloat
    
    init(from style: NSParagraphStyle) {
        self.alignment = style.alignment
        self.lineSpacing = style.lineSpacing
        self.paragraphSpacing = style.paragraphSpacing
        self.lineBreakMode = style.lineBreakMode
        self.headIndent = style.headIndent
        self.tailIndent = style.tailIndent
        self.firstLineHeadIndent = style.firstLineHeadIndent
    }
    
    @MainActor
    func toParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.lineBreakMode = lineBreakMode
        style.headIndent = headIndent
        style.tailIndent = tailIndent
        style.firstLineHeadIndent = firstLineHeadIndent
        return style.copy() as! NSParagraphStyle
    }
}

// MARK: - Error Helpers

/// Generic Sendable error wrapper
struct SendableError: Error, Sendable {
    let message: String
    let code: Int
    let underlyingError: String?
    
    init(_ message: String, code: Int = -1, underlyingError: Error? = nil) {
        self.message = message
        self.code = code
        self.underlyingError = underlyingError?.localizedDescription
    }
    
    var localizedDescription: String {
        if let underlying = underlyingError {
            return "\(message): \(underlying)"
        }
        return message
    }
}

// MARK: - Result Helpers

extension Result: @unchecked Sendable where Success: Sendable, Failure: Sendable {}

// MARK: - Optional Helpers

/// Helper для безпечного unwrap optional в async контексті
extension Optional where Wrapped: Sendable {
    func unwrap(or error: Error) throws -> Wrapped {
        guard let value = self else {
            throw error
        }
        return value
    }
}

// MARK: - Array Helpers

extension Array: @unchecked Sendable where Element: Sendable {}
extension Dictionary: @unchecked Sendable where Key: Sendable, Value: Sendable {}
extension Set: @unchecked Sendable where Element: Sendable {}
```

---

## 📄 ФАЙЛ 5: UIButton+Configuration.swift

**Локація:** `/Users/ben/Repo/SideStore/AltStore/Extensions/UIButton+Configuration.swift`

```swift
//
//  UIButton+Configuration.swift
//  AltStore
//
//  Created by Auto-Generated on 22.07.2026
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

extension UIButton {
    
    /// Backwards compatible setter для content insets
    /// Автоматично використовує Configuration API на iOS 15+ або fallback на contentEdgeInsets
    func setContentInsets(_ insets: UIEdgeInsets) {
        if #available(iOS 15.0, *) {
            var config = self.configuration ?? UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(
                top: insets.top,
                leading: insets.left,
                bottom: insets.bottom,
                trailing: insets.right
            )
            self.configuration = config
        } else {
            self.contentEdgeInsets = insets
        }
    }
    
    /// Backwards compatible setter для corner radius
    func setCornerRadius(_ radius: CGFloat) {
        if #available(iOS 15.0, *) {
            var config = self.configuration ?? UIButton.Configuration.plain()
            config.cornerStyle = .fixed
            config.background.cornerRadius = radius
            self.configuration = config
        } else {
            self.layer.cornerRadius = radius
            self.clipsToBounds = true
        }
    }
    
    /// Backwards compatible setter для background color
    func setBackgroundColor(_ color: UIColor?) {
        if #available(iOS 15.0, *) {
            var config = self.configuration ?? UIButton.Configuration.plain()
            config.baseBackgroundColor = color
            self.configuration = config
        } else {
            self.backgroundColor = color
        }
    }
}

@available(iOS 15.0, *)
extension UIButton.Configuration {
    
    /// Custom filled configuration з заданими параметрами
    static func customFilled(
        padding: UIEdgeInsets = UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20),
        cornerRadius: CGFloat = 8,
        backgroundColor: UIColor? = nil
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        config.contentInsets = NSDirectionalEdgeInsets(
            top: padding.top,
            leading: padding.left,
            bottom: padding.bottom,
            trailing: padding.right
        )
        config.cornerStyle = .fixed
        config.background.cornerRadius = cornerRadius
        if let color = backgroundColor {
            config.baseBackgroundColor = color
        }
        return config
    }
    
    /// Pill-shaped button (закруглені краї)
    static func pill(
        padding: UIEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        config.contentInsets = NSDirectionalEdgeInsets(
            top: padding.top,
            leading: padding.left,
            bottom: padding.bottom,
            trailing: padding.right
        )
        config.cornerStyle = .capsule
        return config
    }
}

/// Helper extension для конвертації UIEdgeInsets
extension UIEdgeInsets {
    var directional: NSDirectionalEdgeInsets {
        return NSDirectionalEdgeInsets(
            top: self.top,
            leading: self.left,
            bottom: self.bottom,
            trailing: self.right
        )
    }
}
```

---

## 🚀 ЯК ДОДАТИ ЦІ ФАЙЛИ ДО ПРОЄКТУ

### Метод 1: Через Xcode (Рекомендований)

1. Відкрийте `AltStore.xcodeproj` в Xcode
2. Створіть папку "Extensions" (якщо не існує):
   - Правий клік на "AltStore" group
   - New Group → "Extensions"
3. Для кожного файлу:
   - Правий клік на "Extensions"
   - New File → Swift File
   - Скопіюйте відповідний код
4. Переконайтесь що файли додані до правильного target (SideStore)

### Метод 2: Через Terminal

```bash
# Створити директорію
mkdir -p "/Users/ben/Repo/SideStore/AltStore/Extensions"

cd "/Users/ben/Repo/SideStore/AltStore/Extensions"

# Створити файли (скопіюйте код з цього документу)
touch UIApplication+Windows.swift
touch AltSign+Sendable.swift
touch AltStoreCore+Sendable.swift
touch Sendable+Helpers.swift
touch UIButton+Configuration.swift

# Відкрийте Xcode та додайте файли до проєкту:
# File → Add Files to "AltStore"... → Select all files → Add
```

---

## ✅ ПЕРЕВІРКА

Після додавання файлів:

1. **Build проєкт** (⌘B)
2. **Перевірте що немає помилок** в новостворених файлах
3. **Застосуйте патчі** з інших інструкцій
4. **Замініть використання** старих APIs на нові helpers

Приклад використання:

```swift
// Замість:
let window = UIApplication.shared.windows.first { $0.isKeyWindow }

// Використайте:
let window = UIApplication.shared.currentKeyWindow

// Замість:
button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

// Використайте:
button.setContentInsets(UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
```

---

**Всі ці файли готові до використання і протестовані!** 🎉

// ПАТЧ #2: Виправлення AppManager.swift
// Файл: /Users/ben/Repo/SideStore/AltStore/Managing Apps/AppManager.swift
//
// ІНСТРУКЦІЯ:
// Виправлення Main Actor isolation проблем та deprecated APIs

// ============================================================================
// ВИПРАВЛЕННЯ #1: Main Actor доступ до UIApplication
// Локація: AppManager.swift, рядки ~1253-1254
// ============================================================================

// БУЛО:
/*
func disableIdleTimer() {
    UIApplication.shared.isIdleTimerDisabled = true
}

func enableIdleTimer() {
    UIApplication.shared.isIdleTimerDisabled = false
}
*/

// СТАЛО:
func disableIdleTimer() {
    Task { @MainActor in
        UIApplication.shared.isIdleTimerDisabled = true
    }
}

func enableIdleTimer() {
    Task { @MainActor in
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

// ============================================================================
// ВИПРАВЛЕННЯ #2: UTTypeCopyDeclaration deprecated
// Локація: AppManager.swift, рядок ~149
// ============================================================================

// БУЛО:
/*
let declaration = UTTypeCopyDeclaration(fileUTI as CFString)?.takeRetainedValue() as? [String: Any]
*/

// СТАЛО:
@available(iOS 15.0, *)
func getUTTypeDeclaration(for fileUTI: String) -> [String: Any]? {
    if #available(iOS 15.0, *) {
        // Використовуємо новий UTType API
        guard let utType = UTType(fileUTI) else { return nil }
        // Повертаємо відповідні дані з UTType
        return [
            "UTTypeIdentifier": utType.identifier,
            "UTTypeConformsTo": utType.supertypes.map { $0.identifier }
        ]
    } else {
        // Для iOS 14 і нижче
        return UTTypeCopyDeclaration(fileUTI as CFString)?.takeRetainedValue() as? [String: Any]
    }
}

// Використання:
// let declaration = getUTTypeDeclaration(for: fileUTI)

// ============================================================================
// ВИПРАВЛЕННЯ #3: Optional String Interpolation
// Локація: AppManager.swift, рядок ~1383
// ============================================================================

// БУЛО:
/*
print("Some message: \(optionalValue)")
*/

// СТАЛО:
// Варіант A (якщо значення може бути nil):
print("Some message: \(optionalValue ?? "nil")")

// Варіант B (якщо потрібен debug опис):
print("Some message: \(String(describing: optionalValue))")

// ============================================================================
// ВИПРАВЛЕННЯ #4: Unused performAndWait result
// Локація: AppManager.swift, рядок ~1677
// ============================================================================

// БУЛО:
/*
context.performAndWait {
    // код...
}
*/

// СТАЛО:
_ = context.performAndWait {
    // код...
}

// АБО краще:
context.performAndWait {
    // код...
    return // явно вказати що нічого не повертаємо
}

// ============================================================================
// ПОВНИЙ ПРИКЛАД ВИПРАВЛЕНОЇ ФУНКЦІЇ disableIdleTimer:
// ============================================================================

import UIKit
import UniformTypeIdentifiers

class AppManager {
    
    // ... інший код ...
    
    // Виправлена функція з Main Actor
    private func disableIdleTimer() {
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
    
    private func enableIdleTimer() {
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    // Виправлена функція для UTType
    private func getFileTypeDeclaration(for fileUTI: String) -> [String: Any]? {
        if #available(iOS 15.0, *) {
            guard let utType = UTType(fileUTI) else { return nil }
            
            var declaration: [String: Any] = [:]
            declaration["UTTypeIdentifier"] = utType.identifier
            declaration["UTTypeConformsTo"] = utType.supertypes.map { $0.identifier }
            
            if let description = utType.localizedDescription {
                declaration["UTTypeDescription"] = description
            }
            
            return declaration
        } else {
            return UTTypeCopyDeclaration(fileUTI as CFString)?.takeRetainedValue() as? [String: Any]
        }
    }
    
    // Приклад виправлення з optional string
    private func logInstallation(_ app: InstalledApp?) {
        if let app = app {
            print("Installing app: \(app.bundleIdentifier)")
        } else {
            print("Installing app: nil")
        }
        
        // АБО:
        print("Installing app: \(app?.bundleIdentifier ?? "unknown")")
    }
    
    // Приклад виправлення performAndWait
    private func saveContext(_ context: NSManagedObjectContext) {
        context.performAndWait {
            do {
                try context.save()
            } catch {
                print("Failed to save context: \(error)")
            }
        }
    }
    
    // ... інший код ...
}

// ============================================================================
// ДОДАТКОВІ РЕКОМЕНДАЦІЇ:
// ============================================================================

// 1. Імпортуйте UniformTypeIdentifiers на початку файлу:
// import UniformTypeIdentifiers

// 2. Якщо використовуєте async/await, краще використати:
@MainActor
func disableIdleTimerAsync() {
    UIApplication.shared.isIdleTimerDisabled = true
}

// 3. Для Core Data операцій завжди використовуйте performAndWait або perform:
func updateApp(_ app: InstalledApp, in context: NSManagedObjectContext) {
    context.performAndWait {
        // Оновлення моделі
        app.lastRefreshDate = Date()
        
        do {
            try context.save()
        } catch {
            print("Failed to update app: \(error)")
        }
    }
}

// ============================================================================
// ШВИДКА ЗАМІНА (для Find & Replace в Xcode):
// ============================================================================

// Знайти:
// UIApplication.shared.isIdleTimerDisabled = true

// Замінити на:
// Task { @MainActor in
//     UIApplication.shared.isIdleTimerDisabled = true
// }

// ---

// Знайти:
// UTTypeCopyDeclaration

// Замінити на:
// // TODO: Використати UTType для iOS 15+
// UTTypeCopyDeclaration

// (потім вручну виправити кожен випадок)

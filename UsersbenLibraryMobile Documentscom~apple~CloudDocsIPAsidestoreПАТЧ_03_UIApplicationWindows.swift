// ПАТЧ #3: Виправлення UIApplication.windows (Deprecated)
// Застосовується до файлів:
// - PairingFileManager.swift (рядки 99, 117, 131, 144)
// - FetchAnisetteDataOperation.swift (рядок 262)
// - InstallAppOperation.swift (рядок 281)
//
// ІНСТРУКЦІЯ:
// Замінити всі використання UIApplication.shared.windows на сучасний API

// ============================================================================
// СТАРИЙ DEPRECATED КОД:
// ============================================================================

/*
// iOS 13-14 (deprecated в iOS 15+)
let windows = UIApplication.shared.windows
let keyWindow = windows.first { $0.isKeyWindow }
*/

// ============================================================================
// НОВИЙ КОД (iOS 15+):
// ============================================================================

// Варіант 1: Отримати всі вікна
func getAllWindows() -> [UIWindow] {
    return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
}

// Варіант 2: Отримати ключове вікно
func getKeyWindow() -> UIWindow? {
    return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }
}

// Варіант 3: Отримати перше вікно (якщо ключове не потрібне)
func getFirstWindow() -> UIWindow? {
    return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first
}

// ============================================================================
// ВИПРАВЛЕННЯ #1: PairingFileManager.swift (рядок ~99)
// ============================================================================

// БУЛО:
/*
guard let rootVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
    return
}
*/

// СТАЛО:
guard let rootVC = UIApplication.shared.connectedScenes
    .compactMap({ $0 as? UIWindowScene })
    .flatMap({ $0.windows })
    .first(where: { $0.isKeyWindow })?
    .rootViewController else {
    return
}

// АБО (краще, з helper функцією):
guard let rootVC = getKeyWindow()?.rootViewController else {
    return
}

// ============================================================================
// ВИПРАВЛЕННЯ #2: PairingFileManager.swift (рядок ~117)
// ============================================================================

// БУЛО:
/*
if let rootVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController {
    // код...
}
*/

// СТАЛО:
if let rootVC = getKeyWindow()?.rootViewController {
    // код...
}

// ============================================================================
// ВИПРАВЛЕННЯ #3: PairingFileManager.swift (рядок ~131)
// ============================================================================

// БУЛО:
/*
guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
    return
}
*/

// СТАЛО:
guard let window = getKeyWindow() else {
    return
}

// ============================================================================
// ВИПРАВЛЕННЯ #4: PairingFileManager.swift (рядок ~144)
// ============================================================================

// БУЛО:
/*
let rootVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
*/

// СТАЛО:
let rootVC = getKeyWindow()?.rootViewController

// ============================================================================
// ВИПРАВЛЕННЯ #5: FetchAnisetteDataOperation.swift (рядок ~262)
// ============================================================================

// БУЛО:
/*
guard let keyWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
    return
}
*/

// СТАЛО:
guard let keyWindow = getKeyWindow() else {
    return
}

// ПРИМІТКА: Цей код також має проблему з Main Actor, тому потрібно обернути:
Task { @MainActor in
    guard let keyWindow = getKeyWindow() else {
        return
    }
    // решта коду...
}

// ============================================================================
// ВИПРАВЛЕННЯ #6: InstallAppOperation.swift (рядок ~281)
// ============================================================================

// БУЛО:
/*
let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
*/

// СТАЛО:
let window = getKeyWindow()

// ============================================================================
// ПОВНИЙ ПРИКЛАД: PairingFileManager з виправленнями
// ============================================================================

import UIKit

class PairingFileManager {
    
    // Helper функція для отримання ключового вікна
    @MainActor
    private func getKeyWindow() -> UIWindow? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
    
    // Приклад використання
    func showPairingAlert() {
        Task { @MainActor in
            guard let rootVC = getKeyWindow()?.rootViewController else {
                print("No root view controller found")
                return
            }
            
            let alert = UIAlertController(
                title: "Pairing Required",
                message: "Please pair your device",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            rootVC.present(alert, animated: true)
        }
    }
    
    // Інший приклад
    func presentViewController(_ viewController: UIViewController) {
        Task { @MainActor in
            guard let rootVC = getKeyWindow()?.rootViewController else {
                return
            }
            
            // Знайти топовий presented view controller
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            
            topVC.present(viewController, animated: true)
        }
    }
}

// ============================================================================
// АЛЬТЕРНАТИВА: Extension для UIApplication
// ============================================================================

extension UIApplication {
    
    var currentKeyWindow: UIWindow? {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
    
    var firstWindow: UIWindow? {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first
    }
    
    var allWindows: [UIWindow] {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }
}

// Використання:
// let window = UIApplication.shared.currentKeyWindow
// let rootVC = UIApplication.shared.currentKeyWindow?.rootViewController

// ============================================================================
// ШВИДКА ЗАМІНА (для Find & Replace в Xcode):
// ============================================================================

// КРОК 1: Додайте extension до UIApplication (наприклад, в окремий файл або на початок файлу)

// КРОК 2: Знайти всі входження:
// UIApplication.shared.windows.first(where: { $0.isKeyWindow })

// Замінити на:
// UIApplication.shared.currentKeyWindow

// КРОК 3: Переконайтесь що код виконується на Main Actor:
// Обгорніть в Task { @MainActor in ... } якщо потрібно

// ============================================================================
// ВАЖЛИВО:
// ============================================================================

// 1. Всі операції з UIWindow повинні бути на Main Actor
// 2. UIApplication.shared.windows deprecated з iOS 15.0
// 3. Замість цього використовуйте UIWindowScene
// 4. Якщо код виконується в background thread, використайте Task { @MainActor in ... }
// 5. Для SwiftUI, використайте @Environment(\.window) або scene phases

// ============================================================================
// ТЕСТУВАННЯ:
// ============================================================================

// Після застосування патчів, перевірте:
// 1. Що alert'и показуються коректно
// 2. Що view controllers представляються правильно
// 3. Що немає crash'ів при доступі до window hierarchy
// 4. Що працює на різних сценаріях (multi-window на iPad, Split View тощо)

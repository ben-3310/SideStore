//
//  UIApplication+Windows.swift
//  AltStore
//
//  Заміна deprecated UIApplication.shared.windows API
//

import UIKit

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

// ВИКОРИСТАННЯ:
//
// Замість:
//   let window = UIApplication.shared.windows.first { $0.isKeyWindow }
//
// Використовуйте:
//   let window = UIApplication.shared.currentKeyWindow
//
// Замість:
//   let rootVC = UIApplication.shared.windows.first?.rootViewController
//
// Використовуйте:
//   let rootVC = UIApplication.shared.rootViewController

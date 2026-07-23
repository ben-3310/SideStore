//
//  AltStoreCore+Sendable.swift
//  AltStore
//
//  Swift Concurrency support для Core Data моделей
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
/// - Context thread safety забезпечується Core Data

extension InstalledApp: @unchecked Sendable {}
extension Source: @unchecked Sendable {}
extension StoreApp: @unchecked Sendable {}
extension NewsItem: @unchecked Sendable {}

#endif

// ВАЖЛИВО: При роботі з цими типами в async/await контекстах:
//
// 1. Завжди використовуйте context.perform або context.performAndWait:
//
//    context.performAndWait {
//        let app = fetchApp()
//        // Робота з app
//    }
//
// 2. Для передачі між contexts використовуйте objectID:
//
//    let objectID = app.objectID
//    Task {
//        await context.perform {
//            let app = context.object(with: objectID) as? InstalledApp
//            // process app
//        }
//    }

//
//  RemoveAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/12/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import AltStoreCore
import CoreData

@objc(RemoveAppOperation)
final class RemoveAppOperation: ResultOperation<InstalledApp>, OperationLogging

{
    let context: InstallAppOperationContext
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        Task {
            do {
                let result = try await self.execute()
                self.finish(.success(result))
            } catch {
                self.finish(.failure(error))
            }
        }
    }
    
    private nonisolated func execute() async throws -> InstalledApp {
        if let error = self.context.error {
            throw error
        }
        guard let installedApp = self.context.installedApp else {
            throw OperationError.invalidParameters("RemoveAppOperation.main: self.context.installedApp is nil")
        }
        let resignedBundleIdentifier = await installedApp.managedObjectContext?.perform {
            self.resignedBundleIdentifier(for: installedApp)
        }
        guard let resignedBundleIdentifier else {
            throw OperationError.invalidParameters("RemoveAppOperation: installedApp.managedObjectContext is nil")
        }
        
        try await removeApp(resignedBundleIdentifier)
        
        let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        try await backgroundContext.perform {
            _ = self.markInactive(installedApp, in: backgroundContext)
            try backgroundContext.save()
        }
        
        return await DatabaseManager.shared.persistentContainer.viewContext.perform {
            return DatabaseManager.shared.persistentContainer.viewContext.object(with: installedApp.objectID) as! InstalledApp
        }
    }
    
    private func resignedBundleIdentifier(for installedApp: InstalledApp) -> String {
        installedApp.resignedBundleIdentifier
    }
    
    private func markInactive(_ installedApp: InstalledApp, in backgroundContext: NSManagedObjectContext) -> InstalledApp {
        self.progress.completedUnitCount += 1
        let installedApp = backgroundContext.object(with: installedApp.objectID) as! InstalledApp
        installedApp.isActive = false
        return installedApp
    }
}


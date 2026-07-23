//
//  RefreshAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
import AltStoreCore
@preconcurrency import AltSign

@objc(RefreshAppOperation)
final class RefreshAppOperation: ResultOperation<InstalledApp>, OperationLogging, @unchecked Sendable
{
    let context: AppOperationContext
    
    // Strong reference to managedObjectContext to keep it alive until we're finished.
    let managedObjectContext: NSManagedObjectContext
    
    init(context: AppOperationContext)
    {
        self.context = context
        self.managedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error {
            self.finish(.failure(error))
            return
        }
        
        Task {
            do {
                let installed = try await self.execute()
                self.finish(.success(installed))
            } catch {
                self.finish(.failure(error))
            }
        }
    }
    
    private nonisolated func execute() async throws -> InstalledApp {
        guard let profiles = self.context.provisioningProfiles else {
            throw OperationError.invalidParameters("RefreshAppOperation.main: self.context.provisioningProfiles is nil")
        }
        
        guard let app = self.context.app else { throw OperationError(.appNotFound(name: nil)) }
        for p in profiles {
            do {
                try await installProvisioningProfiles(p.value.data)
            } catch {
                throw MinimuxerWrapperError.profileInstall
            }
        }
        
        return try await self.managedObjectContext.perform {
            try self.updateInstalledApp(for: app, profiles: profiles)
        }
    }
    
    private func updateInstalledApp(for app: ALTApplication, profiles: [String: ALTProvisioningProfile]) throws -> InstalledApp {
        self.progress.completedUnitCount += 1
        
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), app.bundleIdentifier)
        guard let installedApp = InstalledApp.first(satisfying: predicate, in: self.managedObjectContext) else {
            throw OperationError(.appNotFound(name: app.name))
        }
        installedApp.update(provisioningProfile: profiles.values.first!)
        for installedExtension in installedApp.appExtensions {
            guard let provisioningProfile = profiles[installedExtension.bundleIdentifier] else { continue }
            installedExtension.update(provisioningProfile: provisioningProfile)
        }
        return installedApp
    }
}

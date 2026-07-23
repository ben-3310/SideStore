//
//  FetchAppIDsOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
import AltStoreCore
@preconcurrency import AltSign

@objc(FetchAppIDsOperation)
final class FetchAppIDsOperation: ResultOperation<([AppID], NSManagedObjectContext)>, @unchecked Sendable
{
    let context: AuthenticatedOperationContext
    let managedObjectContext: NSManagedObjectContext
    
    init(context: AuthenticatedOperationContext, managedObjectContext: NSManagedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext())
    {
        self.context = context
        self.managedObjectContext = managedObjectContext
        
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
    
    private nonisolated func execute() async throws -> ([AppID], NSManagedObjectContext) {
        if let error = self.context.error {
            throw error
        }
        guard
            let team = self.context.team,
            let session = self.context.session
        else {
            throw OperationError.invalidParameters("FetchAppIDsOperation.main: self.context.team or self.context.session is nil")
        }
        
        let fetchedAppIDs: [ALTAppID] = try await withCheckedThrowingContinuation { continuation in
            ALTAppleAPI.shared.fetchAppIDs(for: team, session: session) { appIDs, error in
                continuation.resume(with: Result(appIDs, error))
            }
        }
        
        return try await self.managedObjectContext.perform {
            try self.syncAppIDs(fetchedAppIDs, team: team)
        }
    }
    
    private func syncAppIDs(_ fetchedAppIDs: [ALTAppID], team: ALTTeam) throws -> ([AppID], NSManagedObjectContext) {
        guard let team = Team.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Team.identifier), team.identifier), in: self.managedObjectContext) else {
            throw OperationError.notAuthenticated
        }
        
        let fetchedIdentifiers = fetchedAppIDs.map { $0.identifier }
        
        let deletedAppIDsRequest = AppID.fetchRequest() as NSFetchRequest<AppID>
        deletedAppIDsRequest.predicate = NSPredicate(format: "%K == %@ AND NOT (%K IN %@)",
                                                     #keyPath(AppID.team), team,
                                                     #keyPath(AppID.identifier), fetchedIdentifiers)
        
        let deletedAppIDs = try self.managedObjectContext.fetch(deletedAppIDsRequest)
        deletedAppIDs.forEach { self.managedObjectContext.delete($0) }
        
        let appIDs = fetchedAppIDs.map { AppID($0, team: team, context: self.managedObjectContext) }
        return (appIDs, self.managedObjectContext)
    }
}

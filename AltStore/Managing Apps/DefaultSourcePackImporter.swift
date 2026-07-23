//
//  DefaultSourcePackImporter.swift
//  AltStore
//

import Foundation
import CoreData
import AltStoreCore

final class DefaultSourcePackImporter
{
    static let shared = DefaultSourcePackImporter()

    private static let processedVersionKey = "io.sidestore.defaultSourcePack.processedVersion"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = UserDefaults.shared)
    {
        self.userDefaults = userDefaults
    }

    func importIfNeeded() async
    {
        do
        {
            let pack = try self.loadPack()
            let processedVersion = self.userDefaults.integer(forKey: Self.processedVersionKey)
            guard processedVersion < pack.version else {
                debugLog("[DefaultSourcePackImporter] Default source pack \(pack.version) already processed.")
                return
            }

            let summary = await self.importSources(from: pack)
            self.userDefaults.set(pack.version, forKey: Self.processedVersionKey)

            debugLog("[DefaultSourcePackImporter] Processed default source pack \(pack.version): added \(summary.added), skipped \(summary.skipped), failed \(summary.failed).")
        }
        catch
        {
            debugLog("[DefaultSourcePackImporter] Failed to load bundled default sources: \(error.localizedDescription)")
        }
    }

    private func loadPack() throws -> DefaultSourcePack
    {
        guard let url = Bundle.main.url(forResource: "DefaultSources", withExtension: "json")
        else { throw URLError(.fileDoesNotExist) }

        let data = try Data(contentsOf: url)
        return try Foundation.JSONDecoder().decode(DefaultSourcePack.self, from: data)
    }

    private func importSources(from pack: DefaultSourcePack) async -> ImportSummary
    {
        var summary = ImportSummary()
        var seenSourceIDs = Set<String>()

        for sourceURL in pack.repos
        {
            do
            {
                let sourceID = try Source.sourceID(from: sourceURL)
                guard seenSourceIDs.insert(sourceID).inserted else {
                    summary.skipped += 1
                    continue
                }

                if try await self.sourceExists(sourceID: sourceID)
                {
                    summary.skipped += 1
                    continue
                }

                try await self.importSource(sourceURL: sourceURL)
                summary.added += 1
            }
            catch
            {
                summary.failed += 1
                debugLog("[DefaultSourcePackImporter] Failed to import \(sourceURL.absoluteString): \(error.localizedDescription)")
            }
        }

        return summary
    }

    private func sourceExists(sourceID: String) async throws -> Bool
    {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()

        return try await context.performAsync {
            let fetchRequest = Source.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(Source.identifier), sourceID)

            return try context.count(for: fetchRequest) > 0
        }
    }

    private func importSource(sourceURL: URL) async throws
    {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let source = try await AppManager.shared.fetchSource(sourceURL: sourceURL, managedObjectContext: context)

        try await context.performAsync {
            try context.save()
        }

        NotificationCenter.default.post(name: AppManager.didAddSourceNotification, object: source)
    }
}

private struct DefaultSourcePack: Decodable
{
    let version: Int
    let name: String
    let repos: [URL]
}

private struct ImportSummary
{
    var added = 0
    var skipped = 0
    var failed = 0
}

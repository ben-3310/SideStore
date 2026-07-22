//
//  UpdateKnownSourcesOperation.swift
//  AltStore
//
//  Created by Riley Testut on 4/13/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation
import AltStoreCore

private extension URL
{
   static let sources = URL(string: "https://sidestore.io/trusted-sources")!
}

extension UpdateKnownSourcesOperation
{
    private struct Response: Decodable
    {
        var version: Int
        
        var trusted: [KnownSource]?
        var blocked: [KnownSource]?
    }
}

class UpdateKnownSourcesOperation: ResultOperation<([KnownSource], [KnownSource])>, @unchecked Sendable
{
    private let session: URLSession
    
    override init()
    {
        let configuration = URLSessionConfiguration.default
        
        if UserDefaults.standard.responseCachingDisabled
        {
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
        }
        
        self.session = URLSession(configuration: configuration)
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
    
    private nonisolated func execute() async throws -> ([KnownSource], [KnownSource])
    {
        let (data, response) = try await self.session.data(from: .sources)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            throw URLError(.fileDoesNotExist, userInfo: [NSURLErrorKey: URL.sources])
        }
        
        let decoded = try Foundation.JSONDecoder().decode(Response.self, from: data)
        let sources = (trusted: decoded.trusted ?? [], blocked: decoded.blocked ?? [])
        
        // Cache sources
        UserDefaults.shared.recommendedSources = sources.trusted
        UserDefaults.shared.blockedSources = sources.blocked
        
        // Cache trusted source IDs.
        UserDefaults.shared.trustedSourceIDs = sources.trusted.map { $0.identifier }
        
        return sources
    }
}

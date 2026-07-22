//
//  SendAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//
import UIKit
import Foundation
import Network
import AltStoreCore

@objc(SendAppOperation)
final class SendAppOperation: ResultOperation<()>, OperationLogging, @unchecked Sendable
{
    let context: InstallAppOperationContext
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 1
    }
    
    override func main() {
        super.main()

        Task {
            do {
                try await self.execute()
                self.finish(.success(()))
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    private nonisolated func execute() async throws {
        if let error = self.context.error {
            throw error
        }

        guard let resignedApp = self.context.resignedApp else {
            throw OperationError.invalidParameters("SendAppOperation.main: self.resignedApp is nil")
        }

        let app = AnyApp(name: resignedApp.name, bundleIdentifier: self.context.bundleIdentifier, url: resignedApp.fileURL, storeApp: nil)
        let fileURL = InstalledApp.refreshedIPAURL(for: app)
        verboseLog("AFC App `fileURL`: \(fileURL.absoluteString)")

        // only when minimuxer is not ready and below 26.4 should we turn off data
        if #available(iOS 26.4, *) {
            context.shouldTurnOffData = false
        } else if await minimuxerStatus != .ready {
            context.shouldTurnOffData = true
        } else {
            context.shouldTurnOffData = false
        }
        
        if self.context.shouldTurnOffData {
            // Wait for Shortcut to Finish Before Proceeding
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                Task { @MainActor in
                    let shortcutURLoff = URL(string: "shortcuts://run-shortcut?name=TurnOffData")!
                    UIApplication.shared.open(shortcutURLoff, options: [:]) { _ in
                        self.debugLog("Shortcut finished execution. Proceeding with file transfer.")
                        continuation.resume()
                    }
                }
            }
        }
        
        try await self.processFile(at: fileURL, for: app.bundleIdentifier)
    }

    private func processFile(at fileURL: URL, for bundleIdentifier: String) async throws {
        guard let data = NSData(contentsOf: fileURL) else {
            debugLog("IPA doesn't exist????")
            throw OperationError(.appNotFound(name: bundleIdentifier))
        }
        let bytes = Data(data)
        try await yeetAppAFC(bundleIdentifier, bytes)
        self.progress.completedUnitCount += 1
    }
}

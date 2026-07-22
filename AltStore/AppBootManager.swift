//
//  AppBootManager.swift
//  ben4Store
//
//  Created by Magesh K on 9/7/26.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import Foundation
import AltStoreCore

public final class AppBootManager {
    public static let shared = AppBootManager()
    
    @MainActor public var isMinimuxerStarted = false
    @MainActor public var needsPairingPrompt = false
    @MainActor public var needsSideJITPrompt = false
    
    private init() {}
    
    public nonisolated func getSavedPairingFile() -> String? {
        let fm = FileManager.default
        let pairingFileName = "ALTPairingFile.mobiledevicepairing"
        let documentsPath = fm.documentsDirectory.appendingPathComponent(pairingFileName)
        if fm.fileExists(atPath: documentsPath.path),
           let contents = try? String(contentsOf: documentsPath), !contents.isEmpty {
            return contents
        }
        if let url = Bundle.main.url(forResource: "ALTPairingFile", withExtension: "mobiledevicepairing"),
           fm.fileExists(atPath: url.path),
           let data = fm.contents(atPath: url.path),
           let contents = String(data: data, encoding: .utf8),
           !contents.isEmpty, !UserDefaults.standard.isPairingReset { return contents }
        if let plistString = Bundle.main.object(forInfoDictionaryKey: "ALTPairingFile") as? String,
           !plistString.isEmpty, !plistString.contains("insert pairing file here"), !UserDefaults.standard.isPairingReset { return plistString }
        return nil
    }
    
    public nonisolated func startMinimuxer(pairingFile: String) async throws {
        let loggingEnabled = UserDefaults.standard.isMinimuxerConsoleLoggingEnabled
        minimuxerSetLogging(loggingEnabled)
        try await minimuxerStart(pairingFile, mountPath: FileManager.default.documentsDirectory.absoluteString)
        await MainActor.run {
            self.isMinimuxerStarted = true
        }
        
        // Validate the pairing by trying to fetch the UDID
        do {
            debugLog("[AppBootManager] startMinimuxer(): Minimuxer fetchUDID() based connection starting...")
            let deviceUDID = try await fetchUDID()
            debugLog("[AppBootManager] startMinimuxer(): Minimuxer fetchUDID() based connection test SUCCEEDED. UDID: \(deviceUDID ?? "nil")")
            await MainActor.run {
                self.needsPairingPrompt = false
            }
        } catch {
            if error.isMinimuxerPairingFile {
                debugLog("[AppBootManager] startMinimuxer(): Minimuxer fetchUDID() based connection test FAILED. \(error)")
                await MainActor.run {
                    self.isMinimuxerStarted = false
                    self.needsPairingPrompt = true
                }
                throw error
            } else {
                debugLog("[AppBootManager] startMinimuxer(): Minimuxer fetchUDID() based connection test FAILED but PAIRING FILE IS VALID. \(error)")
            }
        }
    }
    
    public nonisolated func performBootSequence() async {
        // 1. Structured concurrent child task A
        async let jitCheck: Void = {
            if #available(iOS 17, *), !UserDefaults.standard.sidejitenable {
                do {
                    try await self.isSideJITServerDetected()
                    await MainActor.run {
                        self.needsSideJITPrompt = true
                    }
                } catch {
                    debugLog("Cannot find sideJITServer")
                }
            }
            
            if #available(iOS 17, *), UserDefaults.standard.sidejitenable {
                await self.askForNetwork()
                debugLog("SideJITServer Enabled")
            }
        }()
        
        // 2. Structured concurrent child task B
        async let minimuxerCheck: Void = {
            #if targetEnvironment(simulator)
            do {
                try await self.startMinimuxer(pairingFile: "ignored-for-sim")
            } catch {
                debugLog("[AppBootManager] Failed to start minimuxer: \(error)")
            }
            #else
            if let pf = self.getSavedPairingFile() {
                do {
                    try await self.startMinimuxer(pairingFile: pf)
                } catch {
                    debugLog("[AppBootManager] Failed to start minimuxer: \(error)")
                }
            } else {
                await MainActor.run {
                    self.needsPairingPrompt = true
                }
            }
            #endif
        }()
        
        // Await both concurrently (Structured Concurrency awaits them in parallel)
        _ = await (jitCheck, minimuxerCheck)
    }
    
    private nonisolated func askForNetwork() async {
        let address = UserDefaults.standard.textInputSideJITServerurl ?? ""
        let SJSURL = address.isEmpty ? "http://sidejitserver._http._tcp.local:8080" : address
        guard let url = URL(string: "\(SJSURL)/re/") else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.0
            
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    debugLog("data: \(data), response: \(response)")
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2.0 seconds
                    throw URLError(.timedOut)
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            debugLog("error: \(error)")
        }
    }

    private nonisolated func isSideJITServerDetected() async throws {
        let address = UserDefaults.standard.textInputSideJITServerurl ?? ""
        let SJSURL = address.isEmpty ? "http://sidejitserver._http._tcp.local:8080" : address
        guard let url = URL(string: SJSURL) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try await URLSession.shared.data(for: request)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2.0 seconds
                throw URLError(.timedOut)
            }
            try await group.next()
            group.cancelAll()
        }
    }
}

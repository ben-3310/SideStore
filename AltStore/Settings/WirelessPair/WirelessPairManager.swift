//
//  WirelessPairManager.swift
//  AltStore
//
//  Created by Magesh K on 04/07/26.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import Foundation
import SwiftUI

@MainActor
final class WirelessPairManager: ObservableObject {
    static let shared = WirelessPairManager()
    
    @Published var statusText = "Ready to pair"
    @Published var subStatusText = "Tap Start to advertise this device on the local network."
    @Published var pinCode: String? = nil
    @Published var isAdvertising = false
    @Published var pairedDevice: MinimuxerPairedDevice? = nil
    @Published var errorMessage: String? = nil
    @Published var serviceID: String? = nil
    @Published var port: Int? = nil
    
    private let pairing = wirelessPairing
    private var startTask: Task<Void, Never>? = nil
    
    private init() {
        // Setup closures once
        pairing.onReadyToPair = { [weak self] (serviceID: String, port: Int) in
            Task { @MainActor in
                guard let self = self else { return }
                self.serviceID = serviceID
                self.port = port
                self.statusText = "Advertising server..."
                self.subStatusText = "Ensure both devices are on the same Wi-Fi."
            }
        }
        
        pairing.onPinReceived = { [weak self] (pin: String) in
            Task { @MainActor in
                guard let self = self else { return }
                self.pinCode = pin
                self.statusText = "Device Connected"
                self.subStatusText = "Enter the pairing code shown below on your other device settings screen."
            }
        }
    }
    
    func togglePairing() {
        if isAdvertising {
            stopPairing()
        } else {
            startPairing()
        }
    }
    
    func startPairing() {
        startTask?.cancel()
        
        isAdvertising = true
        pinCode = nil
        errorMessage = nil
        serviceID = nil
        port = nil
        
        // Debounce the "Waiting..." status text by 200ms
        let debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            guard !Task.isCancelled else { return }
            guard isAdvertising && serviceID == nil else { return }
            statusText = "Waiting for connection..."
            subStatusText = "Open Remote Pairing on your Apple TV / Vision Pro / host device to discover this server."
        }
        startTask = debounceTask
        
        let pairingFile = pairingFilePath()
        
        pairing.start(outPath: pairingFile) { [weak self] (result: Result<MinimuxerPairedDevice, Swift.Error>) in
            Task { @MainActor in
                guard let self = self else { return }
                debounceTask.cancel()
                guard self.isAdvertising else { return }
                self.isAdvertising = false
                self.pinCode = nil
                self.serviceID = nil
                self.port = nil
                
                switch result {
                case .success(let device):
                    self.pairedDevice = device
                    self.statusText = "Success!"
                    self.subStatusText = "Successfully paired with \(device.name) (\(device.model))!\nPairing file saved to documents."
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.statusText = "Pairing Failed"
                    self.subStatusText = "An error occurred during pairing."
                }
            }
        }
    }
    
    func stopPairing() {
        pairing.stop()
        startTask?.cancel()
        startTask = nil
        
        isAdvertising = false
        statusText = "Ready to pair"
        subStatusText = "Tap Start to advertise this device on the local network."
        pinCode = nil
        errorMessage = nil
        serviceID = nil
        port = nil
    }
    
    private func pairingFilePath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("rp_pairing_file.plist").path
    }
}

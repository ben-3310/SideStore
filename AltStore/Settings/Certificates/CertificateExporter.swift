//
//  CertificateExporter.swift
//  AltStore
//
//  Created by Magesh K on 2026-07-03.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import UIKit
import AltSign

enum CertificateExporter {
    
    static func sharePublicCertAsDER(_ cert: ALTCertificate, onError: @escaping (String) -> Void) {
        guard let data = cert.data else { onError("Public certificate data is missing."); return }
        share(data: getDERData(from: data) ?? data, filename: (cert.machineName ?? cert.name) + ".der", onError: onError)
    }
    
    static func sharePublicCertAsPEM(_ cert: ALTCertificate, onError: @escaping (String) -> Void) {
        guard let data = cert.data else { onError("Public certificate data is missing."); return }
        share(data: data, filename: (cert.machineName ?? cert.name) + ".pem", onError: onError)
    }
    
    static func copyPublicCertAsPEM(_ cert: ALTCertificate, onError: @escaping (String) -> Void) {
        guard let data = cert.data else { onError("Public certificate data is missing."); return }
        UIPasteboard.general.string = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
    }
    
    static func shareP12(_ cert: ALTCertificate, password: String, onError: @escaping (String) -> Void) {
        guard let p12Data = cert.encryptedP12Data(password: password) else { onError("Failed to build encrypted p12 data."); return }
        share(data: p12Data, filename: (cert.machineName ?? cert.name) + ".p12", onError: onError)
    }
    
    static func sharePrivateKeyAsPEM(_ cert: ALTCertificate, onError: @escaping (String) -> Void) {
        guard let keyData = cert.privateKey else { onError("Private key is missing."); return }
        share(data: keyData, filename: (cert.machineName ?? cert.name) + "_key.pem", onError: onError)
    }
    
    static func sharePrivateKeyAsDER(_ cert: ALTCertificate, onError: @escaping (String) -> Void) {
        guard let keyData = cert.privateKey else { onError("Private key is missing."); return }
        share(data: getDERData(from: keyData) ?? keyData, filename: (cert.machineName ?? cert.name) + "_key.der", onError: onError)
    }
    
    static func copyPrivateKey(_ cert: ALTCertificate) {
        guard let keyData = cert.privateKey else { return }
        UIPasteboard.general.string = String(data: keyData, encoding: .utf8) ?? keyData.base64EncodedString()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    private static func share(data: Data, filename: String, onError: @escaping (String) -> Void) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL)
        } catch {
            onError("Failed to write temp export file: " + error.localizedDescription)
            return
        }
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        guard let windowScene = UIApplication.shared.connectedScenes
                .filter({ $0.activationState == .foregroundActive })
                .compactMap({ $0 as? UIWindowScene })
                .first,
              let rootVC = windowScene.keyWindow?.rootViewController else { return }
        let presenter = rootVC.presentedViewController ?? rootVC
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(activityVC, animated: true)
    }
}

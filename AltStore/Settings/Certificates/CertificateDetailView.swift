//
//  CertificateDetailView.swift
//  AltStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import SwiftUI
import AltSign

struct DeveloperPortalMetadata {
    var identifier: String?
    var machineName: String?
    var machineIdentifier: String?
    var requesterEmail: String?
}

struct CertificateDetailView: View {
    let certificate: ALTCertificate
    let portalMetadata: DeveloperPortalMetadata?
    
    init(certificate: ALTCertificate, portalMetadata: DeveloperPortalMetadata? = nil) {
        self.certificate = certificate
        self.portalMetadata = portalMetadata
    }
    
    @State private var isRedacted = true
    
    @State private var showPrivateKey = false
    @State private var copiedPrivateKey = false
    @State private var copiedPEM = false
    @State private var copiedSerialNumber = false
    @State private var copiedIdentifier = false
    @State private var copiedFingerprintSHA1 = false
    @State private var copiedFingerprintSHA256 = false
    
    var body: some View {
        let briefInfo = getBriefInfo(for: certificate.data)
        Form {
            Section {
                detailRow(title: "Common Name", value: redactableValue(certificate.name))
                if let machineName = portalMetadata?.machineName {
                    detailRow(title: "Machine Name", value: redactableValue(machineName))
                }
                detailRow(title: "Type", value: briefInfo?.type ?? "Developer Certificate")
                detailRow(title: "Valid From", value: briefInfo?.validFrom ?? "N/A")
                detailRow(title: "Valid Until", value: briefInfo?.validUntil ?? "N/A")
                detailRowWithCopy(title: "Serial Number", value: certificate.serialNumber, isCopied: $copiedSerialNumber)
            } header: {
                Text("Basic Information")
            }
            
            if let metadata = portalMetadata {
                Section {
                    if let identifier = metadata.identifier {
                        detailRowWithCopy(title: "Certificate ID", value: identifier, isCopied: $copiedIdentifier)
                    }
                    if let machineID = metadata.machineIdentifier {
                        detailRow(title: "Machine ID", value: machineID)
                    }
                    if let email = metadata.requesterEmail {
                        detailRow(title: "Requester Email", value: redactableValue(email))
                    }
                } header: {
                    Text("Developer Portal Info")
                }
            }
            
            if let certData = certificate.data {
                let details = parseCertificate(derData: certData)
                Section {
                    detailRow(title: "Version", value: details.version)
                    detailRow(title: "Subject", value: redactableValue(details.subject))
                    detailRow(title: "Issuer", value: details.issuer)
                    detailRow(title: "Serial Number (hex)", value: details.serialHex)
                    detailRow(title: "Serial Number (dec)", value: details.serialDec)
                } header: {
                    Text("X.509 Fields")
                }
                
                if let from = details.validFrom, let until = details.validUntil {
                    let stats = computeValidityStats(from: from, until: until)
                    Section {
                        detailRow(title: "Valid From", value: formatDate(from))
                        detailRow(title: "Valid Until", value: formatDate(until))
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Validity Progress")
                                Spacer()
                                Text(String(format: "%.0f%%", stats.progress * 100))
                                    .foregroundColor(.secondary)
                            }
                            ProgressView(value: stats.progress)
                                .tint(.accentColor)
                        }
                        
                        detailRow(title: "Validity Days", value: "Total: \(stats.totalDays), Elapsed: \(stats.elapsedDays), Remaining: \(stats.remainingDays)")
                    } header: {
                        Text("Validity Period")
                    }
                }
                
                Section {
                    detailRow(title: "Public Key", value: details.publicKeyType)
                    detailRow(title: "Signature Algorithm", value: details.signatureAlgorithm)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("SHA-1 Fingerprint")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            
                            SwiftUI.Button {
                                UIPasteboard.general.string = details.fingerprintSHA1
                                copiedFingerprintSHA1 = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedFingerprintSHA1 = false
                                }
                            } label: {
                                Image(systemName: copiedFingerprintSHA1 ? "checkmark" : "doc.on.doc")
                                    .font(.footnote)
                                    .foregroundColor(copiedFingerprintSHA1 ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(details.fingerprintSHA1)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("SHA-256 Fingerprint")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            
                            SwiftUI.Button {
                                UIPasteboard.general.string = details.fingerprintSHA256
                                copiedFingerprintSHA256 = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedFingerprintSHA256 = false
                                }
                            } label: {
                                Image(systemName: copiedFingerprintSHA256 ? "checkmark" : "doc.on.doc")
                                    .font(.footnote)
                                    .foregroundColor(copiedFingerprintSHA256 ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(details.fingerprintSHA256)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Signature & Public Key Details")
                }
            }
            
            Section {
                detailRow(title: "Has Private Key", value: certificate.privateKey != nil ? "Yes" : "No")
                
                if let privateKey = certificate.privateKey {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Private Key Data")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            
                            SwiftUI.Button {
                                showPrivateKey.toggle()
                            } label: {
                                Image(systemName: showPrivateKey ? "eye.slash" : "eye")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            
                            SwiftUI.Button {
                                UIPasteboard.general.string = privateKey.base64EncodedString()
                                copiedPrivateKey = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedPrivateKey = false
                                }
                            } label: {
                                Image(systemName: copiedPrivateKey ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedPrivateKey ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 12)
                        }
                        
                        if showPrivateKey {
                            Text(privateKey.base64EncodedString())
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                        } else {
                            Text("••••••••••••••••••••••••••••")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                if let certData = certificate.data {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Certificate PEM Data")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            
                            SwiftUI.Button {
                                let pem = String(data: certData, encoding: .utf8) ?? certData.base64EncodedString()
                                UIPasteboard.general.string = pem
                                copiedPEM = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedPEM = false
                                }
                            } label: {
                                Image(systemName: copiedPEM ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedPEM ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(String(data: certData, encoding: .utf8) ?? certData.base64EncodedString())
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Cryptographic Keys")
            }
        }
        .navigationTitle("Certificate Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    isRedacted.toggle()
                } label: {
                    Image(systemName: isRedacted ? "eye.slash" : "eye")
                }
            }
        }
    }
    
    private func redactableValue(_ value: String, sensitive: Bool = true) -> String {
        if sensitive && isRedacted {
            return "••••••••"
        }
        return value
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
    
    private func detailRowWithCopy(title: String, value: String, isCopied: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
            
            if value != "N/A" && !value.isEmpty && value != "••••••••" {
                SwiftUI.Button {
                    UIPasteboard.general.string = value
                    isCopied.wrappedValue = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCopied.wrappedValue = false
                    }
                } label: {
                    Image(systemName: isCopied.wrappedValue ? "checkmark" : "doc.on.doc")
                        .font(.footnote)
                        .foregroundColor(isCopied.wrappedValue ? .green : .accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
        }
    }
}

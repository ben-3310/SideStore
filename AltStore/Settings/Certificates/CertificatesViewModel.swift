//
//  CertificatesViewModel.swift
//  AltStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import SwiftUI
import AltSign
import KeychainAccess
import AltStoreCore

struct PendingImport {
    let url: URL
    let filename: String
}

enum PrivateKeyImportError: LocalizedError {
    case isCertificate
    case invalidKey
    case conversionFailed
    
    var errorDescription: String? {
        switch self {
        case .isCertificate:    return "The selected file is a certificate, not a private key."
        case .invalidKey:       return "The input does not contain a valid private key."
        case .conversionFailed: return "Failed to convert binary private key to PEM format."
        }
    }
}

class CertificatesViewModel: ObservableObject {
    @Published var certificates: [ALTCertificate] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil {
        didSet { showErrorAlert = errorMessage != nil }
    }
    @Published var showErrorAlert = false
    @Published var activeSerialNumber: String? = nil
    @Published var alertMessage: String? = nil
    @Published var showAlert = false
    @Published var remoteSerials: Set<String> = []
    
    @Published var currentSort: SortOption   = .creationDate
    @Published var isAscending: Bool         = false
    @Published var currentGroup: GroupOption = .none
    
    @Published var isGlobalHideActive = false {
        didSet { revealedSerials.removeAll() }
    }
    @Published var isSectionHideActive = false {
        didSet { revealedSerials.removeAll() }
    }
    @Published var revealedSerials: Set<String> = []
    
    @Published var pendingImports: [PendingImport] = []
    @Published var currentImportIndex = 0
    @Published var showPasswordPromptForImport = false
    @Published var importPasswordInput = ""
    @Published var importSuccessCount = 0
    @Published var importFailedCount = 0
    @Published var showImportSummary = false
    @Published var showFailuresAlert = false
    @Published var failedImportsList: [String] = []
    
    var importSummaryMessage: String {
        "Certificate import completed.\nSuccess: \(importSuccessCount)\nFailed: \(importFailedCount)"
    }
    
    var failuresAlertMessage: String {
        failedImportsList.joined(separator: "\n")
    }
    
    var currentImportFilename: String {
        guard currentImportIndex < pendingImports.count else { return "" }
        return pendingImports[currentImportIndex].filename
    }
    
    var lastUsedPassword = ""
    var importedSerialsThisBatch = [String: (hasPrivateKey: Bool, filename: String)]()
    var session: ALTAppleAPISession?
    var team: ALTTeam?
    
    var isPaidAccount: Bool {
        guard let team = self.team else { return false }
        return team.type != .free && team.type != .unknown
    }
    
    private let certificateKeychain = KeychainAccess.Keychain(service: Bundle.Info.appbundleIdentifier)
        .accessibility(.afterFirstUnlock)
    
    func fetchActiveSerialNumber() {
        if let data = Keychain.shared.signingCertificate {
            let cert = (try? ALTCertificate(p12Data: data, password: ""))
                    ?? (try? ALTCertificate(p12Data: data, password: nil))
            if let cert = cert { self.activeSerialNumber = cert.serialNumber; return }
        }
        self.activeSerialNumber = nil
    }
    
    private var activeLocalCert: ALTCertificate? {
        guard let data = Keychain.shared.signingCertificate else { return nil }
        let cert = (try? ALTCertificate(p12Data: data, password: ""))
                ?? (try? ALTCertificate(p12Data: data, password: nil))
        if let cert = cert {
            if let metadata = UserDefaults.standard.dictionary(forKey: "certMetadata_" + cert.serialNumber) as? [String: String] {
                cert.machineName        = metadata["machineName"]
                cert.identifier         = metadata["identifier"]
                cert.requesterEmail     = metadata["requesterEmail"]
                cert.machineIdentifier  = metadata["machineIdentifier"]
            }
            return cert
        }
        return nil
    }
    
    func loadLocalCertificates() -> [ALTCertificate] {
        var localCerts: [ALTCertificate] = []
        let serials = UserDefaults.standard.stringArray(forKey: "importedCertificateSerials") ?? []
        debugLog("[ben4Store] loadLocalCertificates, serials: \(serials)")
        for serial in serials {
            do {
                if let data = try self.certificateKeychain.getData("importedCert_" + serial) {
                    debugLog("[ben4Store]   Retrieved data size: \(data.count) for \(serial)")
                    var loadedCert: ALTCertificate?
                    do {
                        loadedCert = try ALTCertificate(p12Data: data, password: "")
                        debugLog("[ben4Store]   Parsed as p12 empty pass")
                    } catch {
                        debugLog("[ben4Store]   Failed p12 empty pass: \(error)")
                        do {
                            loadedCert = try ALTCertificate(p12Data: data, password: nil)
                            debugLog("[ben4Store]   Parsed as p12 nil pass")
                        } catch {
                            debugLog("[ben4Store]   Failed p12 nil pass: \(error)")
                            if let cert = ALTCertificate(data: data) {
                                loadedCert = cert
                                debugLog("[ben4Store]   Parsed as raw cert")
                            } else {
                                debugLog("[ben4Store]   Failed raw cert parsing")
                            }
                        }
                    }
                    if let cert = loadedCert {
                        if let metadata = UserDefaults.standard.dictionary(forKey: "certMetadata_" + cert.serialNumber) as? [String: String] {
                            cert.machineName        = metadata["machineName"]
                            cert.identifier         = metadata["identifier"]
                            cert.requesterEmail     = metadata["requesterEmail"]
                            cert.machineIdentifier  = metadata["machineIdentifier"]
                        }
                        localCerts.append(cert)
                    }
                } else {
                    debugLog("[ben4Store]   No data found in keychain for importedCert_\(serial)")
                }
            } catch {
                debugLog("[ben4Store]   Keychain error for importedCert_\(serial): \(error)")
            }
        }
        return localCerts
    }
    
    func saveLocalCertificate(_ cert: ALTCertificate) {
        debugLog("[ben4Store] saveLocalCertificate serial: \(cert.serialNumber)")
        if cert.privateKey != nil, let p12Data = cert.p12Data() {
            debugLog("[ben4Store]   p12Data generated, size: \(p12Data.count)")
            do {
                try self.certificateKeychain.set(p12Data, key: "importedCert_" + cert.serialNumber)
                debugLog("[ben4Store]   Successfully saved p12 to keychain")
            } catch {
                debugLog("[ben4Store]   Failed to save p12 to keychain: \(error)")
            }
        } else if let derData = cert.data {
            debugLog("[ben4Store]   derData exists, size: \(derData.count)")
            do {
                try self.certificateKeychain.set(derData, key: "importedCert_" + cert.serialNumber)
                debugLog("[ben4Store]   Successfully saved derData to keychain")
            } catch {
                debugLog("[ben4Store]   Failed to save derData to keychain: \(error)")
            }
        } else {
            debugLog("[ben4Store]   No data available to save")
            return
        }
        var serials = UserDefaults.standard.stringArray(forKey: "importedCertificateSerials") ?? []
        if !serials.contains(cert.serialNumber) {
            serials.append(cert.serialNumber)
            UserDefaults.standard.set(serials, forKey: "importedCertificateSerials")
        }
        var metadataDict: [String: String] = [:]
        if let v = cert.machineName       { metadataDict["machineName"]       = v }
        if let v = cert.identifier        { metadataDict["identifier"]        = v }
        if let v = cert.requesterEmail    { metadataDict["requesterEmail"]    = v }
        if let v = cert.machineIdentifier { metadataDict["machineIdentifier"] = v }
        UserDefaults.standard.set(metadataDict, forKey: "certMetadata_" + cert.serialNumber)
    }
    
    func deleteLocalCertificate(serialNumber: String) {
        try? self.certificateKeychain.remove("importedCert_" + serialNumber)
        var serials = UserDefaults.standard.stringArray(forKey: "importedCertificateSerials") ?? []
        serials.removeAll { $0 == serialNumber }
        UserDefaults.standard.set(serials, forKey: "importedCertificateSerials")
    }
    
    func loadCertificates(presentingViewController: UIViewController?, isPullToRefresh: Bool = false, completion: (() -> Void)? = nil) {
        if !isPullToRefresh { self.isLoading = true }
        self.errorMessage = nil
        self.fetchActiveSerialNumber()
        
        let localCerts = self.loadLocalCertificates()
        let activeCert = self.activeLocalCert
        
        var mergedLocal = localCerts
        if let active = activeCert, !mergedLocal.contains(where: { $0.serialNumber == active.serialNumber }) {
            mergedLocal.append(active)
        }
        self.certificates = mergedLocal
        
        Task { @MainActor in
            defer { self.isLoading = false; completion?() }
            let hasPassword = Keychain.shared.appleIDPassword != nil
            let hasToken    = Keychain.shared.appleIDXcodeToken != nil
            guard Keychain.shared.appleIDEmailAddress != nil && (hasPassword || hasToken) else {
                if isPullToRefresh { self.errorMessage = OperationError.notAuthenticated.localizedDescription }
                return
            }
            do {
                let (team, session) = try await DeveloperPortalService.shared.authenticate(presentingViewController: presentingViewController)
                self.team    = team
                self.session = session
                
                let remoteCerts = try await DeveloperPortalService.shared.fetchCertificates(team: team, session: session)
                var merged = [ALTCertificate]()
                var matchedRemoteSerials = Set<String>()
                
                for remoteCert in remoteCerts {
                    var resolvedPrivateKey: Data?
                    if let active = activeCert, active.serialNumber == remoteCert.serialNumber, active.privateKey != nil {
                        resolvedPrivateKey = active.privateKey
                    } else if let localCopy = localCerts.first(where: { $0.serialNumber == remoteCert.serialNumber && $0.privateKey != nil }) {
                        resolvedPrivateKey = localCopy.privateKey
                    }
                    remoteCert.privateKey = resolvedPrivateKey
                    self.saveLocalCertificate(remoteCert)
                    merged.append(remoteCert)
                    matchedRemoteSerials.insert(remoteCert.serialNumber)
                }
                for localCert in localCerts where !matchedRemoteSerials.contains(localCert.serialNumber) {
                    merged.append(localCert)
                }
                if let active = activeCert, !matchedRemoteSerials.contains(active.serialNumber),
                   !localCerts.contains(where: { $0.serialNumber == active.serialNumber }) {
                    merged.append(active)
                }
                self.certificates  = merged
                self.remoteSerials = matchedRemoteSerials
            } catch {
                if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            }
        }
    }
    
    func startBulkImport(urls: [URL]) {
        self.pendingImports     = urls.map { PendingImport(url: $0, filename: $0.lastPathComponent) }
        self.currentImportIndex = 0
        self.importSuccessCount = 0
        self.importFailedCount  = 0
        self.failedImportsList  = []
        self.importedSerialsThisBatch = [:]
        processNextImport()
    }
    
    func processNextImport() {
        guard currentImportIndex < pendingImports.count else {
            self.pendingImports = []
            self.loadCertificates(presentingViewController: nil)
            showImportSummaryAlert()
            return
        }
        
        let pending = pendingImports[currentImportIndex]
        _ = pending.url.startAccessingSecurityScopedResource()
        defer { pending.url.stopAccessingSecurityScopedResource() }
        
        guard let certData = try? Data(contentsOf: pending.url) else {
            failedImportsList.append("\(pending.filename): Read error.")
            importFailedCount += 1
            currentImportIndex += 1
            processNextImport()
            return
        }
        
        if let rawCert = ALTCertificate(data: certData) {
            if isDuplicate(cert: rawCert, importedSerials: importedSerialsThisBatch) {
                failedImportsList.append("\(pending.filename): Duplicate certificate (already imported).")
                importFailedCount += 1
            } else {
                saveLocalCertificate(rawCert)
                recordSuccessfulImport(serial: rawCert.serialNumber, hasPrivateKey: rawCert.privateKey != nil, filename: pending.filename)
            }
            currentImportIndex += 1
            processNextImport()
            return
        }
        
        if certData.isPKCS12 {
            if !lastUsedPassword.isEmpty {
                do {
                    let altCert = try ALTCertificate(p12Data: certData, password: lastUsedPassword)
                    if isDuplicate(cert: altCert, importedSerials: importedSerialsThisBatch) {
                        failedImportsList.append("\(pending.filename): Duplicate certificate (already imported).")
                        importFailedCount += 1
                    } else {
                        saveLocalCertificate(altCert)
                        recordSuccessfulImport(serial: altCert.serialNumber, hasPrivateKey: altCert.privateKey != nil, filename: pending.filename)
                    }
                    currentImportIndex += 1
                    processNextImport()
                    return
                } catch ALTCertificateError.decryptionFailed {
                } catch {
                    failedImportsList.append("\(pending.filename): \(error.localizedDescription)")
                    importFailedCount += 1
                    currentImportIndex += 1
                    processNextImport()
                    return
                }
            }
            
            do {
                let altCert = try ALTCertificate(p12Data: certData, password: "")
                if isDuplicate(cert: altCert, importedSerials: importedSerialsThisBatch) {
                    failedImportsList.append("\(pending.filename): Duplicate certificate (already imported).")
                    importFailedCount += 1
                } else {
                    saveLocalCertificate(altCert)
                    recordSuccessfulImport(serial: altCert.serialNumber, hasPrivateKey: altCert.privateKey != nil, filename: pending.filename)
                }
                currentImportIndex += 1
                processNextImport()
                return
            } catch ALTCertificateError.decryptionFailed {
                DispatchQueue.main.async {
                    self.importPasswordInput         = ""
                    self.showPasswordPromptForImport = true
                }
                return
            } catch {
                failedImportsList.append("\(pending.filename): \(error.localizedDescription)")
                importFailedCount += 1
                currentImportIndex += 1
                processNextImport()
                return
            }
        } else {
            failedImportsList.append("\(pending.filename): Not a valid certificate format.")
            importFailedCount += 1
            currentImportIndex += 1
            processNextImport()
            return
        }
    }
    
    func submitImportPassword() {
        let pending = pendingImports[currentImportIndex]
        _ = pending.url.startAccessingSecurityScopedResource()
        defer { pending.url.stopAccessingSecurityScopedResource() }
        
        guard let certData = try? Data(contentsOf: pending.url) else {
            self.showPasswordPromptForImport = false
            failedImportsList.append("\(pending.filename): Read error.")
            importFailedCount += 1
            currentImportIndex += 1
            processNextImport()
            return
        }
        
        do {
            let altCert = try ALTCertificate(p12Data: certData, password: importPasswordInput)
            if isDuplicate(cert: altCert, importedSerials: importedSerialsThisBatch) {
                failedImportsList.append("\(pending.filename): Duplicate certificate (already imported).")
                importFailedCount += 1
            } else {
                saveLocalCertificate(altCert)
                recordSuccessfulImport(serial: altCert.serialNumber, hasPrivateKey: altCert.privateKey != nil, filename: pending.filename)
            }
            self.lastUsedPassword = importPasswordInput
            self.showPasswordPromptForImport = false
            currentImportIndex += 1
            processNextImport()
        } catch ALTCertificateError.decryptionFailed {
            self.errorMessage = "Incorrect password for " + pending.filename
        } catch {
            self.showPasswordPromptForImport = false
            failedImportsList.append("\(pending.filename): \(error.localizedDescription)")
            importFailedCount += 1
            currentImportIndex += 1
            processNextImport()
        }
    }
    
    func cancelImport() {
        self.showPasswordPromptForImport = false
        let pending = pendingImports[currentImportIndex]
        failedImportsList.append("\(pending.filename): Password required but skipped.")
        importFailedCount += 1
        currentImportIndex += 1
        processNextImport()
    }
    
    private func showImportSummaryAlert() {
        self.showImportSummary = true
    }
    
    func createCertificate(machineName: String, presentingViewController: UIViewController?) {
        guard let team = self.team, let session = self.session else { self.errorMessage = "Not authenticated"; return }
        self.isLoading = true; self.errorMessage = nil
        Task { @MainActor in
            defer { self.isLoading = false }
            do {
                let newCert = try await DeveloperPortalService.shared.createCertificate(machineName: machineName, team: team, session: session)
                guard let privateKey = newCert.privateKey else { self.errorMessage = "Missing private key from newly created certificate."; return }
                let remoteCerts = try await DeveloperPortalService.shared.fetchCertificates(team: team, session: session)
                if let certificate = remoteCerts.first(where: { $0.serialNumber == newCert.serialNumber }) {
                    certificate.privateKey = privateKey
                    self.saveLocalCertificate(certificate)
                    self.alertMessage = "Certificate created successfully."
                    self.showAlert    = true
                    self.loadCertificates(presentingViewController: nil)
                }
            } catch {
                if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            }
        }
    }
    
    func revokeCertificate(_ certificate: ALTCertificate) {
        guard let team = self.team, let session = self.session else { self.errorMessage = "Not authenticated"; return }
        self.isLoading = true; self.errorMessage = nil
        Task { @MainActor in
            defer { self.isLoading = false }
            do {
                let success = try await DeveloperPortalService.shared.revokeCertificate(certificate, team: team, session: session)
                if success {
                    self.deleteLocalCertificate(serialNumber: certificate.serialNumber)
                    self.certificates.removeAll { $0.serialNumber == certificate.serialNumber }
                    if self.activeSerialNumber == certificate.serialNumber {
                        Keychain.shared.signingCertificate         = nil
                        Keychain.shared.signingCertificatePassword = nil
                        self.activeSerialNumber = nil
                    }
                    self.alertMessage = "Certificate revoked successfully."
                    self.showAlert    = true
                } else {
                    self.errorMessage = "Failed to revoke certificate."
                }
            } catch {
                if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            }
        }
    }
    
    func deleteCertificate(_ certificate: ALTCertificate) {
        deleteLocalCertificate(serialNumber: certificate.serialNumber)
        self.certificates.removeAll { $0.serialNumber == certificate.serialNumber }
        if self.activeSerialNumber == certificate.serialNumber {
            Keychain.shared.signingCertificate         = nil
            Keychain.shared.signingCertificatePassword = nil
            self.activeSerialNumber = nil
        }
        self.alertMessage = "Certificate deleted locally."
        self.showAlert    = true
    }
    
    func makeCertificateActive(_ certificate: ALTCertificate) {
        guard certificate.privateKey != nil else { self.errorMessage = "Cannot activate certificate: private key missing."; return }
        Keychain.shared.signingCertificate         = certificate.p12Data()
        Keychain.shared.signingCertificatePassword = certificate.machineIdentifier ?? ""
        self.fetchActiveSerialNumber()
        self.alertMessage = "Active signing certificate replaced successfully."
        self.showAlert    = true
    }
    
    func deactivateActiveCertificate() {
        Keychain.shared.signingCertificate         = nil
        Keychain.shared.signingCertificatePassword = nil
        self.activeSerialNumber = nil
        self.alertMessage = "Local certificate deactivated."
        self.showAlert    = true
    }
    
    func isCertificateLocallyCached(_ certificate: ALTCertificate) -> Bool {
        let serials = UserDefaults.standard.stringArray(forKey: "importedCertificateSerials") ?? []
        return serials.contains(certificate.serialNumber) || certificate.serialNumber == self.activeSerialNumber
    }
    
    func sortCertificates(_ certs: [ALTCertificate]) -> [ALTCertificate] {
        switch currentSort {
        case .creationDate: return certs.sorted { isAscending ? $0.creationDate < $1.creationDate : $0.creationDate > $1.creationDate }
        case .expiryDate:   return certs.sorted { isAscending ? $0.expiryDate < $1.expiryDate : $0.expiryDate > $1.expiryDate }
        case .name:
            return certs.sorted {
                let cmp = ($0.machineName ?? $0.name).localizedCaseInsensitiveCompare($1.machineName ?? $1.name)
                return isAscending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        case .keys:
            return certs.sorted {
                let v0 = $0.privateKey != nil ? 1 : 0
                let v1 = $1.privateKey != nil ? 1 : 0
                return isAscending ? v0 < v1 : v0 > v1
            }
        }
    }
    
    var groupedCertificatesList: [GroupedCertificates] {
        let sorted = sortCertificates(certificates)
        switch currentGroup {
        case .none:
            return [GroupedCertificates(name: "Certificates", certificates: sorted)]
        case .keys:
            let withKeys    = sorted.filter { $0.privateKey != nil }
            let withoutKeys = sorted.filter { $0.privateKey == nil }
            var groups = [GroupedCertificates]()
            if !withKeys.isEmpty    { groups.append(GroupedCertificates(name: "Public + Private Keys", certificates: withKeys)) }
            if !withoutKeys.isEmpty { groups.append(GroupedCertificates(name: "Public Keys Only",      certificates: withoutKeys)) }
            return groups
        case .name:
            let grouped = Dictionary(grouping: sorted) { cert -> String in
                return cert.machineName.flatMap { $0.first.map { String($0).uppercased() } }
                    ?? cert.name.first.map { String($0).uppercased() }
                    ?? "#"
            }
            return grouped.keys.sorted().map { GroupedCertificates(name: $0, certificates: grouped[$0] ?? []) }
        case .creationDate:
            let grouped = Dictionary(grouping: sorted) { cert -> String in
                let year = Calendar.current.component(.year, from: cert.creationDate)
                return year > 1970 ? "Created in \(year)" : "Created (Unknown Date)"
            }
            return grouped.keys.sorted(by: >).map { GroupedCertificates(name: $0, certificates: grouped[$0] ?? []) }
        case .expiryDate:
            let grouped = Dictionary(grouping: sorted) { cert -> String in
                let year = Calendar.current.component(.year, from: cert.expiryDate)
                return year > 1970 ? "Expires in \(year)" : "Expires (Unknown Date)"
            }
            return grouped.keys.sorted(by: <).map { GroupedCertificates(name: $0, certificates: grouped[$0] ?? []) }
        }
    }
    
    func maskPartially(_ string: String) -> String {
        guard string.count > 8 else { return "••••••••" }
        return "\(string.prefix(4))••••••••\(string.suffix(4))"
    }
    
    func displayActiveSerial(_ activeSerial: String) -> String {
        if isActiveSerialMasked(activeSerial) {
            if isGlobalHideActive { return "••••••••••••••••" }
            return maskPartially(activeSerial)
        }
        return activeSerial
    }
    
    func isSerialMasked(for cert: ALTCertificate, hasPrivateKey: Bool) -> Bool {
        let isRevealed      = revealedSerials.contains(cert.serialNumber)
        let isSectionHidden = isSectionHideActive
        if isGlobalHideActive || isSectionHidden {
            return !isRevealed
        } else {
            return isRevealed
        }
    }
    
    func isActiveSerialMasked(_ activeSerial: String) -> Bool {
        let isRevealed = revealedSerials.contains("active_" + activeSerial)
        if isGlobalHideActive || isSectionHideActive {
            return !isRevealed
        } else {
            return isRevealed
        }
    }
    
    func displaySerial(for cert: ALTCertificate, hasPrivateKey: Bool) -> String {
        if isSerialMasked(for: cert, hasPrivateKey: hasPrivateKey) {
            if isGlobalHideActive { return "••••••••••••••••" }
            return maskPartially(cert.serialNumber)
        }
        return cert.serialNumber
    }
    
    func displayIdentifier(for cert: ALTCertificate, hasPrivateKey: Bool) -> String? {
        guard let ident = cert.identifier else { return nil }
        if isSerialMasked(for: cert, hasPrivateKey: hasPrivateKey) { return "••••••••••" }
        return ident
    }
    
    func displayRequester(for cert: ALTCertificate, hasPrivateKey: Bool) -> String? {
        guard let req = cert.requesterEmail, !req.isEmpty else { return nil }
        if isSerialMasked(for: cert, hasPrivateKey: hasPrivateKey) { return "••••••••••" }
        return req
    }
    
    func displayBriefType(for brief: CertificateBriefInfo, cert: ALTCertificate) -> String {
        if isSerialMasked(for: cert, hasPrivateKey: cert.privateKey != nil) { return "••••••••••" }
        return brief.type
    }
    
    func displayBriefValidity(for brief: CertificateBriefInfo, cert: ALTCertificate) -> String {
        if isSerialMasked(for: cert, hasPrivateKey: cert.privateKey != nil) { return "••••••••••" }
        return "\(brief.validFrom) - \(brief.validUntil)"
    }
    
    private func derToPEM(derData: Data) -> Data? {
        let base64    = derData.base64EncodedString(options: [.lineLength64Characters])
        let pemString = "-----BEGIN PRIVATE KEY-----\n\(base64)\n-----END PRIVATE KEY-----"
        return pemString.data(using: .utf8)
    }
    
    func validateAndFormatPrivateKey(data: Data) throws -> Data {
        if let _ = SecCertificateCreateWithData(nil, data as CFData) { throw PrivateKeyImportError.isCertificate }
        var error: Unmanaged<CFError>?
        let rsaAttr: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        if let _ = SecKeyCreateWithData(data as CFData, rsaAttr as CFDictionary, &error) {
            guard let pem = derToPEM(derData: data) else { throw PrivateKeyImportError.conversionFailed }
            return pem
        }
        let ecAttr: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeEC, kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        if let _ = SecKeyCreateWithData(data as CFData, ecAttr as CFDictionary, nil) {
            guard let pem = derToPEM(derData: data) else { throw PrivateKeyImportError.conversionFailed }
            return pem
        }
        if let pemString = String(data: data, encoding: .utf8) {
            let clean = pemString.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasBegin = clean.contains("-----BEGIN PRIVATE KEY-----")    || clean.contains("-----BEGIN RSA PRIVATE KEY-----")
                        || clean.contains("-----BEGIN EC PRIVATE KEY-----") || clean.contains("-----BEGIN DSA PRIVATE KEY-----")
            let hasEnd   = clean.contains("-----END PRIVATE KEY-----")      || clean.contains("-----END RSA PRIVATE KEY-----")
                        || clean.contains("-----END EC PRIVATE KEY-----")   || clean.contains("-----END DSA PRIVATE KEY-----")
            if hasBegin && hasEnd { return data }
        }
        throw PrivateKeyImportError.invalidKey
    }
    
    func importPrivateKey(data: Data, for cert: ALTCertificate) {
        do {
            cert.privateKey = try validateAndFormatPrivateKey(data: data)
            saveLocalCertificate(cert)
            self.loadCertificates(presentingViewController: nil)
            self.alertMessage = "Successfully added private key to certificate \(cert.name)."
            self.showAlert    = true
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    func clearPrivateKey(for cert: ALTCertificate) {
        cert.privateKey = nil
        saveLocalCertificate(cert)
        self.loadCertificates(presentingViewController: nil)
        self.alertMessage = "Successfully removed private key from certificate \(cert.name)."
        self.showAlert    = true
    }
    
    private func recordSuccessfulImport(serial: String, hasPrivateKey: Bool, filename: String) {
        if let previous = importedSerialsThisBatch[serial] {
            importSuccessCount -= 1
            importFailedCount += 1
            failedImportsList.append("\(previous.filename): Duplicate certificate (already imported).")
        }
        importedSerialsThisBatch[serial] = (hasPrivateKey, filename)
        importSuccessCount += 1
    }
    
    private func isDuplicate(cert: ALTCertificate, importedSerials: [String: (hasPrivateKey: Bool, filename: String)]) -> Bool {
        if let imported = importedSerials[cert.serialNumber] {
            if cert.privateKey == nil || imported.hasPrivateKey {
                return true
            }
        }
        if let existing = self.certificates.first(where: { $0.serialNumber == cert.serialNumber }) {
            if cert.privateKey == nil || existing.privateKey != nil {
                return true
            }
        }
        return false
    }
}

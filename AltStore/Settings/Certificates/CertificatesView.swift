//
//  CertificatesView.swift
//  AltStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import SwiftUI
import AltSign
import UniformTypeIdentifiers

struct CertificatesView: View {
    weak var presentingViewController: UIViewController?
    
    @StateObject private var viewModel = CertificatesViewModel()
    
    private var allowedImportTypes: [UTType] {
        ["p12", "pfx", "pkcs12", "der", "cer", "crt", "pem"].compactMap { UTType(filenameExtension: $0) }
    }
    private var allowedKeyImportTypes: [UTType] {
        ["key", "pem", "der"].compactMap { UTType(filenameExtension: $0) }
    }
    
    @State private var showCreateDialog           = false
    @State private var showFileImporter           = false
    @State private var showRevokeConfirmation     = false
    @State private var showDeactivateConfirmation = false
    @State private var showDeleteConfirmation     = false
    @State private var showExportPasswordPrompt   = false
    @State private var showClearKeyConfirmation   = false
    @State private var hasInitialLoaded           = false
    @State private var hasCopiedActiveSerial      = false
    
    @State private var newMachineName        = ""
    @State private var exportPasswordInput   = ""
    @State private var fileImportMode: FileImportMode       = .certificate
    @State private var keyTextImportItem: KeyTextImportItem? = nil
    @State private var privateKeyTextInput   = ""
    
    @State private var certificateToRevoke:      ALTCertificate? = nil
    @State private var certificateToDelete:      ALTCertificate? = nil
    @State private var certificateToExport:      ALTCertificate? = nil
    @State private var certificateToAddKeyFor:   ALTCertificate? = nil
    @State private var certificateToClearKeyFor: ALTCertificate? = nil
    
    var body: some View {
        ZStack {
            List {
                ActiveCertSectionView(
                    viewModel: viewModel,
                    hasCopiedActiveSerial: $hasCopiedActiveSerial,
                    onDeactivate: { showDeactivateConfirmation = true }
                )
                CertificatesListView(
                    viewModel: viewModel,
                    onRowTap:     { pushDetailView(for: $0) },
                    onRevoke:     { certificateToRevoke = $0; showRevokeConfirmation = true },
                    onExportP12:  { cert in
                        certificateToExport = cert
                        exportPasswordInput = ""
                        showExportPasswordPrompt = true
                    },
                    onClearKey:   { cert in
                        certificateToClearKeyFor = cert
                        showClearKeyConfirmation = true
                    },
                    onAddKeyBin:  { cert in
                        certificateToAddKeyFor = cert
                        fileImportMode = .privateKey
                        showFileImporter = true
                    },
                    onAddKeyText: { cert in
                        keyTextImportItem = KeyTextImportItem(id: cert.serialNumber, cert: cert)
                    },
                    onDelete: { certificateToDelete = $0; showDeleteConfirmation = true }
                )
            }
            .refreshable {
                await withCheckedContinuation { continuation in
                    viewModel.loadCertificates(presentingViewController: presentingViewController, isPullToRefresh: true) {
                        continuation.resume()
                    }
                }
            }
            .navigationTitle("Certificates")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    SwiftUI.Button {
                        viewModel.isGlobalHideActive.toggle()
                    } label: {
                        Image(systemName: viewModel.isGlobalHideActive ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel("Toggle Hide Sensitive Information")
                    
                    SwiftUI.Button {
                        newMachineName = "ben4Store - \(UIDevice.current.name)"
                        showCreateDialog = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create Certificate")
                    .disabled(viewModel.team == nil)
                    
                    SwiftUI.Button {
                        fileImportMode = .certificate
                        showFileImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import Certificates")
                }
            }
            .onAppear {
                guard !hasInitialLoaded else { return }
                hasInitialLoaded = true
                viewModel.loadCertificates(presentingViewController: nil)
            }
            
            if viewModel.isLoading { LoadingOverlay() }
        }
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            SwiftUI.Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .alert("New Certificate", isPresented: $showCreateDialog) {
            TextField("Machine Name", text: $newMachineName)
            SwiftUI.Button("Create") {
                viewModel.createCertificate(machineName: newMachineName, presentingViewController: presentingViewController)
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new certificate. This will create a new certificate on Apple's servers and store the private key locally.")
        }
        .alert("Revoke Certificate", isPresented: $showRevokeConfirmation) {
            SwiftUI.Button("Revoke", role: .destructive) {
                if let cert = certificateToRevoke { viewModel.revokeCertificate(cert) }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to revoke this certificate? This will permanently delete the certificate on Apple's servers and delete it locally.")
        }
        .alert("Deactivate Certificate", isPresented: $showDeactivateConfirmation) {
            SwiftUI.Button("Deactivate", role: .destructive) { viewModel.deactivateActiveCertificate() }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to deactivate the active signing certificate locally?")
        }
        .alert("Delete Certificate", isPresented: $showDeleteConfirmation) {
            SwiftUI.Button("Delete", role: .destructive) {
                if let cert = certificateToDelete { viewModel.deleteCertificate(cert) }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this certificate locally? This will remove it from the cached local store.")
        }
        .alert("Import Certificate Password", isPresented: $viewModel.showPasswordPromptForImport) {
            SecureField("Password", text: $viewModel.importPasswordInput)
            SwiftUI.Button("Import") { viewModel.submitImportPassword() }
            SwiftUI.Button("Cancel", role: .cancel) { viewModel.cancelImport() }
        } message: {
            Text("Enter the password to decrypt the imported certificate file.\n\nFile: \(viewModel.currentImportFilename)")
        }
        .alert("Success", isPresented: $viewModel.showAlert) {
            SwiftUI.Button("OK", role: .cancel) { viewModel.alertMessage = nil }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .alert("Import Summary", isPresented: $viewModel.showImportSummary) {
            if viewModel.importFailedCount > 0 {
                SwiftUI.Button("Show Failed") {
                    DispatchQueue.main.async {
                        viewModel.showFailuresAlert = true
                    }
                }
                SwiftUI.Button("OK", role: .cancel) {}
            } else {
                SwiftUI.Button("OK", role: .cancel) {}
            }
        } message: {
            Text(viewModel.importSummaryMessage)
        }
        .sheet(isPresented: $viewModel.showFailuresAlert) {
            NavigationView {
                List {
                    ForEach(Array(viewModel.failedImportsList.enumerated()), id: \.offset) { index, failure in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(failure)
                                .font(.system(size: 13))
                        }
                        .padding(.vertical, 4)
                    }
                }
                .navigationTitle("Import Failures")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        SwiftUI.Button("OK") {
                            viewModel.showFailuresAlert = false
                        }
                    }
                }
            }
        }
        .alert("Export Certificate Password", isPresented: $showExportPasswordPrompt) {
            SecureField("Password", text: $exportPasswordInput)
            SwiftUI.Button("Export") {
                if let cert = certificateToExport {
                    CertificateExporter.shareP12(cert, password: exportPasswordInput) { viewModel.errorMessage = $0 }
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Set a password to encrypt the exported .p12 certificate file.")
        }
        .alert("Clear Private Key", isPresented: $showClearKeyConfirmation) {
            if let cert = certificateToClearKeyFor {
                SwiftUI.Button("Clear Key", role: .destructive) {
                    viewModel.clearPrivateKey(for: cert)
                    certificateToClearKeyFor = nil
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) { certificateToClearKeyFor = nil }
        } message: {
            if let cert = certificateToClearKeyFor {
                Text("This will clear the locally stored private key of this certificate.\n\nName: \(cert.name)\nS/N: \(cert.serialNumber)")
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: fileImportMode == .certificate ? allowedImportTypes : allowedKeyImportTypes,
            allowsMultipleSelection: fileImportMode == .certificate
        ) { result in
            switch result {
            case .success(let urls):
                switch fileImportMode {
                case .certificate:
                    viewModel.startBulkImport(urls: urls)
                case .privateKey:
                    if let url = urls.first, let cert = certificateToAddKeyFor {
                        _ = url.startAccessingSecurityScopedResource()
                        defer { url.stopAccessingSecurityScopedResource() }
                        do {
                            viewModel.importPrivateKey(data: try Data(contentsOf: url), for: cert)
                        } catch {
                            viewModel.errorMessage = "Failed to read private key: " + error.localizedDescription
                        }
                    }
                }
            case .failure(let error):
                let type = fileImportMode == .certificate ? "files" : "private key"
                viewModel.errorMessage = "Failed to select \(type): " + error.localizedDescription
            }
        }
        .sheet(item: $keyTextImportItem) { item in
            PrivateKeyTextInputView(
                text: $privateKeyTextInput,
                cert: item.cert,
                viewModel: viewModel,
                allowedKeyImportTypes: allowedKeyImportTypes,
                onCancel: {
                    keyTextImportItem = nil
                    privateKeyTextInput = ""
                }
            )
        }
    }
    
    private func pushDetailView(for cert: ALTCertificate) {
        let metadata = DeveloperPortalMetadata(
            identifier: cert.identifier,
            machineName: cert.machineName,
            machineIdentifier: cert.machineIdentifier,
            requesterEmail: cert.requesterEmail
        )
        let detailVC = UIHostingController(rootView: CertificateDetailView(certificate: cert, portalMetadata: metadata))
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        detailVC.navigationItem.scrollEdgeAppearance = appearance
        detailVC.navigationItem.standardAppearance   = appearance
        presentingViewController?.navigationController?.pushViewController(detailVC, animated: true)
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            ProgressView()
                .padding(20)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
        }
    }
}

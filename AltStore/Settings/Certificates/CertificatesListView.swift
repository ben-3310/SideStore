//
//  CertificatesListView.swift
//  AltStore
//
//  Created by Magesh K on 2026-07-03.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import SwiftUI
import AltSign

struct CertificatesListView: View {
    @ObservedObject var viewModel: CertificatesViewModel
    
    var onRowTap:     (ALTCertificate) -> Void
    var onRevoke:     (ALTCertificate) -> Void
    var onExportP12:  (ALTCertificate) -> Void
    var onClearKey:   (ALTCertificate) -> Void
    var onAddKeyBin:  (ALTCertificate) -> Void
    var onAddKeyText: (ALTCertificate) -> Void
    var onDelete:     (ALTCertificate) -> Void
    
    var body: some View {
        if viewModel.certificates.isEmpty {
            Section(header: Text("All Certificates")) {
                if viewModel.isLoading {
                    Text("Fetching certificates...").foregroundColor(.secondary)
                } else {
                    Text("No local certificates found.").foregroundColor(.secondary)
                }
            }
        } else {
            ForEach(viewModel.groupedCertificatesList) { group in
                Section {
                    ForEach(group.certificates, id: \.serialNumber) { cert in
                        CertificateRowView(
                            cert:        cert,
                            viewModel:   viewModel,
                            onRevoke:    { onRevoke(cert) },
                            onExportP12: { onExportP12(cert) },
                            onClearKey:  { onClearKey(cert) },
                            onAddKeyBin: { onAddKeyBin(cert) },
                            onAddKeyText:{ onAddKeyText(cert) },
                            onDelete:    { onDelete(cert) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onRowTap(cert) }
                    }
                } header: {
                    CertGroupHeaderView(group: group, viewModel: viewModel)
                } footer: {
                    if group.id == viewModel.groupedCertificatesList.last?.id {
                        Text("Suffix (R) indicates the certificate is registered remotely on Apple's developer portal.")
                    }
                }
            }
        }
    }
}

private struct CertGroupHeaderView: View {
    let group: GroupedCertificates
    @ObservedObject var viewModel: CertificatesViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            Text(group.name)
            Spacer()
            Menu {
                ForEach(SortOption.allCases) { option in
                    SwiftUI.Button {
                        if viewModel.currentSort == option { viewModel.isAscending.toggle() }
                        else { viewModel.currentSort = option; viewModel.isAscending = (option == .name) }
                    } label: {
                        if viewModel.currentSort == option {
                            Label("\(option.rawValue) \(viewModel.isAscending ? "↑" : "↓")", systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 13)).foregroundColor(.accentColor)
            }
            Menu {
                Picker("Group By", selection: $viewModel.currentGroup) {
                    ForEach(GroupOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Image(systemName: "rectangle.3.group").font(.system(size: 13)).foregroundColor(.accentColor)
            }
            SwiftUI.Button {
                viewModel.isSectionHideActive.toggle()
            } label: {
                Image(systemName: viewModel.isSectionHideActive ? "eye.slash" : "eye")
                    .font(.subheadline)
                    .foregroundColor(viewModel.isGlobalHideActive ? .gray : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGlobalHideActive)
        }
    }
}

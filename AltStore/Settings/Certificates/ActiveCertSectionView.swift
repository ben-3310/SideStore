//
//  ActiveCertSectionView.swift
//  AltStore
//
//  Created by Magesh K on 2026-07-03.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import SwiftUI
import AltSign

struct ActiveCertSectionView: View {
    @ObservedObject var viewModel: CertificatesViewModel
    @Binding var hasCopiedActiveSerial: Bool
    var onDeactivate: () -> Void
    
    var body: some View {
        Section("Active Local Certificate") {
            if let activeSerial = viewModel.activeSerialNumber {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    
                    VStack(alignment: .leading) {
                        HStack(spacing: 6) {
                            Text("Active Signing Certificate").font(.headline)
                            
                            SwiftUI.Button {
                                UIPasteboard.general.string = activeSerial
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                hasCopiedActiveSerial = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { hasCopiedActiveSerial = false }
                            } label: {
                                Image(systemName: hasCopiedActiveSerial ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 13))
                                    .foregroundColor(hasCopiedActiveSerial ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        let displaySerial = viewModel.displayActiveSerial(activeSerial)
                        (
                            Text("SN: ").font(.footnote)
                            + Text(displaySerial).font(.system(size: 13, design: .monospaced))
                        )
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            let key = "active_" + activeSerial
                            if viewModel.revealedSerials.contains(key) { viewModel.revealedSerials.remove(key) }
                            else { viewModel.revealedSerials.insert(key) }
                        }
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .contextMenu {
                    let key      = "active_" + activeSerial
                    let isMasked = viewModel.isActiveSerialMasked(activeSerial)
                    SwiftUI.Button {
                        if viewModel.revealedSerials.contains(key) { viewModel.revealedSerials.remove(key) }
                        else { viewModel.revealedSerials.insert(key) }
                    } label: {
                        Label(isMasked ? "Reveal Details" : "Hide Details",
                              systemImage: isMasked ? "eye" : "eye.slash")
                    }
                    SwiftUI.Button { UIPasteboard.general.string = activeSerial } label: {
                        Label("Copy S/N", systemImage: "doc.on.doc")
                    }
                }
                
                HStack {
                    Image(systemName: "checkmark.seal.fill").font(.title2).opacity(0)
                    SwiftUI.Button(role: .destructive) { onDeactivate() } label: {
                        Text("Deactivate Locally").fontWeight(.medium)
                    }
                }
            } else {
                Text(viewModel.team == nil
                     ? "No active local certificate found.Import a .p12 file to sign your apps."
                     : "No active local certificate found.Create a new certificate or import a .p12 file to sign your apps.")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
    }
}

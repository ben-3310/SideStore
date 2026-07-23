//
//  BonjourDiscoveryView.swift
//  AltStore
//
//  Created by Magesh K on 4/7/26.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import SwiftUI

// MARK: - Root View (Domains List)

/// Entry point: discovers and lists browsable Bonjour domains.
/// Tapping a domain navigates to its service types.
struct BonjourDiscoveryView: View {
    @StateObject private var manager = BonjourDiscoveryManager()
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            if manager.isSearching && manager.domains.isEmpty {
                ProgressView("Searching for domains…")
            } else if manager.domains.isEmpty {
                emptyState
            } else {
                domainsList
            }
        }
        .navigationTitle("Discovery")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.discoverDomains()
        }
        .onDisappear {
            manager.stopDomainSearch()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Domains Found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Make sure you're connected to a local network.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            SwiftUI.Button {
                manager.discoverDomains()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
            
            VStack(spacing: 8) {
                Text("Ensure **Local Network Access** is provided otherwise this function may not work as intended since it is based on L N A...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("**Settings -> apps -> ben4Store -> LocalNetworkAccess = toggle on**")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            .padding(.horizontal, 24)
        }
    }
    
    private var domainsList: some View {
        List {
            Section(header: Text("Browsable Domains")) {
                ForEach(manager.domains, id: \.self) { domain in
                    NavigationLink(destination: ServiceTypesView(domain: domain)) {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.accentColor)
                                .frame(width: 28)
                            Text(domain)
                                .font(.body)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}


// MARK: - Service Types View

/// Lists all service types discovered in a given domain.
/// Tapping a type navigates to its instances.
struct ServiceTypesView: View {
    let domain: String
    @StateObject private var manager = BonjourDiscoveryManager()
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            if manager.isSearching && manager.serviceTypes.isEmpty {
                ProgressView("Searching for service types…")
            } else if manager.serviceTypes.isEmpty {
                emptyState
            } else {
                serviceTypesList
            }
        }
        .navigationTitle(domain)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.discoverServiceTypes(in: domain)
        }
        .onDisappear {
            manager.stopTypeSearch()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Services Found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("No Bonjour services are currently advertised in this domain.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            SwiftUI.Button {
                manager.discoverServiceTypes(in: domain)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
            
            VStack(spacing: 8) {
                Text("Ensure **Local Network Access** is provided otherwise this function may not work as intended since it is based on L N A...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("**Settings -> apps -> ben4Store -> LocalNetworkAccess = toggle on**")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            .padding(.horizontal, 24)
        }
    }
    
    private var serviceTypesList: some View {
        List {
            Section(
                header: Text("\(manager.serviceTypes.count) Service\(manager.serviceTypes.count == 1 ? "" : "s") Found"),
                footer: searchingFooter
            ) {
                ForEach(manager.serviceTypes) { typeInfo in
                    NavigationLink(destination: ServiceInstancesView(
                        serviceType: typeInfo.rawType,
                        domain: domain,
                        friendlyName: typeInfo.friendlyName
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: typeInfo.friendlyName != nil ? "checkmark.seal.fill" : "questionmark.circle")
                                .foregroundColor(typeInfo.friendlyName != nil ? .green : .orange)
                                .frame(width: 28)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                if let friendly = typeInfo.friendlyName {
                                    Text(friendly)
                                        .font(.body)
                                        .lineLimit(1)
                                    Text(typeInfo.rawType)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text(typeInfo.rawType)
                                        .font(.body)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    @ViewBuilder
    private var searchingFooter: some View {
        if manager.isSearching {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Searching…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}


// MARK: - Service Instances View

/// Lists all discovered instances of a specific service type.
/// Tapping an instance navigates to its resolved details.
struct ServiceInstancesView: View {
    let serviceType: String
    let domain: String
    let friendlyName: String?
    
    @StateObject private var manager = BonjourDiscoveryManager()
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            if manager.isSearching && manager.instances.isEmpty {
                ProgressView("Searching for instances…")
            } else if manager.instances.isEmpty {
                emptyState
            } else {
                instancesList
            }
        }
        .navigationTitle(friendlyName ?? serviceType)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.discoverInstances(ofType: serviceType, inDomain: domain)
        }
        .onDisappear {
            manager.stopInstanceSearch()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Instances Found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("No devices are currently advertising this service.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            SwiftUI.Button {
                manager.discoverInstances(ofType: serviceType, inDomain: domain)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
            
            VStack(spacing: 8) {
                Text("Ensure **Local Network Access** is provided otherwise this function may not work as intended since it is based on L N A...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("**Settings -> apps -> ben4Store -> LocalNetworkAccess = toggle on**")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            .padding(.horizontal, 24)
        }
    }
    
    private var instancesList: some View {
        List {
            Section(
                header: VStack(alignment: .leading, spacing: 4) {
                    Text(serviceType)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(manager.instances.count) Instance\(manager.instances.count == 1 ? "" : "s")")
                },
                footer: searchingFooter
            ) {
                ForEach(manager.instances) { instance in
                    NavigationLink(destination: ServiceDetailView(service: instance)) {
                        HStack(spacing: 12) {
                            Image(systemName: "desktopcomputer")
                                .foregroundColor(.accentColor)
                                .frame(width: 28)
                            
                            Text(instance.name)
                                .font(.body)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    @ViewBuilder
    private var searchingFooter: some View {
        if manager.isSearching {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Searching…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}


// MARK: - Service Detail View

/// Shows full resolved details of a service: hostname, port, IP addresses, TXT records.
struct ServiceDetailView: View {
    let service: DiscoveredService
    @StateObject private var manager = BonjourDiscoveryManager()
    @State private var showCopyConfirmation = false
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            if let resolved = manager.resolvedService {
                resolvedContent(resolved)
            } else if let error = manager.resolveError {
                errorState(error)
            } else {
                loadingState
            }
        }
        .navigationTitle("Service Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if manager.resolvedService != nil {
                    SwiftUI.Button("Copy") {
                        copyAllInfo()
                    }
                }
            }
        }
        .onAppear {
            manager.resolveService(service)
        }
        .onDisappear {
            manager.stopResolving()
        }
    }
    
    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Resolving service…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Resolution Failed")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            SwiftUI.Button {
                manager.resolveService(service)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
        }
    }
    
    private func resolvedContent(_ resolved: ResolvedServiceInfo) -> some View {
        List {
            // Service Name Header
            Section {
                VStack(alignment: .center, spacing: 8) {
                    Image(systemName: "bonjour")
                        .font(.system(size: 36))
                        .foregroundColor(.accentColor)
                    Text(resolved.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            // Connection Info
            Section(header: Text("Connection")) {
                DetailRow(label: "Hostname", value: resolved.hostname)
                DetailRow(label: "Port", value: "\(resolved.port)")
                DetailRow(label: "Type", value: resolved.type)
                DetailRow(label: "Domain", value: resolved.domain)
            }
            
            // IP Addresses
            if !resolved.addresses.isEmpty {
                Section(header: Text("Addresses")) {
                    ForEach(resolved.addresses, id: \.self) { address in
                        HStack {
                            Image(systemName: address.contains(":") ? "6.circle" : "4.circle")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text(address)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .contextMenu {
                            SwiftUI.Button {
                                UIPasteboard.general.string = address
                            } label: {
                                Label("Copy Address", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
            
            // TXT Records
            if !resolved.txtRecords.isEmpty {
                Section(header: Text("TXT Record")) {
                    ForEach(resolved.txtRecords, id: \.key) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.key)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text(record.value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            SwiftUI.Button {
                                UIPasteboard.general.string = "\(record.key) = \(record.value)"
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay(alignment: .bottom) {
            if showCopyConfirmation {
                copiedBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private var copiedBanner: some View {
        Text("Copied to Clipboard")
            .font(.subheadline.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.accentColor)
            )
            .padding(.bottom, 16)
    }
    
    private func copyAllInfo() {
        guard let resolved = manager.resolvedService else { return }
        
        var lines: [String] = []
        lines.append("Service: \(resolved.name)")
        lines.append("Type: \(resolved.type)")
        lines.append("Domain: \(resolved.domain)")
        lines.append("Hostname: \(resolved.hostname)")
        lines.append("Port: \(resolved.port)")
        lines.append("")
        
        if !resolved.addresses.isEmpty {
            lines.append("Addresses:")
            for addr in resolved.addresses {
                lines.append("  \(addr)")
            }
            lines.append("")
        }
        
        if !resolved.txtRecords.isEmpty {
            lines.append("TXT Records:")
            for record in resolved.txtRecords {
                lines.append("  \(record.key) = \(record.value)")
            }
        }
        
        UIPasteboard.general.string = lines.joined(separator: "\n")
        
        withAnimation(.spring(response: 0.3)) {
            showCopyConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.3)) {
                showCopyConfirmation = false
            }
        }
    }
}


// MARK: - Detail Row

/// A simple key-value row with context menu for copying
private struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .lineLimit(nil)
        }
        .padding(.vertical, 2)
        .contextMenu {
            SwiftUI.Button {
                UIPasteboard.general.string = value
            } label: {
                Label("Copy \(label)", systemImage: "doc.on.doc")
            }
        }
    }
}

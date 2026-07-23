//
//  AppInfoView.swift
//  AltStore
//
//  Created by Magesh K on 2/7/26.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import SwiftUI
import AltStoreCore
import AltSign

struct AppInfoView: View {
    let installedApp: InstalledApp
    @Environment(\.presentationMode) var presentationMode
    
    @State private var isShowingToast: Bool = false
    @State private var toastMessage: String = ""
    
    private var appBundleURL: URL {
        if installedApp.resignedBundleIdentifier == Bundle.main.bundleIdentifier {
            return Bundle.main.bundleURL
        } else {
            return installedApp.fileURL
        }
    }
    
    private var provisioningProfile: ALTProvisioningProfile? {
        let profileURL = appBundleURL.appendingPathComponent("embedded.mobileprovision")
        return ALTProvisioningProfile(url: profileURL)
    }
    
    private var infoPlist: [String: Any]? {
        let plistURL = appBundleURL.appendingPathComponent("Info.plist")
        return NSDictionary(contentsOf: plistURL) as? [String: Any]
    }
    
    var body: some View {
        NavigationView {
            List {
                // Header
                Section {
                    HStack(spacing: 16) {
                        AppIconView(installedApp: installedApp)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(installedApp.name)
                                .font(.headline)
                            Text(installedApp.bundleIdentifier)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if installedApp.resignedBundleIdentifier != installedApp.bundleIdentifier {
                                Text("Resigned: \(installedApp.resignedBundleIdentifier)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Metadata Section
                Section(header: Text("General Metadata")) {
                    InfoRow(label: "Status", value: installedApp.isActive ? "Active" : "Inactive", valueColor: installedApp.isActive ? .green : .red)
                    InfoRow(label: "Version", value: installedApp.localizedVersion)
                    if let team = installedApp.team {
                        InfoRow(label: "Team Name", value: team.name)
                        InfoRow(label: "Team ID", value: team.identifier)
                    }
                    InfoRow(label: "Expiration Date", value: formatDate(provisioningProfile?.expirationDate ?? installedApp.expirationDate))
                    InfoRow(label: "Refreshed Date", value: formatDate(provisioningProfile?.creationDate ?? installedApp.refreshedDate))
                    InfoRow(label: "Installed Date", value: formatDate(installedApp.installedDate))
                    if let serialNumber = installedApp.certificateSerialNumber {
                        InfoRow(label: "Certificate Serial", value: serialNumber)
                    }
                    InfoRow(label: "Needs Resign", value: installedApp.needsResign ? "Yes" : "No")
                    InfoRow(label: "Uses Main Profile", value: installedApp.useMainProfile ? "Yes" : "No")
                }
                
                // Provisioning Profile Section
                if let profile = provisioningProfile {
                    Section(header: Text("Provisioning Profile")) {
                        NavigationLink(destination: ProvisioningProfileDetailView(profile: profile)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.name)
                                    .font(.subheadline)
                                Text("UUID: \(profile.UUID.uuidString)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Info.plist Section
                if let plist = infoPlist {
                    Section(header: Text("Info.plist")) {
                        NavigationLink(destination: InfoPlistContainerView(plist: plist)) {
                            Text("View Info.plist (\(plist.count) keys)")
                        }
                    }
                }
                
                // App Extensions Section
                if !installedApp.appExtensions.isEmpty {
                    Section(header: Text("App Extensions")) {
                        ForEach(Array(installedApp.appExtensions), id: \.bundleIdentifier) { ext in
                            NavigationLink(destination: ExtensionInfoView(appExtension: ext, parentAppURL: appBundleURL)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ext.name)
                                        .font(.subheadline)
                                    Text(ext.bundleIdentifier)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                // Resources Section
                Section(header: Text("Resources")) {
                    NavigationLink(destination: BundleResourceBrowserView(rootURL: appBundleURL, title: "Bundle Contents")) {
                        Text("Browse Bundle Contents")
                            .font(.subheadline)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("App Details")
            .navigationBarItems(trailing: SwiftUI.Button("Close") {
                presentationMode.wrappedValue.dismiss()
            })
            .overlay(
                AppInfoToastView(isShowing: $isShowingToast, message: toastMessage)
            )
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Provisioning Profile Detail View

struct ProvisioningProfileDetailView: View {
    let profile: ALTProvisioningProfile
    @State private var isShowingToast = false
    @State private var toastMessage = ""
    
    var body: some View {
        List {
            Section(header: Text("Profile Metadata")) {
                ProfileInfoRow(label: "Name", value: profile.name)
                ProfileInfoRow(label: "UUID", value: profile.UUID.uuidString)
                if let identifier = profile.identifier {
                    ProfileInfoRow(label: "Identifier", value: identifier)
                }
                ProfileInfoRow(label: "Team Name", value: profile.teamName)
                ProfileInfoRow(label: "Team Identifier", value: profile.teamIdentifier)
                ProfileInfoRow(label: "App Bundle ID", value: profile.bundleIdentifier)
                ProfileInfoRow(label: "Created", value: formatDate(profile.creationDate))
                ProfileInfoRow(label: "Expires", value: formatDate(profile.expirationDate))
                ProfileInfoRow(label: "Free Developer Profile", value: profile.isFreeProvisioningProfile ? "Yes" : "No")
            }
            
            if !profile.certificates.isEmpty {
                Section(header: Text("Developer Certificates (\(profile.certificates.count))")) {
                    ForEach(profile.certificates, id: \.serialNumber) { cert in
                        NavigationLink(destination: CertificateDetailView(certificate: cert)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cert.name)
                                    .font(.subheadline)
                                Text("Serial: \(cert.serialNumber)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            if !profile.deviceIDs.isEmpty {
                Section(header: Text("Provisioned Devices (\(profile.deviceIDs.count))")) {
                    NavigationLink(destination: DeviceIDsView(devices: profile.deviceIDs)) {
                        Text("View Provisioned Devices")
                    }
                }
            }
            
            Section(header: Text("Entitlements (\(profile.entitlements.count))")) {
                let sortedEntitlements = profile.entitlements.sorted { $0.key.rawValue < $1.key.rawValue }
                ForEach(sortedEntitlements, id: \.key.rawValue) { entitlement, value in
                    EntitlementRow(key: entitlement.rawValue, value: value)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Profile Details")
        .interactiveDismissDisabled(true)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}



// MARK: - Helper Views

struct AppIconView: View {
    let installedApp: InstalledApp
    @State private var image: UIImage? = nil
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.gray.opacity(0.15)
                    .overlay(
                        Image(systemName: "app")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(width: 60, height: 60)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .onAppear {
            installedApp.loadIcon { result in
                if case .success(let img) = result {
                    DispatchQueue.main.async {
                        self.image = img
                    }
                }
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ProfileInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .contextMenu {
            SwiftUI.Button {
                UIPasteboard.general.string = value
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

struct EntitlementRow: View {
    let key: String
    let value: Any
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .bold()
            Text(formatValue(value))
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            SwiftUI.Button {
                UIPasteboard.general.string = formatValue(value)
            } label: {
                Label("Copy Value", systemImage: "doc.on.doc")
            }
            SwiftUI.Button {
                UIPasteboard.general.string = key
            } label: {
                Label("Copy Key", systemImage: "doc.on.doc")
            }
        }
    }
    
    private func formatValue(_ val: Any) -> String {
        if let array = val as? [Any] {
            return "[" + array.map { "\($0)" }.joined(separator: ", ") + "]"
        }
        if let dict = val as? [String: Any] {
            return "{" + dict.map { "\($0.key): \($0.value)" }.joined(separator: ", ") + "}"
        }
        return "\(val)"
    }
}

// MARK: - Device IDs View

struct DeviceIDsView: View {
    let devices: [String]
    
    var body: some View {
        List(devices, id: \.self) { udid in
            HStack {
                Text(udid)
                    .font(.system(.body, design: .monospaced))
                Spacer()
                SwiftUI.Button(action: {
                    UIPasteboard.general.string = udid
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .navigationTitle("Device IDs")
        .interactiveDismissDisabled(true)
    }
}

// MARK: - Extension Info View

struct ExtensionInfoView: View {
    let appExtension: InstalledExtension
    let parentAppURL: URL

    // Resolve the .appex bundle URL by scanning PlugIns/ and matching bundle ID
    private var extensionURL: URL? {
        let pluginsDir = parentAppURL.appendingPathComponent("PlugIns")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: pluginsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        // Match by bundle ID in Info.plist
        for url in contents where url.pathExtension == "appex" {
            let plistURL = url.appendingPathComponent("Info.plist")
            if let dict = NSDictionary(contentsOf: plistURL) as? [String: Any],
               let bid = dict["CFBundleIdentifier"] as? String,
               bid == appExtension.resignedBundleIdentifier || bid == appExtension.bundleIdentifier {
                return url
            }
        }
        // Fallback: name-based guess
        return contents.first { $0.pathExtension == "appex" && $0.deletingPathExtension().lastPathComponent == appExtension.name }
    }

    private var provisioningProfile: ALTProvisioningProfile? {
        guard let url = extensionURL else { return nil }
        return ALTProvisioningProfile(url: url.appendingPathComponent("embedded.mobileprovision"))
    }

    private var infoPlist: [String: Any]? {
        guard let url = extensionURL else { return nil }
        return NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) as? [String: Any]
    }

    // Nested sub-extensions inside this .appex (rare but possible)
    private var subExtensions: [URL] {
        guard let url = extensionURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: url.appendingPathComponent("PlugIns"),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else { return [] }
        return contents.filter { $0.pathExtension == "appex" }
    }

    var body: some View {
        List {
            // General Metadata — sourced from the actual bundle, not CoreData
            Section(header: Text("Extension Metadata")) {
                let plist = infoPlist
                let profile = provisioningProfile

                let bundleName = plist?["CFBundleDisplayName"] as? String
                    ?? plist?["CFBundleName"] as? String
                    ?? appExtension.name
                let bundleID = plist?["CFBundleIdentifier"] as? String ?? appExtension.bundleIdentifier
                let shortVer = plist?["CFBundleShortVersionString"] as? String
                let buildVer = plist?["CFBundleVersion"] as? String
                let versionStr: String = {
                    if let s = shortVer, let b = buildVer { return "\(s) (\(b))" }
                    return shortVer ?? buildVer ?? "N/A"
                }()

                InfoRow(label: "Name", value: bundleName)
                InfoRow(label: "Bundle Identifier", value: bundleID)
                InfoRow(label: "Version", value: versionStr)

                if let minOS = plist?["MinimumOSVersion"] as? String {
                    InfoRow(label: "Min iOS", value: minOS)
                }
                if let exec = plist?["CFBundleExecutable"] as? String {
                    InfoRow(label: "Executable", value: exec)
                }

                // Dates from provisioning profile (ground truth)
                if let profile = profile {
                    InfoRow(label: "Profile Created", value: formatDate(profile.creationDate))
                    InfoRow(label: "Profile Expires", value: formatDate(profile.expirationDate))
                }
            }

            // Provisioning Profile
            if let profile = provisioningProfile {
                Section(header: Text("Provisioning Profile")) {
                    NavigationLink(destination: ProvisioningProfileDetailView(profile: profile)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                                .font(.subheadline)
                            Text("UUID: \(profile.UUID.uuidString)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Expires: \(formatDate(profile.expirationDate))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Info.plist
            if let plist = infoPlist {
                Section(header: Text("Info.plist")) {
                    NavigationLink(destination: InfoPlistContainerView(plist: plist)) {
                        Text("View Info.plist (\(plist.count) keys)")
                            .font(.subheadline)
                    }
                }
            }

            // Nested Sub-Extensions (recursive)
            if !subExtensions.isEmpty {
                Section(header: Text("Nested Extensions (\(subExtensions.count))")) {
                    ForEach(subExtensions, id: \.path) { subURL in
                        let subPlist = NSDictionary(contentsOf: subURL.appendingPathComponent("Info.plist")) as? [String: Any]
                        let subName = subPlist?["CFBundleDisplayName"] as? String
                            ?? subPlist?["CFBundleName"] as? String
                            ?? subURL.deletingPathExtension().lastPathComponent
                        let subBundleID = subPlist?["CFBundleIdentifier"] as? String ?? "Unknown"
                        NavigationLink(destination: BundleInspectorView(bundleURL: subURL)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(subName)
                                    .font(.subheadline)
                                Text(subBundleID)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle(appExtension.name)
        .interactiveDismissDisabled(true)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Generic Bundle Inspector (for recursive .appex drill-down)

struct BundleInspectorView: View {
    let bundleURL: URL

    private var provisioningProfile: ALTProvisioningProfile? {
        ALTProvisioningProfile(url: bundleURL.appendingPathComponent("embedded.mobileprovision"))
    }

    private var infoPlist: [String: Any]? {
        NSDictionary(contentsOf: bundleURL.appendingPathComponent("Info.plist")) as? [String: Any]
    }

    private var subExtensions: [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: bundleURL.appendingPathComponent("PlugIns"),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.filter { $0.pathExtension == "appex" }
    }

    private var displayName: String {
        infoPlist?["CFBundleDisplayName"] as? String
            ?? infoPlist?["CFBundleName"] as? String
            ?? bundleURL.deletingPathExtension().lastPathComponent
    }

    private var bundleID: String {
        infoPlist?["CFBundleIdentifier"] as? String ?? "Unknown"
    }

    private var version: String {
        let short = infoPlist?["CFBundleShortVersionString"] as? String
        let build = infoPlist?["CFBundleVersion"] as? String
        if let s = short, let b = build { return "\(s) (\(b))" }
        return short ?? build ?? "N/A"
    }

    var body: some View {
        List {
            Section(header: Text("Bundle Metadata")) {
                InfoRow(label: "Name", value: displayName)
                InfoRow(label: "Bundle ID", value: bundleID)
                InfoRow(label: "Version", value: version)
                if let execName = infoPlist?["CFBundleExecutable"] as? String {
                    InfoRow(label: "Executable", value: execName)
                }
                if let minOS = infoPlist?["MinimumOSVersion"] as? String {
                    InfoRow(label: "Min iOS", value: minOS)
                }
            }

            if let profile = provisioningProfile {
                Section(header: Text("Provisioning Profile")) {
                    NavigationLink(destination: ProvisioningProfileDetailView(profile: profile)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                                .font(.subheadline)
                            Text("UUID: \(profile.UUID.uuidString)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Expires: \(formatDate(profile.expirationDate))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if let plist = infoPlist {
                Section(header: Text("Info.plist")) {
                    NavigationLink(destination: InfoPlistContainerView(plist: plist)) {
                        Text("View Info.plist (\(plist.count) keys)")
                            .font(.subheadline)
                    }
                }
            }

            if !subExtensions.isEmpty {
                Section(header: Text("Nested Extensions (\(subExtensions.count))")) {
                    ForEach(subExtensions, id: \.path) { subURL in
                        let subPlist = NSDictionary(contentsOf: subURL.appendingPathComponent("Info.plist")) as? [String: Any]
                        let subName = subPlist?["CFBundleDisplayName"] as? String
                            ?? subPlist?["CFBundleName"] as? String
                            ?? subURL.deletingPathExtension().lastPathComponent
                        let subBundleID = subPlist?["CFBundleIdentifier"] as? String ?? "Unknown"
                        NavigationLink(destination: BundleInspectorView(bundleURL: subURL)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(subName)
                                    .font(.subheadline)
                                Text(subBundleID)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // Resources
            Section(header: Text("Resources")) {
                NavigationLink(destination: BundleResourceBrowserView(rootURL: bundleURL, title: "Bundle Contents")) {
                    Text("Browse Bundle Contents")
                        .font(.subheadline)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(true)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}


// MARK: - Toast View

struct AppInfoToastView: View {
    @Binding var isShowing: Bool
    let message: String
    
    var body: some View {
        VStack {
            Spacer()
            if isShowing {
                Text(message)
                    .font(.subheadline)
                    .padding()
                    .background(Color.black.opacity(0.85))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .transition(.slide)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                self.isShowing = false
                            }
                        }
                    }
            }
        }
        .padding(.bottom, 50)
    }
}

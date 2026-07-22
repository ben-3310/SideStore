//
//  BonjourDiscoveryManager.swift
//  AltStore
//
//  Created by Magesh K on 4/7/26.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import Foundation

// MARK: - Data Models

/// Information about a discovered Bonjour service type
struct ServiceTypeInfo: Identifiable, Hashable {
    let id = UUID()
    let rawType: String        // e.g. "_airplay._tcp."
    let friendlyName: String?  // e.g. "AirPlay" (nil if unknown)
    
    var displayName: String {
        friendlyName ?? rawType
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawType)
    }
    
    static func == (lhs: ServiceTypeInfo, rhs: ServiceTypeInfo) -> Bool {
        lhs.rawType == rhs.rawType
    }
}

/// A discovered service instance (before resolution)
struct DiscoveredService: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: String
    let domain: String
    
    // The underlying NetService reference for resolution
    let netService: NetService
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(type)
        hasher.combine(domain)
    }
    
    static func == (lhs: DiscoveredService, rhs: DiscoveredService) -> Bool {
        lhs.name == rhs.name && lhs.type == rhs.type && lhs.domain == rhs.domain
    }
}

/// Fully resolved service details
struct ResolvedServiceInfo: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let domain: String
    let hostname: String
    let port: Int
    let addresses: [String]      // Formatted IP address strings
    let txtRecords: [(key: String, value: String)]
}


// MARK: - BonjourDiscoveryManager

/// Manages Bonjour/DNS-SD discovery of domains, service types, instances, and resolution
final class BonjourDiscoveryManager: NSObject, ObservableObject {
    
    // MARK: Published State
    
    @Published var domains: [String] = []
    @Published var serviceTypes: [ServiceTypeInfo] = []
    @Published var instances: [DiscoveredService] = []
    @Published var resolvedService: ResolvedServiceInfo? = nil
    @Published var isSearching = false
    @Published var resolveError: String? = nil
    
    // MARK: Private
    
    private var domainBrowser: NetServiceBrowser?
    private var typeBrowser: NetServiceBrowser?
    private var instanceBrowser: NetServiceBrowser?
    private var resolvingService: NetService?
    
    private var fallbackBrowsers: [NetServiceBrowser] = []
    private var fallbackTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    
    private var discoveredDomains = Set<String>()
    private var discoveredTypes = Set<String>()
    private var discoveredInstances: [String: DiscoveredService] = [:]
    private var currentDomain: String = "local."
    
    override init() {
        super.init()
    }
    
    deinit {
        stopAll()
    }
    
    // MARK: - Domain Discovery
    
    /// Discover browsable Bonjour domains (typically just "local.")
    func discoverDomains() {
        debugLog("[BonjourDiscovery] Starting domain discovery...")
        stopDomainSearch()
        discoveredDomains.removeAll()
        domains.removeAll()
        isSearching = true
        
        let browser = NetServiceBrowser()
        browser.delegate = self
        domainBrowser = browser
        browser.searchForBrowsableDomains()
    }
    
    func stopDomainSearch() {
        debugLog("[BonjourDiscovery] Stopping domain discovery.")
        domainBrowser?.stop()
        domainBrowser = nil
    }
    
    // MARK: - Service Type Discovery
    
    /// Discover all service types registered in a given domain
    func discoverServiceTypes(in domain: String) {
        let domainWithDot = domain.hasSuffix(".") ? domain : domain + "."
        debugLog("[BonjourDiscovery] Starting service type discovery in domain '\(domainWithDot)'...")
        stopTypeSearch()
        discoveredTypes.removeAll()
        serviceTypes.removeAll()
        currentDomain = domainWithDot
        isSearching = true
        
        let browser = NetServiceBrowser()
        browser.delegate = self
        typeBrowser = browser
        browser.searchForServices(ofType: "_services._dns-sd._udp.", inDomain: domainWithDot)
        
        // Start fallback parallel searches after 1.5 seconds if we haven't found anything
        fallbackTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                // Accessing self inside non-MainActor context requires explicitly checking and dispatching state update
                // properties to MainActor. But here self.serviceTypes is a MainActor-isolated property accessed on main thread
                // or we can run the check on MainActor:
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    debugLog("[BonjourDiscovery] Fallback task resumed. Current service types count: \(self.serviceTypes.count)")
                    if self.serviceTypes.isEmpty {
                        debugLog("[BonjourDiscovery] Falling back to searching declared service types in parallel...")
                        self.startFallbackSearches(in: domainWithDot)
                    }
                }
            } catch {}
        }
        
        // Stop loading spinner after 5.0 seconds if we haven't found anything
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    debugLog("[BonjourDiscovery] Search timeout reached.")
                    self.isSearching = false
                }
            } catch {}
        }
    }
    
    private func startFallbackSearches(in domain: String) {
        let typesToBrowse = commonServiceTypesToBrowse
        
        Task { @MainActor [weak self] in
            for t in typesToBrowse {
                // Yield control to let UI draw between browser creation cycles
                await Task.yield()
                
                guard let self = self else { return }
                let browser = NetServiceBrowser()
                browser.delegate = self
                self.fallbackBrowsers.append(browser)
                browser.searchForServices(ofType: t, inDomain: domain)
                debugLog("[BonjourDiscovery] Fallback: Started browsing for service type '\(t)' in domain '\(domain)'")
            }
        }
    }
    
    func stopTypeSearch() {
        debugLog("[BonjourDiscovery] Stopping service type discovery.")
        typeBrowser?.stop()
        typeBrowser = nil
        fallbackTask?.cancel()
        fallbackTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        for b in fallbackBrowsers {
            b.stop()
        }
        fallbackBrowsers.removeAll()
        isSearching = false
    }
    
    // MARK: - Instance Discovery
    
    /// Discover all instances of a specific service type in a domain
    func discoverInstances(ofType type: String, inDomain domain: String) {
        let domainWithDot = domain.hasSuffix(".") ? domain : domain + "."
        let typeWithDot = type.hasSuffix(".") ? type : type + "."
        debugLog("[BonjourDiscovery] Starting instance discovery for type '\(typeWithDot)' in domain '\(domainWithDot)'...")
        stopInstanceSearch()
        discoveredInstances.removeAll()
        instances.removeAll()
        isSearching = true
        
        let browser = NetServiceBrowser()
        browser.delegate = self
        instanceBrowser = browser
        browser.searchForServices(ofType: typeWithDot, inDomain: domainWithDot)
    }
    
    func stopInstanceSearch() {
        debugLog("[BonjourDiscovery] Stopping instance discovery.")
        instanceBrowser?.stop()
        instanceBrowser = nil
    }
    
    // MARK: - Service Resolution
    
    /// Resolve a service to get its hostname, addresses, port, and TXT records
    func resolveService(_ service: DiscoveredService) {
        debugLog("[BonjourDiscovery] Starting resolution for service '\(service.name)' (\(service.type))...")
        stopResolving()
        resolvedService = nil
        resolveError = nil
        isSearching = true
        
        let netService = service.netService
        netService.delegate = self
        netService.resolve(withTimeout: 10.0)
        resolvingService = netService
    }
    
    func stopResolving() {
        debugLog("[BonjourDiscovery] Stopping service resolution.")
        resolvingService?.stop()
        resolvingService = nil
    }
    
    // MARK: - Stop All
    
    func stopAll() {
        debugLog("[BonjourDiscovery] Stopping all discovery activities.")
        stopDomainSearch()
        stopTypeSearch()
        stopInstanceSearch()
        stopResolving()
        isSearching = false
    }
    
    // MARK: - Helpers
    
    static func friendlyName(for rawType: String) -> String? {
        let normalized = rawType.hasSuffix(".") ? rawType : rawType + "."
        return commonKnownServiceTypes[normalized]
    }
    
    /// Format socket address data into a readable string
    private static func formatAddress(_ data: Data) -> String? {
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        
        let result = data.withUnsafeBytes { rawBufferPointer -> Int32 in
            guard let baseAddress = rawBufferPointer.baseAddress else { return -1 }
            let sockAddr = baseAddress.assumingMemoryBound(to: sockaddr.self)
            return getnameinfo(
                sockAddr,
                socklen_t(data.count),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
        }
        
        guard result == 0 else { return nil }
        
        let addressString = String(cString: hostname)
        guard !addressString.isEmpty else { return nil }
        
        return addressString
    }
    
    /// Parse TXT record data into key-value pairs
    private static func parseTXTRecord(_ data: Data) -> [(key: String, value: String)] {
        let dict = NetService.dictionary(fromTXTRecord: data)
        return dict.map { key, value in
            let valueStr = String(data: value, encoding: .utf8) ?? value.map { String(format: "%02x", $0) }.joined()
            return (key: key, value: valueStr)
        }.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }
}


// MARK: - NetServiceBrowserDelegate

extension BonjourDiscoveryManager: NetServiceBrowserDelegate {
    
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        debugLog("[BonjourDiscovery] netServiceBrowserWillSearch: Browser search started successfully.")
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        debugLog("[BonjourDiscovery] netServiceBrowserDidStopSearch: Browser search stopped.")
        Task { @MainActor [weak self] in
            self?.isSearching = false
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        debugLog("[BonjourDiscovery] netServiceBrowser didNotSearch: Error dictionary: \(errorDict)")
        if browser === self.typeBrowser {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                debugLog("[BonjourDiscovery] Meta-browser failed. Triggering fallback parallel search immediately...")
                self.fallbackTask?.cancel()
                self.fallbackTask = nil
                
                self.startFallbackSearches(in: self.currentDomain)
            }
        } else {
            Task { @MainActor [weak self] in
                self?.isSearching = false
            }
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFindDomain domainString: String, moreComing: Bool) {
        debugLog("[BonjourDiscovery] didFindDomain: Found domain '\(domainString)' (moreComing: \(moreComing))")
        let trimmed = domainString.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !trimmed.isEmpty else { return }
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if self.discoveredDomains.insert(trimmed).inserted {
                self.domains.append(trimmed)
                self.domains.sort()
            }
            if !moreComing {
                self.isSearching = false
            }
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemoveDomain domainString: String, moreComing: Bool) {
        debugLog("[BonjourDiscovery] didRemoveDomain: Removed domain '\(domainString)' (moreComing: \(moreComing))")
        let trimmed = domainString.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.discoveredDomains.remove(trimmed)
            self.domains.removeAll { $0 == trimmed }
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let isFallbackTypeSearch = self.fallbackBrowsers.contains(browser)
        let isTypeSearch = (browser === self.typeBrowser) || isFallbackTypeSearch
        debugLog("[BonjourDiscovery] didFind: Found service name='\(service.name)', type='\(service.type)', domain='\(service.domain)' (isTypeSearch: \(isTypeSearch), isFallbackTypeSearch: \(isFallbackTypeSearch), moreComing: \(moreComing))")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            if isTypeSearch {
                let fullType: String
                if isFallbackTypeSearch {
                    fullType = service.type.hasSuffix(".") ? service.type : service.type + "."
                } else {
                    let reconstructed = "\(service.name).\(service.type)"
                        .replacingOccurrences(of: "..", with: ".")
                    fullType = reconstructed.hasSuffix(".") ? reconstructed : reconstructed + "."
                }
                
                debugLog("[BonjourDiscovery] Found service type reconstructed: '\(fullType)'")
                if self.discoveredTypes.insert(fullType).inserted {
                    let info = ServiceTypeInfo(
                        rawType: fullType,
                        friendlyName: BonjourDiscoveryManager.friendlyName(for: fullType)
                    )
                    self.serviceTypes.append(info)
                    self.serviceTypes.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                }
            } else if browser === self.instanceBrowser {
                let key = "\(service.name)|\(service.type)|\(service.domain)"
                debugLog("[BonjourDiscovery] Found instance key: '\(key)'")
                if self.discoveredInstances[key] == nil {
                    let discovered = DiscoveredService(
                        name: service.name,
                        type: service.type,
                        domain: service.domain,
                        netService: service
                    )
                    self.discoveredInstances[key] = discovered
                    self.instances.append(discovered)
                }
            }
            
            if !moreComing {
                self.isSearching = false
            }
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if browser === self.typeBrowser {
                let fullType = "\(service.name).\(service.type)"
                    .replacingOccurrences(of: "..", with: ".")
                self.discoveredTypes.remove(fullType)
                self.serviceTypes.removeAll { $0.rawType == fullType }
            } else if browser === self.instanceBrowser {
                let key = "\(service.name)|\(service.type)|\(service.domain)"
                self.discoveredInstances.removeValue(forKey: key)
                self.instances.removeAll { $0.name == service.name && $0.type == service.type }
            }
        }
    }
}


// MARK: - NetServiceDelegate (for resolution)

extension BonjourDiscoveryManager: NetServiceDelegate {
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        debugLog("[BonjourDiscovery] netServiceDidResolveAddress: Successfully resolved '\(sender.name)' to host: \(sender.hostName ?? "nil"), port: \(sender.port)")
        
        var addresses: [String] = []
        if let addressData = sender.addresses {
            for data in addressData {
                if let addr = BonjourDiscoveryManager.formatAddress(data) {
                    addresses.append(addr)
                }
            }
        }
        debugLog("[BonjourDiscovery] Resolved addresses: \(addresses)")
        
        var txtRecords: [(key: String, value: String)] = []
        if let txtData = sender.txtRecordData() {
            txtRecords = BonjourDiscoveryManager.parseTXTRecord(txtData)
        }
        debugLog("[BonjourDiscovery] Resolved TXT record count: \(txtRecords.count)")
        
        let resolved = ResolvedServiceInfo(
            name: sender.name,
            type: sender.type,
            domain: sender.domain,
            hostname: sender.hostName ?? "Unknown",
            port: sender.port,
            addresses: addresses,
            txtRecords: txtRecords
        )
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.resolvedService = resolved
            self.isSearching = false
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        debugLog("[BonjourDiscovery] netService didNotResolve: Resolution failed for '\(sender.name)'. Errors: \(errorDict)")
        let errorCode = errorDict[NetService.errorCode] ?? -1
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.resolveError = "Failed to resolve service (error \(errorCode))"
            self.isSearching = false
        }
    }
}

//
//  BonjourDiscoveryManagerV2.swift
//  AltStore
//
//  Created by Magesh K on 4/7/26.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import Foundation
import Network

// MARK: - Data Models

struct ServiceTypeInfoV2: Identifiable, Hashable {
    let id = UUID()
    let rawType: String
    let friendlyName: String?
    
    var displayName: String {
        friendlyName ?? rawType
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawType)
    }
    
    static func == (lhs: ServiceTypeInfoV2, rhs: ServiceTypeInfoV2) -> Bool {
        lhs.rawType == rhs.rawType
    }
}

struct DiscoveredServiceV2: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: String
    let domain: String
    
    // Store the NWBrowser.Result for parsing TXT metadata
    let result: NWBrowser.Result
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(type)
        hasher.combine(domain)
    }
    
    static func == (lhs: DiscoveredServiceV2, rhs: DiscoveredServiceV2) -> Bool {
        lhs.name == rhs.name && lhs.type == rhs.type && lhs.domain == rhs.domain
    }
}

struct ResolvedServiceInfoV2: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let domain: String
    let hostname: String
    let port: UInt16
    let addresses: [String]
    let txtRecords: [(key: String, value: String)]
}


// MARK: - BonjourDiscoveryManagerV2

final class BonjourDiscoveryManagerV2: NSObject, ObservableObject {
    
    // MARK: Published State
    
    @Published var domains: [String] = []
    @Published var serviceTypes: [ServiceTypeInfoV2] = []
    @Published var instances: [DiscoveredServiceV2] = []
    @Published var resolvedService: ResolvedServiceInfoV2? = nil
    @Published var isSearching = false
    @Published var resolveError: String? = nil
    
    // MARK: Private
    
    private var typeBrowser: NetServiceBrowser?
    private var instanceBrowser: NWBrowser?
    private var fallbackBrowsers: [NWBrowser] = []
    private var activeConnection: NWConnection?
    private var timeoutTask: Task<Void, Never>?
    
    private var discoveredTypes = Set<String>()
    private var discoveredInstances = Set<DiscoveredServiceV2>()
    
    override init() {
        super.init()
    }
    
    deinit {
        stopAll()
    }
    
    // MARK: - Domain Discovery
    
    func discoverDomains() {
        debugLog("[BonjourDiscoveryV2] Starting domain discovery...")
        isSearching = true
        // Network.framework doesn't browse domains. We present the standard default 'local' domain.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.domains = ["local"]
            self.isSearching = false
        }
    }
    
    func stopDomainSearch() {
        isSearching = false
    }
    
    // MARK: - Service Type Discovery
    
    func discoverServiceTypes(in domain: String) {
        let domainWithDot = domain.hasSuffix(".") ? domain : domain + "."
        debugLog("[BonjourDiscoveryV2] Starting service type discovery in domain '\(domainWithDot)'...")
        stopTypeSearch()
        discoveredTypes.removeAll()
        serviceTypes.removeAll()
        isSearching = true
        
        // Use NetServiceBrowser for the meta-query (_services._dns-sd._udp)
        // since Foundation NetServiceBrowser does not have the strict type format validation 
        // that causes Network.framework to crash with BadParam.
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_services._dns-sd._udp.", inDomain: domainWithDot)
        typeBrowser = browser
        
        // Parallel fallback searches as a backup to scan for all expected services.
        self.startFallbackSearches(in: domainWithDot)
        
        // Stop loading spinner after 5 seconds if we haven't found anything
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self = self else { return }
                debugLog("[BonjourDiscoveryV2] Search timeout reached.")
                self.isSearching = false
            } catch {}
        }
    }
    
    private func startFallbackSearches(in domain: String) {
        let typesToBrowse = commonServiceTypesToBrowse
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            for t in typesToBrowse {
                let typeWithoutDot = t.hasSuffix(".") ? String(t.dropLast()) : t
                let parameters = typeWithoutDot.contains("_tcp") ? NWParameters.tcp : NWParameters.udp
                parameters.includePeerToPeer = true
                
                let descriptor = NWBrowser.Descriptor.bonjour(type: typeWithoutDot, domain: domain)
                let browser = NWBrowser(for: descriptor, using: parameters)
                
                browser.browseResultsChangedHandler = { [weak self] results, changes in
                    guard let self = self else { return }
                    if !results.isEmpty {
                        Task { @MainActor in
                            if self.discoveredTypes.insert(t).inserted {
                                debugLog("[BonjourDiscoveryV2] Fallback found active type: \(t)")
                                let info = ServiceTypeInfoV2(
                                    rawType: t,
                                    friendlyName: Self.friendlyName(for: t)
                                )
                                self.serviceTypes.append(info)
                                self.serviceTypes.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                            }
                        }
                    }
                }
                
                browser.start(queue: .global(qos: .userInitiated))
                
                Task { @MainActor in
                    self.fallbackBrowsers.append(browser)
                }
            }
        }
    }
    
    func stopTypeSearch() {
        debugLog("[BonjourDiscoveryV2] Stopping service type discovery.")
        typeBrowser?.stop()
        typeBrowser = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        for b in fallbackBrowsers {
            b.cancel()
        }
        fallbackBrowsers.removeAll()
        isSearching = false
    }
    
    // MARK: - Instance Discovery
    
    func discoverInstances(ofType type: String, inDomain domain: String) {
        let domainWithDot = domain.hasSuffix(".") ? domain : domain + "."
        let typeWithoutDot = type.hasSuffix(".") ? String(type.dropLast()) : type
        
        debugLog("[BonjourDiscoveryV2] Starting instance discovery for '\(typeWithoutDot)' in '\(domainWithDot)'...")
        stopInstanceSearch()
        discoveredInstances.removeAll()
        instances.removeAll()
        isSearching = true
        
        let descriptor = NWBrowser.Descriptor.bonjour(type: typeWithoutDot, domain: domainWithDot)
        let parameters = typeWithoutDot.contains("_tcp") ? NWParameters.tcp : NWParameters.udp
        parameters.includePeerToPeer = true
        
        let browser = NWBrowser(for: descriptor, using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleInstanceResults(results, forType: type, domain: domain)
        }
        
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in
                    self?.isSearching = false
                }
            }
        }
        
        instanceBrowser = browser
        browser.start(queue: .global(qos: .userInitiated))
    }
    
    private func handleInstanceResults(_ results: Set<NWBrowser.Result>, forType type: String, domain: String) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            var newInstances: [DiscoveredServiceV2] = []
            for result in results {
                if case .service(let name, _, _, _) = result.endpoint {
                    let discovered = DiscoveredServiceV2(
                        name: name,
                        type: type,
                        domain: domain,
                        result: result
                    )
                    newInstances.append(discovered)
                }
            }
            
            self.instances = newInstances
            self.isSearching = false
        }
    }
    
    func stopInstanceSearch() {
        debugLog("[BonjourDiscoveryV2] Stopping instance discovery.")
        instanceBrowser?.cancel()
        instanceBrowser = nil
        isSearching = false
    }
    
    // MARK: - Service Resolution
    
    func resolveService(_ service: DiscoveredServiceV2) {
        debugLog("[BonjourDiscoveryV2] Resolving service '\(service.name)'...")
        activeConnection?.cancel()
        resolvedService = nil
        resolveError = nil
        isSearching = true
        
        // Parse TXT records from browser result metadata
        var txtRecords: [(key: String, value: String)] = []
        if case .bonjour(let txtRecord) = service.result.metadata {
            let dict = txtRecord.dictionary
            for (key, value) in dict {
                txtRecords.append((key: key, value: value))
            }
            txtRecords.sort { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        }
        
        // We establish a dummy TCP connection to resolve the IP addresses and port.
        // It will complete the DNS resolution process and give us the endpoint info without needing to authenticate.
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        
        let connection = NWConnection(to: service.result.endpoint, using: parameters)
        activeConnection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            debugLog("[BonjourDiscoveryV2] Resolution connection state: \(state)")
            
            switch state {
            case .ready, .waiting:
                // If ready or waiting, we copy the resolved endpoint details
                if let path = connection.currentPath,
                   let remote = path.remoteEndpoint,
                   case .hostPort(let host, let port) = remote {
                    
                    let resolvedHost = "\(host)"
                    let portVal = port.rawValue
                    debugLog("[BonjourDiscoveryV2] Resolved endpoint: \(resolvedHost):\(portVal)")
                    
                    // Cancel connection immediately as we only needed the resolution info
                    connection.cancel()
                    self.activeConnection = nil
                    
                    let addresses = Self.resolveHostToIPs(resolvedHost)
                    
                    Task { @MainActor in
                        self.resolvedService = ResolvedServiceInfoV2(
                            name: service.name,
                            type: service.type,
                            domain: service.domain,
                            hostname: resolvedHost,
                            port: portVal,
                            addresses: addresses,
                            txtRecords: txtRecords
                        )
                        self.isSearching = false
                    }
                }
            case .failed(let error):
                debugLog("[BonjourDiscoveryV2] Resolution failed: \(error)")
                connection.cancel()
                self.activeConnection = nil
                Task { @MainActor in
                    self.resolveError = "Resolution failed: \(error.localizedDescription)"
                    self.isSearching = false
                }
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    func stopResolving() {
        debugLog("[BonjourDiscoveryV2] Stopping service resolution.")
        activeConnection?.cancel()
        activeConnection = nil
        isSearching = false
    }
    
    // MARK: - Stop All
    
    func stopAll() {
        stopDomainSearch()
        stopTypeSearch()
        stopInstanceSearch()
        stopResolving()
    }
    
    // MARK: - Helpers
    
    static func friendlyName(for rawType: String) -> String? {
        let normalized = rawType.hasSuffix(".") ? rawType : rawType + "."
        return commonKnownServiceTypes[normalized]
    }
    
    private static func resolveHostToIPs(_ host: String) -> [String] {
        var addresses: [String] = []
        var results: UnsafeMutablePointer<addrinfo>?
        
        let rc = getaddrinfo(host, nil, nil, &results)
        if rc == 0, let firstAddr = results {
            var ptr: UnsafeMutablePointer<addrinfo>? = firstAddr
            while ptr != nil {
                if let addr = ptr?.pointee {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let saLen = socklen_t(addr.ai_addrlen)
                    let nameInfoResult = getnameinfo(
                        addr.ai_addr,
                        saLen,
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if nameInfoResult == 0 {
                        let ipStr = String(cString: hostname)
                        if !ipStr.isEmpty && !addresses.contains(ipStr) {
                            addresses.append(ipStr)
                        }
                    }
                }
                ptr = ptr?.pointee.ai_next
            }
            freeaddrinfo(results)
        }
        return addresses
    }
}


// MARK: - NetServiceBrowserDelegate (For dynamic service type meta-query)

extension BonjourDiscoveryManagerV2: NetServiceBrowserDelegate {
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        debugLog("[BonjourDiscoveryV2] NetServiceBrowser didFind: name='\(service.name)', type='\(service.type)'")
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            let fullType = "\(service.name).\(service.type)"
                .replacingOccurrences(of: "..", with: ".")
            let normalized = fullType.hasSuffix(".") ? fullType : fullType + "."
            
            if self.discoveredTypes.insert(normalized).inserted {
                debugLog("[BonjourDiscoveryV2] NetServiceBrowser found new service type: \(normalized)")
                let info = ServiceTypeInfoV2(
                    rawType: normalized,
                    friendlyName: Self.friendlyName(for: normalized)
                )
                self.serviceTypes.append(info)
                self.serviceTypes.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            }
            
            if !moreComing {
                self.isSearching = false
            }
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        debugLog("[BonjourDiscoveryV2] NetServiceBrowser didNotSearch: \(errorDict)")
    }
}

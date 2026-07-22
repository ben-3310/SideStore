//
//  CertificateTypes.swift
//  AltStore
//
//  Created by Magesh K on 2026-07-03.
//  Copyright © 2026 ben4Store. All rights reserved.
//

import AltSign

enum SortOption: String, CaseIterable, Identifiable {
    case creationDate = "Creation Date"
    case expiryDate   = "Expiry Date"
    case name         = "Name"
    case keys         = "Keys"
    var id: String { rawValue }
}

enum GroupOption: String, CaseIterable, Identifiable {
    case none         = "None"
    case creationDate = "Creation Date"
    case expiryDate   = "Expiry Date"
    case name         = "Name"
    case keys         = "Keys"
    var id: String { rawValue }
}

enum FileImportMode {
    case certificate
    case privateKey
}

struct KeyTextImportItem: Identifiable {
    let id: String
    let cert: ALTCertificate
}

struct GroupedCertificates: Identifiable {
    var id: String { name }
    let name: String
    let certificates: [ALTCertificate]
}

extension ALTCertificate: @retroactive Identifiable {
    public var id: String { serialNumber }
}

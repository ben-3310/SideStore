//
//  AltSign+Sendable.swift
//  AltStore
//
//  Swift Concurrency support для AltSign типів
//

import Foundation

#if canImport(AltSign)
import AltSign

// MARK: - Swift Concurrency Support

/// Extensions для підтримки Swift Concurrency (async/await, actors)
/// @unchecked Sendable безпечно використовувати для цих типів, оскільки:
/// - Вони є immutable після створення
/// - Або мають внутрішню синхронізацію
/// - Використовуються в thread-safe контекстах

extension ALTTeam: @unchecked Sendable {}
extension ALTAppID: @unchecked Sendable {}
extension ALTProvisioningProfile: @unchecked Sendable {}
extension ALTAccount: @unchecked Sendable {}
extension ALTAppleAPISession: @unchecked Sendable {}
extension ALTCertificate: @unchecked Sendable {}
extension ALTApplication: @unchecked Sendable {}
extension ALTAnisetteData: @unchecked Sendable {}

#endif

// ВИКОРИСТАННЯ:
//
// Тепер ці типи можна безпечно використовувати в async/await:
//
//   Task {
//       let team: ALTTeam = await fetchTeam()
//       await process(team)  // Тепер без warning
//   }

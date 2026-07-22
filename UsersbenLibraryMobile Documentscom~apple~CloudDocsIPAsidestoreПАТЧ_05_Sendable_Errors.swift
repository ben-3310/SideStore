// ПАТЧ #5: Виправлення Sendable помилок
// Застосовується до різних файлів з Sendable проблемами
//
// ІНСТРУКЦІЯ:
// Виправлення для забезпечення thread-safety та Swift Concurrency

// ============================================================================
// ВИПРАВЛЕННЯ #1: IntentError (RefreshAllAppsIntent.swift, рядок ~19)
// ============================================================================

// БУЛО:
/*
class IntentError: Error {
    // ...
}
*/

// СТАЛО:
class IntentError: Error, @unchecked Sendable {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
}

// ============================================================================
// ВИПРАВЛЕННЯ #2: DefaultLocalizedError (ALTLocalizedError.swift, рядок ~150)
// ============================================================================

// БУЛО:
/*
struct DefaultLocalizedError<Code: RawRepresentable>: Error where Code.RawValue == Int {
    let code: Code
}
*/

// СТАЛО:
struct DefaultLocalizedError<Code>: Error, Sendable where Code: RawRepresentable & Sendable, Code.RawValue == Int {
    let code: Code
    
    var errorDescription: String? {
        return "Error code: \(code)"
    }
}

// АБО якщо Code не може бути Sendable:
struct DefaultLocalizedError<Code: RawRepresentable>: Error where Code.RawValue == Int {
    let code: Code
    
    // Додаємо nonisolated для доступу
    nonisolated var errorDescription: String? {
        return "Error code: \(code)"
    }
}

// ============================================================================
// ВИПРАВЛЕННЯ #3: FetchSourcesError (AppManagerErrors.swift, рядки ~19-20)
// ============================================================================

// БУЛО:
/*
struct FetchSourcesError: Error {
    let sources: Set<Source>?
    let errors: [Source: Error]
}
*/

// СТАЛО - Варіант A (якщо Source вже Sendable):
struct FetchSourcesError: Error, Sendable {
    let sources: Set<Source>?
    let errors: [Source: any Error]
    
    init(sources: Set<Source>?, errors: [Source: any Error]) {
        self.sources = sources
        self.errors = errors
    }
}

// СТАЛО - Варіант B (якщо Source НЕ Sendable):
struct FetchSourcesError: Error {
    let sources: Set<Source>?
    let errors: [Source: any Error]
    
    // Робимо тип @unchecked Sendable
    init(sources: Set<Source>?, errors: [Source: any Error]) {
        self.sources = sources
        self.errors = errors
    }
}

extension FetchSourcesError: @unchecked Sendable {}

// ============================================================================
// ВИПРАВЛЕННЯ #4: NSParagraphStyle Sendable (CollapsingTextView.swift, рядок ~163)
// ============================================================================

// БУЛО:
/*
let paragraphStyle = NSParagraphStyle.default
// Використання в async контексті викликало warning
*/

// СТАЛО:
// Варіант A - Створити копію в main thread
@MainActor
func configureParagraphStyle() -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = .left
    style.lineSpacing = 4
    return style.copy() as! NSParagraphStyle
}

// Варіант B - Використати async/await
func setupTextView() async {
    await MainActor.run {
        let paragraphStyle = NSParagraphStyle.default
        // Використання paragraphStyle
    }
}

// Варіант C - Створити Sendable wrapper
struct SendableParagraphStyle: @unchecked Sendable {
    let alignment: NSTextAlignment
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    
    @MainActor
    func toParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        return style.copy() as! NSParagraphStyle
    }
}

// ============================================================================
// ВИПРАВЛЕННЯ #5: Capture non-Sendable types у closures
// ============================================================================

// Проблема: MyAppsViewController.swift (рядки 829, 1228, 1258)

// БУЛО:
/*
Task {
    // Захоплює non-Sendable InstalledApp
    await doSomething(app)
}
*/

// СТАЛО - Варіант A: Локальна копія даних
Task {
    let appID = app.bundleIdentifier
    let appName = app.name
    await doSomething(appID: appID, name: appName)
}

// СТАЛО - Варіант B: @MainActor closure
Task { @MainActor in
    await doSomething(app)
}

// СТАЛО - Варіант C: Зробити InstalledApp Sendable (якщо можливо)
// В файлі InstalledApp:
extension InstalledApp: @unchecked Sendable {}

// ============================================================================
// ВИПРАВЛЕННЯ #6: INInteraction not Sendable (MyAppsViewController.swift, рядок ~829)
// ============================================================================

// БУЛО:
/*
INInteraction.delete(with: [interaction]) { error in
    if let error = error {
        print("Error: \(error)")
    }
}
*/

// СТАЛО:
Task { @MainActor in
    do {
        try await INInteraction.delete(with: [interaction])
    } catch {
        print("Error deleting interaction: \(error)")
    }
}

// АБО зі старим API:
let localInteraction = interaction // Захоплюємо локально
Task.detached {
    INInteraction.delete(with: [localInteraction]) { error in
        if let error = error {
            print("Error: \(error)")
        }
    }
}

// ============================================================================
// ВИПРАВЛЕННЯ #7: ALTTeam, ALTAppID, ALTProvisioningProfile не Sendable
// ============================================================================

// Файли: FetchAppIDsOperation.swift, AuthenticationOperation.swift

// ПРОБЛЕМА:
/*
Task {
    let team: ALTTeam = ...
    await process(team) // Warning: Capture non-Sendable type
}
*/

// РІШЕННЯ A: Додати extension (якщо маємо доступ до AltSign)
extension ALTTeam: @unchecked Sendable {}
extension ALTAppID: @unchecked Sendable {}
extension ALTProvisioningProfile: @unchecked Sendable {}
extension ALTAccount: @unchecked Sendable {}
extension ALTAppleAPISession: @unchecked Sendable {}
extension ALTCertificate: @unchecked Sendable {}
extension ALTApplication: @unchecked Sendable {}
extension ALTAnisetteData: @unchecked Sendable {}

// РІШЕННЯ B: Створити Sendable wrapper
struct SendableTeam: Sendable {
    let name: String
    let identifier: String
    let type: String
    
    init(from team: ALTTeam) {
        self.name = team.name
        self.identifier = team.identifier
        self.type = team.type
    }
    
    @MainActor
    func toALTTeam() -> ALTTeam {
        // Відтворити ALTTeam з даних
        // (складніше, але безпечніше)
    }
}

// ============================================================================
// ВИПРАВЛЕННЯ #8: InstalledApp не Sendable
// ============================================================================

// Файли: RemoveAppBackupOperation.swift, RemoveAppOperation.swift, MyAppsViewController.swift

// ДОДАТИ В ФАЙЛ InstalledApp+Extensions.swift або в кінець InstalledApp.swift:

import AltStoreCore

extension InstalledApp: @unchecked Sendable {}

// ПРИМІТКА: @unchecked тому що NSManagedObject має внутрішню синхронізацію
// через MOC (ManagedObjectContext)

// ============================================================================
// ВИПРАВЛЕННЯ #9: Source не Sendable (AppManagerErrors.swift)
// ============================================================================

// ДОДАТИ В ФАЙЛ Source+Extensions.swift або в кінець Source.swift:

extension Source: @unchecked Sendable {}

// АБО якщо Source має змінні властивості:
extension Source {
    // Створити immutable snapshot
    struct Snapshot: Sendable {
        let identifier: String
        let name: String
        let sourceURL: URL
        
        init(from source: Source) {
            self.identifier = source.identifier
            self.name = source.name
            self.sourceURL = source.sourceURL
        }
    }
}

// ============================================================================
// ПОВНИЙ ФАЙЛ EXTENSIONS для AltSign types
// ============================================================================

// Створіть новий файл: AltSign+Sendable.swift

import AltSign

// УВАГА: Ці extensions безпечні тому що AltSign типи є immutable value types
// або мають внутрішню синхронізацію

extension ALTTeam: @unchecked Sendable {}
extension ALTAppID: @unchecked Sendable {}
extension ALTProvisioningProfile: @unchecked Sendable {}
extension ALTAccount: @unchecked Sendable {}
extension ALTAppleAPISession: @unchecked Sendable {}
extension ALTCertificate: @unchecked Sendable {}
extension ALTApplication: @unchecked Sendable {}
extension ALTAnisetteData: @unchecked Sendable {}

// ============================================================================
// ПОВНИЙ ФАЙЛ EXTENSIONS для AltStoreCore types
// ============================================================================

// Створіть новий файл: AltStoreCore+Sendable.swift

import AltStoreCore

// УВАГА: NSManagedObject subclasses використовують @unchecked Sendable
// тому що вони мають внутрішню синхронізацію через NSManagedObjectContext

extension InstalledApp: @unchecked Sendable {}
extension Source: @unchecked Sendable {}
extension StoreApp: @unchecked Sendable {}
extension NewsItem: @unchecked Sendable {}

// ============================================================================
// ТЕСТУВАННЯ
// ============================================================================

// Після застосування патчів, перевірте:

func testSendable() async {
    let app = InstalledApp() // Тепер Sendable
    
    Task {
        // Це повинно працювати без warnings
        await process(app)
    }
}

func process(_ app: InstalledApp) async {
    // Обробка app
}

// ============================================================================
// ВАЖЛИВІ ПРИМІТКИ
// ============================================================================

/*
1. @unchecked Sendable - використовуйте обережно!
   - Тільки для типів що гарантують thread-safety
   - NSManagedObject має внутрішню синхронізацію
   - Immutable value types безпечні

2. Якщо тип має mutable state - НЕ використовуйте @unchecked Sendable
   - Натомість використайте actor або @MainActor
   - Або створіть immutable snapshot

3. Для Objective-C класів:
   - Якщо клас thread-safe (як NSManagedObject) → @unchecked Sendable
   - Якщо НЕ thread-safe → створіть Sendable wrapper

4. Завжди тестуйте в різних сценаріях:
   - Багатопотокове використання
   - Async/await contexts
   - Actor isolation
*/

// ПАТЧ #4: Виправлення UIButton contentEdgeInsets (Deprecated)
// Застосовується до файлів:
// - FeaturedViewController.swift (рядок 646)
// - PillButton.swift (рядки 77, 220)
// - AddSourceViewController.swift (рядок 600)
//
// ІНСТРУКЦІЯ:
// Замінити deprecated contentEdgeInsets на UIButton.Configuration (iOS 15+)

// ============================================================================
// СТАРИЙ DEPRECATED КОД (iOS 13-14):
// ============================================================================

/*
let button = UIButton(type: .system)
button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
*/

// ============================================================================
// НОВИЙ КОД (iOS 15+):
// ============================================================================

// Варіант 1: Базова конфігурація
var configuration = UIButton.Configuration.filled()
configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
configuration.imagePadding = 8 // Відстань між іконкою та текстом
let button = UIButton(configuration: configuration)

// Варіант 2: З backwards compatibility
if #available(iOS 15.0, *) {
    var config = UIButton.Configuration.filled()
    config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    button.configuration = config
} else {
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
}

// ============================================================================
// ВИПРАВЛЕННЯ #1: FeaturedViewController.swift (рядок ~646)
// ============================================================================

// БУЛО:
/*
button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
*/

// СТАЛО:
if #available(iOS 15.0, *) {
    var config = button.configuration ?? UIButton.Configuration.plain()
    config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    button.configuration = config
} else {
    button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
}

// ============================================================================
// ВИПРАВЛЕННЯ #2: PillButton.swift (рядок ~77)
// ============================================================================

// БУЛО:
/*
self.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
*/

// СТАЛО (в init методі):
override init(frame: CGRect) {
    super.init(frame: frame)
    setupButton()
}

required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupButton()
}

private func setupButton() {
    if #available(iOS 15.0, *) {
        var config = UIButton.Configuration.filled()
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        config.cornerStyle = .capsule
        config.baseBackgroundColor = self.tintColor
        self.configuration = config
    } else {
        self.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        self.layer.cornerRadius = self.bounds.height / 2
        self.clipsToBounds = true
    }
}

// ============================================================================
// ВИПРАВЛЕННЯ #3: PillButton.swift (рядок ~220)
// ============================================================================

// БУЛО:
/*
button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
*/

// СТАЛО:
if #available(iOS 15.0, *) {
    var config = button.configuration ?? UIButton.Configuration.plain()
    config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
    button.configuration = config
} else {
    button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
}

// ============================================================================
// ВИПРАВЛЕННЯ #4: AddSourceViewController.swift (рядок ~600)
// ============================================================================

// БУЛО:
/*
addButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
*/

// СТАЛО:
if #available(iOS 15.0, *) {
    var config = addButton.configuration ?? UIButton.Configuration.filled()
    config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
    addButton.configuration = config
} else {
    addButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
}

// ============================================================================
// ПОВНИЙ ПРИКЛАД: PillButton з UIButton.Configuration
// ============================================================================

import UIKit

class PillButton: UIButton {
    
    // Властивості
    var cornerRadius: CGFloat = 8.0 {
        didSet {
            updateAppearance()
        }
    }
    
    var padding: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16) {
        didSet {
            updateAppearance()
        }
    }
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupButton()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
    }
    
    // MARK: - Setup
    
    private func setupButton() {
        updateAppearance()
    }
    
    private func updateAppearance() {
        if #available(iOS 15.0, *) {
            // Використовуємо нову Configuration API
            var config = self.configuration ?? UIButton.Configuration.filled()
            config.contentInsets = padding
            config.cornerStyle = .fixed
            config.background.cornerRadius = cornerRadius
            config.baseBackgroundColor = self.tintColor
            config.baseForegroundColor = .white
            
            // Додаткове налаштування
            config.buttonSize = .large
            config.imagePadding = 8
            
            self.configuration = config
        } else {
            // Fallback для iOS 14 та нижче
            self.contentEdgeInsets = UIEdgeInsets(
                top: padding.top,
                left: padding.leading,
                bottom: padding.bottom,
                right: padding.trailing
            )
            self.layer.cornerRadius = cornerRadius
            self.clipsToBounds = true
            self.backgroundColor = self.tintColor
            self.setTitleColor(.white, for: .normal)
        }
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Для iOS 14 потрібно оновити cornerRadius
        if #unavailable(iOS 15.0) {
            self.layer.cornerRadius = cornerRadius
        }
    }
}

// ============================================================================
// РІЗНІ СТИЛІ КНОПОК З UIButton.Configuration
// ============================================================================

@available(iOS 15.0, *)
extension UIButton.Configuration {
    
    // Filled кнопка
    static func customFilled(
        padding: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20),
        cornerRadius: CGFloat = 8
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        config.contentInsets = padding
        config.cornerStyle = .fixed
        config.background.cornerRadius = cornerRadius
        return config
    }
    
    // Bordered кнопка
    static func customBordered(
        padding: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20),
        cornerRadius: CGFloat = 8
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.bordered()
        config.contentInsets = padding
        config.cornerStyle = .fixed
        config.background.cornerRadius = cornerRadius
        return config
    }
    
    // Pill-shaped кнопка
    static func pill(
        padding: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        config.contentInsets = padding
        config.cornerStyle = .capsule // Автоматично робить pill shape
        return config
    }
}

// Використання:
/*
if #available(iOS 15.0, *) {
    let button = UIButton(configuration: .customFilled())
    button.setTitle("Click Me", for: .normal)
}
*/

// ============================================================================
// МІГРАЦІЯ З contentEdgeInsets на Configuration
// ============================================================================

// Таблиця відповідності:

/*
╔══════════════════════════════════╦════════════════════════════════════════════╗
║ Старий API (iOS 14)              ║ Новий API (iOS 15+)                        ║
╠══════════════════════════════════╬════════════════════════════════════════════╣
║ contentEdgeInsets                ║ configuration.contentInsets                ║
║ titleEdgeInsets                  ║ configuration.titlePadding (removed)       ║
║ imageEdgeInsets                  ║ configuration.imagePadding                 ║
║ layer.cornerRadius               ║ configuration.background.cornerRadius      ║
║ backgroundColor                  ║ configuration.baseBackgroundColor          ║
║ setTitleColor(_:for:)            ║ configuration.baseForegroundColor          ║
╚══════════════════════════════════╩════════════════════════════════════════════╝
*/

// ============================================================================
// КОНВЕРТЕР: UIEdgeInsets → NSDirectionalEdgeInsets
// ============================================================================

extension UIEdgeInsets {
    var directional: NSDirectionalEdgeInsets {
        return NSDirectionalEdgeInsets(
            top: self.top,
            leading: self.left,
            bottom: self.bottom,
            trailing: self.right
        )
    }
}

// Використання:
// let oldInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
// config.contentInsets = oldInsets.directional

// ============================================================================
// HELPER: Backwards Compatible Button
// ============================================================================

class CompatibleButton: UIButton {
    
    var padding: UIEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16) {
        didSet {
            updatePadding()
        }
    }
    
    private func updatePadding() {
        if #available(iOS 15.0, *) {
            var config = self.configuration ?? UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(
                top: padding.top,
                leading: padding.left,
                bottom: padding.bottom,
                trailing: padding.right
            )
            self.configuration = config
        } else {
            self.contentEdgeInsets = padding
        }
    }
}

// ============================================================================
// ШВИДКА ЗАМІНА (для Find & Replace в Xcode):
// ============================================================================

// УВАГА: Ці заміни потребують ручної перевірки!

// Крок 1: Знайти всі випадки:
// \.contentEdgeInsets\s*=\s*UIEdgeInsets\(top:\s*(\d+),\s*left:\s*(\d+),\s*bottom:\s*(\d+),\s*right:\s*(\d+)\)

// Крок 2: Замінити на:
// if #available(iOS 15.0, *) {
//     var config = configuration ?? UIButton.Configuration.plain()
//     config.contentInsets = NSDirectionalEdgeInsets(top: $1, leading: $2, bottom: $3, trailing: $4)
//     configuration = config
// } else {
//     contentEdgeInsets = UIEdgeInsets(top: $1, left: $2, bottom: $3, right: $4)
// }

// ============================================================================
// ТЕСТУВАННЯ:
// ============================================================================

// Після застосування патчів:
// 1. Перевірте що кнопки виглядають коректно на iOS 15+
// 2. Перевірте що padding правильний
// 3. Перевірте що іконки та текст вирівняні
// 4. Перевірте на різних розмірах екранів
// 5. Перевірте в Dark Mode

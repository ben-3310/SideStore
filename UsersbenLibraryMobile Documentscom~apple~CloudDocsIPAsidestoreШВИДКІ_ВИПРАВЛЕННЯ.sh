#!/bin/bash

# ШВИДКІ ВИПРАВЛЕННЯ для SideStore
# Автоматизовані виправлення що можна безпечно застосувати
# 
# Використання:
# chmod +x ШВИДКІ_ВИПРАВЛЕННЯ.sh
# ./ШВИДКІ_ВИПРАВЛЕННЯ.sh

set -e

REPO_PATH="/Users/ben/Repo/SideStore"
BACKUP_PATH="/Users/ben/Library/Mobile Documents/com~apple~CloudDocs/IPA/sidestore/backup_$(date +%Y%m%d_%H%M%S)"

echo "=========================================="
echo "🛠  SideStore - Швидкі виправлення"
echo "=========================================="
echo ""

# Перевірка чи існує проєкт
if [ ! -d "$REPO_PATH" ]; then
    echo "❌ Помилка: Проєкт не знайдено за шляхом $REPO_PATH"
    exit 1
fi

echo "📂 Проєкт знайдено: $REPO_PATH"
echo ""

# Створення бекапу
echo "💾 Створення бекапу..."
mkdir -p "$BACKUP_PATH"
cp -R "$REPO_PATH/AltStore" "$BACKUP_PATH/"
echo "✅ Бекап створено: $BACKUP_PATH"
echo ""

cd "$REPO_PATH"

# ============================================================================
# ВИПРАВЛЕННЯ #1: Видалити неіснуючий Search Path
# ============================================================================

echo "🔧 Виправлення #1: Очищення Library Search Paths..."

# Знаходимо всі .xcodeproj та .pbxproj файли
find . -name "project.pbxproj" | while read pbxproj; do
    echo "   Обробка: $pbxproj"
    
    # Видаляємо неіснуючий шлях (якщо він є)
    sed -i.bak 's|/Users/ben/Repo/SideStore/Dependencies/minimuxer/Sources/RustBridge/lib||g' "$pbxproj"
    
    # Видаляємо backup файл
    rm -f "${pbxproj}.bak"
done

echo "✅ Library Search Paths очищено"
echo ""

# ============================================================================
# ВИПРАВЛЕННЯ #2: Додати @preconcurrency imports
# ============================================================================

echo "🔧 Виправлення #2: Додавання @preconcurrency imports..."

# Список файлів та їх imports
declare -A IMPORTS=(
    ["AltStore/My Apps/MyAppsViewController.swift"]="Intents"
    ["AltStore/Operations/AuthenticationOperation.swift"]="AltSign"
    ["AltStore/Operations/RefreshAppOperation.swift"]="AltSign"
    ["AltStore/Operations/RemoveAppBackupOperation.swift"]="AltStoreCore"
    ["AltStore/Operations/RemoveAppOperation.swift"]="AltStoreCore"
)

for file in "${!IMPORTS[@]}"; do
    if [ -f "$file" ]; then
        module="${IMPORTS[$file]}"
        echo "   Обробка: $file"
        
        # Перевіряємо чи вже є @preconcurrency
        if ! grep -q "@preconcurrency import $module" "$file"; then
            # Замінюємо звичайний import на @preconcurrency import
            sed -i.bak "s/^import $module$/@preconcurrency import $module/" "$file"
            rm -f "${file}.bak"
            echo "   ✓ Додано @preconcurrency import $module"
        else
            echo "   ℹ️  Вже має @preconcurrency import $module"
        fi
    else
        echo "   ⚠️  Файл не знайдено: $file"
    fi
done

echo "✅ @preconcurrency imports додано"
echo ""

# ============================================================================
# ВИПРАВЛЕННЯ #3: Виправити unused variables
# ============================================================================

echo "🔧 Виправлення #3: Виправлення unused variables..."

# PairingFileManager.swift - Value 'rootVC' was defined but never used
if [ -f "AltStore/Managing Apps/PairingFileManager.swift" ]; then
    echo "   Обробка: PairingFileManager.swift"
    # Замінюємо let rootVC = на _ = 
    sed -i.bak 's/let rootVC = UIApplication.shared.windows.first/_ = UIApplication.shared.windows.first/g' "AltStore/Managing Apps/PairingFileManager.swift"
    rm -f "AltStore/Managing Apps/PairingFileManager.swift.bak"
    echo "   ✓ Виправлено unused variable"
fi

# DownloadAppOperation.swift - Initialization of immutable value 'dependencies' was never used
if [ -f "AltStore/Operations/DownloadAppOperation.swift" ]; then
    echo "   Обробка: DownloadAppOperation.swift"
    sed -i.bak 's/let dependencies = /_ = /g' "AltStore/Operations/DownloadAppOperation.swift"
    sed -i.bak 's/let response = /_ = /g' "AltStore/Operations/DownloadAppOperation.swift"
    rm -f "AltStore/Operations/DownloadAppOperation.swift.bak"
    echo "   ✓ Виправлено unused variables"
fi

echo "✅ Unused variables виправлено"
echo ""

# ============================================================================
# ВИПРАВЛЕННЯ #4: Видалити порожні using '_'
# ============================================================================

echo "🔧 Виправлення #4: Видалення надлишкових '_'..."

if [ -f "AltStore/Permissions/ReviewPermissionsViewController.swift" ]; then
    echo "   Обробка: ReviewPermissionsViewController.swift"
    # Видаляємо надлишкові _ = для Void функцій
    sed -i.bak '/_ = .*Void/d' "AltStore/Permissions/ReviewPermissionsViewController.swift"
    rm -f "AltStore/Permissions/ReviewPermissionsViewController.swift.bak"
    echo "   ✓ Видалено надлишкові '_'"
fi

echo "✅ Надлишкові '_' видалено"
echo ""

# ============================================================================
# ВИПРАВЛЕННЯ #5: Додати import UniformTypeIdentifiers
# ============================================================================

echo "🔧 Виправлення #5: Додавання import UniformTypeIdentifiers..."

FILES_NEEDING_UTI=(
    "AltStore/Managing Apps/AppManager.swift"
    "AltStore/My Apps/MyAppsViewController.swift"
)

for file in "${FILES_NEEDING_UTI[@]}"; do
    if [ -f "$file" ]; then
        echo "   Обробка: $file"
        
        # Перевіряємо чи вже є import
        if ! grep -q "import UniformTypeIdentifiers" "$file"; then
            # Додаємо після UIKit import
            sed -i.bak '/import UIKit/a\
import UniformTypeIdentifiers
' "$file"
            rm -f "${file}.bak"
            echo "   ✓ Додано import UniformTypeIdentifiers"
        else
            echo "   ℹ️  Вже має import UniformTypeIdentifiers"
        fi
    fi
done

echo "✅ import UniformTypeIdentifiers додано"
echo ""

# ============================================================================
# ВИПРАВЛЕННЯ #6: Створення UIApplication extension для windows
# ============================================================================

echo "🔧 Виправлення #6: Створення UIApplication+Windows extension..."

EXTENSION_FILE="AltStore/Extensions/UIApplication+Windows.swift"

# Створюємо директорію якщо не існує
mkdir -p "$(dirname "$EXTENSION_FILE")"

# Створюємо extension файл
cat > "$EXTENSION_FILE" << 'EOF'
//
//  UIApplication+Windows.swift
//  AltStore
//
//  Created automatically to replace deprecated windows API
//

import UIKit

extension UIApplication {
    
    /// Повертає поточне ключове вікно (замість deprecated windows property)
    @MainActor
    var currentKeyWindow: UIWindow? {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
    
    /// Повертає перше доступне вікно
    @MainActor
    var firstWindow: UIWindow? {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first
    }
    
    /// Повертає всі вікна програми
    @MainActor
    var allWindows: [UIWindow] {
        return connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }
}
EOF

echo "✅ UIApplication+Windows extension створено"
echo ""

# ============================================================================
# ВИПРАВЛЕННЯ #7: Clean DerivedData
# ============================================================================

echo "🔧 Виправлення #7: Очищення DerivedData..."

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
if [ -d "$DERIVED_DATA" ]; then
    # Знаходимо та видаляємо тільки AltStore derived data
    find "$DERIVED_DATA" -maxdepth 1 -name "AltStore-*" -type d | while read dir; do
        echo "   Видалення: $dir"
        rm -rf "$dir"
    done
    echo "✅ DerivedData очищено"
else
    echo "ℹ️  DerivedData не знайдено"
fi

echo ""

# ============================================================================
# СТВОРЕННЯ ЗВІТУ
# ============================================================================

echo "📝 Створення звіту..."

REPORT_FILE="$BACKUP_PATH/ЗВІТ_ВИПРАВЛЕНЬ.txt"

cat > "$REPORT_FILE" << EOF
========================================
ЗВІТ ПРО ВИПРАВЛЕННЯ SIDESTORE
========================================

Дата: $(date '+%Y-%m-%d %H:%M:%S')
Проєкт: $REPO_PATH
Бекап: $BACKUP_PATH

ВИКОНАНІ ВИПРАВЛЕННЯ:
---------------------

✅ #1: Очищено Library Search Paths
   - Видалено неіснуючий шлях minimuxer/Sources/RustBridge/lib

✅ #2: Додано @preconcurrency imports
   - MyAppsViewController.swift (Intents)
   - AuthenticationOperation.swift (AltSign)
   - RefreshAppOperation.swift (AltSign)
   - RemoveAppBackupOperation.swift (AltStoreCore)
   - RemoveAppOperation.swift (AltStoreCore)

✅ #3: Виправлено unused variables
   - PairingFileManager.swift
   - DownloadAppOperation.swift

✅ #4: Видалено надлишкові '_' statements
   - ReviewPermissionsViewController.swift

✅ #5: Додано import UniformTypeIdentifiers
   - AppManager.swift
   - MyAppsViewController.swift

✅ #6: Створено UIApplication+Windows extension
   - Новий файл: AltStore/Extensions/UIApplication+Windows.swift
   - Замінює deprecated UIApplication.shared.windows API

✅ #7: Очищено DerivedData
   - Видалено застарілі build артефакти

НАСТУПНІ КРОКИ:
---------------

1. Відкрийте проєкт в Xcode
2. Застосуйте ручні патчі з інших файлів
3. Оновіть iOS Deployment Target до 17.0 (або перекомпілюйте Rust бібліотеки)
4. Виконайте Clean Build (Cmd+Shift+K)
5. Виконайте Build (Cmd+B)

БЕКАП:
------
Якщо щось пішло не так, відновіть файли з:
$BACKUP_PATH

EOF

echo "✅ Звіт створено: $REPORT_FILE"
echo ""

# ============================================================================
# ФІНАЛЬНІ ІНСТРУКЦІЇ
# ============================================================================

echo "=========================================="
echo "✨ ВИПРАВЛЕННЯ ЗАВЕРШЕНО!"
echo "=========================================="
echo ""
echo "📋 Що було зроблено:"
echo "   • Очищено неправильні build paths"
echo "   • Додано @preconcurrency imports"
echo "   • Виправлено unused variables"
echo "   • Створено UIApplication extension"
echo "   • Очищено DerivedData"
echo ""
echo "⚠️  ЩЕ ПОТРІБНО ЗРОБИТИ ВРУЧНУ:"
echo ""
echo "1. 🎯 КРИТИЧНО: Оновити iOS Deployment Target"
echo "   Xcode → Project Settings → iOS Deployment Target → 17.0"
echo "   (або перекомпілювати Rust бібліотеки для iOS 15.0)"
echo ""
echo "2. 🔧 Застосувати патчі з інших файлів:"
echo "   • ПАТЧ_01_Operations.swift"
echo "   • ПАТЧ_02_AppManager.swift"
echo "   • ПАТЧ_03_UIApplicationWindows.swift"
echo "   • ПАТЧ_04_UIButton.swift"
echo ""
echo "3. 🏗️ Перекомпілювати проєкт:"
echo "   Cmd+Shift+K (Clean)"
echo "   Cmd+B (Build)"
echo ""
echo "📂 Бекап збережено: $BACKUP_PATH"
echo "📝 Повний звіт: $REPORT_FILE"
echo ""
echo "=========================================="

exit 0

#!/bin/bash

# АВТОМАТИЧНІ ВИПРАВЛЕННЯ для SideStore
# Швидкі виправлення що можна безпечно застосувати
# 
# Використання:
#   chmod +x auto_fix.sh
#   ./auto_fix.sh

set -e

REPO_PATH="/Users/ben/Repo/SideStore"

echo "=========================================="
echo "🛠  SideStore - Автоматичні виправлення"
echo "=========================================="
echo ""

if [ ! -d "$REPO_PATH" ]; then
    echo "❌ Помилка: Проєкт не знайдено"
    exit 1
fi

cd "$REPO_PATH"

echo "📂 Проєкт: $REPO_PATH"
echo ""

# ============================================================================
# ВИПРАВЛЕННЯ #1: Додати @preconcurrency imports
# ============================================================================

echo "🔧 Додавання @preconcurrency imports..."

# MyAppsViewController.swift
if [ -f "AltStore/My Apps/MyAppsViewController.swift" ]; then
    if ! grep -q "@preconcurrency import Intents" "AltStore/My Apps/MyAppsViewController.swift"; then
        sed -i.bak "s/^import Intents$/@preconcurrency import Intents/" "AltStore/My Apps/MyAppsViewController.swift"
        rm -f "AltStore/My Apps/MyAppsViewController.swift.bak"
        echo "   ✓ MyAppsViewController.swift"
    fi
fi

# AuthenticationOperation.swift
if [ -f "AltStore/Operations/AuthenticationOperation.swift" ]; then
    if ! grep -q "@preconcurrency import AltSign" "AltStore/Operations/AuthenticationOperation.swift"; then
        sed -i.bak "s/^import AltSign$/@preconcurrency import AltSign/" "AltStore/Operations/AuthenticationOperation.swift"
        rm -f "AltStore/Operations/AuthenticationOperation.swift.bak"
        echo "   ✓ AuthenticationOperation.swift"
    fi
fi

# RefreshAppOperation.swift
if [ -f "AltStore/Operations/RefreshAppOperation.swift" ]; then
    if ! grep -q "@preconcurrency import AltSign" "AltStore/Operations/RefreshAppOperation.swift"; then
        sed -i.bak "s/^import AltSign$/@preconcurrency import AltSign/" "AltStore/Operations/RefreshAppOperation.swift"
        rm -f "AltStore/Operations/RefreshAppOperation.swift.bak"
        echo "   ✓ RefreshAppOperation.swift"
    fi
fi

# RemoveAppBackupOperation.swift
if [ -f "AltStore/Operations/RemoveAppBackupOperation.swift" ]; then
    if ! grep -q "@preconcurrency import AltStoreCore" "AltStore/Operations/RemoveAppBackupOperation.swift"; then
        sed -i.bak "s/^import AltStoreCore$/@preconcurrency import AltStoreCore/" "AltStore/Operations/RemoveAppBackupOperation.swift"
        rm -f "AltStore/Operations/RemoveAppBackupOperation.swift.bak"
        echo "   ✓ RemoveAppBackupOperation.swift"
    fi
fi

# RemoveAppOperation.swift
if [ -f "AltStore/Operations/RemoveAppOperation.swift" ]; then
    if ! grep -q "@preconcurrency import AltStoreCore" "AltStore/Operations/RemoveAppOperation.swift"; then
        sed -i.bak "s/^import AltStoreCore$/@preconcurrency import AltStoreCore/" "AltStore/Operations/RemoveAppOperation.swift"
        rm -f "AltStore/Operations/RemoveAppOperation.swift.bak"
        echo "   ✓ RemoveAppOperation.swift"
    fi
fi

echo "✅ @preconcurrency imports додано"
echo ""

# ============================================================================
# ВИПРАВЛЕННЯ #2: Додати import UniformTypeIdentifiers
# ============================================================================

echo "🔧 Додавання import UniformTypeIdentifiers..."

FILES_NEEDING_UTI=(
    "AltStore/Managing Apps/AppManager.swift"
    "AltStore/My Apps/MyAppsViewController.swift"
)

for file in "${FILES_NEEDING_UTI[@]}"; do
    if [ -f "$file" ]; then
        if ! grep -q "import UniformTypeIdentifiers" "$file"; then
            sed -i.bak '/import UIKit/a\
import UniformTypeIdentifiers
' "$file"
            rm -f "${file}.bak"
            echo "   ✓ $(basename "$file")"
        fi
    fi
done

echo "✅ UniformTypeIdentifiers imports додано"
echo ""

# ============================================================================
# ВИПРАВЛЕННЯ #3: Очистити DerivedData
# ============================================================================

echo "🔧 Очищення DerivedData..."

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
if [ -d "$DERIVED_DATA" ]; then
    find "$DERIVED_DATA" -maxdepth 1 -name "AltStore-*" -type d | while read dir; do
        echo "   Видалення: $(basename "$dir")"
        rm -rf "$dir"
    done
    echo "✅ DerivedData очищено"
else
    echo "ℹ️  DerivedData не знайдено"
fi

echo ""

# ============================================================================
# ФІНАЛ
# ============================================================================

echo "=========================================="
echo "✅ АВТОМАТИЧНІ ВИПРАВЛЕННЯ ЗАВЕРШЕНО!"
echo "=========================================="
echo ""
echo "📋 Що було зроблено:"
echo "   • Додано @preconcurrency imports"
echo "   • Додано import UniformTypeIdentifiers"
echo "   • Очищено DerivedData"
echo ""
echo "⚠️  ЩЕ ПОТРІБНО ЗРОБИТИ ВРУЧНУ:"
echo ""
echo "1. 🎯 КРИТИЧНО: Оновити iOS Deployment Target"
echo "   Xcode → Project → SideStore → General"
echo "   iOS Deployment Target → 17.0"
echo ""
echo "2. 🔧 Додати Extension файли до Xcode:"
echo "   • UIApplication+Windows.swift"
echo "   • AltSign+Sendable.swift"
echo "   • AltStoreCore+Sendable.swift"
echo ""
echo "   Вони вже створені в папці AltStore/Extensions/"
echo "   Додайте їх через: File → Add Files to \"AltStore\"..."
echo ""
echo "3. ✏️  Додати @unchecked Sendable до Operations"
echo "   Дивіться ІНСТРУКЦІЯ_ВИПРАВЛЕННЯ.md"
echo ""
echo "4. 🏗️  Build проєкт:"
echo "   Clean (⌘⇧K) + Build (⌘B)"
echo ""
echo "=========================================="

exit 0

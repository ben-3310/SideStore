# Дизайн устранения перечисленных предупреждений Xcode 27

**Дата:** 2026-07-22  
**Статус:** одобрено пользователем

## Цель

Устранить семь групп предупреждений из чистой Debug-сборки схемы `SideStore`
в Xcode 27.0, не меняя символьную ссылку `Dependencies` и её целевой каталог.

## Подтверждённые причины

1. Баннер `Update to recommended settings` вызван устаревшим
   `LastUpgradeCheck = 1020` при текущем Xcode 27.0.
2. В Debug и Release таргета SideStore остался путь к удалённому каталогу
   `Dependencies/minimuxer/Sources/RustBridge/lib`.
3. SideStore напрямую добавляет продукт OpenSSL в `Link Binary With Libraries`,
   хотя итоговый executable не использует его символы. При этом динамический
   `AltStoreCore.framework` зависит от OpenSSL, поэтому framework должен остаться
   в app bundle и быть явно помечен как необходимая runtime-зависимость.
4. `em_proxy-swift` объединяет готовый Rust-архив с Swift-обёрткой. Некоторые
   Rust object-файлы корректно не экспортируют глобальные символы, а Apple
   `libtool` по умолчанию сообщает о каждом из них.
5. Storyboard содержит устаревшее имя SF Symbol `terminal`, пустую и не
   используемую prototype-cell и явный `plain`-style у bar button item с
   custom view.

## Выбранное решение

### Настройки проекта

- Обновить только `LastUpgradeCheck` до `2700`, не выполнять широкую
  автоматическую миграцию всех build settings.
- Удалить устаревший `LIBRARY_SEARCH_PATHS` из Debug и Release SideStore.
- Сохранить продукт OpenSSL в `Link Binary With Libraries`, чтобы Swift Package
  продолжал автоматически встраивать framework, и добавить SideStore
  `-Xlinker -needed_framework -Xlinker OpenSSL`. Это семантически помечает
  OpenSSL как обязательную runtime-зависимость AltStoreCore вместо глобального
  подавления `unused dylib` warnings.
- Добавить `OTHER_LIBTOOLFLAGS = "-no_warning_for_no_symbols"` только в Debug и
  Release `em_proxy-swift`. Это штатный флаг Apple `libtool` и он не скрывает
  другие предупреждения линкера.

### Storyboards

- Заменить имя системного изображения `terminal` на `apple.terminal` как в
  `imageReference`, так и в декларации ресурса.
- Удалить пустую prototype-cell `W0l-zW-MjJ`: `AddSourceViewController`
  регистрирует все используемые cell-классы программно.
- Удалить только атрибут `style="plain"` у `FLf-DS-F77`, сохранив custom view и
  все его connections.

## Проверка

Сначала добавляются структурные regression-тесты, которые должны упасть на
текущем состоянии. После минимальных изменений выполняются:

1. выбранные Python regression-тесты;
2. полный `scripts/ci/test_xcode27_source_cleanup.py`;
3. чистая unsigned Debug-сборка `SideStore` для `generic/platform=iOS` в новом
   временном DerivedData;
4. поиск каждого исходного сообщения в `.xcactivitylog`.
5. проверка, что `OpenSSL.framework` присутствует в app bundle и остаётся в
   load commands SideStore и AltStoreCore.

Критерий готовности: сборка успешна, а все перечисленные пользователем
сообщения отсутствуют. Другие предупреждения внутри защищённых локальных
зависимостей не входят в эту миграцию и не должны маскироваться глобально.

## Ограничения

- Не изменять, не перемещать и не пересоздавать `Dependencies`.
- Не редактировать исходники или проекты в `SideStore_Dependencies`.
- Сохранить все несвязанные staged, unstaged и untracked изменения пользователя.
- Не менять deployment target, signing, entitlements и bundle identifiers.

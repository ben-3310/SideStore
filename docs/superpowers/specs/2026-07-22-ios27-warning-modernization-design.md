# Полировка SideStore для Xcode 27 и физического iPhone — дизайн

## Контекст

Целевая среда — установленный Xcode 27 beta и подключённый по кабелю физический iPhone 13 с iOS 27.0. Проект уже умеет выполнять подписанную сборку, один детерминированный UI launch smoke, установку и foreground-запуск на этом устройстве. Новый этап устраняет compile error и предупреждения, показанные Xcode, не меняя назначение приложения и не ослабляя проверки сборки.

Работа выполняется в ветке `agent/physical-device-launch`. Существующий незакоммиченный каталог `Dependencies/em_proxy/em_proxy.xcodeproj/xcuserdata/` принадлежит локальному Xcode и не входит в scope.

## Цели

- Проектный код и локальная зависимость `Dependencies/AltSign` собираются Xcode 27 без compiler warnings из согласованного списка и без новых warnings.
- Устаревшая генерация RSA переводится на высокоуровневый EVP API OpenSSL 3 без изменения формата CSR или приватного ключа.
- Устраняются ложные проверки типов, небезопасные associated-object keys, устаревшие UIKit API и неполные Swift 6 concurrency-аннотации.
- Чистая подписанная сборка, UI launch test, установка и запуск повторно подтверждаются на физическом iPhone 13/iOS 27.0.
- Изменения публикуются только в fork пользователя; upstream `SideStore/SideStore` не изменяется.

## Не-цели

- Не переписывать Roxas, Core Data или signing pipeline целиком.
- Не менять deployment target, bundle identifiers, entitlements приложения или пользовательские данные телефона.
- Не подавлять предупреждения глобально через `SWIFT_SUPPRESS_WARNINGS` или аналогичные флаги.
- Не редактировать содержимое `DerivedData` и SwiftPM checkout вручную.
- Не создавать и не поддерживать fork `ZIPFoundation` только ради предупреждения manifest-файла.

## Рассмотренные подходы

### 1. Подавление предупреждений

Минимальный diff, но скрывает будущие регрессии и оставляет deprecated API. Отклонено.

### 2. Только перечисленные строки

Низкий риск, но после clean build могут остаться связанные предупреждения build phases или новых проверок Xcode 27. Недостаточно для цели «максимально отполированный проект».

### 3. Полная полировка с проверяемым warning baseline

Выбранный подход: исправить first-party и локальный dependency source, устранить warnings проекта, строго контролировать единственное внешнее исключение и повторить physical-device flow.

## Технический дизайн

### AltSign

`ALTApplication.dumpMachOInfo()` остаётся публичным Objective-C-visible API, потому что вызывается из основного приложения. Метод будет вынесен из `private extension` в extension с подходящим уровнем доступа.

Логирование сертификатов будет учитывать фактическую non-optional модель `name`/`identifier` и удалит недостижимые правые части `??`. Неиспользуемая конкатенация AES-GCM ciphertext/tag будет удалена; `AES.GCM.SealedBox` продолжит получать отдельные `ciphertext` и `tag`.

`CertificatesManager.generateCSR` перейдёт с deprecated `RSA_new`, `RSA_generate_key_ex`, `EVP_PKEY_set1_RSA` и `RSA_free` на `EVP_PKEY_CTX`:

1. создать RSA context;
2. вызвать `EVP_PKEY_keygen_init`;
3. задать 2048 бит через `EVP_PKEY_CTX_set_rsa_keygen_bits`;
4. получить владеющий `EVP_PKEY` через `EVP_PKEY_keygen`;
5. использовать существующий код формирования и подписи CSR;
6. освободить context и key ровно один раз.

Функциональный контракт не меняется: возвращаются DER/PEM-данные CSR и приватного ключа, пригодные для существующего `ALTCertificateRequest`.

### Swift 6 concurrency

Классы, наследующие Foundation/Core Data типы с `@unchecked Sendable`, явно повторят унаследованную conformance там, где этого требует Xcode 27: decoder, persistent containers, операции, operation queue и wrapped NSError. Это не объявляет новые mutable-типы безопасными для произвольного конкурентного использования; оно только делает уже унаследованный unchecked-контракт явным.

### Roxas и UIKit

- Удалить conditional downcasts, когда generic `contentView` уже имеет точный `UICollectionView`/`UITableView` тип.
- Заменить `if let window = ..., window != nil` на прямую проверку наличия окна.
- Явно отбросить результат `cacheSnapshots(for:)`, потому что метод вызывается ради установки snapshot-cache.
- Использовать `.medium` вместо удалённого визуального alias `.white` для activity indicator.
- Удалить записи в `UIApplication.isNetworkActivityIndicatorVisible`: при минимальной iOS 14 системного индикатора уже нет; protocol hooks сохранятся как безопасные no-op.
- Заменить String-переменные associated-object keys на стабильные адресные токены `UInt8`.

### Foundation extensions

- Удалить условные casts ключей `NSError.userInfo`, которые уже имеют тип `String`.
- Пометить conformance `OperatingSystemVersion: Comparable` как `@retroactive`, сохранив существующую numeric-семантику сравнения.

### Project/build warnings

Clean build используется как источник истины. Помимо исходного списка исправляются связанные first-party warnings Xcode 27: availability-аннотации, entitlements в Copy Bundle Resources и shell-script phases без корректно описанной политики запуска/outputs. Изменения build graph не должны менять содержимое подписанного app bundle или порядок создания `SideBackup.ipa`.

### ZIPFoundation

Проект уже закреплён на официальном `ZIPFoundation 0.9.20`, который остаётся последним релизом на дату дизайна. Официальная development-ветка также объявляет Swift 4 в `Package@swift-5.9.swift`, из-за чего Xcode 27 показывает warning о deprecated watchOS language version. Обновления, которое устраняет warning, сейчас нет.

Этот warning не маскируется глобально и не исправляется патчем DerivedData. Проверка warning baseline разрешает ровно это внешнее сообщение с путём внутри `SourcePackages/checkouts/ZIPFoundation`; любое другое предупреждение, включая новое предупреждение той же зависимости, считается ошибкой проверки. Если upstream выпустит исправленный официальный релиз до реализации, допускается обновление lockfile только после успешной проверки API и physical-device flow.

Источники: официальный репозиторий [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) и официальная документация OpenSSL по [EVP_PKEY key generation](https://docs.openssl.org/3.6/man3/EVP_PKEY_keygen/).

## Проверки и TDD

Для каждого класса предупреждений сначала добавляется regression-проверка, которая воспроизводит нежелательный source/build pattern, затем выполняется минимальное исправление.

Обязательные проверки:

1. source-level regression tests для access level, EVP migration, Sendable restatements, cast/nil/deprecation cleanup и безопасных associated-object keys;
2. существующие `scripts/device` unit tests;
3. существующие `scripts/ci` tests;
4. сборка локального `AltSign` package;
5. clean signed `xcodebuild build-for-testing` для точного физического destination;
6. анализ полного build log: ноль first-party/local-dependency warnings и только один точный allowlisted warning `ZIPFoundation`;
7. строгий xcresult: один passed, ноль failed, ноль skipped, итог `Passed`;
8. строгая проверка подписи, установка, foreground-launch и process proof на iPhone 13/iOS 27.0;
9. `git diff --check`, secret/identifier scan и проверка отсутствия изменений Runner/workflows.

## Обработка ошибок

- Любая ошибка компиляции, подписи, теста, установки или запуска блокирует публикацию кандидата.
- Любой новый warning вне точного внешнего allowlist блокирует завершение.
- Если EVP API из поставляемого OpenSSL xcframework недоступен Swift importer-у, исправление переносится в небольшой C bridge внутри `AltSign`; deprecated RSA API не возвращается.
- Если предупреждение можно убрать только изменением поведения, сначала добавляется behavior regression test. Без доказательства эквивалентности изменение не принимается.
- Телефон не очищается и пользовательские данные не удаляются; устанавливается только собранный SideStore после успешных локальных gates.

## Review и публикация

После реализации создаётся immutable candidate commit. Независимый read-only review проверяет корректность EVP ownership, concurrency-аннотации, build graph и физический evidence. Блокирующие findings исправляются максимум за два адресных цикла. Approved candidate отправляется только в `ben-3310/SideStore`; существующий draft PR обновляется, upstream не затрагивается.

## Критерии готовности

- Исходный compile error устранён.
- Все перечисленные first-party и `AltSign` warnings устранены без глобального suppression.
- Clean build не содержит новых warnings; допускается только точный документированный upstream-warning `ZIPFoundation`.
- CSR/signing functionality собирается и проходит regression tests после EVP migration.
- На подключённом iPhone 13/iOS 27.0 подтверждены build, UI smoke, codesign, install, launch и running process.
- Рабочее дерево не содержит локальных идентификаторов, секретов, DerivedData или чужого `xcuserdata`.

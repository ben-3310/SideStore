# Дизайн автоматизації SideStore через asc

## Мета

Налаштувати репозиторій SideStore для повторюваного локального процесу
`Xcode → archive → IPA → TestFlight` через `asc`, не запускаючи автоматичне
подання в App Store Review або зовнішній TestFlight review.

## Поточний стан

- Встановлено `asc 3.1.1` через Homebrew.
- App Store Connect app ID: `6793432450`.
- Bundle ID: `com.SideStore.benStore.972MD5K36E`.
- Xcode-проєкт: `AltStore.xcodeproj`.
- Release-схема: `SideStore - Release`.
- У App Store Connect є версія `1.0` у стані `PREPARE_FOR_SUBMISSION`.
- У TestFlight немає збірок і груп.
- Три App Store provisioning profiles `benStore` активні та використовують
  сертифікат `9BNNH44387`.
- Репозиторій має сторонні незакоммічені зміни, які не входять до цієї задачі.

## Обраний підхід

Використати нативний `.asc/workflow.json` і чинні Xcode build settings. Не
впроваджувати `asc xcode inject`, оскільки поточні `Build.xcconfig` та локальний
`CodeSigning.xcconfig` уже формують правильні product bundle identifiers.
Fastlane не буде частиною нового workflow.

Цей підхід мінімізує зміни Xcode-проєкту й залишає один видимий сценарій
автоматизації в `asc`.

## Автентифікація і секрети

- Перенести credential `asc Developer 2` із `.asc/config.json` у macOS
  Keychain.
- Не комітити API key, issuer ID, private-key path або вміст `.p8`.
- Залишити `.asc/config.json` у `.gitignore`.
- Увімкнути строгий вибір auth profile для workflow, щоб змішані джерела
  credentials завершувалися помилкою.
- Перевірити результат командами `asc auth status --validate` та
  `asc auth doctor`.

## TestFlight

- Перевірити наявність внутрішньої групи `Internal Testers` для app ID
  `6793432450`; створити її лише тоді, коли точного збігу за назвою ще немає.
- Workflow має додавати успішно оброблену збірку до цієї групи.
- Workflow не додає зовнішніх тестувальників і не використовує
  `--submit --confirm`.

## Workflow

Файл `.asc/workflow.json` міститиме workflow `testflight_internal`:

1. Перевірити auth і доступ до app ID.
2. Перевірити обов’язковий runtime-параметр `VERSION`.
3. Отримати наступний build number через
   `asc builds next-build-number`.
4. Створити archive схеми `SideStore - Release` для generic iOS device через
   `asc xcode archive`.
5. Передати `MARKETING_VERSION` і `CURRENT_PROJECT_VERSION` як явні build
   settings, не редагуючи їх постійні значення у проєкті.
6. Експортувати IPA через `asc xcode export` у `.asc/artifacts`.
7. Локально перевірити в IPA bundle ID, marketing version і build number.
   Окремий `asc xcode validate` не входить у workflow, оскільки його `altool`
   backend вимагає окремого file-based API key resolution і дублює серверну
   перевірку наступного upload-кроку.
8. Завантажити IPA через `asc publish testflight`, дочекатися processing та
   додати build до `Internal Testers`.

Назви артефактів включатимуть version і build number, щоб повторний запуск не
перезаписував іншу збірку випадково.

## Файли

- `.asc/workflow.json` — version-controlled workflow без секретів.
- `.asc/ExportOptions.plist` — наявні детерміновані App Store Connect export
  options з automatic signing; workflow передає цей файл явно.
- `.asc/artifacts/` — локальні archive та IPA; каталог і його вміст не
  комітяться.
- `ASC.md` — version-controlled довідка, згенерована встановленою версією
  `asc`; `.gitignore` матиме точний виняток `!ASC.md`.
- `fastlane/` — не видаляється автоматично; старий шлях залишається поза новим
  workflow до окремого рішення про міграцію.

## Обробка помилок

- Workflow зупиняється на першій невдалій команді.
- Upload не запускається, якщо archive, export або локальна перевірка IPA
  неуспішні.
- Повторний upload того самого build number не виконується автоматично.
- Немає кроків видалення profiles, certificates, Bundle IDs, builds або
  TestFlight groups.
- Немає автоматичного App Store submission.

## Перевірка

Перед реальним upload:

1. `asc auth status --validate`.
2. `asc auth doctor` без warnings про config-backed credentials.
3. `asc workflow validate`.
4. `asc workflow list`.
5. `asc workflow run --dry-run testflight_internal VERSION:1.0`.
6. Локальний archive/export smoke test із перевіркою bundle ID та version у
   готовому IPA.

Після реального upload перевірити build через `asc builds list` і належність до
`Internal Testers`. Реальний upload дозволений цією задачею, але App Store
submission не входить у scope.

## Критерії завершення

- Credentials зберігаються в Keychain, а не в repo-local config.
- `asc auth doctor` не повідомляє про небезпечне зберігання credentials.
- Внутрішня група `Internal Testers` існує.
- Workflow валідний і проходить dry-run.
- Workflow створює IPA з bundle ID `com.SideStore.benStore.972MD5K36E`.
- Збірка успішно завантажується в TestFlight і додається до внутрішньої групи.
- Жодного App Store Review submission не створено.
- Сторонні незакоммічені зміни користувача збережено.

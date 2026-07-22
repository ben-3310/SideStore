# SideStore Self-Hosted Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Подготовить `air` как изолированный repository-level GitHub Actions runner для доверенных сборок `ben-3310/SideStore`.

**Architecture:** Постоянный macOS ARM64 runner работает под отдельным стандартным пользователем `github-runner-sidestore`, имеет собственные SSH-ключ, HOME, `_work` и кэши и регистрируется только в fork `ben-3310/SideStore`. На него маршрутизируются только `nightly` и `stable`; публичные pull request продолжают выполняться на GitHub-hosted `macos-26`.

**Tech Stack:** macOS 26, Xcode 26.6, iOS 26 SDK/runtime, Homebrew, GitHub Actions runner macOS ARM64, `launchd`, GitHub CLI, SSH, YAML workflows.

## Global Constraints

- Не изменять и не останавливать существующий runner `china_link` под `ben`.
- Не добавлять `github-runner-sidestore` в `admin` и не выдавать ему `sudo`.
- Не направлять `pull_request` или иной недоверенный код на постоянный self-hosted runner.
- Не выводить пароли, registration token, закрытый SSH-ключ и signing secrets.
- Использовать Xcode 26.6 и labels `self-hosted`, `macOS`, `ARM64`, `sidestore`, `xcode-26-6`.
- Не публиковать workflow и коммиты без отдельного разрешения пользователя.
- Сохранять пользовательские незатреканные `.build/`, IPA и dSYM-архивы.

---

## Структура изменений

- `docs/superpowers/specs/2026-07-22-sidestore-self-hosted-runner-design.md` — утверждённые требования и security boundary.
- `docs/superpowers/plans/2026-07-22-sidestore-self-hosted-runner.md` — этот исполняемый план.
- `.github/workflows/nightly.yml` — маршрутизация доверенной nightly-сборки и preflight зависимостей.
- `.github/workflows/stable.yml` — маршрутизация доверенной stable-сборки и preflight зависимостей.
- `/Users/ben/.ssh/air_github_runner_sidestore_ed25519{,.pub}` — локальная выделенная пара SSH-ключей.
- `/Users/github-runner-sidestore/` на `air` — изолированный HOME пользователя.
- `/Users/github-runner-sidestore/actions-runner/` на `air` — официальный runner и `_work`.
- `/Library/LaunchDaemons/actions.runner.ben-3310-SideStore.air-sidestore.plist` — root-owned headless service, запускающий официальный `runsvc.sh` от имени runner.

### Task 1: Preflight хоста и Xcode

**Files:**
- Inspect: `/Applications/Xcode.app`
- Inspect: `/Users/ben/actions-runner`

**Interfaces:**
- Consumes: законченная пользователем установка Xcode.
- Produces: подтверждённые пути Xcode/Homebrew и снимок состояния `china_link`.

- [ ] **Step 1: Зафиксировать baseline хоста**

Через существующую SSH-сессию `ben@192.168.88.222` выполнить:

```bash
sw_vers
uname -m
df -h /
launchctl list | grep 'actions.runner.ben-3310-china_link'
ps -axo user,pid,command | grep '[R]unner.Listener'
```

Expected: `arm64`, не менее 100 GiB свободно, `china_link` запущен под `ben`.

- [ ] **Step 2: Проверить Xcode 26.6**

```bash
test -d /Applications/Xcode.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Xcode.app/Contents/Info.plist
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -showsdks
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list runtimes
```

Expected: Xcode `26.6`, iOS 26 SDK и доступный iOS 26 runtime. Если Xcode ещё устанавливается или версия отличается, не менять workflows и не объявлять runner готовым.

- [ ] **Step 3: Завершить системную инициализацию Xcode**

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

Expected: `xcode-select -p` возвращает `/Applications/Xcode.app/Contents/Developer`, команды завершаются с кодом `0`.

- [ ] **Step 4: Проверить системные зависимости**

```bash
for command_name in git python3 make bash zip unzip curl shasum; do
  command -v "$command_name" || exit 1
done
/opt/homebrew/bin/brew --version
curl -fsSIL https://github.com >/dev/null
pmset -g custom
```

Expected: все команды найдены, GitHub доступен по HTTPS. Для постоянной
доступности runner установить `sudo pmset -c sleep 0`, если `sleep` в секции
AC Power не равен `0`; батарейный режим не менять.

### Task 2: Изолированный пользователь и SSH

**Files:**
- Create: `/Users/ben/.ssh/air_github_runner_sidestore_ed25519`
- Create: `/Users/ben/.ssh/air_github_runner_sidestore_ed25519.pub`
- Create: `/Users/github-runner-sidestore/.ssh/authorized_keys`
- Create: `/Users/github-runner-sidestore/.zprofile`

**Interfaces:**
- Consumes: административную SSH-сессию `ben` и её подтверждённый `sudo`.
- Produces: key-only SSH-доступ к стандартному пользователю `github-runner-sidestore`.

- [ ] **Step 1: Создать выделенный локальный ключ**

Если ключ отсутствует:

```bash
ssh-keygen -t ed25519 \
  -f /Users/ben/.ssh/air_github_runner_sidestore_ed25519 \
  -N '' \
  -C 'github-runner-sidestore@air'
chmod 600 /Users/ben/.ssh/air_github_runner_sidestore_ed25519
chmod 644 /Users/ben/.ssh/air_github_runner_sidestore_ed25519.pub
```

Expected: закрытый ключ не печатается, `ssh-keygen -lf ...pub` показывает ED25519 fingerprint.

- [ ] **Step 2: Создать стандартную macOS-учётную запись**

В сессии `ben` вычислить свободный UID и создать запись:

```bash
runner_uid="$(( $(dscl . -list /Users UniqueID | awk '$2 >= 501 && $2 < 1000 {print $2}' | sort -n | tail -1) + 1 ))"
sudo dscl . -create /Users/github-runner-sidestore
sudo dscl . -create /Users/github-runner-sidestore UserShell /bin/zsh
sudo dscl . -create /Users/github-runner-sidestore RealName 'GitHub Runner SideStore'
sudo dscl . -create /Users/github-runner-sidestore UniqueID "$runner_uid"
sudo dscl . -create /Users/github-runner-sidestore PrimaryGroupID 20
sudo dscl . -create /Users/github-runner-sidestore NFSHomeDirectory /Users/github-runner-sidestore
sudo dscl . -passwd /Users/github-runner-sidestore '*'
sudo dscl . -create /Users/github-runner-sidestore IsHidden 1
sudo createhomedir -c -u github-runner-sidestore
sudo chmod 700 /Users/github-runner-sidestore
```

Expected: `id github-runner-sidestore` существует, `admin` отсутствует.

- [ ] **Step 3: Разрешить только SSH и developer tools**

```bash
sudo dseditgroup -o edit -a github-runner-sidestore -t user com.apple.access_ssh
sudo dseditgroup -o edit -a github-runner-sidestore -t user _developer
```

Expected: пользователь входит в `com.apple.access_ssh` и `_developer`, но не в `admin`.

Закрыть HOME `ben` только для нового runner, сохранив доступ остальных
пользователей:

```bash
sudo chmod +a 'user:github-runner-sidestore deny list,search,readattr,readextattr,readsecurity' /Users/ben
```

Expected: `github-runner-sidestore` не может читать или перечислять
`/Users/ben`, а существующий runner `china_link` продолжает работать под `ben`.

- [ ] **Step 4: Установить public key и закрыть permissions**

Public key передать из локального файла через текущую SSH-сессию и создать:

```bash
sudo install -d -m 700 -o github-runner-sidestore -g staff /Users/github-runner-sidestore/.ssh
sudo install -m 600 -o github-runner-sidestore -g staff /dev/stdin /Users/github-runner-sidestore/.ssh/authorized_keys
```

Expected: `authorized_keys` принадлежит `github-runner-sidestore:staff`, режим `0600`.

- [ ] **Step 5: Создать профиль и закрытые каталоги**

Записать `.zprofile` со строками:

```bash
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
umask 077
```

Создать от имени runner:

```bash
mkdir -p ~/actions-runner/_work \
  ~/Library/Developer/Xcode/DerivedData \
  ~/Library/Caches/org.swift.swiftpm \
  ~/Library/Caches/Homebrew \
  ~/Library/Logs
chmod 700 ~/actions-runner ~/actions-runner/_work ~/Library/Developer/Xcode/DerivedData \
  ~/Library/Caches/org.swift.swiftpm ~/Library/Caches/Homebrew ~/Library/Logs
```

Expected: каталоги принадлежат runner и недоступны другим пользователям на запись.

- [ ] **Step 6: Проверить SSH-вход по ключу**

```bash
ssh -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -i /Users/ben/.ssh/air_github_runner_sidestore_ed25519 \
  github-runner-sidestore@192.168.88.222 \
  'id; printf "%s\n" "$HOME"; umask'
```

Expected: вход без пароля; UID нового пользователя, HOME `/Users/github-runner-sidestore`, umask `0077`.

Дополнительно:

```bash
dscl . -read /Users/github-runner-sidestore Password
```

Expected: password attribute заблокирован значением `*`; пароль не установлен.

### Task 3: Toolchain и GitHub runner

**Files:**
- Create: `/Users/github-runner-sidestore/actions-runner/*`
- Create: `/Users/github-runner-sidestore/actions-runner/.env`

**Interfaces:**
- Consumes: Xcode 26.6 и SSH-доступ из Task 2.
- Produces: проверенный, ещё не зарегистрированный runner package и доступные SideStore build tools.

- [ ] **Step 1: Установить общие build tools под владельцем Homebrew**

В сессии `ben`:

```bash
/opt/homebrew/bin/brew install ldid xcbeautify wget
/opt/homebrew/bin/brew list --versions ldid xcbeautify wget
```

Expected: обе formula установлены; runner не получает запись в `/opt/homebrew`.

- [ ] **Step 2: Проверить toolchain из профиля runner**

```bash
ssh -i /Users/ben/.ssh/air_github_runner_sidestore_ed25519 \
  github-runner-sidestore@192.168.88.222 \
  'for c in xcodebuild xcrun git python3 make bash zip unzip ldid xcbeautify wget; do command -v "$c" || exit 1; done'
```

Expected: все команды найдены без `sudo`.

- [ ] **Step 3: Получить актуальный официальный release metadata**

Локально запросить release и извлечь точные asset URL и SHA-256:

```bash
runner_tag="$(gh api repos/actions/runner/releases/latest --jq .tag_name)"
runner_version="${runner_tag#v}"
runner_asset="actions-runner-osx-arm64-${runner_version}.tar.gz"
runner_url="$(gh api repos/actions/runner/releases/latest \
  --jq ".assets[] | select(.name == \"${runner_asset}\") | .browser_download_url")"
runner_sha256="$(gh api repos/actions/runner/releases/latest --jq .body | \
  sed -n 's/.*BEGIN SHA osx-arm64 -->\([0-9a-f]\{64\}\).*/\1/p')"
test -n "$runner_url"
test "${#runner_sha256}" -eq 64
```

Не использовать непроверенный URL или checksum из стороннего источника.

Expected: версия не ниже установленной у `china_link`; на 2026-07-22 ожидается `v2.336.0`, но реализация использует фактический latest release.

- [ ] **Step 4: Скачать и проверить пакет**

От имени runner:

```bash
curl -fL "$runner_url" -o /tmp/actions-runner-osx-arm64.tar.gz
printf '%s  %s\n' "$runner_sha256" /tmp/actions-runner-osx-arm64.tar.gz | shasum -a 256 -c -
tar -xzf /tmp/actions-runner-osx-arm64.tar.gz -C ~/actions-runner
rm /tmp/actions-runner-osx-arm64.tar.gz
~/actions-runner/bin/Runner.Listener --version
```

Expected: checksum `OK`, listener выводит выбранную версию.

- [ ] **Step 5: Зафиксировать service environment**

В `~/actions-runner/.env` записать:

```text
PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
HOME=/Users/github-runner-sidestore
```

Expected: файл принадлежит runner, режим `0600`, секретов нет.

Официальный `runsvc.sh` восстанавливает PATH из `~/actions-runner/.path`,
поэтому записать отдельно:

```text
/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin
```

Expected: `.path` принадлежит runner, режим `0600`; после перезапуска service
в stdout-журнале зафиксирован этот PATH.

### Task 4: Регистрация в GitHub и launchd service

**Files:**
- Create: `/Users/github-runner-sidestore/actions-runner/.runner`
- Create: `/Library/LaunchDaemons/actions.runner.ben-3310-SideStore.air-sidestore.plist`

**Interfaces:**
- Consumes: официальный runner package и аутентифицированный `gh` пользователя `ben`.
- Produces: `online`/`idle` repository-level runner с точными labels.

- [ ] **Step 1: Получить короткоживущий registration token**

```bash
gh api --method POST repos/ben-3310/SideStore/actions/runners/registration-token --jq .token
```

Передать значение напрямую в удалённый `config.sh`, не печатать и не сохранять.

- [ ] **Step 2: Зарегистрировать runner**

От имени `github-runner-sidestore` выполнить:

```bash
cd ~/actions-runner
./config.sh --unattended \
  --url https://github.com/ben-3310/SideStore \
  --token "$registration_token" \
  --name air-sidestore \
  --labels sidestore,xcode-26-6 \
  --work _work \
  --replace
unset registration_token
```

Expected: конфигурация завершена, `.runner` имеет режим `0600`, labels включают стандартные и пользовательские.

- [ ] **Step 3: Установить и запустить headless macOS service**

```bash
cd ~/actions-runner
./svc.sh install
```

Официальный `svc.sh` создаёт исходный plist и `runsvc.sh`. Поскольку новый
пользователь не имеет GUI bootstrap domain, администратор устанавливает этот
plist как LaunchDaemon:

```bash
runner_source=/Users/github-runner-sidestore/Library/LaunchAgents/actions.runner.ben-3310-SideStore.air-sidestore.plist
runner_daemon=/Library/LaunchDaemons/actions.runner.ben-3310-SideStore.air-sidestore.plist
sudo install -o root -g wheel -m 644 "$runner_source" "$runner_daemon"
sudo /usr/libexec/PlistBuddy -c 'Add :KeepAlive bool true' "$runner_daemon"
sudo /usr/libexec/PlistBuddy -c 'Add :ThrottleInterval integer 10' "$runner_daemon"
sudo plutil -lint "$runner_daemon"
sudo launchctl bootstrap system "$runner_daemon"
sudo launchctl enable system/actions.runner.ben-3310-SideStore.air-sidestore
sudo launchctl kickstart -k system/actions.runner.ben-3310-SideStore.air-sidestore
```

Переместить исходный LaunchAgent из автозагрузочного каталога в каталог runner
с суффиксом `.launchagent-disabled.plist`, чтобы исключить двойной запуск после
GUI-login.

Expected: `launchctl print system/actions.runner.ben-3310-SideStore.air-sidestore`
показывает running LaunchDaemon, `username = github-runner-sidestore`,
`keepalive | runatload | creates session`.

Проверить восстановление процесса:

```bash
old_pid="$(pgrep -u "$(id -u)" -x Runner.Listener)"
kill "$old_pid"
for attempt in 1 2 3 4 5; do
  sleep 2
  new_pid="$(pgrep -u "$(id -u)" -x Runner.Listener || true)"
  test -n "$new_pid" && test "$new_pid" != "$old_pid" && break
done
test -n "$new_pid"
test "$new_pid" != "$old_pid"
```

Expected: `launchd` запускает новый `Runner.Listener` с другим PID.

- [ ] **Step 4: Проверить GitHub readback**

```bash
gh api repos/ben-3310/SideStore/actions/runners \
  --jq '.runners[] | select(.name == "air-sidestore") | {name,os,status,busy,labels:[.labels[].name]}'
```

Expected: `status` — `online`, `busy` — `false`; labels содержат `self-hosted`, `macOS`, `ARM64`, `sidestore`, `xcode-26-6`.

- [ ] **Step 5: Проверить отсутствие секретов и влияние на china_link**

Проверить имена ключей plist, `.env`, process owner, права каталогов и журналы без печати значений чувствительных файлов. Повторить `./svc.sh status` для `china_link`.

Expected: оба runner online; SideStore listener работает под `github-runner-sidestore`; token отсутствует в plist и `.env`.

### Task 5: Workflow routing с тестом до изменения

**Files:**
- Modify: `.github/workflows/nightly.yml`
- Modify: `.github/workflows/stable.yml`
- Preserve: `.github/workflows/pr.yml`
- Preserve: `.github/workflows/alpha.yml`

**Interfaces:**
- Consumes: exact labels зарегистрированного runner.
- Produces: локальный candidate commit, который маршрутизирует только доверенные workflow.

- [ ] **Step 1: Написать failing structural check**

Запустить временную read-only проверку:

```bash
python3 - <<'PY'
from pathlib import Path

expected = {
    ".github/workflows/nightly.yml": "[self-hosted, macOS, ARM64, sidestore, xcode-26-6]",
    ".github/workflows/stable.yml": "[self-hosted, macOS, ARM64, sidestore, xcode-26-6]",
    ".github/workflows/pr.yml": "macos-26",
    ".github/workflows/alpha.yml": "macos-26",
}

failed = []
for filename, expected_value in expected.items():
    values = [
        line.split("runs-on:", 1)[1].strip()
        for line in Path(filename).read_text().splitlines()
        if line.strip().startswith("runs-on:")
    ]
    if values != [expected_value]:
        failed.append(f"{filename}: expected {expected_value!r}, got {values!r}")

if failed:
    raise SystemExit("\n".join(failed))
print("workflow routing checks passed")
PY
```

Run до изменения: Ruby/Python YAML parse или адресный parser строк.

Expected: FAIL только для `nightly.yml` и `stable.yml`.

- [ ] **Step 2: Изменить trusted workflows**

В `nightly.yml` и `stable.yml` заменить:

```yaml
runs-on: macos-26
```

на:

```yaml
runs-on: [self-hosted, macOS, ARM64, sidestore, xcode-26-6]
```

В существующем шаге `Setup Xcode` заменить:

```yaml
xcode-version: "26.4"
```

на подтверждённую preflight версию:

```yaml
xcode-version: "26.6"
```

Сам action запускать только при `runner.environment == 'github-hosted'`. Для
self-hosted добавить отдельный шаг без `sudo`, проверяющий точный
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` и вывод
`xcodebuild -version` с `Xcode 26.6`.

Шаг `brew install ldid xcbeautify` заменить парой:

```yaml
- name: Install build dependencies
  if: runner.environment == 'github-hosted'
  run: brew install ldid xcbeautify wget

- name: Verify build dependencies
  if: runner.environment == 'self-hosted'
  run: |
    command -v ldid
    command -v xcbeautify
    command -v wget
```

В simulator destinations `Makefile` заменить отсутствующий `OS=26.0` на
`OS=latest`; `pr.yml` и `alpha.yml` при этом остаются GitHub-hosted.

- [ ] **Step 3: Повторить structural check**

Expected: PASS для всех четырёх workflow; `pr.yml` и `alpha.yml` не изменены.

- [ ] **Step 4: Проверить YAML и diff**

```bash
git diff --check
git diff -- .github/workflows/nightly.yml .github/workflows/stable.yml
```

Дополнительно запустить доступный YAML parser или `actionlint` без автоматического изменения файлов.

Expected: синтаксис корректен, изменены только `runs-on` и dependency preflight двух trusted workflow.

- [ ] **Step 5: Создать локальный candidate commit**

```bash
git add .github/workflows/nightly.yml .github/workflows/stable.yml
git commit -m 'ci: route trusted SideStore builds to air runner'
```

Expected: commit локальный; push не выполняется.

### Task 6: Smoke-test и приёмка

**Files:**
- Create transient: `/Users/github-runner-sidestore/smoke/SideStore.XXXXXX`
- Inspect: runner diagnostics and GitHub readback

**Interfaces:**
- Consumes: готовый toolchain, отдельного пользователя и registered service.
- Produces: evidence готовности или точный blocker без публикации workflow.

- [ ] **Step 1: Создать чистый checkout с submodules**

От имени runner:

```bash
mkdir -p ~/smoke
smoke_root="$(mktemp -d "$HOME/smoke/SideStore.XXXXXX")"
git clone --recurse-submodules https://github.com/ben-3310/SideStore.git "$smoke_root"
cd "$smoke_root"
git submodule status --recursive
```

Expected: clone и все submodules завершены, нет префикса `-` в status.

- [ ] **Step 2: Запустить preflight проекта**

```bash
cd "$smoke_root"
python3 scripts/ci/workflow.py get-marketing-version
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project AltStore.xcodeproj -scheme SideStore -showBuildSettings >/tmp/sidestore-build-settings.txt
```

Expected: marketing version читается, build settings получены.

- [ ] **Step 3: Запустить сборочный smoke-test без signing secrets**

```bash
cd "$smoke_root"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 scripts/ci/workflow.py build
```

Expected: archive SideStore, fake signing, IPA и dSYM созданы без signing
secrets. Затем выполнить `tests-build`, отдельно `boot-sim-async` и только после
него `tests-run`. Если сборка выявляет отсутствующий SDK/runtime/dependency,
зафиксировать точную ошибку и не маршрутизировать workflow.

- [ ] **Step 4: Проверить service и оба runner после нагрузки**

Expected: `air-sidestore` снова `online`/`idle`, `china_link` остаётся online, ownership `_work` и кэшей принадлежит соответствующим пользователям.

- [ ] **Step 5: Финальный security audit**

Проверить:

```text
github-runner-sidestore not in admin
HOME, .ssh, actions-runner, _work and caches are not group/world writable
runner process UID is github-runner-sidestore
registration token is absent from plist, .env and logs
pr.yml still uses macos-26
no push occurred
```

Expected: все условия выполнены. Только после этого runner объявляется готовым к публикации workflow candidate.

### Task 7: Финальный self-review и handoff

**Files:**
- Review: committed spec and plan
- Review: workflow candidate diff

**Interfaces:**
- Consumes: evidence Tasks 1-6.
- Produces: итоговый отчёт и запрос отдельного разрешения на push.

- [ ] **Step 1: Проверить scope и рабочее дерево**

```bash
git status --short --branch
git log -3 --oneline --decorate
git diff origin/develop...HEAD -- .github/workflows/nightly.yml .github/workflows/stable.yml docs/superpowers
```

Expected: только дизайн, план и две workflow; пользовательские артефакты сохранены.

- [ ] **Step 2: Проверить неизменяемый candidate**

Зафиксировать base SHA, candidate SHA, диапазон diff, команды и результаты проверок, незакрытые критерии.

- [ ] **Step 3: Выполнить самостоятельный review**

Проверить security boundary, label matching, toolchain version, secrets, права, rollback и отсутствие влияния на `china_link`. Блокирующие findings исправить до handoff.

- [ ] **Step 4: Передать результат пользователю**

Сообщить состояние remote runner, SSH alias/key path, Xcode/toolchain evidence, GitHub readback, smoke-test, локальные commits и отсутствие push. Отдельно запросить разрешение на публикацию workflow candidate.

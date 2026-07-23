# SideStore iOS 27 Local Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Зарегистрировать текущий Mac как изолированный SideStore compatibility runner с Xcode 27.0 и гарантированным Simulator destination iOS 27.0.

**Architecture:** Release workflow остаются привязаны к `air-sidestore`/Xcode 26.6. Новый `denys-mbp-sidestore` работает под отдельным стандартным пользователем и обслуживает только отдельный доверенный compatibility workflow с точными labels `xcode-27-0` и `ios-27`; destination передаётся через `SIMULATOR_DEVICE=iPhone 13` и `SIMULATOR_OS=27.0`.

**Tech Stack:** macOS 27, Xcode-beta 27.0, iOS 27.0 Simulator, GitHub Actions runner 2.336.0 ARM64, launchd, Homebrew, Python unittest, YAML workflows.

## Global Constraints

- Не переустанавливать и не переименовывать `/Applications/Xcode-beta.app`.
- Не добавлять `github-runner-sidestore` в `admin`, `sudo` или `com.apple.access_ssh`.
- Не давать compatibility workflow deploy/signing secrets и не запускать его на `pull_request`.
- Не изменять routing `nightly.yml` и `stable.yml` с `air-sidestore`/`xcode-26-6`.
- Использовать `SIMULATOR_DEVICE=iPhone 13` и `SIMULATOR_OS=27.0` для
  simulator build на новом runner.
- Не объявлять удалённые `UITests` зелёными; acceptance ограничен archive, build-for-testing и boot iOS 27.0.
- Не выводить registration token, пароль, credential contents или private keys.
- Не затрагивать пользовательские `.build`, IPA и dSYM в основном checkout.
- Не выполнять push без отдельного разрешения пользователя.

---

### Task 1: Изолировать implementation candidate

**Files:**
- Inspect: `/Users/ben/Repo/SideStore`
- Create worktree: `/Users/ben/Repo/SideStore/.worktrees/sidestore-ios27-runner`
- Create branch: `codex/sidestore-ios27-runner`

**Interfaces:**
- Consumes: утверждённый design commit `999f08e`.
- Produces: чистый named-branch worktree для workflow/test изменений.

- [ ] **Step 1: Проверить основной checkout**

```bash
git status --short --branch
git worktree list --porcelain
git rev-parse HEAD
```

Expected: только сохранённые пользовательские `.build`/IPA/dSYM untracked; HEAD содержит design commit.

- [ ] **Step 2: Создать worktree**

```bash
git worktree add /Users/ben/Repo/SideStore/.worktrees/sidestore-ios27-runner \
  -b codex/sidestore-ios27-runner
```

Expected: новый worktree на `codex/sidestore-ios27-runner`, основной checkout не изменён.

### Task 2: Сделать simulator destination управляемым окружением

**Files:**
- Modify: `Makefile`
- Modify/Test: `scripts/ci/test_runner_workflows.py`

**Interfaces:**
- Consumes: env `SIMULATOR_DEVICE` и `SIMULATOR_OS`, defaults `iPhone 17 Pro`
  и `latest`.
- Produces: все три simulator targets используют заданные model и OS.

- [ ] **Step 1: Написать failing regression test**

Заменить `test_simulator_destination_uses_installed_runtime` на:

```python
def test_simulator_destination_can_be_pinned_by_runner(self) -> None:
    makefile = (REPO_ROOT / "Makefile").read_text()

    self.assertIn("SIMULATOR_DEVICE ?= iPhone 17 Pro", makefile)
    self.assertIn("SIMULATOR_OS ?= latest", makefile)
    self.assertNotIn("OS=26.0", makefile)
    self.assertNotIn("OS=latest", makefile)
    self.assertEqual(makefile.count("OS=$(SIMULATOR_OS)"), 3)
    self.assertEqual(makefile.count("name=$(SIMULATOR_DEVICE)"), 3)
```

- [ ] **Step 2: Подтвердить RED**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  scripts.ci.test_runner_workflows.RunnerWorkflowTests.test_simulator_destination_can_be_pinned_by_runner -v
```

Expected: FAIL, потому что `SIMULATOR_OS ?= latest` отсутствует.

- [ ] **Step 3: Реализовать минимальное изменение Makefile**

Добавить рядом с build overrides:

```make
SIMULATOR_OS ?= latest
SIMULATOR_DEVICE ?= iPhone 17 Pro
```

В `build-and-test`, `build-tests`, `run-tests` заменить destination на:

```make
-destination 'platform=iOS Simulator,name=$(SIMULATOR_DEVICE),OS=$(SIMULATOR_OS)'
```

- [ ] **Step 4: Подтвердить GREEN и полный suite**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v
```

Expected: все tests PASS.

- [ ] **Step 5: Создать commit**

```bash
git add Makefile scripts/ci/test_runner_workflows.py
git commit -m 'ci: allow runners to pin simulator runtime'
```

### Task 3: Добавить доверенный iOS 27 compatibility workflow

**Files:**
- Create: `.github/workflows/ios27-compatibility.yml`
- Modify/Test: `scripts/ci/test_runner_workflows.py`

**Interfaces:**
- Consumes: labels `sidestore,xcode-27-0,ios-27`, env
  `SIMULATOR_DEVICE=iPhone 13`, `SIMULATOR_OS=27.0`.
- Produces: compile/archive/build-for-testing/boot gate без release/deploy действий.

- [ ] **Step 1: Написать failing workflow contract test**

Добавить:

```python
def test_ios27_compatibility_workflow_is_trusted_and_pinned(self) -> None:
    text = workflow_text("ios27-compatibility.yml")

    self.assertEqual(
        runs_on_value("ios27-compatibility.yml"),
        "[self-hosted, macOS, ARM64, sidestore, xcode-27-0, ios-27]",
    )
    self.assertNotIn("pull_request:", text)
    self.assertIn('SIMULATOR_DEVICE: "iPhone 13"', text)
    self.assertIn('SIMULATOR_OS: "27.0"', text)
    self.assertIn("xcodebuild -version | grep -Fx 'Xcode 27.0'", text)
    self.assertIn('grep -F "iOS 27.0 (27.0', text)
    self.assertIn("python3 scripts/ci/workflow.py build", text)
    self.assertIn("python3 scripts/ci/workflow.py tests-build", text)
    self.assertIn('runtime_id = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"', text)
    self.assertNotIn("upload-release", text)
    self.assertNotIn("CROSS_REPO_PUSH_KEY", text)
```

- [ ] **Step 2: Подтвердить RED**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  scripts.ci.test_runner_workflows.RunnerWorkflowTests.test_ios27_compatibility_workflow_is_trusted_and_pinned -v
```

Expected: ERROR/FAIL, потому что workflow ещё отсутствует.

- [ ] **Step 3: Создать workflow**

Создать `.github/workflows/ios27-compatibility.yml`:

```yaml
name: SideStore iOS 27 Compatibility

on:
  push:
    branches: [develop]
  workflow_dispatch:

concurrency:
  group: ios27-${{ github.ref }}
  cancel-in-progress: true

jobs:
  compatibility:
    runs-on: [self-hosted, macOS, ARM64, sidestore, xcode-27-0, ios-27]
    timeout-minutes: 90
    env:
      SIMULATOR_DEVICE: "iPhone 13"
      SIMULATOR_OS: "27.0"

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
          fetch-depth: 0

      - name: Verify Xcode 27 toolchain
        run: |
          test "$DEVELOPER_DIR" = "/Applications/Xcode-beta.app/Contents/Developer"
          xcodebuild -version | grep -Fx 'Xcode 27.0'
          xcrun simctl list runtimes | grep -F "iOS 27.0 (27.0"
          command -v ldid
          command -v xcbeautify
          command -v wget

      - name: Repository regression checks
        run: |
          PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
            -s scripts/ci -p 'test_*.py' -v

      - name: Archive compatibility build
        run: python3 scripts/ci/workflow.py build

      - name: Build for iOS 27 Simulator
        run: python3 scripts/ci/workflow.py tests-build

      - name: Boot iOS 27 Simulator
        run: |
          python3 - <<'PY'
          import json
          import subprocess

          runtime_id = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
          devices = json.loads(
              subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"])
          )["devices"][runtime_id]
          udid = next(
              device["udid"]
              for device in devices
              if device["name"] == os.environ["SIMULATOR_DEVICE"]
              and device["isAvailable"]
          )
          subprocess.run(["xcrun", "simctl", "boot", udid], check=False)
          subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True)
          subprocess.run(["xcrun", "simctl", "shutdown", udid], check=True)
          PY
```

- [ ] **Step 4: Подтвердить GREEN, YAML и security boundary**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ios27-compatibility.yml")'
git diff --check
```

Expected: tests/YAML/diff PASS; `nightly.yml`, `stable.yml`, `pr.yml`, `alpha.yml` не изменены.

- [ ] **Step 5: Создать commit**

```bash
git add .github/workflows/ios27-compatibility.yml scripts/ci/test_runner_workflows.py
git commit -m 'ci: add trusted iOS 27 compatibility lane'
```

### Task 4: Завершить профиль локального пользователя

**Files:**
- Modify: `/Users/github-runner-sidestore/.zprofile`
- Modify: `/Users/github-runner-sidestore/actions-runner/.env`
- Modify: `/Users/github-runner-sidestore/actions-runner/.path`

**Interfaces:**
- Consumes: `/Applications/Xcode-beta.app`, Homebrew tools.
- Produces: детерминированные Xcode 27/iOS 27 service environment и закрытые caches.

- [ ] **Step 1: Зафиксировать environment**

`.zprofile`:

```bash
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
export SIMULATOR_DEVICE="iPhone 13"
export SIMULATOR_OS="27.0"
umask 077
```

`.env`:

```text
PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
SIMULATOR_DEVICE=iPhone 13
SIMULATOR_OS=27.0
HOME=/Users/github-runner-sidestore
```

`.path`:

```text
/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin
```

Expected: files owner `github-runner-sidestore:staff`, mode `0600`.

- [ ] **Step 2: Проверить изоляцию и toolchain**

```bash
sudo -u github-runner-sidestore -H env \
  PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin \
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  SIMULATOR_DEVICE="iPhone 13" \
  SIMULATOR_OS=27.0 \
  /bin/zsh -c 'id; xcodebuild -version; xcrun simctl list runtimes; command -v ldid xcbeautify wget'
```

Expected: UID 502, Xcode 27.0, iOS 27.0 runtime и все tools доступны; `admin` отсутствует.

### Task 5: Зарегистрировать runner и создать LaunchDaemon

**Files:**
- Modify generated: `/Users/github-runner-sidestore/actions-runner/.runner`
- Modify generated: `/Users/github-runner-sidestore/actions-runner/.credentials*`
- Create: `/Library/LaunchDaemons/actions.runner.ben-3310-SideStore.denys-mbp-sidestore.plist`

**Interfaces:**
- Consumes: одноразовый GitHub registration token.
- Produces: `denys-mbp-sidestore` online с точными labels.

- [ ] **Step 1: Получить token и зарегистрировать без его вывода**

```bash
registration_token=$(gh api --method POST \
  repos/ben-3310/SideStore/actions/runners/registration-token --jq .token)
sudo -u github-runner-sidestore -H env \
  PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin \
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  SIMULATOR_DEVICE="iPhone 13" \
  SIMULATOR_OS=27.0 \
  /Users/github-runner-sidestore/actions-runner/config.sh \
  --unattended \
  --url https://github.com/ben-3310/SideStore \
  --token "$registration_token" \
  --name denys-mbp-sidestore \
  --labels sidestore,xcode-27-0,ios-27 \
  --work _work \
  --replace
unset registration_token
```

Expected: registration succeeds; token не печатается и не записывается.

- [ ] **Step 2: Закрыть credentials**

```bash
sudo chmod 600 /Users/github-runner-sidestore/actions-runner/.credentials*
```

Expected: `.credentials` и `.credentials_rsaparams` owner runner, mode `0600`.

- [ ] **Step 3: Создать root-owned LaunchDaemon**

Plist должен содержать:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>actions.runner.ben-3310-SideStore.denys-mbp-sidestore</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/github-runner-sidestore/actions-runner/runsvc.sh</string>
  </array>
  <key>WorkingDirectory</key>
  <string>/Users/github-runner-sidestore/actions-runner</string>
  <key>UserName</key>
  <string>github-runner-sidestore</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>/Users/github-runner-sidestore</string>
    <key>PATH</key><string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>DEVELOPER_DIR</key><string>/Applications/Xcode-beta.app/Contents/Developer</string>
    <key>SIMULATOR_DEVICE</key><string>iPhone 13</string>
    <key>SIMULATOR_OS</key><string>27.0</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>SessionCreate</key><true/>
  <key>Umask</key><integer>63</integer>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key>
  <string>/Users/github-runner-sidestore/Library/Logs/actions-runner.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/github-runner-sidestore/Library/Logs/actions-runner.stderr.log</string>
</dict>
</plist>
```

Установить `root:wheel 0644`, проверить `plutil -lint`, затем:

```bash
sudo launchctl bootstrap system \
  /Library/LaunchDaemons/actions.runner.ben-3310-SideStore.denys-mbp-sidestore.plist
sudo launchctl enable system/actions.runner.ben-3310-SideStore.denys-mbp-sidestore
sudo launchctl kickstart -k system/actions.runner.ben-3310-SideStore.denys-mbp-sidestore
```

- [ ] **Step 4: Отключить sleep только от адаптера**

```bash
sudo pmset -c sleep 0
```

Expected: AC `sleep 0`, Battery `sleep 1`.

### Task 6: Smoke-test на Xcode/iOS 27

**Files:**
- Create transient: `/Users/github-runner-sidestore/smoke/SideStore`
- Inspect: `/Users/github-runner-sidestore/Library/Developer/Xcode/DerivedData`

**Interfaces:**
- Consumes: exact candidate commit и submodules.
- Produces: archive, IPA/dSYM, simulator build и boot evidence.

- [ ] **Step 1: Передать exact candidate через git bundle**

```bash
git bundle create /tmp/sidestore-ios27-runner.bundle codex/sidestore-ios27-runner
sudo -u github-runner-sidestore -H git clone \
  -b codex/sidestore-ios27-runner \
  /tmp/sidestore-ios27-runner.bundle \
  /Users/github-runner-sidestore/smoke/SideStore
sudo -u github-runner-sidestore -H git -C \
  /Users/github-runner-sidestore/smoke/SideStore submodule update --init --recursive
```

- [ ] **Step 2: Запустить regression/YAML checks**

```bash
sudo -u github-runner-sidestore -H env \
  PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin \
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  SIMULATOR_DEVICE="iPhone 13" \
  SIMULATOR_OS=27.0 \
  /bin/zsh -c 'cd ~/smoke/SideStore && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/ci -p "test_*.py" -v'
```

Expected: all regression tests PASS.

- [ ] **Step 3: Выполнить release-compatible archive/package**

```bash
python3 scripts/ci/workflow.py build
```

Expected: `Archive Succeeded`, `SideStore.ipa` и `SideStore.dSYMs.zip` существуют.

- [ ] **Step 4: Выполнить simulator build и boot iOS 27**

```bash
python3 scripts/ci/workflow.py tests-build
```

При отсутствии создать `iPhone 13` с device type
`com.apple.CoreSimulator.SimDeviceType.iPhone-13`, затем выбрать его строго из runtime
`com.apple.CoreSimulator.SimRuntime.iOS-27-0`, выполнить `simctl bootstatus -b`
и shutdown.

Expected: `Test Build Succeeded`; именно iOS 27.0 device достигает `Booted`.

### Task 7: Финальный аудит и handoff

**Files:**
- Inspect: local branch/worktree, launchd plist, runner HOME, GitHub runner API.

**Interfaces:**
- Consumes: все предыдущие acceptance evidence.
- Produces: immutable candidate SHA и отчёт без secrets.

- [ ] **Step 1: Проверить service restart**

Адресно завершить только listener UID 502, подтвердить новый PID и
`KeepAlive`/`last exit code = 0`.

- [ ] **Step 2: Проверить GitHub readback**

```bash
gh api repos/ben-3310/SideStore/actions/runners \
  --jq '.runners[] | select(.name == "denys-mbp-sidestore")'
```

Expected: `online`, `busy=false`, exact labels.

- [ ] **Step 3: Security audit**

Проверить UID/groups, modes HOME/credentials/service, отсутствие доступа к
`/Users/ben`, отсутствие token/password/private key patterns в `.env`, `.path`,
plist и logs. Не выводить credential contents.

- [ ] **Step 4: Финальный self-review**

Review immutable range от design/plan base до candidate SHA. Findings получают
стабильные ID, блокируют только correctness/security/data-loss/обязательные
criteria. Допускается не более двух адресных fix/recheck циклов.

- [ ] **Step 5: Handoff без push**

Сообщить runner/service/status, exact candidate SHA, smoke evidence, известное
ограничение отсутствующего `UITests` target и отдельно запросить разрешение на
push compatibility workflow.

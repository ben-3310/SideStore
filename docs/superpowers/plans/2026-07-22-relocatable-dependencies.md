# Relocatable Dependencies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permit an external local Dependencies checkout while preserving recursive Git checkouts and CI builds.

**Architecture:** Existing Xcode paths keep using `Dependencies/...`. A Python verifier accepts either a directory or directory symlink and requires the three project dependencies. The CI workflow entrypoints call it before build commands; contributor documentation gives the explicit relative-link setup.

**Tech Stack:** Python 3 standard library, unittest, Git, Xcode.

## Global Constraints

- Do not modify Xcode paths, application sources, contents of `Dependencies`, or nested gitlinks.
- The verifier never creates, deletes, moves, or replaces `Dependencies`.
- Accept a directory from a recursive checkout and a relative symlink that
  resolves to a directory; reject absolute symlink targets.
- Require `AltSign`, `em_proxy`, and `minimuxer` directories.
- `../SideStore_Dependencies` is the recommended primary-checkout example, not
  a required stored symlink target.

---

### Task 1: Dependency-layout verifier

**Files:**
- Create: `scripts/ci/dependencies.py`
- Create: `scripts/ci/test_dependencies.py`

**Interfaces:**
- Produces: `verify_dependencies(root: Path) -> None` and `DependencyLayoutError`.
- Consumes: a repository root containing `Dependencies`.

- [ ] **Step 1: Write failing tests**

```python
def test_accepts_directory_from_recursive_checkout(self):
    verify_dependencies(make_root_with_dependencies(self.tmpdir))

def test_accepts_relative_symlink_to_external_directory(self):
    external = make_dependencies(self.tmpdir / "SideStore_Dependencies")
    root = self.tmpdir / "SideStore"; root.mkdir()
    (root / "Dependencies").symlink_to(external, target_is_directory=True)
    verify_dependencies(root)

def test_rejects_missing_dependencies_path(self):
    with self.assertRaisesRegex(DependencyLayoutError, "missing Dependencies"):
        verify_dependencies(self.tmpdir)

def test_rejects_regular_file_and_broken_symlink(self):
    for setup in (make_dependencies_file, make_broken_dependencies_symlink):
        with self.subTest(setup=setup.__name__), self.assertRaises(DependencyLayoutError):
            verify_dependencies(setup(self.tmpdir))

def test_rejects_missing_required_child(self):
    root = make_root_with_dependencies(self.tmpdir, omit="minimuxer")
    with self.assertRaisesRegex(DependencyLayoutError, "minimuxer"):
        verify_dependencies(root)
```

- [ ] **Step 2: Verify RED**

Run: `python3 -m unittest scripts.ci.test_dependencies -v`

Expected: FAIL because `scripts.ci.dependencies` does not exist.

- [ ] **Step 3: Implement minimal verifier**

```python
REQUIRED_DEPENDENCIES = ("AltSign", "em_proxy", "minimuxer")

class DependencyLayoutError(RuntimeError):
    pass

def verify_dependencies(root: Path) -> None:
    dependencies = root / "Dependencies"
    if not dependencies.exists():
        raise DependencyLayoutError("missing Dependencies; initialise submodules or create the relative link")
    if not dependencies.is_dir():
        raise DependencyLayoutError("Dependencies must be a directory or a symlink to one")
    for name in REQUIRED_DEPENDENCIES:
        if not (dependencies / name).is_dir():
            raise DependencyLayoutError(f"missing required dependency: Dependencies/{name}")
```

Add an `argparse` CLI with `--root`, success output containing the resolved path, and exit code `1` for `DependencyLayoutError`.

- [ ] **Step 4: Verify GREEN and commit**

Run: `python3 -m unittest scripts.ci.test_dependencies -v`

Expected: PASS for directory, symlink, absent path, regular file, broken link, and absent child.

```bash
git add scripts/ci/dependencies.py scripts/ci/test_dependencies.py
git commit -m "test: verify dependency layout before builds"
```

### Task 2: Build gate and contributor setup

**Files:**
- Modify: `scripts/ci/workflow.py:142-166`
- Modify: `scripts/ci/test_workflow_pipelines.py:23-49`
- Modify: `CONTRIBUTING.md:31-44`

**Interfaces:**
- Consumes: `verify_dependencies(ROOT)`.
- Produces: archive and test-build flows which validate layout before `make`.

- [ ] **Step 1: Write failing pipeline tests**

```python
def test_build_verifies_dependencies_before_make(self):
    with patch.object(self.workflow, "verify_dependencies") as verify, patch.object(self.workflow, "run"):
        self.workflow.build()
    self.assertEqual(verify.call_args.args, (self.workflow.ROOT,))

def test_tests_build_verifies_dependencies_before_make(self):
    with patch.object(self.workflow, "verify_dependencies") as verify, patch.object(self.workflow, "run"):
        self.workflow.tests_build()
    self.assertEqual(verify.call_args.args, (self.workflow.ROOT,))
```

- [ ] **Step 2: Verify RED**

Run: `python3 -m unittest scripts.ci.test_workflow_pipelines -v`

Expected: FAIL because `workflow.py` does not import or call `verify_dependencies`.

- [ ] **Step 3: Implement the gate and document setup**

```python
from scripts.ci.dependencies import verify_dependencies

def build():
    verify_dependencies(ROOT)
    run("mkdir -p build/logs")

def tests_build():
    verify_dependencies(ROOT)
    run("mkdir -p build/logs")
```

Document this explicit local-only sequence in `CONTRIBUTING.md`:

```zsh
mv Dependencies ../SideStore_Dependencies
ln -s ../SideStore_Dependencies Dependencies
python3 scripts/ci/dependencies.py
```

Precede it with a warning not to run `mv` when the source contains uncommitted work; CI and ordinary recursive clones may retain their normal `Dependencies` directory.

- [ ] **Step 4: Verify GREEN and commit**

Run: `python3 -m unittest scripts.ci.test_dependencies scripts.ci.test_workflow_pipelines -v`

Expected: all tests pass and existing pipefail checks remain green.

```bash
git add CONTRIBUTING.md scripts/ci/workflow.py scripts/ci/test_workflow_pipelines.py
git commit -m "docs: support external dependencies checkout"
```

### Task 3: Local conversion and integration validation

**Files:**
- Modify: the untracked root `Dependencies` symlink only.

**Interfaces:**
- Produces: `Dependencies -> ../SideStore_Dependencies` in the primary checkout.

- [ ] **Step 1: Inspect only the link**

Run: `ls -ld Dependencies && readlink Dependencies`

Expected: the existing absolute symlink target.

- [ ] **Step 2: Replace the symlink only**

Run: `rm Dependencies && ln -s ../SideStore_Dependencies Dependencies`

Expected: a relative symlink; the target contents are untouched.

- [ ] **Step 3: Validate**

Run: `python3 scripts/ci/dependencies.py && python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v && git diff --check`

Expected: verifier success, all CI regression tests pass, and no whitespace errors.

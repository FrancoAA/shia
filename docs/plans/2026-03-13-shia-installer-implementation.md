# shia Installer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a curl-installable `install.sh` that installs `shia` into user-local paths and update README with the new install flow.

**Architecture:** Implement a root-level Bash installer that clones/updates the repo in `~/.local/share/shia/src`, writes a stable wrapper to `~/.local/bin/shia`, and optionally updates shell PATH config. Keep script idempotent and shell-aware across macOS/Linux.

**Tech Stack:** Bash, git, curl, jq, README markdown docs

---

### Task 1: Add root installer script

**Files:**
- Create: `install.sh`
- Reference: `../bashia/install.sh`

**Step 1: Write script skeleton and constants**

Create `install.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/FrancoAA/shia.git"
INSTALL_DIR="${HOME}/.local/bin"
SHIA_DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/shia"
SHIA_SRC="${SHIA_DATA_DIR}/src"
```

**Step 2: Add dependency checks and source resolution**

- Validate `curl`, `jq`, `git` exist.
- Resolve local script directory and detect local-source mode when `shia` file exists beside installer.
- Fallback to clone/update mode when running via curl pipe.

**Step 3: Add wrapper creation and PATH handling**

- Create `~/.local/bin`.
- Write wrapper at `~/.local/bin/shia` that executes `${SOURCE_DIR}/shia`.
- Detect if install dir is on PATH.
- If missing, detect rc file and append export line only once.
- If non-interactive, print manual PATH instructions.

**Step 4: Make installer executable**

Run: `chmod +x install.sh`

**Step 5: Commit (optional in this session)**

```bash
git add install.sh
git commit -m "feat: add curl-based installer for shia"
```

### Task 2: Update README install instructions

**Files:**
- Modify: `README.md`

**Step 1: Replace clone-first install section**

- Add primary install command:

```bash
curl -fsSL https://raw.githubusercontent.com/FrancoAA/shia/main/install.sh | bash
```

- Keep `shia init` as first-time setup next step.
- Keep a secondary section for cloning locally if users prefer.

**Step 2: Commit (optional in this session)**

```bash
git add README.md
git commit -m "docs: document one-line shia installation"
```

### Task 3: Verify behavior

**Files:**
- Verify: `install.sh`, `README.md`

**Step 1: Syntax check installer**

Run: `bash -n install.sh`
Expected: no output, exit code 0

**Step 2: Execute local install mode**

Run: `./install.sh`
Expected:
- Creates/updates `~/.local/bin/shia`
- Reports local source or clone/update source path
- Prints PATH guidance if needed

**Step 3: Smoke-check executable**

Run: `~/.local/bin/shia --version`
Expected: prints `shia v...`

**Step 4: Validate docs and git diff**

Run: `git diff -- install.sh README.md`
Expected: installer + docs changes align with described behavior

**Step 5: Final commit (optional in this session)**

```bash
git add install.sh README.md
git commit -m "feat: add shia installer and update install docs"
```

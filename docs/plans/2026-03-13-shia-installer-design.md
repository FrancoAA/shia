# shia Installer Design

## Goal

Provide a one-command installation flow for `shia` so users can run a curl-piped installer that sets up the CLI and makes it executable from their shell.

## Chosen Approach

Use a git-clone based installer script (Option 1) modeled after `bashia/install.sh`.

- Source code lives in `~/.local/share/shia/src`
- Executable wrapper lives in `~/.local/bin/shia`
- Installer supports both local execution and curl-piped execution
- PATH setup is optional and shell-aware

## Why This Approach

- `shia` is a multi-file project (`lib/`, `defaults/`), so cloning source is more maintainable than copying files piecemeal.
- Updates are simple and reliable (`git -C <src> pull`).
- Behavior stays consistent with existing tooling patterns in sibling projects.

## Installer Behavior

1. Validate required commands: `curl`, `jq`, `git`.
2. Detect install mode:
   - If script is run from a local clone and `shia` exists next to installer, use local source.
   - Otherwise clone or update `https://github.com/FrancoAA/shia.git` into data directory.
3. Create `~/.local/bin` if needed.
4. Create wrapper script `~/.local/bin/shia` that executes source `shia` entrypoint.
5. If install dir is not on PATH:
   - Detect shell rc file (`.zshrc`, `.bash_profile`/`.bashrc`, fallback `.profile`).
   - Prompt to append PATH export when interactive.
   - Avoid duplicate PATH entries.

## UX Details

- Clear status messages for install/update paths.
- If PATH is already configured, installer exits with success guidance.
- If non-interactive and PATH is missing, print manual instructions instead of blocking on prompt.

## Docs Update

Update README install section to prioritize:

```bash
curl -fsSL https://raw.githubusercontent.com/FrancoAA/shia/main/install.sh | bash
```

Then direct users to run `shia init`.

## Verification

- `bash -n install.sh` passes.
- Running installer from local repo mode creates wrapper in `~/.local/bin`.
- README instructions match script behavior and paths.

# shia - Single-shot Shell AI Utility

## Overview

`shia` is a single-shot CLI utility that sends a prompt to an LLM, optionally with piped stdin, and outputs the raw result. No REPL, no conversation state. It supports the full shellia plugin system, tools, and skills.

## Usage Patterns

```bash
# Direct prompt
shia "explain what kubernetes pods are"

# Piped input
cat error.log | shia "what's causing these errors"
git diff | shia "write a commit message for this"
ls -la | shia "which files were modified today"

# With a skill pre-loaded
shia -s coding "refactor this function" < main.py

# With flags
shia --debug "list running docker containers"
shia --dry-run "delete all .tmp files"
shia --profile work "check our API status"
shia --model anthropic/claude-sonnet-4 "summarize this" < report.txt

# Subcommands
shia init              # Setup wizard
shia plugins           # List loaded plugins
shia profiles          # List profiles
shia profile add work  # Add a new profile
```

## Architecture

Fork of shellia's core modules, stripped of REPL, web mode, and session management. Pure single-shot execution.

### Directory Structure

```
shia
lib/
  utils.sh          # Logging, spinner, version (stripped of format_markdown)
  config.sh         # Config loading with shellia fallback
  profiles.sh       # Multi-profile management
  prompt.sh         # System prompt assembly
  api.sh            # LLM API client + tool call loop
  executor.sh       # Dangerous command pattern matching
  tools.sh          # Tool registry (auto-discovery)
  plugins.sh        # Plugin system (hooks, CLI commands/flags)
  tools/
    run_command.sh   # Execute shell commands
    delegate_task.sh # Sub-agent delegation
  plugins/
    core/plugin.sh      # CLI: init, plugins
    safety/plugin.sh    # Hook: dangerous command confirmation
    settings/plugin.sh  # CLI flags: --debug, --dry-run, --profile, --model
    skills/plugin.sh    # Skill discovery + load_skill tool
    websearch/plugin.sh # web_search tool (Brave Search API)
    history/plugin.sh   # Hook: log prompts to history (simplified)
defaults/
  system_prompt.txt  # Base system prompt (rewritten for shia)
  dangerous_commands # Dangerous command patterns
```

### What Changes from Shellia

| Module | Changes |
|--------|---------|
| Entry point (`shia`) | New. No REPL, no web mode. Single-shot only. |
| `lib/utils.sh` | Remove `format_markdown` and `_fmt_inline`. No themes. Simpler ANSI detection. |
| `lib/config.sh` | Config dir = `~/.config/shia/`, falls back to `~/.config/shellia/` for API config. |
| `lib/profiles.sh` | Rebranded references. Config dir uses SHIA_CONFIG_DIR. |
| `lib/prompt.sh` | Rebranded. References `shia` not `shellia`. |
| `lib/api.sh` | Remove web mode event emission. Remove `build_conversation_messages`. |
| `lib/executor.sh` | Unchanged. |
| `lib/themes.sh` | Removed entirely. Not needed for raw output. |
| `lib/tools.sh` | Unchanged. |
| `lib/plugins.sh` | Remove REPL command dispatch. Remove `generate_help` REPL references. Rebrand. |
| `lib/repl.sh` | Removed entirely. |
| Tools: `run_plan.sh` | Removed. |
| Tools: `ask_user.sh` | Removed. |
| Tools: `todo_write.sh` | Removed. |
| Plugins: `themes/` | Removed. |
| Plugins: `serve/` | Removed. |
| Plugins: `telegram/` | Removed. |
| Plugins: `ralp/` | Removed. |
| `defaults/system_prompt.txt` | Rewritten for shia: single-shot only, no interactive mode instructions. |

### Config Fallback Logic

```
SHIA_CONFIG_DIR = ~/.config/shia/
SHIA_FALLBACK_DIR = ~/.config/shellia/

For each config source:
  1. Check SHIA_CONFIG_DIR first
  2. If not found, check SHIA_FALLBACK_DIR
  3. If neither exists, prompt user to run `shia init`
```

This means if you already have shellia configured, `shia` works out of the box with no setup.

### Output Behavior

- Default: raw text output, no ANSI codes, no markdown formatting
- `--color` flag: opt-in to ANSI-formatted markdown output (for terminal display)
- Stderr: used for spinner, tool UX, debug logs (always with ANSI if terminal)
- Stdout: always clean response text (pipe-safe by default)

### Entry Point Flow

```
1. Source lib modules
2. Check dependencies (jq, curl)
3. Load plugins (built-in + user)
4. Parse CLI flags (plugin-provided)
5. Try CLI subcommand dispatch (init, plugins, profiles, profile)
6. Read stdin if piped
7. Combine prompt + piped input
8. Load config (with shellia fallback)
9. Validate config
10. Load tools
11. Fire init hook
12. Build system prompt (mode = "pipe" or "single-prompt")
13. Build single messages
14. Build tools array
15. Show spinner on stderr
16. api_chat_loop
17. Print raw response to stdout
18. Fire shutdown hook
```

### Plugin Hooks (Subset)

Since there's no REPL, the hook set is reduced:

| Hook | When |
|------|------|
| `init` | After config loaded, before API call |
| `shutdown` | Before exit |
| `user_message` | After prompt is assembled |
| `assistant_message` | After response received |
| `before_api_call` | Before each API request |
| `after_api_call` | After each API response |
| `before_tool_call` | Before tool execution |
| `after_tool_call` | After tool execution |
| `prompt_build` | Building system prompt |

Removed: `conversation_reset` (no sessions).

### Skill Loading

Two mechanisms:
1. **CLI flag:** `shia -s <skill-name> "prompt"` -- pre-loads a skill into the system prompt
2. **LLM tool:** `load_skill` -- LLM can load skills on demand during execution

Skills are discovered from:
- `~/.agents/skills/` (shared hub)
- `~/.config/shia/skills/` (shia-exclusive, fallback to `~/.config/shellia/skills/`)

### Variables Naming Convention

All shellia variables are renamed: `SHELLIA_*` -> `SHIA_*`
- `SHIA_API_URL`, `SHIA_API_KEY`, `SHIA_MODEL`
- `SHIA_CONFIG_DIR`, `SHIA_DEBUG`, `SHIA_DRY_RUN`
- `SHIA_DIR`, `SHIA_VERSION`

Environment variable fallback: `SHIA_API_KEY` takes precedence, then falls back to `SHELLIA_API_KEY` from shellia's config.

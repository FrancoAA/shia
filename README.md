# shia

`shia` is a single-shot shell AI CLI. You pass a prompt once, it builds a system prompt with local context, executes tool calls as needed, and prints one final response.

## Requirements

- Bash 3.2+
- `jq`
- `curl`
- `git` (for installer)

## Install

Quick install:

```bash
curl -fsSL https://raw.githubusercontent.com/FrancoAA/shia/main/install.sh | bash
```

Manual install from source:

```bash
git clone git@github.com:FrancoAA/shia.git
cd shia
./install.sh
./shia --help
```

## First-time setup

Run:

```bash
shia init
```

This creates config under `~/.config/shia`:

- `config` (active profile selection)
- `profiles` (API URL, API key, model per profile)
- `dangerous_commands` (patterns used by safety plugin)
- `system_prompt` (your extra prompt instructions)

## Usage

Single prompt:

```bash
shia "list all running docker containers"
```

Pipe + prompt:

```bash
cat error.log | shia "what is failing and why"
```

Common options:

- `--profile <name>`: use a specific profile for this request
- `--model <model-id>`: override model for this request
- `--debug`: print internal debug logs
- `--dry-run`: show commands without executing them
- `-s <skill>` / `--skill <skill>`: pre-load one skill into prompt context

Subcommands:

- `shia init`: interactive setup wizard
- `shia plugins`: list loaded plugins and their hooks
- `shia profiles`: list configured profiles
- `shia profile add <name>`: create/update a profile
- `shia profile remove <name>`: remove a profile

## Plugin interface

Plugins are discovered from:

- Built-ins: `lib/plugins`
- User plugins: `~/.config/shia/plugins`

Supported plugin layout:

- `plugins/<name>.sh`
- `plugins/<name>/plugin.sh`

Each plugin must define:

- `plugin_<name>_info()`: one-line description
- `plugin_<name>_hooks()`: space-separated hook names

For each subscribed hook, shia calls:

- `plugin_<name>_on_<hook>()`

Available hook points in the runtime:

- `init`: after config/tools load
- `prompt_build`: append context into system prompt
- `before_tool_call`: inspect/block tool execution
- `user_message`: after user prompt is finalized
- `assistant_message`: after model response is produced
- `shutdown`: right before process exit

CLI extensions from plugins:

- Commands: `cli_cmd_<name>_handler`, optional `_help`, optional `_setup`
- Flags: `cli_flag_<name>_handler`, optional `_help`

Tool extensions from plugins:

- Tool schema: `tool_<name>_schema`
- Tool executor: `tool_<name>_execute`

## Included plugins

- `core`: exposes core CLI commands (`init`, `plugins`)
- `settings`: adds CLI flags and profile commands
- `safety`: blocks dangerous `run_command` calls unless confirmed
- `skills`: discovers skills and provides the `load_skill` tool
- `websearch`: provides `web_search` tool (Brave Search API)

Note: `websearch` requires `BRAVE_SEARCH_API_KEY` (or plugin config key `api_key`) to function.

## Project layout

- `shia`: CLI entrypoint
- `lib/`: runtime modules (config, prompt, API loop, tools, plugins)
- `lib/tools/`: built-in tools (`run_command`, `delegate_task`)
- `lib/plugins/`: built-in plugins
- `defaults/`: default system prompt and dangerous command patterns

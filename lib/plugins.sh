#!/usr/bin/env bash
# Plugin registry: discovers, loads, and manages plugins with hook-based extensibility
# Compatible with Bash 3.2+ (no associative arrays)

SHIA_LOADED_PLUGINS=()
_SHIA_HOOK_ENTRIES=()

_hook_get_plugins() {
    local hook="$1"
    local result=""
    local entry
    for entry in ${_SHIA_HOOK_ENTRIES[@]+"${_SHIA_HOOK_ENTRIES[@]}"}; do
        if [[ "$entry" == "${hook}:"* ]]; then
            local plugin="${entry#*:}"
            result="${result:+${result} }${plugin}"
        fi
    done
    echo "$result"
}

_hook_has_subscribers() {
    local hook="$1"
    local entry
    for entry in ${_SHIA_HOOK_ENTRIES[@]+"${_SHIA_HOOK_ENTRIES[@]}"}; do
        [[ "$entry" == "${hook}:"* ]] && return 0
    done
    return 1
}

_hook_add() {
    local hook="$1"
    local plugin="$2"
    _SHIA_HOOK_ENTRIES+=("${hook}:${plugin}")
}

_hook_remove_plugin() {
    local plugin="$1"
    local new_entries=()
    local entry
    for entry in ${_SHIA_HOOK_ENTRIES[@]+"${_SHIA_HOOK_ENTRIES[@]}"}; do
        if [[ "$entry" != *":${plugin}" ]]; then
            new_entries+=("$entry")
        fi
    done
    _SHIA_HOOK_ENTRIES=(${new_entries[@]+"${new_entries[@]}"})
}

_hook_list_names() {
    local seen=""
    local entry
    for entry in ${_SHIA_HOOK_ENTRIES[@]+"${_SHIA_HOOK_ENTRIES[@]}"}; do
        local hook="${entry%%:*}"
        if [[ " ${seen} " != *" ${hook} "* ]]; then
            echo "$hook"
            seen="${seen:+${seen} }${hook}"
        fi
    done
}

load_builtin_plugins() {
    _load_plugins_from_dir "${SHIA_DIR}/lib/plugins"
}

load_plugins() {
    _load_plugins_from_dir "${SHIA_DIR}/lib/plugins"
    _load_plugins_from_dir "${SHIA_CONFIG_DIR}/plugins"
}

_load_plugins_from_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    for plugin_file in "${dir}"/*.sh; do
        [[ -f "$plugin_file" ]] || continue
        local name
        name=$(basename "$plugin_file" .sh)
        _register_plugin "$name" "$plugin_file"
    done
    for plugin_dir in "${dir}"/*/; do
        [[ -d "$plugin_dir" ]] || continue
        local plugin_file="${plugin_dir}plugin.sh"
        [[ -f "$plugin_file" ]] || continue
        local name
        name=$(basename "$plugin_dir")
        _register_plugin "$name" "$plugin_file"
    done
}

_register_plugin() {
    local name="$1"
    local file="$2"
    source "$file" || {
        log_warn "plugin: failed to source '${file}'"
        return 1
    }
    if ! declare -F "plugin_${name}_info" >/dev/null 2>&1; then
        log_warn "plugin: '${name}' missing plugin_${name}_info()"
        return 1
    fi
    if ! declare -F "plugin_${name}_hooks" >/dev/null 2>&1; then
        log_warn "plugin: '${name}' missing plugin_${name}_hooks()"
        return 1
    fi
    if _plugin_is_loaded "$name"; then
        _unregister_plugin_hooks "$name"
        local new_list=()
        local p
        for p in "${SHIA_LOADED_PLUGINS[@]}"; do
            [[ "$p" != "$name" ]] && new_list+=("$p")
        done
        SHIA_LOADED_PLUGINS=(${new_list[@]+"${new_list[@]}"})
    fi
    SHIA_LOADED_PLUGINS+=("$name")
    local hooks
    hooks=$("plugin_${name}_hooks")
    local hook
    for hook in $hooks; do
        _hook_add "$hook" "$name"
    done
    debug_log "plugins" "loaded '${name}' from $(basename "$file")"
}

_plugin_is_loaded() {
    local name="$1"
    local p
    for p in ${SHIA_LOADED_PLUGINS[@]+"${SHIA_LOADED_PLUGINS[@]}"}; do
        [[ "$p" == "$name" ]] && return 0
    done
    return 1
}

_unregister_plugin_hooks() {
    local name="$1"
    _hook_remove_plugin "$name"
}

fire_hook() {
    local hook_name="$1"
    shift
    _hook_has_subscribers "$hook_name" || return 0
    local plugins
    plugins=$(_hook_get_plugins "$hook_name")
    local plugin
    for plugin in $plugins; do
        local func="plugin_${plugin}_on_${hook_name}"
        if declare -F "$func" >/dev/null 2>&1; then
            "$func" "$@"
        fi
    done
}

fire_prompt_hook() {
    local mode="${1:-}"
    local output=""
    _hook_has_subscribers "prompt_build" || { echo ""; return 0; }
    local plugins
    plugins=$(_hook_get_plugins "prompt_build")
    local plugin
    for plugin in $plugins; do
        local func="plugin_${plugin}_on_prompt_build"
        if declare -F "$func" >/dev/null 2>&1; then
            local chunk
            chunk=$("$func" "$mode")
            output="${output}${chunk}"
        fi
    done
    echo "$output"
}

plugin_config_get() {
    local plugin_name="$1"
    local key="$2"
    local default="${3:-}"
    local config_file="${SHIA_CONFIG_DIR}/plugins/${plugin_name}/config"
    if [[ ! -f "$config_file" ]]; then
        echo "$default"
        return 0
    fi
    local value
    value=$(grep "^${key}=" "$config_file" 2>/dev/null | head -1 | cut -d'=' -f2-)
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

list_plugins() {
    if [[ ${#SHIA_LOADED_PLUGINS[@]} -eq 0 ]]; then
        echo "No plugins loaded."
        return 0
    fi
    echo "Loaded plugins:"
    local plugin
    for plugin in "${SHIA_LOADED_PLUGINS[@]}"; do
        local info hooks
        info=$("plugin_${plugin}_info" 2>/dev/null)
        hooks=$("plugin_${plugin}_hooks" 2>/dev/null)
        echo "  ${plugin} - ${info:-no description}"
        if [[ -n "$hooks" ]]; then
            echo "    hooks: ${hooks}"
        fi
    done
}

dispatch_cli_command() {
    local cmd_name="$1"
    shift
    local func_name="cli_cmd_${cmd_name//-/_}_handler"
    if ! declare -F "$func_name" >/dev/null 2>&1; then
        return 1
    fi
    local setup_func="cli_cmd_${cmd_name//-/_}_setup"
    if declare -F "$setup_func" >/dev/null 2>&1; then
        local setup_steps
        setup_steps=$("$setup_func")
        _run_cli_setup "$setup_steps"
    fi
    "$func_name" "$@"
}

_run_cli_setup() {
    local steps="$1"
    local step
    for step in $steps; do
        case "$step" in
            config)      load_config ;;
            validate)    validate_config ;;
            tools)       load_tools ;;
            plugins)     load_plugins ;;
            hooks_init)  fire_hook "init" ;;
        esac
    done
}

get_cli_commands() {
    declare -F | awk '{print $3}' | grep '^cli_cmd_.*_handler$' | sed 's/^cli_cmd_//;s/_handler$//' | sort
}

get_cli_command_help() {
    local help_funcs
    help_funcs=$(declare -F | awk '{print $3}' | grep '^cli_cmd_.*_help$' | sort)
    [[ -z "$help_funcs" ]] && return 0
    local func
    for func in $help_funcs; do
        "$func"
    done
}

parse_cli_flags() {
    PROMPT_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --*)
                local flag_name="${1#--}"
                flag_name="${flag_name//-/_}"
                local handler="cli_flag_${flag_name}_handler"
                if declare -F "$handler" >/dev/null 2>&1; then
                    shift
                    local _cli_flag_tmp
                    _cli_flag_tmp=$(mktemp)
                    "$handler" "$@" > "$_cli_flag_tmp"
                    local consumed
                    consumed=$(cat "$_cli_flag_tmp")
                    rm -f "$_cli_flag_tmp"
                    consumed=${consumed:-0}
                    local i
                    for ((i = 0; i < consumed; i++)); do
                        shift
                    done
                else
                    PROMPT_ARGS+=("$1")
                    shift
                fi
                ;;
            *)
                PROMPT_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

get_cli_flag_help() {
    local help_funcs
    help_funcs=$(declare -F | awk '{print $3}' | grep '^cli_flag_.*_help$' | sort)
    [[ -z "$help_funcs" ]] && return 0
    local func
    for func in $help_funcs; do
        "$func"
    done
}

generate_help() {
    echo "Usage: shia [OPTIONS] [COMMAND] [PROMPT]"
    echo ""
    echo "A single-shot shell AI utility. Send a prompt, get a response."
    echo ""
    local cmd_help
    cmd_help=$(get_cli_command_help)
    if [[ -n "$cmd_help" ]]; then
        echo "Commands:"
        echo "$cmd_help"
        echo ""
    fi
    local flag_help
    flag_help=$(get_cli_flag_help)
    if [[ -n "$flag_help" ]]; then
        echo "Options:"
        echo "$flag_help"
    fi
    echo "  --help, -h                Show this help message"
    echo "  --version                 Print version"
    echo ""
    echo "Examples:"
    echo "  shia \"explain kubernetes pods\""
    echo "  cat error.log | shia \"what's wrong\""
    echo "  git diff | shia \"write a commit message\""
    echo "  shia -s coding \"refactor this\" < main.py"
}

#!/usr/bin/env bash
# Plugin: safety — dangerous command detection and confirmation

plugin_safety_info() {
    echo "Dangerous command detection and confirmation prompts"
}

plugin_safety_hooks() {
    echo "init before_tool_call"
}

plugin_safety_on_init() {
    load_dangerous_commands
    debug_log "plugin:safety" "loaded ${#DANGEROUS_PATTERNS[@]} dangerous patterns"
}

plugin_safety_on_before_tool_call() {
    local tool_name="$1"
    local tool_args="$2"

    case "$tool_name" in
        run_command)
            local cmd
            cmd=$(echo "$tool_args" | jq -r '.command' 2>/dev/null)
            [[ -z "$cmd" ]] && return 0
            _safety_check_command "$cmd"
            ;;
    esac
}

_safety_check_command() {
    local cmd="$1"
    if is_dangerous "$cmd"; then
        debug_log "plugin:safety" "dangerous pattern matched: ${cmd}"
        echo -e "\033[0;33mWarning: '${cmd}' matches a dangerous pattern.\033[0m" >&2
        # If no tty available, block by default
        if [[ ! -e /dev/tty ]]; then
            log_warn "Command blocked by safety plugin (no tty for confirmation)." >&2
            SHIA_TOOL_BLOCKED=true
            return 0
        fi
        local confirm=""
        read -rp "Run this? [y/N]: " confirm </dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_warn "Command blocked by safety plugin." >&2
            SHIA_TOOL_BLOCKED=true
            return 0
        fi
    fi
}

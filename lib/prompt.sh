#!/usr/bin/env bash
# System prompt assembly for shia
build_system_prompt() {
    local mode="${1:-single-prompt}"
    local shell_name
    shell_name=$(detect_shell)
    local base_prompt
    base_prompt=$(cat "${SHIA_DIR}/defaults/system_prompt.txt")
    base_prompt="${base_prompt}

CONTEXT:
- User's shell: ${shell_name}
- Operating system: $(uname -s)
- Current directory: $(pwd)
- Mode: ${mode}
- shia install directory: ${SHIA_DIR}
- shia config directory: ${SHIA_CONFIG_DIR}
- User plugins directory: ${SHIA_CONFIG_DIR}/plugins
"
    if [[ -f "$SHIA_USER_PROMPT_FILE" ]]; then
        local user_additions
        user_additions=$(grep -v '^[[:space:]]*#' "$SHIA_USER_PROMPT_FILE" | grep -v '^[[:space:]]*$' || true)
        if [[ -n "$user_additions" ]]; then
            base_prompt="${base_prompt}

USER PREFERENCES:
${user_additions}"
        fi
    fi
    local plugin_additions
    plugin_additions=$(fire_prompt_hook "$mode")
    if [[ -n "$plugin_additions" ]]; then
        base_prompt="${base_prompt}
${plugin_additions}"
    fi
    debug_log "shell" "$shell_name"
    debug_block "system_prompt" "$base_prompt" 5
    echo "$base_prompt"
}

detect_shell() {
    local shell_path="${SHELL:-/bin/bash}"
    basename "$shell_path"
}

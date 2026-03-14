#!/usr/bin/env bash
# Configuration loading for shia
# Falls back to shellia config if shia's own config doesn't exist

SHIA_CONFIG_DIR="${SHIA_CONFIG_DIR:-${XDG_CONFIG_HOME:-${HOME}/.config}/shia}"
SHIA_FALLBACK_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/shellia"
SHIA_CONFIG_FILE="${SHIA_CONFIG_FILE:-${SHIA_CONFIG_DIR}/config}"
SHIA_DANGEROUS_FILE="${SHIA_DANGEROUS_FILE:-${SHIA_CONFIG_DIR}/dangerous_commands}"
SHIA_USER_PROMPT_FILE="${SHIA_USER_PROMPT_FILE:-${SHIA_CONFIG_DIR}/system_prompt}"

# Resolve a config path with shellia fallback
# Args: $1 = path relative to config dir (e.g. "config", "profiles", "dangerous_commands")
# Returns: the first existing path, or the shia path if neither exists
_resolve_config_path() {
    local relative="$1"
    local shia_path="${SHIA_CONFIG_DIR}/${relative}"
    local shellia_path="${SHIA_FALLBACK_DIR}/${relative}"

    if [[ -f "$shia_path" ]]; then
        echo "$shia_path"
    elif [[ -f "$shellia_path" ]]; then
        debug_log "config" "fallback to shellia: ${relative}"
        echo "$shellia_path"
    else
        echo "$shia_path"
    fi
}

# Load config from file, env vars, and profiles
load_config() {
    # Resolve config file with fallback
    local config_file
    config_file=$(_resolve_config_path "config")

    # Load config file if it exists (env vars already set take precedence)
    if [[ -f "$config_file" ]]; then
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            # Trim whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            # Map SHELLIA_ keys to SHIA_ equivalents
            local shia_key="${key/SHELLIA_/SHIA_}"
            # Only set if not already set via env var (check both SHIA_ and original)
            if [[ -z "${!shia_key:-}" && -z "${!key:-}" ]]; then
                export "$shia_key=$value"
            fi
        done < "$config_file"
    fi

    # Apply defaults for settings not set by env vars or config file
    SHIA_PROFILE="${SHIA_PROFILE:-${SHELLIA_PROFILE:-default}}"

    # Initialize API vars — check SHIA_ first, then SHELLIA_ fallback
    SHIA_API_URL="${SHIA_API_URL:-${SHELLIA_API_URL:-}}"
    SHIA_API_KEY="${SHIA_API_KEY:-${SHELLIA_API_KEY:-}}"
    SHIA_MODEL="${SHIA_MODEL:-${SHELLIA_MODEL:-}}"

    # Resolve profiles file with fallback
    local profiles_file
    profiles_file=$(_resolve_config_path "profiles")
    SHIA_PROFILES_FILE="$profiles_file"

    # Load API settings from profile if profiles file exists
    if [[ -f "$SHIA_PROFILES_FILE" ]]; then
        # Only load profile if API vars aren't already set via env
        if [[ -z "$SHIA_API_URL" && -z "$SHIA_API_KEY" ]]; then
            if profile_exists "$SHIA_PROFILE"; then
                load_profile "$SHIA_PROFILE"
            else
                log_error "Profile '${SHIA_PROFILE}' not found."
                log_info "Available profiles: $(list_profile_names)"
            fi
        fi
    fi

    # Resolve dangerous commands file with fallback
    SHIA_DANGEROUS_FILE=$(_resolve_config_path "dangerous_commands")
    if [[ ! -f "$SHIA_DANGEROUS_FILE" ]]; then
        SHIA_DANGEROUS_FILE="${SHIA_DIR}/defaults/dangerous_commands"
    fi

    # Resolve user prompt file with fallback
    SHIA_USER_PROMPT_FILE=$(_resolve_config_path "system_prompt")
}

# Validate that required config is present
validate_config() {
    if [[ -z "$SHIA_API_URL" ]]; then
        die "SHIA_API_URL is not set. Run 'shia init' or set the environment variable."
    fi
    if [[ -z "$SHIA_API_KEY" ]]; then
        die "SHIA_API_KEY is not set. Run 'shia init' or set the environment variable."
    fi
    if [[ -z "$SHIA_MODEL" ]]; then
        die "SHIA_MODEL is not set. Run 'shia init' or set the environment variable."
    fi
}

# Interactive setup wizard
shia_init() {
    echo -e "\033[1mshia init\033[0m"
    echo ""

    if [[ -d "$SHIA_CONFIG_DIR" ]]; then
        echo "Existing configuration found at ${SHIA_CONFIG_DIR}"
        read -rp "Reconfigure? [y/N]: " reconfigure
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            echo "Keeping existing configuration."
            return 0
        fi
    fi

    mkdir -p "$SHIA_CONFIG_DIR"

    # API URL
    read -rp "API provider URL [https://openrouter.ai/api/v1]: " api_url
    api_url="${api_url:-https://openrouter.ai/api/v1}"

    # API Key
    read -rsp "API key: " api_key
    echo ""
    if [[ -z "$api_key" ]]; then
        die "API key cannot be empty."
    fi

    # Model
    read -rp "Model ID (e.g. anthropic/claude-sonnet-4, openai/gpt-4o): " model
    if [[ -z "$model" ]]; then
        die "Model ID cannot be empty."
    fi

    # Write config file
    cat > "${SHIA_CONFIG_DIR}/config" <<EOF
# shia configuration
SHIA_PROFILE=default
EOF
    chmod 600 "${SHIA_CONFIG_DIR}/config"

    # Create profiles file with "default" profile
    local profiles_json
    profiles_json=$(jq -n \
        --arg url "$api_url" \
        --arg key "$api_key" \
        --arg model "$model" \
        '{"default": {"api_url": $url, "api_key": $key, "model": $model}}')
    echo "$profiles_json" > "${SHIA_CONFIG_DIR}/profiles"
    chmod 600 "${SHIA_CONFIG_DIR}/profiles"

    # Copy dangerous commands if not present
    if [[ ! -f "${SHIA_CONFIG_DIR}/dangerous_commands" ]]; then
        cp "${SHIA_DIR}/defaults/dangerous_commands" "${SHIA_CONFIG_DIR}/dangerous_commands"
    fi

    # Create empty user system prompt if not present
    if [[ ! -f "${SHIA_CONFIG_DIR}/system_prompt" ]]; then
        cat > "${SHIA_CONFIG_DIR}/system_prompt" <<'EOF'
# Custom instructions for shia (appended to base prompt)
# Uncomment and edit lines below, or add your own.
# Examples:
#   Prefer eza over ls
#   Use doas instead of sudo
#   Always use long flags for readability
EOF
    fi

    log_success "Configuration saved."
    echo ""
    echo "Profile 'default' created with model: ${model}"
    echo ""
    echo "You can now use shia:"
    echo "  shia \"list all running docker containers\""
    echo "  cat file.txt | shia \"explain this\""
    echo ""
    echo "Add more profiles with: shia profile add <name>"
}

#!/usr/bin/env bash
# Multi-profile management for shia
SHIA_PROFILES_FILE="${SHIA_PROFILES_FILE:-}"

profile_exists() {
    local name="$1"
    [[ -f "$SHIA_PROFILES_FILE" ]] || return 1
    jq -e --arg name "$name" 'has($name)' "$SHIA_PROFILES_FILE" >/dev/null 2>&1
}

load_profile() {
    local name="$1"
    if [[ ! -f "$SHIA_PROFILES_FILE" ]]; then
        log_error "No profiles file found. Run 'shia init' to set up."
        return 1
    fi
    if ! profile_exists "$name"; then
        log_error "Profile '${name}' not found."
        log_info "Available profiles: $(list_profile_names)"
        return 1
    fi
    SHIA_API_URL=$(jq -r --arg name "$name" '.[$name].api_url' "$SHIA_PROFILES_FILE")
    SHIA_API_KEY=$(jq -r --arg name "$name" '.[$name].api_key' "$SHIA_PROFILES_FILE")
    SHIA_MODEL=$(jq -r --arg name "$name" '.[$name].model' "$SHIA_PROFILES_FILE")
    SHIA_PROFILE="$name"
    debug_log "profile" "loaded '${name}' (model=${SHIA_MODEL})"
}

list_profile_names() {
    if [[ ! -f "$SHIA_PROFILES_FILE" ]]; then
        echo "(none)"
        return
    fi
    jq -r 'keys | join(", ")' "$SHIA_PROFILES_FILE"
}

list_profiles() {
    if [[ ! -f "$SHIA_PROFILES_FILE" ]]; then
        echo "No profiles configured. Run 'shia init' to set up."
        return
    fi
    local profiles
    profiles=$(jq -r 'keys[]' "$SHIA_PROFILES_FILE")
    if [[ -z "$profiles" ]]; then
        echo "No profiles configured. Run 'shia profile add <name>' to create one."
        return
    fi
    local current="${SHIA_PROFILE:-default}"
    echo "Profiles:"
    while IFS= read -r name; do
        local model api_url
        model=$(jq -r --arg name "$name" '.[$name].model' "$SHIA_PROFILES_FILE")
        api_url=$(jq -r --arg name "$name" '.[$name].api_url' "$SHIA_PROFILES_FILE")
        if [[ "$name" == "$current" ]]; then
            echo "  * ${name}  model: ${model}  url: ${api_url}"
        else
            echo "    ${name}  model: ${model}  url: ${api_url}"
        fi
    done <<< "$profiles"
}

add_profile() {
    local name="$1"
    if profile_exists "$name"; then
        log_warn "Profile '${name}' already exists."
        read -rp "Overwrite? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Cancelled."
            return 0
        fi
    fi
    read -rp "API provider URL [https://openrouter.ai/api/v1]: " api_url
    api_url="${api_url:-https://openrouter.ai/api/v1}"
    read -rsp "API key: " api_key
    echo ""
    if [[ -z "$api_key" ]]; then
        log_error "API key cannot be empty."
        return 1
    fi
    read -rp "Model ID (e.g. anthropic/claude-sonnet-4, openai/gpt-4o): " model
    if [[ -z "$model" ]]; then
        log_error "Model ID cannot be empty."
        return 1
    fi
    if [[ ! -f "$SHIA_PROFILES_FILE" ]]; then
        echo '{}' > "$SHIA_PROFILES_FILE"
        chmod 600 "$SHIA_PROFILES_FILE"
    fi
    local updated
    updated=$(jq --arg name "$name" --arg url "$api_url" --arg key "$api_key" --arg model "$model" \
        '.[$name] = {"api_url": $url, "api_key": $key, "model": $model}' "$SHIA_PROFILES_FILE")
    echo "$updated" > "$SHIA_PROFILES_FILE"
    log_success "Profile '${name}' saved."
}

remove_profile() {
    local name="$1"
    if ! profile_exists "$name"; then
        log_error "Profile '${name}' not found."
        return 1
    fi
    local count
    count=$(jq 'keys | length' "$SHIA_PROFILES_FILE")
    if [[ "$count" -le 1 ]]; then
        log_error "Cannot remove the last profile. Add another profile first."
        return 1
    fi
    read -rp "Remove profile '${name}'? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Cancelled."
        return 0
    fi
    local updated
    updated=$(jq --arg name "$name" 'del(.[$name])' "$SHIA_PROFILES_FILE")
    echo "$updated" > "$SHIA_PROFILES_FILE"
    log_success "Profile '${name}' removed."
    if [[ "${SHIA_PROFILE:-}" == "$name" ]]; then
        local first
        first=$(jq -r 'keys[0]' "$SHIA_PROFILES_FILE")
        log_info "Switched to profile: ${first}"
        SHIA_PROFILE="$first"
    fi
}

#!/usr/bin/env bash
# Plugin: settings — CLI flags and profile management

plugin_settings_info() {
    echo "Settings, flags, and profile management"
}

plugin_settings_hooks() {
    echo ""
}

# === CLI flags ===

# --- --dry-run ---
cli_flag_dry_run_handler() {
    SHIA_DRY_RUN=true
    echo 0
}

cli_flag_dry_run_help() {
    echo "  --dry-run                 Show command without executing"
}

# --- --debug ---
cli_flag_debug_handler() {
    SHIA_DEBUG=true
    echo 0
}

cli_flag_debug_help() {
    echo "  --debug                   Show debug information"
}

# --- --profile ---
cli_flag_profile_handler() {
    if [[ -z "${1:-}" ]]; then
        die "Usage: --profile <name>"
    fi
    SHIA_PROFILE="$1"
    echo 1
}

cli_flag_profile_help() {
    echo "  --profile <name>          Use a specific profile"
}

# --- --model ---
cli_flag_model_handler() {
    if [[ -z "${1:-}" ]]; then
        die "Usage: --model <model-id>"
    fi
    SHIA_MODEL="$1"
    echo 1
}

cli_flag_model_help() {
    echo "  --model <model-id>        Override model for this request"
}

# --- -s / --skill ---
cli_flag_s_handler() {
    if [[ -z "${1:-}" ]]; then
        die "Usage: -s <skill-name>"
    fi
    SHIA_PRELOAD_SKILL="$1"
    echo 1
}

cli_flag_s_help() {
    echo "  -s <skill-name>           Pre-load a skill into the prompt"
}

cli_flag_skill_handler() {
    if [[ -z "${1:-}" ]]; then
        die "Usage: --skill <skill-name>"
    fi
    SHIA_PRELOAD_SKILL="$1"
    echo 1
}

cli_flag_skill_help() {
    echo "  --skill <skill-name>      Pre-load a skill into the prompt"
}

# === CLI subcommands ===

# --- profiles ---
cli_cmd_profiles_handler() {
    list_profiles
}

cli_cmd_profiles_help() {
    echo "  profiles                  List all profiles"
}

cli_cmd_profiles_setup() {
    echo "config"
}

# --- profile add|remove ---
cli_cmd_profile_handler() {
    local action="${1:-}"
    local name="${2:-}"

    case "$action" in
        add)
            [[ -z "$name" ]] && die "Usage: shia profile add <name>"
            add_profile "$name"
            ;;
        remove)
            [[ -z "$name" ]] && die "Usage: shia profile remove <name>"
            remove_profile "$name"
            ;;
        *)
            die "Usage: shia profile add|remove <name>"
            ;;
    esac
}

cli_cmd_profile_help() {
    echo "  profile add|remove <name> Add or remove a profile"
}

cli_cmd_profile_setup() {
    echo "config"
}

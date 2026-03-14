#!/usr/bin/env bash
# Shared utilities for shia

SHIA_VERSION="0.1.0"

# Debug mode (set via --debug flag or SHIA_DEBUG env var)
SHIA_DEBUG="${SHIA_DEBUG:-false}"

debug_log() {
    [[ "$SHIA_DEBUG" == "true" || "$SHIA_DEBUG" == "1" ]] || return 0
    local label="$1"
    shift
    echo -e "\033[2m[debug] ${label}:\033[0m $*" >&2
}

debug_block() {
    [[ "$SHIA_DEBUG" == "true" || "$SHIA_DEBUG" == "1" ]] || return 0
    local label="$1"
    local content="$2"
    local max_lines="${3:-10}"
    local line_count
    line_count=$(echo "$content" | wc -l | tr -d ' ')
    echo -e "\033[2m[debug] ${label} (${line_count} lines):\033[0m" >&2
    if [[ $line_count -le $max_lines ]]; then
        echo -e "\033[2m${content}\033[0m" >&2
    else
        echo -e "\033[2m$(echo "$content" | head -n "$max_lines")\033[0m" >&2
        echo -e "\033[2m  ... ($((line_count - max_lines)) more lines)\033[0m" >&2
    fi
}

log_info() {
    echo -e "\033[0;34m${1}\033[0m" >&2
}

log_success() {
    echo -e "\033[0;32m${1}\033[0m" >&2
}

log_warn() {
    echo -e "\033[0;33m${1}\033[0m" >&2
}

log_error() {
    echo -e "\033[0;31m${1}\033[0m" >&2
}

die() {
    log_error "Error: $1"
    exit 1
}

# Check if a required command exists
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."
}

# Platform-specific install hint for a command
_install_hint() {
    local cmd="$1"
    local hint=""
    case "$(uname -s)" in
        Darwin)
            case "$cmd" in
                jq)   hint="brew install jq" ;;
                curl) hint="brew install curl" ;;
                git)  hint="xcode-select --install  OR  brew install git" ;;
                *)    hint="brew install $cmd" ;;
            esac
            ;;
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                hint="sudo apt-get install $cmd"
            elif command -v dnf >/dev/null 2>&1; then
                hint="sudo dnf install $cmd"
            elif command -v pacman >/dev/null 2>&1; then
                hint="sudo pacman -S $cmd"
            elif command -v apk >/dev/null 2>&1; then
                hint="sudo apk add $cmd"
            else
                hint="Install '$cmd' using your package manager"
            fi
            ;;
        *)
            hint="Install '$cmd' using your package manager"
            ;;
    esac
    echo "$hint"
}

# Check all required dependencies and report missing ones with install hints
check_dependencies() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    log_error "Missing required dependencies:"
    echo "" >&2
    for cmd in "${missing[@]}"; do
        local hint
        hint=$(_install_hint "$cmd")
        echo -e "  \033[1m${cmd}\033[0m  ->  ${hint}" >&2
    done
    echo "" >&2
    exit 1
}

# Spinner for long-running operations
SPINNER_PID=""

spinner_start() {
    local msg="${1:-Thinking...}"
    # Only show spinner if stderr is a terminal
    [[ -t 2 ]] || return 0

    (
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0
        local start_time=$SECONDS
        while true; do
            local elapsed=$(( SECONDS - start_time ))
            local display_msg="$msg"
            if [[ $elapsed -ge 10 ]]; then
                display_msg="Still thinking..."
            fi
            printf "\r\033[2m%s %s (%ds)\033[0m" "${frames[$i]}" "$display_msg" "$elapsed" >&2
            i=$(( (i + 1) % ${#frames[@]} ))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null
}

spinner_stop() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
        # Clear the spinner line
        printf "\r\033[K" >&2
    fi
}

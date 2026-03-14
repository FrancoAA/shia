#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/FrancoAA/shia.git"
INSTALL_DIR="${HOME}/.local/bin"
SHIA_DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/shia"
SHIA_SRC="${SHIA_DATA_DIR}/src"

echo "Installing shia..."

for cmd in curl jq git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: '$cmd' is required. Please install it first."
        exit 1
    fi
done

SCRIPT_DIR=""
if [[ -f "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -n "$SCRIPT_DIR" && -f "${SCRIPT_DIR}/shia" ]]; then
    SOURCE_DIR="$SCRIPT_DIR"
    echo "Using local source: ${SOURCE_DIR}"
else
    echo "Fetching shia source..."
    if [[ -d "$SHIA_SRC" ]]; then
        echo "Updating existing installation..."
        git -C "$SHIA_SRC" pull --quiet
    else
        mkdir -p "$SHIA_DATA_DIR"
        git clone --quiet "$REPO_URL" "$SHIA_SRC"
    fi
    SOURCE_DIR="$SHIA_SRC"
fi

mkdir -p "$INSTALL_DIR"

cat > "${INSTALL_DIR}/shia" <<EOF
#!/usr/bin/env bash
exec "${SOURCE_DIR}/shia" "\$@"
EOF
chmod +x "${INSTALL_DIR}/shia"

echo "Installed to ${INSTALL_DIR}/shia"

# --- PATH setup ---

NEEDS_SOURCE=""

if [[ ! ":$PATH:" == *":${INSTALL_DIR}:"* ]]; then
    detect_rc_file() {
        local shell_name
        shell_name=$(basename "${SHELL:-/bin/bash}")

        case "$shell_name" in
            zsh)
                echo "${HOME}/.zshrc"
                ;;
            bash)
                if [[ "$(uname -s)" == "Darwin" ]]; then
                    if [[ -f "${HOME}/.bash_profile" ]]; then
                        echo "${HOME}/.bash_profile"
                    else
                        echo "${HOME}/.bashrc"
                    fi
                else
                    echo "${HOME}/.bashrc"
                fi
                ;;
            *)
                echo "${HOME}/.profile"
                ;;
        esac
    }

    RC_FILE=$(detect_rc_file)
    PATH_LINE='export PATH="${HOME}/.local/bin:${PATH}"'

    echo
    echo "${INSTALL_DIR} is not in your PATH."

    if [[ -f "$RC_FILE" ]] && grep -Fq "$PATH_LINE" "$RC_FILE"; then
        echo "PATH export already exists in ${RC_FILE}."
        NEEDS_SOURCE="$RC_FILE"
    elif [[ -t 0 ]]; then
        read -rp "Add it to ${RC_FILE}? [Y/n]: " add_to_path
        add_to_path="${add_to_path:-Y}"

        if [[ "$add_to_path" =~ ^[Yy]$ ]]; then
            {
                echo
                echo "# Added by shia installer"
                echo "$PATH_LINE"
            } >> "$RC_FILE"
            echo "Added to ${RC_FILE}"
            NEEDS_SOURCE="$RC_FILE"
        else
            echo
            echo "Add this to your shell config manually:"
            echo '  export PATH="${HOME}/.local/bin:${PATH}"'
        fi
    else
        echo
        echo "Add this to your shell config manually:"
        echo '  export PATH="${HOME}/.local/bin:${PATH}"'
    fi
fi

# --- LLM provider setup ---

SHIA_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/shia"

setup_provider() {
    echo
    echo -e "\033[1mLLM provider setup\033[0m"
    echo

    if [[ -d "$SHIA_CONFIG_DIR" ]]; then
        echo "Existing configuration found at ${SHIA_CONFIG_DIR}"
        read -rp "Reconfigure? [y/N]: " reconfigure
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            echo "Keeping existing configuration."
            return 0
        fi
    fi

    mkdir -p "$SHIA_CONFIG_DIR"

    read -rp "API provider URL [https://openrouter.ai/api/v1]: " api_url
    api_url="${api_url:-https://openrouter.ai/api/v1}"

    read -rsp "API key: " api_key
    echo
    if [[ -z "$api_key" ]]; then
        echo "Error: API key cannot be empty."
        echo "Run 'shia init' later to configure."
        return 1
    fi

    read -rp "Model ID (e.g. anthropic/claude-sonnet-4, openai/gpt-4o): " model
    if [[ -z "$model" ]]; then
        echo "Error: Model ID cannot be empty."
        echo "Run 'shia init' later to configure."
        return 1
    fi

    # Write config
    cat > "${SHIA_CONFIG_DIR}/config" <<CONF
# shia configuration
SHIA_PROFILE=default
CONF
    chmod 600 "${SHIA_CONFIG_DIR}/config"

    # Write profiles
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
        cp "${SOURCE_DIR}/defaults/dangerous_commands" "${SHIA_CONFIG_DIR}/dangerous_commands"
    fi

    # Create user system prompt if not present
    if [[ ! -f "${SHIA_CONFIG_DIR}/system_prompt" ]]; then
        cat > "${SHIA_CONFIG_DIR}/system_prompt" <<'PROMPT'
# Custom instructions for shia (appended to base prompt)
# Uncomment and edit lines below, or add your own.
# Examples:
#   Prefer eza over ls
#   Use doas instead of sudo
#   Always use long flags for readability
PROMPT
    fi

    echo
    echo -e "\033[32mConfiguration saved.\033[0m"
    echo "Profile 'default' created with model: ${model}"
}

if [[ -t 0 ]]; then
    setup_provider || true
else
    echo
    echo "Run 'shia init' to configure your API provider."
fi

# --- Final instructions ---

echo
if [[ -n "$NEEDS_SOURCE" ]]; then
    echo "Run 'source ${NEEDS_SOURCE}' or restart your terminal, then:"
    echo "  shia \"list all running docker containers\""
else
    echo "shia is ready! Try:"
    echo "  shia \"list all running docker containers\""
    echo "  cat file.txt | shia \"explain this\""
fi

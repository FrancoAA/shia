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

if [[ ":$PATH:" == *":${INSTALL_DIR}:"* ]]; then
    echo
    echo "shia is ready! Run 'shia init' to configure your API provider."
    exit 0
fi

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
    echo "Run 'source ${RC_FILE}' or restart your terminal, then run 'shia init'."
    exit 0
fi

if [[ -t 0 ]]; then
    read -rp "Add it to ${RC_FILE}? [Y/n]: " add_to_path
    add_to_path="${add_to_path:-Y}"
else
    add_to_path="n"
fi

if [[ "$add_to_path" =~ ^[Yy]$ ]]; then
    {
        echo
        echo "# Added by shia installer"
        echo "$PATH_LINE"
    } >> "$RC_FILE"
    echo "Added to ${RC_FILE}"
    echo
    echo "Run 'source ${RC_FILE}' or restart your terminal, then:"
    echo "  shia init"
else
    echo
    echo "Add this to your shell config manually:"
    echo '  export PATH="${HOME}/.local/bin:${PATH}"'
    echo
    echo "Then run 'shia init' to configure your API provider."
fi

#!/usr/bin/env bash
load_dangerous_commands() {
    DANGEROUS_PATTERNS=()
    local danger_file="${SHIA_DANGEROUS_FILE:-${SHIA_DIR}/defaults/dangerous_commands}"
    if [[ -f "$danger_file" ]]; then
        while IFS= read -r pattern; do
            [[ -z "$pattern" ]] && continue
            [[ "$pattern" =~ ^[[:space:]]*# ]] && continue
            DANGEROUS_PATTERNS+=("$pattern")
        done < "$danger_file"
    fi
}

is_dangerous() {
    local cmd="$1"
    for pattern in "${DANGEROUS_PATTERNS[@]+"${DANGEROUS_PATTERNS[@]}"}"; do
        if [[ "$cmd" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

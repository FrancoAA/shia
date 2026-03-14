#!/usr/bin/env bash
load_tools() {
    local tools_dir="${SHIA_DIR}/lib/tools"
    if [[ -d "$tools_dir" ]]; then
        for tool_file in "${tools_dir}"/*.sh; do
            [[ -f "$tool_file" ]] || continue
            source "$tool_file"
            debug_log "tools" "loaded $(basename "$tool_file")"
        done
    fi
}

build_tools_array() {
    local funcs
    funcs=$(declare -F | awk '{print $3}' | grep '^tool_.*_schema$' | sort)
    if [[ -z "$funcs" ]]; then
        echo '[]'
        return
    fi
    local schemas="[]"
    for func in $funcs; do
        local schema
        schema=$("$func")
        schemas=$(echo "$schemas" | jq --argjson s "$schema" '. + [$s]')
    done
    echo "$schemas"
}

dispatch_tool_call() {
    local tool_name="$1"
    local tool_args="$2"
    local func_name="tool_${tool_name}_execute"
    debug_log "tools" "dispatch: ${tool_name}"
    if declare -F "$func_name" >/dev/null 2>&1; then
        "$func_name" "$tool_args"
    else
        echo "Error: unknown tool '${tool_name}'"
        return 1
    fi
}

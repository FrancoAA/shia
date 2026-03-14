#!/usr/bin/env bash
# Plugin: skills — agent skill discovery and loading

_SHIA_SKILL_NAMES=()
_SHIA_SKILL_ENTRIES=()

SHIA_LOADED_SKILL_CONTENT=""
SHIA_LOADED_SKILL_NAME=""

plugin_skills_info() {
    echo "Agent skill discovery and loading"
}

plugin_skills_hooks() {
    echo "init prompt_build"
}

plugin_skills_on_init() {
    _skills_discover
    local count=${#_SHIA_SKILL_NAMES[@]}
    debug_log "plugin:skills" "discovered ${count} skill(s)"

    # Pre-load skill if -s flag was used
    if [[ -n "${SHIA_PRELOAD_SKILL:-}" ]]; then
        local content
        content=$(_skills_load_content "$SHIA_PRELOAD_SKILL")
        if [[ $? -eq 0 && -n "$content" ]]; then
            SHIA_LOADED_SKILL_CONTENT="$content"
            SHIA_LOADED_SKILL_NAME="$SHIA_PRELOAD_SKILL"
            debug_log "plugin:skills" "pre-loaded skill: ${SHIA_PRELOAD_SKILL}"
        else
            log_warn "Skill '${SHIA_PRELOAD_SKILL}' not found."
        fi
    fi
}

plugin_skills_on_prompt_build() {
    local mode="${1:-}"
    local count=${#_SHIA_SKILL_NAMES[@]}

    [[ $count -eq 0 ]] && return 0

    echo ""
    echo "AVAILABLE SKILLS:"
    echo "You have access to specialized skills that provide domain-specific instructions."
    echo "Use the load_skill tool when a task matches one of these skills:"

    local name
    for name in ${_SHIA_SKILL_NAMES[@]+"${_SHIA_SKILL_NAMES[@]}"}; do
        local desc
        desc=$(_skills_get_description "$name")
        echo "- ${name}: ${desc}"
    done

    if [[ -n "${SHIA_LOADED_SKILL_CONTENT:-}" ]]; then
        local loaded_name="${SHIA_LOADED_SKILL_NAME:-}"
        local loaded_content="${SHIA_LOADED_SKILL_CONTENT}"

        echo ""
        echo "LOADED SKILL CONTEXT:"
        if [[ -n "$loaded_name" ]]; then
            echo "Skill: ${loaded_name}"
        fi
        printf '<skill_content name="%s">\n' "$loaded_name"
        echo "$loaded_content"
        echo "</skill_content>"
    fi
}

_skills_discover() {
    _SHIA_SKILL_NAMES=()
    _SHIA_SKILL_ENTRIES=()

    # 1. Shared hub (lowest priority)
    _skills_scan_dir "${HOME}/.agents/skills"

    # 2. Shellia fallback
    _skills_scan_dir "${HOME}/.config/shellia/skills"

    # 3. Shia-exclusive (highest priority — overrides both)
    _skills_scan_dir "${SHIA_CONFIG_DIR}/skills"
}

_skills_scan_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0

    local skill_dir
    for skill_dir in "${dir}"/*/; do
        [[ -d "$skill_dir" ]] || continue
        local skill_file="${skill_dir}SKILL.md"
        [[ -f "$skill_file" ]] || continue

        local name="" description=""
        local frontmatter
        frontmatter=$(_skills_parse_frontmatter "$skill_file")

        if [[ -n "$frontmatter" ]]; then
            name=$(echo "$frontmatter" | grep '^name:' | head -1 | sed 's/^name:[[:space:]]*//')
            description=$(echo "$frontmatter" | grep '^description:' | head -1 | sed 's/^description:[[:space:]]*//')
        fi

        if [[ -z "$name" ]]; then
            name=$(basename "$skill_dir")
        fi

        if [[ -z "$description" ]]; then
            debug_log "plugin:skills" "skipping '${name}' — no description in frontmatter"
            continue
        fi

        _skills_register "$name" "$description" "$skill_file"
    done
}

_skills_parse_frontmatter() {
    local file="$1"
    local in_frontmatter=false
    local found_start=false

    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            if [[ "$found_start" == "false" ]]; then
                found_start=true
                in_frontmatter=true
                continue
            else
                break
            fi
        fi
        if [[ "$in_frontmatter" == "true" ]]; then
            echo "$line"
        fi
    done < "$file"
}

_skills_register() {
    local name="$1"
    local description="$2"
    local path="$3"

    local count=${#_SHIA_SKILL_NAMES[@]}
    if [[ $count -gt 0 ]]; then
        local i
        for i in $(seq 0 $(( count - 1 ))); do
            if [[ "${_SHIA_SKILL_NAMES[$i]}" == "$name" ]]; then
                _SHIA_SKILL_ENTRIES[$i]="${name}|${description}|${path}"
                debug_log "plugin:skills" "override '${name}' from ${path}"
                return 0
            fi
        done
    fi

    _SHIA_SKILL_NAMES+=("$name")
    _SHIA_SKILL_ENTRIES+=("${name}|${description}|${path}")
    debug_log "plugin:skills" "registered '${name}' from ${path}"
}

_skills_get_description() {
    local target="$1"
    local count=${#_SHIA_SKILL_ENTRIES[@]}
    [[ $count -eq 0 ]] && { echo ""; return 0; }
    local i
    for i in $(seq 0 $(( count - 1 ))); do
        local entry="${_SHIA_SKILL_ENTRIES[$i]}"
        local name="${entry%%|*}"
        if [[ "$name" == "$target" ]]; then
            local rest="${entry#*|}"
            echo "${rest%%|*}"
            return 0
        fi
    done
    echo ""
}

_skills_get_path() {
    local target="$1"
    local count=${#_SHIA_SKILL_ENTRIES[@]}
    [[ $count -eq 0 ]] && { echo ""; return 0; }
    local i
    for i in $(seq 0 $(( count - 1 ))); do
        local entry="${_SHIA_SKILL_ENTRIES[$i]}"
        local name="${entry%%|*}"
        if [[ "$name" == "$target" ]]; then
            local rest="${entry#*|}"
            echo "${rest#*|}"
            return 0
        fi
    done
    echo ""
}

_skills_load_content() {
    local name="$1"
    local path
    path=$(_skills_get_path "$name")

    if [[ -z "$path" || ! -f "$path" ]]; then
        echo "Error: skill '${name}' not found."
        return 1
    fi

    local found_start=false past_frontmatter=false body=""
    while IFS= read -r line; do
        if [[ "$past_frontmatter" == "true" ]]; then
            body="${body}${line}
"
            continue
        fi
        if [[ "$line" == "---" ]]; then
            if [[ "$found_start" == "false" ]]; then
                found_start=true
                continue
            else
                past_frontmatter=true
                continue
            fi
        fi
        if [[ "$found_start" == "false" ]]; then
            past_frontmatter=true
            body="${line}
"
        fi
    done < "$path"

    echo "$body" | sed '/./,$!d'
}

# --- load_skill tool ---

tool_load_skill_schema() {
    local skill_list=""
    local name
    for name in ${_SHIA_SKILL_NAMES[@]+"${_SHIA_SKILL_NAMES[@]}"}; do
        local desc
        desc=$(_skills_get_description "$name")
        skill_list="${skill_list}\n- ${name}: ${desc}"
    done

    local description="Load a specialized skill that provides domain-specific instructions and workflows. When you recognize that a task matches one of the available skills, use this tool to load the full skill instructions. The skill content will be returned to you — follow it directly."

    if [[ -n "$skill_list" ]]; then
        description="${description}\n\nAvailable skills:${skill_list}"
    fi

    local expanded_desc
    expanded_desc=$(printf '%b' "$description")

    jq -n --arg desc "$expanded_desc" '{
        type: "function",
        function: {
            name: "load_skill",
            description: $desc,
            parameters: {
                type: "object",
                properties: {
                    name: {
                        type: "string",
                        description: "The name of the skill to load"
                    }
                },
                required: ["name"]
            }
        }
    }'
}

tool_load_skill_execute() {
    local args_json="$1"
    local skill_name
    skill_name=$(echo "$args_json" | jq -r '.name')

    if [[ -z "$skill_name" ]]; then
        echo "Error: skill name is required."
        return 1
    fi

    local path
    path=$(_skills_get_path "$skill_name")

    if [[ -z "$path" || ! -f "$path" ]]; then
        echo "Error: skill '${skill_name}' not found. Available skills:"
        local name
        for name in ${_SHIA_SKILL_NAMES[@]+"${_SHIA_SKILL_NAMES[@]}"}; do
            local desc
            desc=$(_skills_get_description "$name")
            echo "  - ${name}: ${desc}"
        done
        return 1
    fi

    local skill_dir
    skill_dir=$(dirname "$path")

    echo -e "\033[2mLoading skill: ${skill_name}\033[0m" >&2

    local content
    content=$(_skills_load_content "$skill_name")

    printf '<skill_content name="%s">\n' "$skill_name"
    echo "$content"
    printf 'Base directory for this skill: %s\n' "$skill_dir"
    printf 'Relative paths in this skill are relative to this base directory.\n'
    printf '</skill_content>\n'
}

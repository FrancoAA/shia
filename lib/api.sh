#!/usr/bin/env bash
SHIA_MAX_TOOL_LOOPS=100
SHIA_TOOL_BLOCKED=false

api_chat() {
    local messages="$1"
    local tools="${2:-[]}"
    local msg_count char_count
    msg_count=$(echo "$messages" | jq 'length')
    char_count=$(echo "$messages" | wc -c | tr -d ' ')
    debug_log "api" "model=${SHIA_MODEL} messages=${msg_count} chars=${char_count} temp=0.2"
    debug_log "api" "endpoint=${SHIA_API_URL}/chat/completions"
    local tmp_response
    tmp_response=$(mktemp)
    trap "rm -f '$tmp_response'" RETURN
    local request_body tools_count
    tools_count=$(echo "$tools" | jq 'length')
    if [[ "$tools_count" -gt 0 ]]; then
        request_body=$(jq -n --arg model "$SHIA_MODEL" --argjson messages "$messages" --argjson tools "$tools" \
            '{model: $model, messages: $messages, tools: $tools, temperature: 0.2}')
        debug_log "api" "tools=${tools_count}"
    else
        request_body=$(jq -n --arg model "$SHIA_MODEL" --argjson messages "$messages" \
            '{model: $model, messages: $messages, temperature: 0.2}')
    fi
    fire_hook "before_api_call" "$messages"
    local http_code
    http_code=$(curl -s -w "%{http_code}" -o "$tmp_response" \
        "${SHIA_API_URL}/chat/completions" \
        -H "Authorization: Bearer ${SHIA_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$request_body" 2>/dev/null) || {
        log_error "Network error: could not connect to ${SHIA_API_URL}"
        return 1
    }
    local body
    body=$(cat "$tmp_response")
    debug_log "api" "http_status=${http_code}"
    case "$http_code" in
        200) ;;
        401) log_error "Authentication failed (HTTP 401). Check your API key."; return 1 ;;
        429) log_error "Rate limited (HTTP 429). Wait a moment and try again."; return 1 ;;
        4*) log_error "Client error (HTTP ${http_code})."; log_error "Response: $(echo "$body" | jq -r '.error.message // .error // .' 2>/dev/null || echo "$body")"; return 1 ;;
        5*) log_error "Server error (HTTP ${http_code}). Try again later."; return 1 ;;
        *) log_error "Unexpected HTTP status: ${http_code}"; return 1 ;;
    esac
    local message
    message=$(echo "$body" | jq '.choices[0].message // empty' 2>/dev/null)
    if [[ -z "$message" ]]; then
        log_error "Malformed API response (no message in choices)."
        return 1
    fi
    local usage
    usage=$(echo "$body" | jq -r 'if .usage then "prompt=\(.usage.prompt_tokens // "?") completion=\(.usage.completion_tokens // "?") total=\(.usage.total_tokens // "?")" else "not reported" end' 2>/dev/null)
    debug_log "api" "tokens: ${usage}"
    local content
    content=$(echo "$message" | jq -r '.content // empty' 2>/dev/null)
    [[ -n "$content" ]] && debug_block "response" "$content" 5
    local tool_calls_count
    tool_calls_count=$(echo "$message" | jq '.tool_calls // [] | length' 2>/dev/null)
    debug_log "api" "tool_calls=${tool_calls_count}"
    fire_hook "after_api_call" "$message"
    echo "$message"
}

api_chat_loop() {
    local messages="$1"
    local tools="$2"
    local loop_count=0
    while true; do
        ((loop_count++))
        if [[ $loop_count -gt $SHIA_MAX_TOOL_LOOPS ]]; then
            log_error "Tool call loop exceeded maximum iterations (${SHIA_MAX_TOOL_LOOPS}). Stopping."
            return 1
        fi
        debug_log "loop" "iteration=${loop_count}"
        local assistant_message
        assistant_message=$(api_chat "$messages" "$tools") || return $?
        local content
        content=$(echo "$assistant_message" | jq -r '.content // empty' 2>/dev/null)
        local tool_calls tool_calls_count
        tool_calls=$(echo "$assistant_message" | jq '.tool_calls // []' 2>/dev/null)
        tool_calls_count=$(echo "$tool_calls" | jq 'length')
        if [[ $tool_calls_count -eq 0 ]]; then
            if [[ -n "$content" ]]; then
                echo "$content"
            fi
            SHIA_LAST_MESSAGES="$messages"
            SHIA_LAST_ASSISTANT_MESSAGE="$assistant_message"
            return 0
        fi
        if [[ -n "$content" ]]; then
            echo "$content" >&2
        fi
        messages=$(echo "$messages" | jq --argjson msg "$assistant_message" '. + [$msg]')
        for ((i = 0; i < tool_calls_count; i++)); do
            local tool_call tool_id tool_name tool_args
            tool_call=$(echo "$tool_calls" | jq ".[$i]")
            tool_id=$(echo "$tool_call" | jq -r '.id')
            tool_name=$(echo "$tool_call" | jq -r '.function.name')
            tool_args=$(echo "$tool_call" | jq -r '.function.arguments')
            debug_log "loop" "executing tool: ${tool_name} (id=${tool_id})"
            local spinner_was_active=false
            if [[ -n "${SPINNER_PID:-}" ]]; then
                spinner_stop
                spinner_was_active=true
                echo -e "\033[2mRunning tool: ${tool_name}\033[0m" >&2
            fi
            local tool_result tool_exit=0 tool_started_at=$SECONDS
            fire_hook "before_tool_call" "$tool_name" "$tool_args"
            if [[ "${SHIA_TOOL_BLOCKED:-false}" == "true" ]]; then
                SHIA_TOOL_BLOCKED=false
                tool_result="Command blocked by plugin policy."
                tool_exit=0
            else
                tool_result=$(dispatch_tool_call "$tool_name" "$tool_args") || tool_exit=$?
                fire_hook "after_tool_call" "$tool_name" "${tool_result:-}" "$tool_exit"
            fi
            messages=$(echo "$messages" | jq --arg id "$tool_id" --arg result "$tool_result" \
                '. + [{"role": "tool", "tool_call_id": $id, "content": $result}]')
        done
    done
}

build_single_messages() {
    local system_prompt="$1"
    local user_prompt="$2"
    jq -n --arg sys "$system_prompt" --arg usr "$user_prompt" \
        '[{"role": "system", "content": $sys}, {"role": "user", "content": $usr}]'
}

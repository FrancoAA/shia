#!/usr/bin/env bash
# Plugin: websearch — web search via Brave Search API

plugin_websearch_info() {
    echo "Web search via Brave Search API"
}

plugin_websearch_hooks() {
    echo "init"
}

plugin_websearch_on_init() {
    local api_key
    api_key=$(_websearch_get_api_key)
    if [[ -z "$api_key" ]]; then
        debug_log "plugin:websearch" "no API key configured — web_search tool will be unavailable"
    else
        debug_log "plugin:websearch" "API key configured"
    fi
}

_websearch_get_api_key() {
    if [[ -n "${BRAVE_SEARCH_API_KEY:-}" ]]; then
        echo "$BRAVE_SEARCH_API_KEY"
        return 0
    fi
    plugin_config_get "websearch" "api_key" ""
}

tool_web_search_schema() {
    cat <<'EOF'
{
    "type": "function",
    "function": {
        "name": "web_search",
        "description": "Search the web using Brave Search. Returns web results with titles, URLs, and content snippets. Use this when you need current information, facts, documentation, or anything that may be beyond your training data.",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "The search query"
                },
                "count": {
                    "type": "integer",
                    "description": "Number of results to return (1-20, default: 5)"
                }
            },
            "required": ["query"]
        }
    }
}
EOF
}

tool_web_search_execute() {
    local args_json="$1"
    local query count

    query=$(echo "$args_json" | jq -r '.query')
    count=$(echo "$args_json" | jq -r '.count // 5')

    if [[ -z "$query" || "$query" == "null" ]]; then
        echo "Error: search query is required."
        return 1
    fi

    if [[ "$count" -lt 1 ]] 2>/dev/null; then count=1
    elif [[ "$count" -gt 20 ]] 2>/dev/null; then count=20
    fi

    local api_key
    api_key=$(_websearch_get_api_key)

    if [[ -z "$api_key" ]]; then
        echo "Error: Brave Search API key not configured. Set BRAVE_SEARCH_API_KEY environment variable."
        return 1
    fi

    echo -e "\033[2mSearching: ${query}\033[0m" >&2

    local encoded_query
    encoded_query=$(printf '%s' "$query" | jq -sRr '@uri')

    local tmp_response
    tmp_response=$(mktemp)

    local http_code curl_exit=0
    http_code=$(curl -s --connect-timeout "${SHIA_WEBSEARCH_CONNECT_TIMEOUT:-10}" --max-time "${SHIA_WEBSEARCH_MAX_TIME:-30}" -w "%{http_code}" -o "$tmp_response" \
        "https://api.search.brave.com/res/v1/web/search?q=${encoded_query}&count=${count}" \
        -H "Accept: application/json" \
        -H "X-Subscription-Token: ${api_key}" \
        2>/dev/null) || curl_exit=$?

    if [[ $curl_exit -ne 0 ]]; then
        rm -f "$tmp_response"
        echo "Error: Brave Search request failed (curl exit ${curl_exit})."
        return 1
    fi

    if [[ "$http_code" -ne 200 ]]; then
        local error_body
        error_body=$(cat "$tmp_response")
        rm -f "$tmp_response"
        debug_log "plugin:websearch" "API error: HTTP ${http_code}"
        echo "Error: Brave Search API returned HTTP ${http_code}."
        local error_msg
        error_msg=$(echo "$error_body" | jq -r '.message // .error // empty' 2>/dev/null)
        if [[ -n "$error_msg" ]]; then
            echo "Details: ${error_msg}"
        fi
        return 1
    fi

    local response
    response=$(cat "$tmp_response")
    rm -f "$tmp_response"

    local result_count
    result_count=$(echo "$response" | jq '.web.results | length' 2>/dev/null)

    if [[ -z "$result_count" || "$result_count" == "0" || "$result_count" == "null" ]]; then
        echo "No results found for: ${query}"
        return 0
    fi

    echo -e "\033[0;32mFound ${result_count} result(s)\033[0m" >&2

    echo "$response" | jq -r '
        .web.results[:'"$count"'] | to_entries[] |
        "[\(.key + 1)] \(.value.title)\n    URL: \(.value.url)\n    \(.value.description // "No description")\n"
    ' 2>/dev/null
}

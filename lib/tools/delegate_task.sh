#!/usr/bin/env bash
# Tool: delegate_task — delegate a task to a subagent

tool_delegate_task_schema() {
    cat <<'EOF'
{
    "type": "function",
    "function": {
        "name": "delegate_task",
        "description": "Delegate a task to a subagent that runs in its own isolated conversation context. The subagent has access to all tools (run_command) and will execute the task autonomously, returning a concise summary of its findings or results. Use this when the intermediate steps of a task (exploration, research, multi-step analysis) would add noise to the main conversation. The subagent's internal tool calls and reasoning are not added to your context — only the final summary comes back.",
        "parameters": {
            "type": "object",
            "properties": {
                "task": {
                    "type": "string",
                    "description": "Clear, detailed description of what the subagent should accomplish. Be specific about what information to return."
                },
                "context": {
                    "type": "string",
                    "description": "Relevant context from the current conversation that the subagent needs to do its job (e.g., file paths, variable names, prior findings)."
                }
            },
            "required": ["task"]
        }
    }
}
EOF
}

tool_delegate_task_execute() {
    local args_json="$1"
    local task context

    task=$(echo "$args_json" | jq -r '.task')
    context=$(echo "$args_json" | jq -r '.context // empty')

    debug_log "tool" "delegate_task: ${task}"

    echo -e "\033[1;35mDelegating task to subagent:\033[0m" >&2
    echo -e "  \033[0;36m${task}\033[0m" >&2
    echo "" >&2

    local base_prompt
    base_prompt=$(build_system_prompt "subagent")
    SHIA_LOADED_SKILL_CONTENT=""
    SHIA_LOADED_SKILL_NAME=""

    local subagent_instructions="You are a focused subagent. Your job is to complete the given task thoroughly and return a clear, concise summary of your findings or results.

Rules for subagents:
- Stay focused on the assigned task. Do not go off-topic.
- Use tools as needed to accomplish the task.
- When done, provide a final summary that is useful to the caller without requiring them to see your intermediate steps.
- Do not engage in open-ended conversation or ask follow-up questions unless absolutely necessary."

    local system_prompt="${base_prompt}

SUBAGENT MODE:
${subagent_instructions}"

    local user_message="Task: ${task}"
    if [[ -n "$context" ]]; then
        user_message="${user_message}

Context:
${context}"
    fi

    local messages
    messages=$(build_single_messages "$system_prompt" "$user_message")

    local tools
    tools=$(build_tools_array | jq '[.[] | select(.function.name != "delegate_task")]')

    spinner_start "Subagent working..."
    local result exit_code=0
    result=$(api_chat_loop "$messages" "$tools") || exit_code=$?
    spinner_stop

    if [[ $exit_code -ne 0 ]]; then
        echo -e "  \033[0;31mSubagent failed.\033[0m" >&2
        echo "Subagent error: task could not be completed."
        return $exit_code
    fi

    echo -e "  \033[0;32mSubagent completed.\033[0m" >&2
    echo "" >&2

    echo "$result"
}

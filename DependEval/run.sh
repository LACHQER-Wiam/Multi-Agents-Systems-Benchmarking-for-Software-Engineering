#!/bin/bash

# script for running evaluations; supports api and react agents with multiple LLM providers
# models: claude-* (anthropic), gpt-* (openai), gemini-* (google)
# "java" "javascript" "php" "python" "typescript" "c#" "c++" "c"  ,  "task2" "task4"
models=("gpt-4.1") #haiku-4-5. opus-4-6
languages=("javascript")
tasks=("task4")
type_agent="react"  # react or api

log_dir="./logs"
mkdir -p "$log_dir"

# Set provider from model name (for react agent)
get_provider() {
    case "$1" in
        claude-*) echo "anthropic" ;;
        gpt-*)    echo "openai" ;;
        gemini-*) echo "google" ;;
        *)        echo "openai" ;;
    esac
}

for task in "${tasks[@]}"; do
    for model in "${models[@]}"; do
        for language in "${languages[@]}"; do
            safe_model_name=$(echo "$model" | sed 's|/|_|g')
            log_file="$log_dir/${safe_model_name}_${type_agent}_${language}_${task}_api.txt"
            provider=$(get_provider "$model")
            echo "Running $type_agent model: $model (provider: $provider) with language: $language and task: $task" | tee -a "$log_file"

            python -u run.py --type_agent "$type_agent" --model_name "$model" --language "$language" --task "$task" --provider "$provider" --max_token_nums 16000 >> "$log_file" 2>&1
            if [ $? -ne 0 ]; then
                echo "Error encountered while running model: $model with language: $language and task: $task" | tee -a "$log_file"
                echo "Check log file for details: $log_file" | tee -a "$log_file"
                exit 1
            fi

            # react writes *_ReAct_predictions.json; api writes *_predictions.json
            if [ "$type_agent" == "react" ]; then
                result_json="./results/$task/$type_agent/$language/${model//\//-}-$language/${model##*/}_ReAct_predictions.json"
            else
                result_json="./results/$task/$type_agent/$language/${model//\//-}-$language/${model##*/}_predictions.json"
            fi

            if [ "$task" == "task1" ]; then
                python eval_ME_api.py --input "$result_json" 2>&1 | tee -a "$log_file"
            elif [ "$task" == "task2" ]; then
                python eval_DR_api.py --input "$result_json" 2>&1 | tee -a "$log_file"
            elif [ "$task" == "task4" ]; then
                python eval_RC_api.py --input "$result_json" 2>&1 | tee -a "$log_file"
            fi

            echo "Completed task: $model with language: $language and task: $task (log: $log_file)" | tee -a "$log_file"
        done
    done
done

echo "All API tasks and evaluations completed successfully!"
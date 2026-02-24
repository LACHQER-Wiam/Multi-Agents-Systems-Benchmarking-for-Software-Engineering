#!/bin/bash

# script for running evaluations via Anthropic API; mirrors run.sh logic
# models list here are the anthropic model identifiers (claude-2.1, claude-3, etc.)
# "java" "javascript" "php" "python" "typescript" "c#" "c++" "c"  ,  "task2" "task4"
models=("claude-haiku-4-5") #haiku-4-5. opus-4-6
languages=("python")
tasks=("task4")
type_agent="AtoA"  # react or api

log_dir="./logs"
mkdir -p "$log_dir"

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "Warning: ANTHROPIC_API_KEY not set. Export it before running."
fi

for task in "${tasks[@]}"; do
    for model in "${models[@]}"; do
        for language in "${languages[@]}"; do
            safe_model_name=$(echo "$model" | sed 's|/|_|g')
            log_file="$log_dir/${safe_model_name}_${type_agent}_${language}_${task}_api.txt"
            echo "Running API model: $model with language: $language and task: $task" | tee -a "$log_file"

            python -u run.py --type_agent "$type_agent" --model_name "$model" --language "$language" --task "$task" > "$log_file" 2>&1
            if [ $? -ne 0 ]; then
                echo "Error encountered while running API model: $model with language: $language and task: $task" | tee -a "$log_file"
                echo "Check log file for details: $log_file" | tee -a "$log_file"
                exit 1
            fi

            result_json="./results/$task/$type_agent/$language/${model//\//-}-$language/${model##*/}_predictions.json"

            if [ "$task" == "task1" ]; then
                python3 eval_ME_api.py --input "$result_json" 2>&1 | tee -a "$log_file"
            elif [ "$task" == "task2" ]; then
                python3 eval_DR_api.py --input "$result_json" 2>&1 | tee -a "$log_file"
            elif [ "$task" == "task4" ]; then
                python3 eval_RC_api.py --input "$result_json" 2>&1 | tee -a "$log_file"
            fi

            echo "Completed task: $model with language: $language and task: $task (log: $log_file)" | tee -a "$log_file"
        done
    done
done

echo "All API tasks and evaluations completed successfully!"
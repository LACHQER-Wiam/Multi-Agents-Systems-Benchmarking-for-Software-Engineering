#!/bin/bash

# script for running evaluations via Anthropic API; mirrors run.sh logic
# models list here are the anthropic model identifiers (claude-2.1, claude-3, etc.)
# "java" "javascript" "php" "python" "typescript" "c" "c++"
models=("claude-opus-4-6")
languages=("c#")
tasks=("task1" "task2" "task4")

log_dir="./logs"
mkdir -p "$log_dir"

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "Warning: ANTHROPIC_API_KEY not set. Export it before running."
fi

for task in "${tasks[@]}"; do
    for model in "${models[@]}"; do
        for language in "${languages[@]}"; do
            safe_model_name=$(echo "$model" | sed 's|/|_|g')
            log_file="$log_dir/${safe_model_name}_${language}_${task}_api.txt"
            echo "Running API model: $model with language: $language and task: $task" | tee -a "$log_file"

            python -u run_api.py --model_name "$model" --language "$language" --task "$task" > "$log_file" 2>&1
            if [ $? -ne 0 ]; then
                echo "Error encountered while running API model: $model with language: $language and task: $task" | tee -a "$log_file"
                echo "Check log file for details: $log_file" | tee -a "$log_file"
                exit 1
            fi

            result_jsonl="./results/$task/${model//\//-}-$language/${model##*/}.jsonl"

            if [ "$task" == "task1" ]; then
                python3 eval_ME.py --input_dir "$result_jsonl" 2>&1 | tee -a "$log_file"
            elif [ "$task" == "task2" ]; then
                python3 eval_DR.py --input_dir "$result_jsonl" 2>&1 | tee -a "$log_file"
            elif [ "$task" == "task4" ]; then
                python3 eval_RC.py --input_dir "$result_jsonl" 2>&1 | tee -a "$log_file"
            fi

            echo "Completed task: $model with language: $language and task: $task (log: $log_file)" | tee -a "$log_file"
        done
    done
done

echo "All API tasks and evaluations completed successfully!"
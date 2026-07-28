#!/usr/bin/env bash

set -u

RUN_ID=$(date +%Y%m%d_%H%M%S)
LOG_DIR="oracle_clean_logs_${RUN_ID}"
JOBS_DIR="jobs/oracle_clean_${RUN_ID}"

mkdir -p "$LOG_DIR" "$JOBS_DIR"

SUMMARY_FILE="$LOG_DIR/summary.txt"

echo "Oracle clean run started: $(date)" | tee "$SUMMARY_FILE"
echo "Run ID: $RUN_ID" | tee -a "$SUMMARY_FILE"
echo "Jobs directory: $JOBS_DIR" | tee -a "$SUMMARY_FILE"
echo "" | tee -a "$SUMMARY_FILE"

for i in $(seq -w 1 60); do
    TASK="task0${i}"
    JOB_NAME="oracle_${TASK}_${RUN_ID}"
    LOG_FILE="$LOG_DIR/${TASK}.log"

    echo "==================================================" | tee -a "$SUMMARY_FILE"
    echo "Starting $TASK at $(date)" | tee -a "$SUMMARY_FILE"
    echo "Job name: $JOB_NAME" | tee -a "$SUMMARY_FILE"

    if [ ! -d "$TASK" ]; then
        echo "$TASK: MISSING DIRECTORY" | tee -a "$SUMMARY_FILE"
        continue
    fi

    harbor run \
        --path "$TASK" \
        --agent oracle \
        --force-build \
        --job-name "$JOB_NAME" \
        --jobs-dir "$JOBS_DIR" \
        > "$LOG_FILE" 2>&1

    EXIT_CODE=$?

    if [ "$EXIT_CODE" -ne 0 ]; then
        echo "$TASK: HARBOR ERROR — exit code $EXIT_CODE" | tee -a "$SUMMARY_FILE"
    elif grep -qE '│[[:space:]]*1\.0[[:space:]]*│' "$LOG_FILE"; then
        echo "$TASK: PASS — reward 1.0" | tee -a "$SUMMARY_FILE"
    elif grep -qE '│[[:space:]]*0\.0[[:space:]]*│' "$LOG_FILE"; then
        echo "$TASK: FAIL — reward 0.0" | tee -a "$SUMMARY_FILE"
    elif grep -q "Exception" "$LOG_FILE"; then
        echo "$TASK: EXCEPTION" | tee -a "$SUMMARY_FILE"
    else
        echo "$TASK: UNKNOWN — inspect $LOG_FILE" | tee -a "$SUMMARY_FILE"
    fi

    echo "Finished $TASK at $(date)" | tee -a "$SUMMARY_FILE"
    echo "" | tee -a "$SUMMARY_FILE"

    sleep 3
done

echo "==================================================" | tee -a "$SUMMARY_FILE"
echo "Oracle clean run finished: $(date)" | tee -a "$SUMMARY_FILE"

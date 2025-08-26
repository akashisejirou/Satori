#!/bin/bash
set -e

BASE_DIRS=$(ls -d ~/satori[0-9]* 2>/dev/null || true)

if [ -z "$BASE_DIRS" ]; then
    echo "No Satori nodes found to update."
    exit 0
fi

for NODE_DIR in $BASE_DIRS; do
    echo "hecking updates for $NODE_DIR..."
    cd "$NODE_DIR"

    LOG_FILE="$NODE_DIR/${NODE_NAME}.log"
    {
        echo "---------------------------------------------"
        echo "Update check started at $(date)"
        echo "---------------------------------------------"

        echo "Pulling latest image..."
        docker compose pull || { echo "Failed to pull in $NODE_DIR"; continue; }

        echo "Restarting container..."
        docker compose down || true
        docker compose up -d || { echo "Failed to start in $NODE_DIR"; continue; }

        nohup docker compose logs -f "$NODE_NAME" >> "$LOG_FILE" 2>&1 &

        echo "Update finished for $NODE_DIR. Logs at $LOG_FILE"
    } >> "$LOG_FILE" 2>&1
done

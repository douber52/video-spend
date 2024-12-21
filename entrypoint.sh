#!/bin/bash
set -e

# Function to handle cleanup on exit
cleanup() {
    echo "Cleaning up resources..."
    echo "Running terraform destroy..."
    terraform destroy -auto-approve || true
    pkill -f "python3 cost_manager.py"
    echo "Cleanup complete, exiting container..."
    exit 0
}

# Trap SIGTERM and SIGINT
trap cleanup SIGTERM SIGINT
trap cleanup EXIT

echo "==== Starting entrypoint script ===="

echo "==== Current directory contents ===="
ls -la

# Verify GCP credentials
echo "==== Testing GCP Authentication ===="
gcloud auth activate-service-account --key-file=/app/key.json
gcloud config set project ${GCP_PROJECT_ID} --quiet

echo "==== Starting Python application ===="
python3 cost_manager.py &

# Wait for any process to exit
wait -n

# Exit with status of process that exited first
echo "Main process exited, cleaning up..."
exit $?
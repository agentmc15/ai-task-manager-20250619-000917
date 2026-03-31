#!/bin/bash
# Load the Phi-3 Mini model into the Ollama container
# Run this once after 'docker compose up' to create the model

set -e

CONTAINER_NAME="clarity-ollama"
MODEL_NAME="phi3-mini"

echo "Waiting for Ollama container to be ready..."
until docker exec $CONTAINER_NAME ollama list > /dev/null 2>&1; do
    sleep 2
    echo "  waiting..."
done
echo "Ollama is ready."

# Check if model already exists
if docker exec $CONTAINER_NAME ollama list | grep -q "$MODEL_NAME"; then
    echo "Model '$MODEL_NAME' already exists. Skipping creation."
    exit 0
fi

# Create the model from the mounted GGUF + Modelfile
echo "Creating model '$MODEL_NAME' from GGUF..."
docker exec -w /models $CONTAINER_NAME ollama create $MODEL_NAME -f /models/Modelfile

echo ""
echo "Model '$MODEL_NAME' created successfully!"
echo "Test it with: docker exec $CONTAINER_NAME ollama run $MODEL_NAME 'What is an ATO?'"
echo ""
echo "API available at: http://localhost:11434/v1/chat/completions"

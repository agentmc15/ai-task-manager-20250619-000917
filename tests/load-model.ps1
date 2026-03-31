# Load the Phi-3 Mini model into the Ollama container
# Run this once after 'docker compose up' to create the model

$CONTAINER_NAME = "clarity-ollama"
$MODEL_NAME = "phi3-mini"

Write-Host "Waiting for Ollama container to be ready..."
do {
    Start-Sleep -Seconds 2
    Write-Host "  waiting..."
    $result = docker exec $CONTAINER_NAME ollama list 2>&1
} until ($LASTEXITCODE -eq 0)

Write-Host "Ollama is ready."

# Check if model already exists
$models = docker exec $CONTAINER_NAME ollama list
if ($models -match $MODEL_NAME) {
    Write-Host "Model '$MODEL_NAME' already exists. Skipping creation."
    exit 0
}

# Create the model from the mounted GGUF + Modelfile
Write-Host "Creating model '$MODEL_NAME' from GGUF..."
docker exec -w /models $CONTAINER_NAME ollama create $MODEL_NAME -f /models/Modelfile

Write-Host ""
Write-Host "Model '$MODEL_NAME' created successfully!"
Write-Host "Test: docker exec $CONTAINER_NAME ollama run $MODEL_NAME 'What is an ATO?'"
Write-Host "API: http://localhost:11434/v1/chat/completions"
